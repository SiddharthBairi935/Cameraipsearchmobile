import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/camera_device.dart';

class InventoryStore {
  static const _databaseName = 'oxita_camera_inventory.db';
  static const _databaseVersion = 1;
  Database? _database;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, _databaseName);
    _database = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE devices (
            device_key TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _database!;
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
        // A malformed row is skipped; the rest of the inventory remains available.
      }
    }
    return result;
  }

  Future<void> save(List<CameraDevice> devices) async {
    final db = await _db;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final device in devices) {
        final key = device.macAddress.isNotEmpty ? device.macAddress : device.id;
        if (key.isEmpty) continue;
        batch.insert('devices', {
          'device_key': key,
          'payload': jsonEncode(device.toJson()),
          'updated_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> upsert(CameraDevice device) async => save([...(await load()).where((d) =>
      (d.macAddress.isNotEmpty ? d.macAddress : d.id) !=
      (device.macAddress.isNotEmpty ? device.macAddress : device.id)), device]);

  Future<void> delete(CameraDevice device) async {
    final key = device.macAddress.isNotEmpty ? device.macAddress : device.id;
    await (await _db).delete('devices', where: 'device_key = ?', whereArgs: [key]);
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
