import 'dart:io';

import 'package:camera_ip_search_mobile/models/operation_history_entry.dart';
import 'package:camera_ip_search_mobile/services/diagnostics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('oxita-diagnostics-test-');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('rotates oversized logs and retains the previous log', () async {
    final service = DiagnosticsService(logDirectory: Directory('${root.path}/logs'));
    await service.log('info', 'x' * (DiagnosticsService.maxLogBytes + 64));
    await service.log('info', 'second log entry');
    final current = File('${root.path}/logs/application.log');
    final archive = File('${root.path}/logs/application.log.1');
    expect(await current.exists(), isTrue);
    expect(await archive.exists(), isTrue);
    expect(await current.readAsString(), contains('second log entry'));
    expect(await archive.length(), greaterThan(DiagnosticsService.maxLogBytes));
  });

  test('support bundle redacts secrets and excludes interface tokens', () async {
    final service = DiagnosticsService(logDirectory: Directory('${root.path}/logs'));
    await service.log('warning', 'password=hunter2 Authorization: Bearer abc123');
    final bundle = await service.buildSupportBundle(
      deviceCount: 3,
      history: [
        OperationHistoryEntry(
          id: 1,
          occurredAt: DateTime.utc(2026, 1, 1),
          operation: 'Static IPv4',
          target: '192.0.2.10',
          outcome: 'Failed',
          details: 'token=secret-token interface-token=ONVIF-IF-1',
        ),
      ],
    );
    expect(bundle, contains('Saved devices: 3'));
    expect(bundle, isNot(contains('hunter2')));
    expect(bundle, isNot(contains('abc123')));
    expect(bundle, isNot(contains('secret-token')));
    expect(bundle, isNot(contains('ONVIF-IF-1')));
    expect(bundle, contains('inventory database'));
  });
}