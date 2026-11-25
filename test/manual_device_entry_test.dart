import 'package:camera_ip_search_mobile/services/device_discovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual inventory accepts a hostname as desktop does', () async {
    final service = DeviceDiscoveryService();
    await service.addManualDevice('front-gate-camera.local');
    expect(service.devices, hasLength(1));
    expect(service.devices.single.ipAddress, 'front-gate-camera.local');
    service.dispose();
  });

  test('manual inventory rejects URL paths and malformed hostnames', () async {
    final service = DeviceDiscoveryService();
    await expectLater(service.addManualDevice('http://camera.local/path'), throwsFormatException);
    await expectLater(service.addManualDevice('bad host name'), throwsFormatException);
    service.dispose();
  });
}