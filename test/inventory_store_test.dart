import 'dart:io';

import 'package:camera_ip_search_mobile/services/inventory_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('oxita-inventory-test-');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('new database passes quick_check and persists bounded operation history', () async {
    final store = InventoryStore(databasePath: '${directory.path}/inventory.sqlite');
    expect(await store.integrityCheck(), 'ok');
    for (var i = 0; i < 1005; i++) {
      await store.recordOperation(
        operation: 'Discovery',
        target: '192.0.2.$i',
        outcome: 'Completed',
        details: 'Test operation $i',
      );
    }
    final history = await store.loadHistory(limit: 250);
    expect(history, hasLength(250));
    expect(history.first.details, 'Test operation 1004');
    expect((await store.loadHistory(limit: 1000)), hasLength(1000));
    await store.close();
  });

  test('upgrades a version-one inventory without dropping devices table', () async {
    final path = '${directory.path}/legacy.sqlite';
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE devices (device_key TEXT PRIMARY KEY, payload TEXT NOT NULL, updated_at TEXT NOT NULL)');
          await db.insert('devices', {
            'device_key': 'legacy-device',
            'payload': '{"id":"legacy-device","ipAddress":"192.0.2.10"}',
            'updated_at': '2026-01-01T00:00:00Z',
          });
        },
      ),
    );
    await legacy.close();

    final store = InventoryStore(databasePath: path);
    expect(await store.integrityCheck(), 'ok');
    final rows = await store.load();
    expect(rows, hasLength(1));
    expect(rows.single.ipAddress, '192.0.2.10');
    await store.recordOperation(operation: 'Migration', outcome: 'Completed');
    expect(await store.loadHistory(), hasLength(1));
    await store.close();
  });

  test('does not overwrite a damaged database file during open', () async {
    final path = '${directory.path}/damaged.sqlite';
    final file = File(path);
    const original = 'not-a-valid-sqlite-database';
    await file.writeAsString(original, flush: true);
    final store = InventoryStore(databasePath: path);
    await expectLater(store.load(), throwsA(anything));
    expect(await file.readAsString(), original);
    await store.close();
  });
}