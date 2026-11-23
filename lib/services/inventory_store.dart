import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/camera_device.dart';
import '../models/operation_history_entry.dart';
import 'sensitive_data_redactor.dart';

class InventoryStore {
  static const _databaseName = 'oxita_camera_inventory.db';
  static const _databaseVersion = 2;
  static const maximumHistoryRecords = 1000;
  Database? _database;

  Future<Database> get _db async {
    if (_database != null && _database!.isOpen) return _database!;
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, _databaseName);
    _database = await openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) async {
        final result = await db.rawQuery('PRAGMA quick_check');
        final status = result.isEmpty ? '' : result.first.values.first.toString();
        if (status.toLowerCase() != 'ok') {
          throw StateError('Inventory database integrity check failed ($status). The original database was not modified. Preserve a copy before recovery.');
        }
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE devices (device_key TEXT PRIMARY KEY, payload TEXT NOT NULL, updated_at TEXT NOT NULL)');
        await _createHistoryTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createHistoryTable(db);
      },
    );
    return _database!;
  }

  static Future<void> _createHistoryTable(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS operation_history (id INTEGER PRIMARY KEY AUTOINCREMENT, occurred_at TEXT NOT NULL, operation TEXT NOT NULL, target TEXT NOT NULL, outcome TEXT NOT NULL, details TEXT NOT NULL)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_operation_history_id ON operation_history(id DESC)');
  }

  Future<String> get databasePath async => (await _db).path;

  Future<List<CameraDevice>> load() async {
    final rows = await (await _db).query('devices', orderBy: 'updated_at DESC');
    final result = <CameraDevice>[];
    for (final row in rows) {
      try {
        final json = jsonDecode(row['payload']! as String);
        if (json is Map<String, dynamic>) result.add(CameraDevice.fromJson(json));
      } on FormatException {
        // Isolate malformed JSON rows without losing the remaining inventory.
      } on TypeError {
        // Isolate rows with invalid field types.
      }
    }
    return result;
  }

  Future<void> save(List<CameraDevice> devices) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('devices');
      final batch = txn.batch();
      for (final device in devices) {
        final key = device.macAddress.isNotEmpty ? device.macAddress : device.id;
        if (key.isEmpty) continue;
        batch.insert('devices', {'device_key': key, 'payload': jsonEncode(device.toJson()), 'updated_at': DateTime.now().toUtc().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> upsert(CameraDevice device) async => save([
    ...(await load()).where((d) => (d.macAddress.isNotEmpty ? d.macAddress : d.id) != (device.macAddress.isNotEmpty ? device.macAddress : device.id)),
    device,
  ]);

  Future<void> delete(CameraDevice device) async {
    final key = device.macAddress.isNotEmpty ? device.macAddress : device.id;
    await (await _db).delete('devices', where: 'device_key = ?', whereArgs: [key]);
  }

  Future<void> recordOperation({required String operation, String target = '', required String outcome, String details = ''}) async {
    final db = await _db;
    await db.insert('operation_history', {
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'operation': SensitiveDataRedactor.redact(operation, maxLength: 2000),
      'target': SensitiveDataRedactor.redact(target, maxLength: 2000),
      'outcome': SensitiveDataRedactor.redact(outcome, maxLength: 2000),
      'details': SensitiveDataRedactor.redact(details, maxLength: 2000),
    });
    await db.rawDelete('DELETE FROM operation_history WHERE id NOT IN (SELECT id FROM operation_history ORDER BY id DESC LIMIT ?)', [maximumHistoryRecords]);
  }

  Future<List<OperationHistoryEntry>> loadHistory({int limit = 250}) async {
    final rows = await (await _db).query('operation_history', columns: const ['id', 'occurred_at', 'operation', 'target', 'outcome', 'details'], orderBy: 'id DESC', limit: limit.clamp(1, maximumHistoryRecords));
    return rows.map(OperationHistoryEntry.fromMap).toList(growable: false);
  }

  Future<int> deviceCount() async => Sqflite.firstIntValue(await (await _db).rawQuery('SELECT COUNT(*) FROM devices')) ?? 0;

  Future<String> integrityCheck() async {
    final rows = await (await _db).rawQuery('PRAGMA quick_check');
    return rows.isEmpty ? 'No integrity result returned' : rows.first.values.first.toString();
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}