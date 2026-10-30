import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/database.dart';
import '../models/task.dart';

const kActionDone = 'done';
const kActionSnooze = 'snooze';
const kSnoozeMinutes = 10;

/// Имя порта, через который фоновый обработчик говорит UI «обнови данные».
const kMainPortName = 'task_reminder_main_port';

/// Максимальное число напоминаний в повторе.
const kMaxReminderCount = 10;

/// Android хранит не более ~500 будильников на приложение — оставляем запас.
const kMaxScheduled = 300;

/// На сколько дней вперёд планируются регулярные задачи. Окно сдвигается
/// при каждом открытии приложения и при каждом действии с уведомлением.
const kHorizonDays = 45;

/// Данные, которые «едут» внутри уведомления.
class ReminderPayload {
  final int taskId;
  final int occMs; // момент выпадения задачи (без сдвига повтора)
  final int index; // номер напоминания в серии, с 0
  final int atMs; // когда сработает это уведомление
  final bool snooze;
  final String fp; // отпечаток настроек задачи

  const ReminderPayload({
    required this.taskId,
    required this.occMs,
    required this.index,
    required this.atMs,
    this.snooze = false,
    this.fp = '',
  });

  String encode() => jsonEncode({
        't': taskId,
        'o': occMs,
        'i': index,
        'a': atMs,
        's': snooze ? 1 : 0,
        'f': fp,
      });

