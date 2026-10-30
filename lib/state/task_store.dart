import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../models/task.dart';
import '../services/notification_service.dart';

/// Состояние приложения: задачи + отметки выполнения.
/// После любого изменения перепланирует уведомления.
class TaskStore extends ChangeNotifier {
  TaskStore._();
  static final TaskStore instance = TaskStore._();

  final _db = AppDatabase.instance;

  List<Task> _tasks = const [];
  Map<String, OccurrenceStatus> _statuses = const {};
  bool _loaded = false;

  List<Task> get tasks => _tasks;
  bool get loaded => _loaded;

  Future<void> load({bool resync = true}) async {
    _tasks = await _db.allTasks();
    _statuses = await _db.allOccurrenceStatuses();
    _loaded = true;
    notifyListeners();
    if (resync) await NotificationService.resync(_tasks, _statuses);
  }

  Task? taskById(int id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  OccurrenceStatus statusOf(Task t, DateTime occ) =>
      _statuses[occKey(t.id!, occ.millisecondsSinceEpoch)] ?? OccurrenceStatus.pending;

  /// Задачи на день, отсортированные по времени.
  List<Occurrence> occurrencesOn(DateTime day) {
    final list = <Occurrence>[];
    for (final t in _tasks) {
      if (t.occursOn(day)) {
        final time = t.timeOn(day);
        list.add(Occurrence(t, time, statusOf(t, time)));
      }
    }
    list.sort((a, b) {
      final c = a.time.compareTo(b.time);
      return c != 0 ? c : a.task.title.compareTo(b.task.title);
    });
    return list;
  }

  int countOn(DateTime day) => _tasks.where((t) => t.occursOn(day)).length;

  Future<Task> save(Task t) async {
    Task saved;
    if (t.id == null) {
      final id = await _db.insertTask(t);
      saved = t.copyWith(id: id);
    } else {
      await _db.updateTask(t);
      saved = t;
    }
    await load();
    return saved;
  }

  Future<void> delete(Task t) async {
    if (t.id == null) return;
    await _db.deleteTask(t.id!);
    await load();
  }

  Future<void> setDone(Task t, DateTime occ, bool done) async {
    final occMs = occ.millisecondsSinceEpoch;
    if (done) {
      await ReminderActions.markDone(t.id!, occMs);
    } else {
      await _db.setOccurrenceStatus(t.id!, occMs, OccurrenceStatus.pending);
    }
    await load();
  }

  Future<void> snooze(int taskId, int occMs) async {
    await ReminderActions.snooze(taskId, occMs);
    await load();
  }

  Future<void> purgeOld() =>
      _db.purgeOccurrencesBefore(DateTime.now().subtract(const Duration(days: 400)));
}
