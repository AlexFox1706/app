import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import '../services/device_bridge.dart';
import '../services/notification_service.dart';
import '../state/task_store.dart';
import '../widgets/task_tile.dart' show weekdayShort;

/// Создание и редактирование задачи.
class TaskEditScreen extends StatefulWidget {
  final Task? task;
  final DateTime initialDate;

  const TaskEditScreen({super.key, this.task, required this.initialDate});

  @override
  State<TaskEditScreen> createState() => _TaskEditScreenState();
}

class _TaskEditScreenState extends State<TaskEditScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _desc;

  late DateTime _date;
  DateTime? _endDate;
  late TimeOfDay _time;
  late bool _recurring;
  late RepeatType _repeat; // daily / weekly / monthly для регулярной
  late Set<int> _weekdays;
  late int _count;
  late int _interval;
  String? _soundUri;
  String? _soundTitle;
  late bool _insistent;
  late bool _vibrate;
  late bool _enabled;
  bool _saving = false;

  static const _intervals = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60];

  bool get _isNew => widget.task == null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _title = TextEditingController(text: t?.title ?? '');
    _desc = TextEditingController(text: t?.description ?? '');
    _date = dateOnly(t?.startDate ?? widget.initialDate);
    _endDate = t?.endDate;
    if (t != null) {
      _time = TimeOfDay(hour: t.hour, minute: t.minute);
    } else {
      // Ближайшие «круглые» полчаса.
      final n = DateTime.now().add(const Duration(minutes: 30));
      _time = TimeOfDay(hour: n.hour, minute: n.minute < 30 ? 30 : 0);
      if (n.minute >= 30) _time = TimeOfDay(hour: (n.hour + 1) % 24, minute: 0);
    }
    _recurring = t?.isRecurring ?? false;
    _repeat = (t == null || t.repeatType == RepeatType.once) ? RepeatType.daily : t.repeatType;
    _weekdays = {...?t?.weekdays};
    if (_weekdays.isEmpty) _weekdays = {_date.weekday};
    _count = t?.reminderCount ?? 1;
    _interval = t?.reminderIntervalMin ?? 5;
    if (!_intervals.contains(_interval)) _interval = 5;
    _soundUri = t?.soundUri;
    _soundTitle = t?.soundTitle;
    _insistent = t?.insistent ?? false;
    _vibrate = t?.vibrate ?? true;
    _enabled = t?.enabled ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Task _build() {
    return Task(
      id: widget.task?.id,
      title: _title.text.trim(),
      description: _desc.text.trim(),
      startDate: _date,
      endDate: _recurring ? _endDate : null,
      hour: _time.hour,
      minute: _time.minute,
      repeatType: _recurring ? _repeat : RepeatType.once,
      weekdays: _recurring && _repeat == RepeatType.weekly ? _weekdays : const {},
      reminderCount: _count,
      reminderIntervalMin: _interval,
      soundUri: _soundUri,
      soundTitle: _soundTitle,
      insistent: _insistent,
      vibrate: _vibrate,
      enabled: _enabled,
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_recurring && _repeat == RepeatType.weekly && _weekdays.isEmpty) {
      _snack('Выберите хотя бы один день недели');
      return;
    }
    if (_recurring && _endDate != null && _endDate!.isBefore(_date)) {
      _snack('Дата окончания раньше даты начала');
      return;
    }
    final task = _build();
    if (!task.isRecurring && task.timeOn(task.startDate).isBefore(DateTime.now())) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Время уже прошло'),
          content: const Text('Задача сохранится, но напоминания по ней не будет.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Изменить время')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
          ],
        ),
      );
      if (go != true) return;
    }
    setState(() => _saving = true);
    await TaskStore.instance.save(task);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final t = widget.task!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить задачу?'),
        content: Text(t.isRecurring ? 'Будут удалены все повторения.' : 'Задача будет удалена.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    await TaskStore.instance.delete(t);
    if (mounted) Navigator.of(context).pop();
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _pickDate({bool end = false}) async {
    final initial = end ? (_endDate ?? _date.add(const Duration(days: 30))) : _date;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: end ? 'Дата окончания' : (_recurring ? 'Дата начала' : 'Дата'),
    );
    if (d == null) return;
    setState(() {
      if (end) {
        _endDate = dateOnly(d);
      } else {
        _date = dateOnly(d);
      }
    });
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t != null) setState(() => _time = t);
  }

  Future<void> _pickSound() async {
    final kind = await showModalBottomSheet<SoundKind?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Откуда взять звук')),
            for (final k in SoundKind.values)
              ListTile(
                leading: Icon(switch (k) {
                  SoundKind.notification => Icons.notifications_rounded,
                  SoundKind.alarm => Icons.alarm_rounded,
                  SoundKind.ringtone => Icons.ring_volume_rounded,
                }),
                title: Text(k.label),
                onTap: () => Navigator.pop(ctx, k),
              ),
            if (_soundUri != null)
              ListTile(
                leading: const Icon(Icons.restart_alt_rounded),
                title: const Text('Стандартный звук уведомления'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _soundUri = null;
                    _soundTitle = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
    if (kind == null) return;
    try {
      final picked = await DeviceBridge.pickSound(kind: kind, currentUri: _soundUri);
      if (picked == null) return;
      // Свой файл из памяти телефона — системе нужен доступ к аудио.
      if (picked.uri.contains('external')) await DeviceBridge.ensureAudioPermission();
      setState(() {
        _soundUri = picked.uri;
        _soundTitle = picked.title;
      });
    } catch (e) {
      _snack('Не удалось открыть выбор звука: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateFmt = DateFormat('d MMMM y, EEE');
    final preview = _build();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Новая задача' : 'Задача'),
        actions: [
          if (!_isNew)
            IconButton(tooltip: 'Удалить', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_isNew ? 'Создать' : 'Сохранить'),
          ),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextFormField(
                controller: _title,
                autofocus: _isNew,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Название', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите название' : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextFormField(
                controller: _desc,
                minLines: 2,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Описание', border: OutlineInputBorder()),
              ),
            ),

            const _Section('Когда'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Разовая'), icon: Icon(Icons.looks_one_rounded)),
                  ButtonSegment(value: true, label: Text('Регулярная'), icon: Icon(Icons.repeat_rounded)),
                ],
                selected: {_recurring},
                onSelectionChanged: (s) => setState(() => _recurring = s.first),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_rounded),
              title: Text(_recurring ? 'Начиная с' : 'Дата'),
              subtitle: Text(dateFmt.format(_date)),
              onTap: () => _pickDate(),
            ),
            ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Время'),
              subtitle: Text(_time.format24()),
              onTap: _pickTime,
            ),
            if (_recurring) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final r in const [RepeatType.daily, RepeatType.weekly, RepeatType.monthly])
                      ChoiceChip(
                        label: Text(switch (r) {
                          RepeatType.daily => 'Каждый день',
                          RepeatType.weekly => 'По дням недели',
                          RepeatType.monthly => 'Каждый месяц',
                          RepeatType.once => '',
                        }),
                        selected: _repeat == r,
                        onSelected: (_) => setState(() => _repeat = r),
                      ),
                  ],
                ),
              ),
              if (_repeat == RepeatType.weekly)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var d = 1; d <= 7; d++)
                        FilterChip(
                          label: Text(weekdayShort[d - 1]),
                          selected: _weekdays.contains(d),
                          showCheckmark: false,
                          onSelected: (v) => setState(() => v ? _weekdays.add(d) : _weekdays.remove(d)),
                        ),
                    ],
                  ),
                ),
              if (_repeat == RepeatType.monthly)
                Padding(
                  padding: const EdgeInsets.fromLTRB(72, 0, 16, 4),
                  child: Text('${_date.day}-го числа каждого месяца',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              SwitchListTile(
                secondary: const Icon(Icons.event_busy_rounded),
                title: const Text('Дата окончания'),
                subtitle: Text(_endDate == null ? 'Без окончания' : dateFmt.format(_endDate!)),
                value: _endDate != null,
                onChanged: (v) {
                  if (v) {
                    _pickDate(end: true);
                  } else {
                    setState(() => _endDate = null);
                  }
                },
              ),
              if (_endDate != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 64),
                    child: TextButton(onPressed: () => _pickDate(end: true), child: const Text('Изменить дату')),
                  ),
                ),
            ],

            const _Section('Напоминания'),
            ListTile(
              leading: const Icon(Icons.notifications_active_rounded),
              title: const Text('Сколько раз напомнить'),
              trailing: _Stepper(
                value: _count,
                min: 1,
                max: kMaxReminderCount,
                onChanged: (v) => setState(() => _count = v),
              ),
            ),
            if (_count > 1)
              ListTile(
                leading: const Icon(Icons.timelapse_rounded),
                title: const Text('Интервал между напоминаниями'),
                trailing: DropdownButton<int>(
                  value: _interval,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final i in _intervals) DropdownMenuItem(value: i, child: Text('$i мин')),
                  ],
                  onChanged: (v) => setState(() => _interval = v ?? _interval),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
              child: Text(
                _count == 1
                    ? 'Одно напоминание в ${describeReminderTimes(preview)}'
                    : 'Напомню в ${describeReminderTimes(preview)} — пока не нажмёте «Выполнено»',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.music_note_rounded),
              title: const Text('Звук'),
              subtitle: Text(_soundTitle ?? 'Стандартный звук уведомления'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _pickSound,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.repeat_one_rounded),
              title: const Text('Звучать, пока не отреагирую'),
              subtitle: const Text('Звук повторяется до нажатия на уведомление'),
              value: _insistent,
              onChanged: (v) => setState(() => _insistent = v),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.vibration_rounded),
              title: const Text('Вибрация'),
              value: _vibrate,
              onChanged: (v) => setState(() => _vibrate = v),
            ),
            if (!_isNew)
              SwitchListTile(
                secondary: const Icon(Icons.power_settings_new_rounded),
                title: const Text('Напоминания включены'),
                subtitle: const Text('Выключенная задача остаётся в календаре, но не звонит'),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );
}

class _Stepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _Stepper({required this.value, required this.min, required this.max, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
          SizedBox(
            width: 24,
            child: Text('$value', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      );
}

extension on TimeOfDay {
  String format24() => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