  static ReminderPayload? tryParse(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return ReminderPayload(
        taskId: m['t'] as int,
        occMs: m['o'] as int,
        index: m['i'] as int,
        atMs: m['a'] as int,
        snooze: m['s'] == 1,
        fp: (m['f'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Стабильный хэш (String.hashCode в Dart между запусками не гарантирован).
int fnv32(String s) {
  var h = 0x811c9dc5;
  for (final c in utf8.encode(s)) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h & 0x3FFFFFFF;
}

int reminderNotificationId(int taskId, int occMs, int index) => fnv32('r|$taskId|$occMs|$index');
int snoozeNotificationId(int taskId, int occMs) => fnv32('s|$taskId|$occMs');

/// Канал на каждую комбинацию «звук + вибрация»: на Android 8+ звук
/// задаётся каналом и после создания канала не меняется.
String channelIdFor(Task t) => 'rem_${fnv32('${t.soundUri}|${t.vibrate}').toRadixString(16)}';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();

  static AndroidFlutterLocalNotificationsPlugin? get android =>
      plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<void> init({required DidReceiveNotificationResponseCallback onResponse}) async {
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: onResponse,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );
  }

  /// Если приложение запущено нажатием на уведомление (или полноэкранным
  /// уведомлением на заблокированном экране) — возвращает его.
  static Future<NotificationResponse?> launchResponse() async {
    final details = await plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return details.notificationResponse;
  }

  // ---------- Разрешения ----------

  static Future<bool> notificationsEnabled() async => (await android?.areNotificationsEnabled()) ?? false;
  static Future<bool> exactAlarmsAllowed() async => (await android?.canScheduleExactNotifications()) ?? false;

  static Future<void> requestNotifications() async => android?.requestNotificationsPermission();
  static Future<void> requestExactAlarms() async => android?.requestExactAlarmsPermission();
  static Future<void> requestFullScreen() async => android?.requestFullScreenIntentPermission();

  /// «Будильник» — самый надёжный режим (срабатывает и в глубоком сне).
  /// Без разрешения на точное время — хотя бы приблизительно.
  static Future<AndroidScheduleMode> scheduleMode() async =>
      await exactAlarmsAllowed() ? AndroidScheduleMode.alarmClock : AndroidScheduleMode.inexactAllowWhileIdle;

  // ---------- Внешний вид уведомления ----------

  static NotificationDetails _details(Task t, {required bool isLast, required bool isSnooze, String? subText}) {
    final body = t.description.trim().isEmpty ? 'Время: ${_fmtTime(t)}' : t.description.trim();
    final soundName = t.soundTitle ?? 'стандартный звук';
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelIdFor(t),
        'Напоминания — $soundName${t.vibrate ? '' : ' (без вибрации)'}',
        channelDescription: 'Напоминания о задачах',
        icon: 'ic_notification',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        // Полноэкранное уведомление: на заблокированном экране открывает
        // экран напоминания, на разблокированном — всплывает сверху.
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
        playSound: true,
        sound: t.soundUri == null ? null : UriAndroidNotificationSound(t.soundUri!),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: t.vibrate,
        vibrationPattern: t.vibrate ? Int64List.fromList([0, 700, 300, 700, 300, 700]) : null,
        // FLAG_INSISTENT = 4: звук повторяется, пока уведомление не убрано.
        additionalFlags: t.insistent ? Int32List.fromList(<int>[4]) : null,
        // Промежуточное напоминание само исчезает, когда приходит следующее.
        timeoutAfter: (isLast || isSnooze) ? null : t.reminderIntervalMin * 60 * 1000,
        styleInformation: BigTextStyleInformation(body),
        ticker: t.title,
        subText: subText,
        autoCancel: true,
        actions: const [
          AndroidNotificationAction(kActionDone, 'Выполнено', cancelNotification: true),
          AndroidNotificationAction(kActionSnooze, 'Отложить на $kSnoozeMinutes мин', cancelNotification: true),
        ],
      ),
    );
  }

  static String _fmtTime(Task t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _bodyFor(Task t) => t.description.trim().isEmpty ? 'Время: ${_fmtTime(t)}' : t.description.trim();

  // ---------- Планирование ----------

  static Future<void> _queue = Future.value();

  /// Приводит запланированные уведомления в соответствие с задачами.
  /// Вызовы выстраиваются в очередь, чтобы не мешать друг другу.
  static Future<void> resync(List<Task> tasks, Map<String, OccurrenceStatus> statuses) {
    final run = _queue.then((_) => _resync(tasks, statuses));
    _queue = run.catchError((Object e, StackTrace s) {
      debugPrint('resync error: $e\n$s');
    });
    return _queue;
  }

  static Future<void> _resync(List<Task> tasks, Map<String, OccurrenceStatus> statuses) async {
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: kHorizonDays));
    final byId = {for (final t in tasks) if (t.id != null) t.id!: t};

    // 1. Что должно быть запланировано.
    final planned = <_Planned>[];
    for (final t in tasks) {
      if (!t.enabled || t.id == null) continue;
      // Вчерашний день — на случай, если серия повторов переходит через полночь.
      for (final occ in t.occurrencesBetween(now.subtract(const Duration(days: 1)), horizon)) {
        final occMs = occ.millisecondsSinceEpoch;
        final st = statuses[occKey(t.id!, occMs)];
        if (st == OccurrenceStatus.done || st == OccurrenceStatus.snoozed) continue;
        final times = t.reminderTimes(occ);
        for (var i = 0; i < times.length; i++) {
          if (!times[i].isAfter(now)) continue;
          planned.add(_Planned(t, occMs, i, times[i]));
        }
      }
    }
    planned.sort((a, b) => a.at.compareTo(b.at));
    if (planned.length > kMaxScheduled) planned.removeRange(kMaxScheduled, planned.length);
    final desired = {
      for (final p in planned) reminderNotificationId(p.task.id!, p.occMs, p.index): p,
    };

    // 2. Что уже запланировано — убираем лишнее, оставляем совпадающее.
    final alreadyOk = <int>{};
    for (final req in await plugin.pendingNotificationRequests()) {
      final pl = ReminderPayload.tryParse(req.payload);
      if (pl == null) {
        await plugin.cancel(id: req.id);
        continue;
      }
      if (pl.taskId == 0) continue; // тестовое напоминание
      if (pl.snooze) {
        final t = byId[pl.taskId];
        final st = statuses[occKey(pl.taskId, pl.occMs)];
        if (t == null || !t.enabled || st != OccurrenceStatus.snoozed) {
          await plugin.cancel(id: req.id);
        }
        continue;
      }
      final want = desired[req.id];
      if (want == null) {
        await plugin.cancel(id: req.id);
      } else if (want.payload.encode() == req.payload) {
        alreadyOk.add(req.id);
      }
    }

    // 3. Добавляем недостающее (повторный zonedSchedule с тем же id заменяет старое).
    final mode = await scheduleMode();
    for (final e in desired.entries) {
      if (alreadyOk.contains(e.key)) continue;
      final p = e.value;
      final t = p.task;
      try {
        await plugin.zonedSchedule(
          id: e.key,
          title: t.title,
          body: _bodyFor(t),
          scheduledDate: tz.TZDateTime.from(p.at, tz.UTC),
          notificationDetails: _details(
            t,
            isLast: p.index == t.reminderCount - 1,
            isSnooze: false,
            subText: t.reminderCount > 1 ? 'Напоминание ${p.index + 1} из ${t.reminderCount}' : null,
          ),
          androidScheduleMode: mode,
          payload: p.payload.encode(),
        );
      } catch (e) {
        // время успело пройти, пока планировали, или нет разрешения — пропускаем
        debugPrint('schedule ${e.toString()}');
      }
    }

    // 4. Удаляем каналы звуков, которые больше никто не использует.
    await _cleanupChannels(tasks);
  }

  static Future<void> _cleanupChannels(List<Task> tasks) async {
    final a = android;
    if (a == null) return;
    final used = tasks.map(channelIdFor).toSet();
    final channels = await a.getNotificationChannels() ?? const <AndroidNotificationChannel>[];
    for (final c in channels) {
      if (c.id.startsWith('rem_') && !used.contains(c.id)) {
        await a.deleteNotificationChannel(channelId: c.id);
      }
    }
  }

