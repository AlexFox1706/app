import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../models/task.dart';
import '../services/device_bridge.dart';
import '../services/notification_service.dart';
import '../state/task_store.dart';

/// Полноэкранное напоминание. Открывается нажатием на уведомление
/// или само — поверх экрана блокировки.
class AlarmScreen extends StatefulWidget {
  static const routeName = '/alarm';

  final ReminderPayload payload;
  final bool fromNotification;

  const AlarmScreen({super.key, required this.payload, required this.fromNotification});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  Task? _task;
  bool _loading = true;
  bool _busy = false;

  DateTime get _occ => DateTime.fromMillisecondsSinceEpoch(widget.payload.occMs);

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isTest => widget.payload.taskId == 0;

  Future<void> _load() async {
    final t = _isTest
        ? NotificationService.testTask(_occ)
        : await AppDatabase.instance.taskById(widget.payload.taskId);
    if (!mounted) return;
    setState(() {
      _task = t;
      _loading = false;
    });
  }

  Future<void> _close() async {
    if (widget.fromNotification) {
      await DeviceBridge.releaseLockScreen();
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      await _close();
    }
  }

  Future<void> _done() => _run(() async {
        final t = _task;
        if (_isTest) {
          await NotificationService.dismissShown(widget.payload);
        } else if (t != null) {
          await TaskStore.instance.setDone(t, _occ, true);
        }
      });

  Future<void> _snooze() => _run(() => TaskStore.instance.snooze(widget.payload.taskId, widget.payload.occMs));

  Future<void> _dismiss() => _run(() => NotificationService.dismissShown(widget.payload));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = _task;
    final remaining = t == null || widget.payload.snooze ? 0 : t.reminderCount - widget.payload.index - 1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: Scaffold(
        backgroundColor: cs.primaryContainer,
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.notifications_active_rounded, size: 56, color: cs.onPrimaryContainer),
                      const SizedBox(height: 16),
                      Text(
                        DateFormat.Hm().format(_occ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Text(
                        DateFormat('EEEE, d MMMM').format(_occ),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onPrimaryContainer.withValues(alpha: 0.75)),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        t?.title ?? 'Задача удалена',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            t?.description ?? '',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: cs.onPrimaryContainer),
                          ),
                        ),
                      ),
                      if (widget.payload.snooze)
                        _hint('Отложенное напоминание', cs)
                      else if (remaining > 0)
                        _hint('Ещё напомню $remaining раз(а), если не отметить', cs),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: t == null || _busy ? null : _done,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Выполнено'),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      ),
                      const SizedBox(height: 12),
                      if (!_isTest)
                        FilledButton.tonalIcon(
                          onPressed: t == null || _busy ? null : _snooze,
                          icon: const Icon(Icons.snooze_rounded),
                          label: const Text('Отложить на $kSnoozeMinutes мин'),
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy ? null : _dismiss,
                        child: const Text('Закрыть'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _hint(String text, ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onPrimaryContainer.withValues(alpha: 0.7)),
        ),
      );
}
