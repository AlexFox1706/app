import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/task.dart';
import '../services/notification_service.dart';
import '../state/task_store.dart';
import '../widgets/task_tile.dart';
import 'settings_screen.dart';
import 'task_edit_screen.dart';

enum _ViewMode { day, week }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _store = TaskStore.instance;
  late final AppLifecycleListener _lifecycle;

  DateTime _selected = dateOnly(DateTime.now());
  DateTime _focused = dateOnly(DateTime.now());
  CalendarFormat _format = CalendarFormat.week;
  _ViewMode _mode = _ViewMode.day;
  PermissionState? _perms;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () {
      // Сдвигаем окно планирования и подтягиваем изменения из фона.
      _store.load();
      _checkPermissions();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstRunPermissions());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _firstRunPermissions() async {
    // Системный запрос показывается, только если пользователь ещё не отвечал.
    await NotificationService.requestNotifications();
    await _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final p = await PermissionState.check();
    if (mounted) setState(() => _perms = p);
  }

  /// Неделя, которая сейчас видна в календаре (листается свайпом).
  DateTime get _weekStart {
    final d = dateOnly(_focused);
    return DateTime(d.year, d.month, d.day - (d.weekday - 1));
  }

  Future<void> _openEditor({Task? task}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TaskEditScreen(task: task, initialDate: _selected),
    ));
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    _checkPermissions();
  }

  Future<void> _confirmDelete(Task t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить задачу?'),
        content: Text(t.isRecurring
            ? '«${t.title}» будет удалена целиком, со всеми повторениями.'
            : '«${t.title}» будет удалена.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true) await _store.delete(t);
  }

  void _showActions(Occurrence o) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(o.isDone ? Icons.undo_rounded : Icons.check_rounded),
              title: Text(o.isDone ? 'Снять отметку' : 'Отметить выполненной'),
              onTap: () {
                Navigator.pop(ctx);
                _store.setDone(o.task, o.time, !o.isDone);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Изменить'),
              onTap: () {
                Navigator.pop(ctx);
                _openEditor(task: o.task);
              },
            ),
            ListTile(
              leading: Icon(o.task.enabled ? Icons.notifications_off_rounded : Icons.notifications_active_rounded),
              title: Text(o.task.enabled ? 'Выключить напоминания' : 'Включить напоминания'),
              onTap: () {
                Navigator.pop(ctx);
                _store.save(o.task.copyWith(enabled: !o.task.enabled));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Удалить'),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(o.task);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Задачи'),
            actions: [
              IconButton(
                tooltip: 'Сегодня',
                icon: const Icon(Icons.today_rounded),
                onPressed: () => setState(() {
                  _selected = dateOnly(DateTime.now());
                  _focused = _selected;
                }),
              ),
              IconButton(
                tooltip: 'Настройки',
                icon: Badge(
                  isLabelVisible: _perms != null && !_perms!.criticalOk,
                  child: const Icon(Icons.settings_rounded),
                ),
                onPressed: _openSettings,
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Задача'),
          ),
          body: Column(
            children: [
              if (_perms != null && !_perms!.criticalOk) _PermissionBanner(onTap: _openSettings),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: SegmentedButton<_ViewMode>(
                  segments: const [
                    ButtonSegment(value: _ViewMode.day, label: Text('День'), icon: Icon(Icons.view_day_rounded)),
                    ButtonSegment(value: _ViewMode.week, label: Text('Неделя'), icon: Icon(Icons.view_week_rounded)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
              ),
              _buildCalendar(context),
              const Divider(height: 1),
              Expanded(child: _mode == _ViewMode.day ? _buildDay(context) : _buildWeek(context)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCalendar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TableCalendar<Occurrence>(
      locale: 'ru',
      firstDay: DateTime(2020, 1, 1),
      lastDay: DateTime(2100, 12, 31),
      focusedDay: _focused,
      currentDay: DateTime.now(),
      startingDayOfWeek: StartingDayOfWeek.monday,
      calendarFormat: _format,
      // Кнопка в шапке показывает, на какой вид переключит нажатие.
      availableCalendarFormats: const {
        CalendarFormat.week: 'Неделя',
        CalendarFormat.month: 'Месяц',
      },
      rowHeight: 46,
      selectedDayPredicate: (d) => isSameDay(d, _selected),
      eventLoader: (d) => _store.occurrencesOn(d),
      onDaySelected: (selected, focused) => setState(() {
        _selected = dateOnly(selected);
        _focused = dateOnly(focused);
      }),
      onPageChanged: (focused) => setState(() => _focused = dateOnly(focused)),
      onFormatChanged: (f) => setState(() => _format = f),
      headerStyle: HeaderStyle(
        titleCentered: true,
        titleTextFormatter: (date, locale) => toBeginningOfSentenceCase(DateFormat.yMMMM(locale).format(date)),
        formatButtonDecoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      calendarStyle: CalendarStyle(
        outsideDaysVisible: false,
        markersMaxCount: 3,
        markerSize: 5,
        markerDecoration: BoxDecoration(color: cs.tertiary, shape: BoxShape.circle),
        todayDecoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
        todayTextStyle: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600),
        selectedDecoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
        selectedTextStyle: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _tile(Occurrence o) => TaskTile(
        key: ValueKey('${o.task.id}-${o.time.millisecondsSinceEpoch}'),
        occ: o,
        onToggleDone: (v) => _store.setDone(o.task, o.time, v),
        onTap: () => _openEditor(task: o.task),
        onLongPress: () => _showActions(o),
      );

  Widget _buildDay(BuildContext context) {
    final list = _store.occurrencesOn(_selected);
    final header = toBeginningOfSentenceCase(DateFormat('EEEE, d MMMM').format(_selected));
    if (list.isEmpty) {
      return ListView(
        children: [
          _DayHeader(title: header, count: 0),
          const SizedBox(height: 48),
          Icon(Icons.event_available_rounded, size: 56, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 12),
          const Center(child: Text('На этот день задач нет')),
        ],
      );
    }
    final done = list.where((o) => o.isDone).length;
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        _DayHeader(title: header, count: list.length, done: done),
        ...list.map(_tile),
      ],
    );
  }

  Widget _buildWeek(BuildContext context) {
    final start = _weekStart;
    final children = <Widget>[];
    for (var i = 0; i < 7; i++) {
      final day = DateTime(start.year, start.month, start.day + i);
      final list = _store.occurrencesOn(day);
      final isToday = isSameDay(day, DateTime.now());
      children.add(_DayHeader(
        title: toBeginningOfSentenceCase(DateFormat('EEEE, d MMMM').format(day)),
        count: list.length,
        done: list.where((o) => o.isDone).length,
        highlight: isToday,
        onTap: () => setState(() {
          _selected = day;
          _focused = day;
          _mode = _ViewMode.day;
        }),
      ));
      if (list.isEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 16, 8),
          child: Text('Нет задач', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        ));
      } else {
        children.addAll(list.map(_tile));
      }
    }
    return ListView(padding: const EdgeInsets.only(bottom: 96), children: children);
  }
}

class _DayHeader extends StatelessWidget {
  final String title;
  final int count;
  final int done;
  final bool highlight;
  final VoidCallback? onTap;

  const _DayHeader({required this.title, required this.count, this.done = 0, this.highlight = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: highlight ? cs.primary : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            if (count > 0)
              Text('$done / $count', style: TextStyle(color: cs.outline, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _PermissionBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.errorContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Не все разрешения выданы — напоминания могут не прийти. Нажмите, чтобы настроить.',
                  style: TextStyle(color: cs.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
