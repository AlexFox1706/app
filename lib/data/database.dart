import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/task.dart';

/// Локальное хранилище (SQLite). Используется и из основного приложения,
/// и из фонового обработчика кнопок уведомления.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'task_reminder.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            start_date INTEGER NOT NULL,
            end_date INTEGER,
            hour INTEGER NOT NULL,
            minute INTEGER NOT NULL,
            repeat_type TEXT NOT NULL,
            weekdays TEXT NOT NULL DEFAULT '',
            reminder_count INTEGER NOT NULL DEFAULT 1,
            reminder_interval INTEGER NOT NULL DEFAULT 5,
            sound_uri TEXT,
            sound_title TEXT,
            insistent INTEGER NOT NULL DEFAULT 0,
            vibrate INTEGER NOT NULL DEFAULT 1,
            enabled INTEGER NOT NULL DEFAULT 1
          )
        ''');
        // Отметки по конкретным выпадениям: выполнено / отложено.
        await db.execute('''
          CREATE TABLE occurrences (
            task_id INTEGER NOT NULL,
            occ_ms INTEGER NOT NULL,
            status TEXT NOT NULL,
            PRIMARY KEY (task_id, occ_ms)
          )
        ''');
      },
    );
  }

  // ---------- Задачи ----------

  Future<List<Task>> allTasks() async {
    final rows = await (await db).query('tasks', orderBy: 'hour, minute, id');
    return rows.map(Task.fromMap).toList();
  }

  Future<Task?> taskById(int id) async {
    final rows = await (await db).query('tasks', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Task.fromMap(rows.first);
  }

  Future<int> insertTask(Task t) async => (await db).insert('tasks', t.toMap()..remove('id'));

  Future<void> updateTask(Task t) async =>
      (await db).update('tasks', t.toMap(), where: 'id = ?', whereArgs: [t.id]);

  Future<void> deleteTask(int id) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('tasks', where: 'id = ?', whereArgs: [id]);
      await txn.delete('occurrences', where: 'task_id = ?', whereArgs: [id]);
    });
  }

  // ---------- Выпадения ----------

  /// Ключ: "taskId|occMs".
  Future<Map<String, OccurrenceStatus>> allOccurrenceStatuses() async {
    final rows = await (await db).query('occurrences');
    return {
      for (final r in rows)
        occKey(r['task_id'] as int, r['occ_ms'] as int): OccurrenceStatus.fromName(r['status'] as String?),
    };
  }

  Future<void> setOccurrenceStatus(int taskId, int occMs, OccurrenceStatus status) async {
    final d = await db;
    if (status == OccurrenceStatus.pending) {
      await d.delete('occurrences', where: 'task_id = ? AND occ_ms = ?', whereArgs: [taskId, occMs]);
    } else {
      await d.insert(
        'occurrences',
        {'task_id': taskId, 'occ_ms': occMs, 'status': status.name},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Удаляет отметки старше [before], чтобы база не росла бесконечно.
  Future<void> purgeOccurrencesBefore(DateTime before) async {
    await (await db).delete('occurrences',
        where: 'occ_ms < ?', whereArgs: [before.millisecondsSinceEpoch]);
  }
}

String occKey(int taskId, int occMs) => '$taskId|$occMs';
