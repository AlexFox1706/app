import 'dart:convert';

/// Как часто повторяется задача.
enum RepeatType {
  once, // разовая
  daily, // каждый день
  weekly, // по выбранным дням недели
  monthly; // каждый месяц в то же число

  static RepeatType fromName(String name) =>
      RepeatType.values.firstWhere((e) => e.name == name, orElse: () => RepeatType.once);
}

/// Задача (шаблон). Конкретные «выпадения» задачи на дни — [Occurrence].
class Task {
  final int? id;
  final String title;
  final String description;

  /// Дата задачи (для разовой) или дата начала (для регулярной). Только дата.
  final DateTime startDate;

  /// Дата окончания для регулярной задачи (включительно). null — бессрочно.
  final DateTime? endDate;

  final int hour;
  final int minute;

  final RepeatType repeatType;

  /// Дни недели для [RepeatType.weekly]: 1 = Пн ... 7 = Вс.
  final Set<int> weekdays;

  /// Сколько раз напомнить (1 — одно уведомление).
  final int reminderCount;

  /// Интервал между повторными напоминаниями, минуты.
  final int reminderIntervalMin;

  /// content:// URI звука с устройства. null — системный звук по умолчанию.
  final String? soundUri;
  final String? soundTitle;

  /// Звук играет по кругу, пока не нажмёшь на уведомление / не закроешь его.
  final bool insistent;
  final bool vibrate;

  /// Выключенная задача не напоминает, но видна в календаре.
  final bool enabled;

  const Task({
    this.id,
    required this.title,
    this.description = '',
    required this.startDate,
    this.endDate,
    required this.hour,
    required this.minute,
    this.repeatType = RepeatType.once,
    this.weekdays = const {},
    this.reminderCount = 1,
    this.reminderIntervalMin = 5,
    this.soundUri,
    this.soundTitle,
    this.insistent = false,
    this.vibrate = true,
    this.enabled = true,
  });

  bool get isRecurring => repeatType != RepeatType.once;

  Task copyWith({
    int? id,
    String? title,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    int? hour,
    int? minute,
    RepeatType? repeatType,
    Set<int>? weekdays,
    int? reminderCount,
    int? reminderIntervalMin,
    String? soundUri,
    String? soundTitle,
    bool clearSound = false,
    bool? insistent,
    bool? vibrate,
    bool? enabled,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      repeatType: repeatType ?? this.repeatType,
      weekdays: weekdays ?? this.weekdays,
      reminderCount: reminderCount ?? this.reminderCount,
      reminderIntervalMin: reminderIntervalMin ?? this.reminderIntervalMin,
      soundUri: clearSound ? null : (soundUri ?? this.soundUri),
      soundTitle: clearSound ? null : (soundTitle ?? this.soundTitle),
      insistent: insistent ?? this.insistent,
      vibrate: vibrate ?? this.vibrate,
      enabled: enabled ?? this.enabled,
    );
  }

  // ---------- Расписание ----------

  /// Выпадает ли задача на день [day] (время не учитывается).
  bool occursOn(DateTime day) {
    final d = dateOnly(day);
    final start = dateOnly(startDate);
    if (d.isBefore(start)) return false;
    if (repeatType != RepeatType.once && endDate != null && d.isAfter(dateOnly(endDate!))) {
      return false;
    }
    switch (repeatType) {
      case RepeatType.once:
        return d == start;
      case RepeatType.daily:
        return true;
      case RepeatType.weekly:
        return weekdays.contains(d.weekday);
      case RepeatType.monthly:
        // 31-е число в коротком месяце превращается в последний день месяца.
        final lastDay = DateTime(d.year, d.month + 1, 0).day;
        final target = startDate.day > lastDay ? lastDay : startDate.day;
        return d.day == target;
    }
  }

  /// Момент начала задачи в день [day] (локальное время).
  DateTime timeOn(DateTime day) => DateTime(day.year, day.month, day.day, hour, minute);

  /// Все выпадения в интервале дней [from]..[to] включительно.
  List<DateTime> occurrencesBetween(DateTime from, DateTime to) {
    final result = <DateTime>[];
    var d = dateOnly(from);
    final last = dateOnly(to);
    while (!d.isAfter(last)) {
      if (occursOn(d)) result.add(timeOn(d));
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return result;
  }

  /// Моменты всех напоминаний для одного выпадения.
  List<DateTime> reminderTimes(DateTime occurrence) => List.generate(
        reminderCount,
        (i) => occurrence.add(Duration(minutes: i * reminderIntervalMin)),
      );

  /// Отпечаток настроек, влияющих на уведомления. Если он поменялся —
  /// уведомления этой задачи будут перепланированы.
  String get notificationFingerprint => jsonEncode([
        title,
        description,
        soundUri,
        insistent,
        vibrate,
        reminderCount,
        reminderIntervalMin,
      ]);

  // ---------- SQLite ----------

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'description': description,
        'start_date': dateOnly(startDate).millisecondsSinceEpoch,
        'end_date': endDate == null ? null : dateOnly(endDate!).millisecondsSinceEpoch,
        'hour': hour,
        'minute': minute,
        'repeat_type': repeatType.name,
        'weekdays': (weekdays.toList()..sort()).join(','),
        'reminder_count': reminderCount,
        'reminder_interval': reminderIntervalMin,
        'sound_uri': soundUri,
        'sound_title': soundTitle,
        'insistent': insistent ? 1 : 0,
        'vibrate': vibrate ? 1 : 0,
        'enabled': enabled ? 1 : 0,
      };

  factory Task.fromMap(Map<String, Object?> m) {
    final wd = (m['weekdays'] as String?) ?? '';
    return Task(
      id: m['id'] as int?,
      title: m['title'] as String,
      description: (m['description'] as String?) ?? '',
      startDate: DateTime.fromMillisecondsSinceEpoch(m['start_date'] as int),
      endDate: m['end_date'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['end_date'] as int),
      hour: m['hour'] as int,
      minute: m['minute'] as int,
      repeatType: RepeatType.fromName(m['repeat_type'] as String),
      weekdays: wd.isEmpty ? <int>{} : wd.split(',').map(int.parse).toSet(),
      reminderCount: m['reminder_count'] as int,
      reminderIntervalMin: m['reminder_interval'] as int,
      soundUri: m['sound_uri'] as String?,
      soundTitle: m['sound_title'] as String?,
      insistent: (m['insistent'] as int) == 1,
      vibrate: (m['vibrate'] as int) == 1,
      enabled: (m['enabled'] as int) == 1,
    );
  }
}

/// Статус конкретного выпадения задачи.
enum OccurrenceStatus {
  pending, // ещё не отмечено
  done, // выполнено
  snoozed; // отложено (запланировано отдельное напоминание)

  static OccurrenceStatus fromName(String? name) =>
      OccurrenceStatus.values.firstWhere((e) => e.name == name, orElse: () => OccurrenceStatus.pending);
}

/// Задача в конкретный день.
class Occurrence {
  final Task task;
  final DateTime time;
  final OccurrenceStatus status;

  const Occurrence(this.task, this.time, this.status);

  bool get isDone => status == OccurrenceStatus.done;
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
