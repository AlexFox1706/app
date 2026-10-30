import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'screens/alarm_screen.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'state/task_store.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru');
  Intl.defaultLocale = 'ru';

  await NotificationService.init(onResponse: _onNotificationTap);
  final launch = await NotificationService.launchResponse();

  _listenBackgroundIsolate();

  runApp(TaskReminderApp(launchResponse: launch));

  await TaskStore.instance.purgeOld();
  await TaskStore.instance.load();
}

/// Фоновый обработчик кнопок уведомления сообщает сюда, что данные поменялись.
final _port = ReceivePort();
void _listenBackgroundIsolate() {
  IsolateNameServer.removePortNameMapping(kMainPortName);
  IsolateNameServer.registerPortWithName(_port.sendPort, kMainPortName);
  _port.listen((_) => TaskStore.instance.load());
}

/// Нажатие на уведомление (или полноэкранное уведомление), когда приложение запущено.
void _onNotificationTap(NotificationResponse r) {
  final p = ReminderPayload.tryParse(r.payload);
  if (p == null) return;
  openAlarmScreen(p, fromNotification: true);
}

void openAlarmScreen(ReminderPayload p, {required bool fromNotification}) {
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  // Не плодим экраны: если уже открыт экран напоминания — заменяем его.
  nav.popUntil((route) => route.settings.name != AlarmScreen.routeName);
  nav.push(MaterialPageRoute(
    settings: const RouteSettings(name: AlarmScreen.routeName),
    fullscreenDialog: true,
    builder: (_) => AlarmScreen(payload: p, fromNotification: fromNotification),
  ));
}

class TaskReminderApp extends StatefulWidget {
  final NotificationResponse? launchResponse;
  const TaskReminderApp({super.key, this.launchResponse});

  @override
  State<TaskReminderApp> createState() => _TaskReminderAppState();
}

class _TaskReminderAppState extends State<TaskReminderApp> {
  @override
  void initState() {
    super.initState();
    final p = ReminderPayload.tryParse(widget.launchResponse?.payload);
    // Кнопки «Выполнено/Отложить» обрабатываются в фоне; здесь — только нажатие
    // на само уведомление или полноэкранный показ.
    if (p != null && (widget.launchResponse?.actionId == null || widget.launchResponse!.actionId!.isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openAlarmScreen(p, fromNotification: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3D5AFE);
    return MaterialApp(
      title: 'Напоминалка',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
