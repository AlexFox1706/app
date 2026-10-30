import 'package:flutter_test/flutter_test.dart';
import 'package:task_reminder/models/task.dart';

void main() {
  test('разовая задача выпадает только в свой день', () {
    final t = Task(title: 'a', startDate: DateTime(2026, 11, 2), hour: 9, minute: 0);
    expect(t.occursOn(DateTime(2026, 11, 2)), isTrue);
    expect(t.occursOn(DateTime(2026, 11, 3)), isFalse);
  });

  test('по дням недели (Пн, Ср) с датой окончания', () {
    final t = Task(
      title: 'b',
      startDate: DateTime(2026, 11, 2), // понедельник
      endDate: DateTime(2026, 11, 11),
      hour: 8,
      minute: 30,
      repeatType: RepeatType.weekly,
      weekdays: {1, 3},
    );
    final occ = t.occurrencesBetween(DateTime(2026, 11, 1), DateTime(2026, 11, 30));
    expect(occ.map((d) => d.day), [2, 4, 9, 11]);
  });

  test('каждый месяц 31-го → последний день короткого месяца', () {
    final t = Task(
      title: 'c',
      startDate: DateTime(2026, 1, 31),
      hour: 10,
      minute: 0,
      repeatType: RepeatType.monthly,
    );
    expect(t.occursOn(DateTime(2026, 2, 28)), isTrue);
    expect(t.occursOn(DateTime(2026, 4, 30)), isTrue);
    expect(t.occursOn(DateTime(2026, 4, 29)), isFalse);
  });

  test('повторы напоминаний', () {
    final t = Task(
      title: 'd',
      startDate: DateTime(2026, 11, 2),
      hour: 23,
      minute: 55,
      reminderCount: 3,
      reminderIntervalMin: 5,
    );
    final times = t.reminderTimes(t.timeOn(DateTime(2026, 11, 2)));
    expect(times.last, DateTime(2026, 11, 3, 0, 5));
  });

  test('сохранение в БД и обратно', () {
    final t = Task(
      id: 7,
      title: 'e',
      description: 'описание',
      startDate: DateTime(2026, 11, 2),
      hour: 7,
      minute: 15,
      repeatType: RepeatType.weekly,
      weekdays: {5, 1},
      soundUri: 'content://media/internal/audio/media/12',
      soundTitle: 'Звонок',
      insistent: true,
    );
    final back = Task.fromMap(t.toMap());
    expect(back.weekdays, {1, 5});
    expect(back.soundTitle, 'Звонок');
    expect(back.insistent, isTrue);
    expect(back.notificationFingerprint, t.notificationFingerprint);
  });
}