  /// Отложенное напоминание через [kSnoozeMinutes] минут.
  static Future<void> scheduleSnooze(Task t, int occMs) async {
    final at = DateTime.now().add(const Duration(minutes: kSnoozeMinutes));
    final payload = ReminderPayload(
      taskId: t.id!,
      occMs: occMs,
      index: 0,
      atMs: at.millisecondsSinceEpoch,
      snooze: true,
      fp: t.notificationFingerprint,
    );
    await plugin.zonedSchedule(
      id: snoozeNotificationId(t.id!, occMs),
      title: t.title,
      body: _bodyFor(t),
      scheduledDate: tz.TZDateTime.from(at, tz.UTC),
      notificationDetails: _details(t, isLast: true, isSnooze: true, subText: 'Отложено'),
      androidScheduleMode: await scheduleMode(),
      payload: payload.encode(),
    );
  }

  /// Тестовое напоминание (taskId = 0) — чтобы проверить звук и показ
  /// на заблокированном экране.
  static Future<void> scheduleTest({Duration delay = const Duration(seconds: 15)}) async {
    final at = DateTime.now().add(delay);
    final t = testTask(at);
    final payload = ReminderPayload(taskId: 0, occMs: at.millisecondsSinceEpoch, index: 0, atMs: at.millisecondsSinceEpoch);
    await plugin.zonedSchedule(
      id: reminderNotificationId(0, payload.occMs, 0),
      title: t.title,
      body: t.description,
      scheduledDate: tz.TZDateTime.from(at, tz.UTC),
      notificationDetails: _details(t, isLast: true, isSnooze: false),
      androidScheduleMode: await scheduleMode(),
      payload: payload.encode(),
    );
  }

  static Task testTask(DateTime at) => Task(
        title: 'Проверка напоминания',
        description: 'Если этот экран появился поверх блокировки и прозвучал звук — всё настроено правильно.',
        startDate: at,
        hour: at.hour,
        minute: at.minute,
      );

  /// Убирает только показанное уведомление (останавливает звук), остальные
  /// повторы серии остаются в силе.
  static Future<void> dismissShown(ReminderPayload p) => plugin.cancel(
      id: p.snooze ? snoozeNotificationId(p.taskId, p.occMs) : reminderNotificationId(p.taskId, p.occMs, p.index));

  /// Убирает все уведомления (и показанные, и запланированные) одного выпадения.
  static Future<void> cancelOccurrence(int taskId, int occMs) async {
    for (var i = 0; i < kMaxReminderCount; i++) {
      await plugin.cancel(id: reminderNotificationId(taskId, occMs, i));
    }
    await plugin.cancel(id: snoozeNotificationId(taskId, occMs));
  }
}

class _Planned {
  final Task task;
  final int occMs;
  final int index;
  final DateTime at;
  _Planned(this.task, this.occMs, this.index, this.at);

  ReminderPayload get payload => ReminderPayload(
        taskId: task.id!,
        occMs: occMs,
        index: index,
        atMs: at.millisecondsSinceEpoch,
        fp: task.notificationFingerprint,
      );
}

/// Действия над выпадением задачи. Работают и в UI, и в фоне.
class ReminderActions {
  static Future<void> markDone(int taskId, int occMs) async {
    await AppDatabase.instance.setOccurrenceStatus(taskId, occMs, OccurrenceStatus.done);
    await NotificationService.cancelOccurrence(taskId, occMs);
  }

  static Future<void> snooze(int taskId, int occMs) async {
    final task = await AppDatabase.instance.taskById(taskId);
    if (task == null) return;
    await AppDatabase.instance.setOccurrenceStatus(taskId, occMs, OccurrenceStatus.snoozed);
    await NotificationService.cancelOccurrence(taskId, occMs);
    await NotificationService.scheduleSnooze(task, occMs);
  }
}

/// Нажатие кнопки «Выполнено» / «Отложить» в шторке, когда приложение
/// закрыто или свёрнуто. Выполняется в отдельном фоновом изоляте.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final p = ReminderPayload.tryParse(response.payload);
  if (p == null) return;
  if (p.taskId == 0) return; // тестовое напоминание — уведомление уже убрано
  try {
    if (response.actionId == kActionDone) {
      await ReminderActions.markDone(p.taskId, p.occMs);
    } else if (response.actionId == kActionSnooze) {
      await ReminderActions.snooze(p.taskId, p.occMs);
    }
  } catch (e, s) {
    debugPrint('background action error: $e\n$s');
  }
  // Если приложение открыто — пусть обновит экран.
  IsolateNameServer.lookupPortByName(kMainPortName)?.send('refresh');
}

/// Человекочитаемое описание моментов напоминаний: «09:00, 09:05, 09:10».
String describeReminderTimes(Task t) {
  final base = DateTime(2000, 1, 1, t.hour, t.minute);
  final f = DateFormat.Hm();
  return t.reminderTimes(base).map(f.format).join(', ');
}
