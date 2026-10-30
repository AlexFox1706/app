import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';

class TaskTile extends StatelessWidget {
  final Occurrence occ;
  final ValueChanged<bool> onToggleDone;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const TaskTile({
    super.key,
    required this.occ,
    required this.onToggleDone,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = occ.task;
    final done = occ.isDone;
    final muted = done || !t.enabled;

    final chips = <Widget>[
      if (t.isRecurring) _Badge(icon: Icons.repeat_rounded, text: repeatLabel(t)),
      if (t.reminderCount > 1) _Badge(icon: Icons.notifications_rounded, text: '×${t.reminderCount}'),
      if (occ.status == OccurrenceStatus.snoozed) const _Badge(icon: Icons.snooze_rounded, text: 'отложено'),
      if (!t.enabled) const _Badge(icon: Icons.notifications_off_rounded, text: 'выкл'),
    ];

    return Card(
      elevation: 0,
      color: done ? cs.surfaceContainerHighest.withValues(alpha: 0.5) : cs.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  DateFormat.Hm().format(occ.time),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: muted ? cs.outline : cs.primary,
                      ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            decoration: done ? TextDecoration.lineThrough : null,
                            color: muted ? cs.outline : null,
                          ),
                    ),
                    if (t.description.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          t.description.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    if (chips.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(spacing: 10, runSpacing: 4, children: chips),
                      ),
                  ],
                ),
              ),
              Checkbox(value: done, onChanged: (v) => onToggleDone(v ?? false)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Badge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 12, color: c)),
      ],
    );
  }
}

const weekdayShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

String repeatLabel(Task t) {
  switch (t.repeatType) {
    case RepeatType.once:
      return 'разово';
    case RepeatType.daily:
      return 'каждый день';
    case RepeatType.weekly:
      if (t.weekdays.length == 7) return 'каждый день';
      if (t.weekdays.length == 5 && t.weekdays.every((d) => d <= 5)) return 'по будням';
      if (t.weekdays.length == 2 && t.weekdays.containsAll({6, 7})) return 'по выходным';
      final days = t.weekdays.toList()..sort();
      return days.map((d) => weekdayShort[d - 1]).join(', ');
    case RepeatType.monthly:
      return '${t.startDate.day}-го числа';
  }
}
