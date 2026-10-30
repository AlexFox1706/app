import 'package:flutter/material.dart';

import '../services/device_bridge.dart';
import '../services/notification_service.dart';

/// Состояние всех разрешений, от которых зависит надёжность напоминаний.
class PermissionState {
  final bool notifications;
  final bool exactAlarms;
  final bool fullScreen;
  final bool battery;

  const PermissionState({
    required this.notifications,
    required this.exactAlarms,
    required this.fullScreen,
    required this.battery,
  });

  /// Критичные для работы напоминаний.
  bool get criticalOk => notifications && exactAlarms && fullScreen;

  static Future<PermissionState> check() async => PermissionState(
        notifications: await NotificationService.notificationsEnabled(),
        exactAlarms: await NotificationService.exactAlarmsAllowed(),
        fullScreen: await DeviceBridge.canUseFullScreenIntent(),
        battery: await DeviceBridge.isIgnoringBatteryOptimizations(),
      );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  PermissionState? _state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Возвращаемся из системных настроек — перепроверяем.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await PermissionState.check();
    if (mounted) setState(() => _state = s);
  }

  Future<void> _test() async {
    await NotificationService.scheduleTest();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Напоминание придёт через 15 секунд. Заблокируйте экран, чтобы проверить.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки напоминаний')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _PermTile(
                  ok: s.notifications,
                  title: 'Уведомления',
                  subtitle: 'Без этого напоминания не появятся совсем.',
                  onFix: () async {
                    await NotificationService.requestNotifications();
                    final enabled = await NotificationService.notificationsEnabled();
                    if (!enabled) await DeviceBridge.openAppSettings();
                    _refresh();
                  },
                ),
                _PermTile(
                  ok: s.exactAlarms,
                  title: 'Точное время',
                  subtitle: 'Напоминание срабатывает минута в минуту, даже в режиме сна телефона.',
                  onFix: () async {
                    await NotificationService.requestExactAlarms();
                    _refresh();
                  },
                ),
                _PermTile(
                  ok: s.fullScreen,
                  title: 'Показ поверх блокировки',
                  subtitle: 'Полноэкранное напоминание на заблокированном экране (Android 14+).',
                  onFix: () async {
                    await NotificationService.requestFullScreen();
                    _refresh();
                  },
                ),
                _PermTile(
                  ok: s.battery,
                  title: 'Без ограничений батареи',
                  subtitle: 'Система не будет «усыплять» приложение и задерживать напоминания.',
                  onFix: () async {
                    await DeviceBridge.requestIgnoreBatteryOptimizations();
                    _refresh();
                  },
                ),
                const Divider(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Xiaomi, Huawei, Honor, Oppo, Vivo, Realme',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          const Text(
                            'На этих телефонах в настройках приложения дополнительно включите:\n'
                            '• Автозапуск\n'
                            '• Экран блокировки / «Показывать на экране блокировки»\n'
                            '• Всплывающие окна (окна поверх других приложений)\n'
                            '• Контроль активности / батарея: «Нет ограничений»',
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: DeviceBridge.openAppSettings,
                            icon: const Icon(Icons.settings_outlined),
                            label: const Text('Открыть настройки приложения'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton.icon(
                    onPressed: _test,
                    icon: const Icon(Icons.alarm_on_rounded),
                    label: const Text('Проверить напоминание (через 15 сек)'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _PermTile extends StatelessWidget {
  final bool ok;
  final String title;
  final String subtitle;
  final VoidCallback onFix;

  const _PermTile({required this.ok, required this.title, required this.subtitle, required this.onFix});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        ok ? Icons.check_circle_rounded : Icons.error_rounded,
        color: ok ? Colors.green : cs.error,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: ok ? null : FilledButton.tonal(onPressed: onFix, child: const Text('Включить')),
      isThreeLine: true,
    );
  }
}
