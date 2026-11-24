import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ip_search_mobile/models/camera_device.dart';
import 'package:camera_ip_search_mobile/services/batch_operation_service.dart';

CameraDevice onvif(String id, String ip) => CameraDevice(
  id: id, ipAddress: ip, deviceServiceUrl: 'http://$ip/onvif/device_service',
  discoverySources: const ['ONVIF WS-Discovery'],
);

void main() {
  group('BatchOperationPreflight', () {
    test('marks ONVIF reads ready and dangerous writes unavailable', () {
      final preflight = const BatchOperationPreflight();
      expect(preflight.build([onvif('cam-a', '192.168.1.10')], DeviceBatchOperation.readDeviceInformation).single.state, BatchTargetState.ready);
      expect(preflight.build([onvif('cam-a', '192.168.1.10')], DeviceBatchOperation.reboot).single.state, BatchTargetState.unsupportedOperation);
    });
    test('marks every duplicate ID and address unsafe', () {
      final results = const BatchOperationPreflight().build([
        onvif('same', '192.168.1.10'), onvif('same', '192.168.1.11'),
        onvif('other', '192.168.1.10'),
      ], DeviceBatchOperation.readDeviceInformation);
      expect(results[0].state, BatchTargetState.duplicateTarget);
      expect(results[1].state, BatchTargetState.duplicateTarget);
      expect(results[2].state, BatchTargetState.duplicateAddress);
    });
    test('runner executes only preflight-approved targets and records failure', () async {
      final runner = BatchOperationRunner();
      var calls = 0;
      final result = await runner.start(
        devices: [onvif('cam-a', '192.168.1.10'), onvif('cam-b', '192.168.1.11')],
        operation: DeviceBatchOperation.reboot,
        handler: (_, __) async { calls++; return null; },
      );
      expect(calls, 0);
      expect(result.every((r) => r.state == BatchTargetState.unsupportedOperation), isTrue);
    });
    test('runner supports cooperative cancellation between devices', () async {
      final runner = BatchOperationRunner();
      var calls = 0;
      final result = await runner.start(
        devices: [onvif('cam-a', '192.168.1.10'), onvif('cam-b', '192.168.1.11')],
        operation: DeviceBatchOperation.readDeviceInformation,
        handler: (_, __) async { calls++; runner.cancel(); return null; },
      );
      expect(calls, 1);
      expect(result[0].state, BatchTargetState.succeeded);
      expect(result[1].state, BatchTargetState.cancelled);
    });
  });
}
