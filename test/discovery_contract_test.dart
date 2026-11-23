import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ip_search_mobile/models/camera_device.dart';

void main() {
  group('Camera device inventory model', () {
    test('round-trips a project camera record', () {
      final device = CameraDevice(
        id: 'AA:BB:CC:DD:EE:01',
        ipAddress: '192.168.1.253',
        macAddress: 'AA:BB:CC:DD:EE:01',
        manufacturer: 'Oxita',
        model: 'NT98566',
        firmwareVersion: 'v1.0.0-rc1',
        activationState: 'Not activated',
        discoverySources: const ['Project UDP 9988'],
        interfaceName: 'wlan0',
      );
      final decoded = CameraDevice.fromJson(jsonDecode(jsonEncode(device.toJson())) as Map<String, dynamic>);
      expect(decoded.ipAddress, device.ipAddress);
      expect(decoded.macAddress, device.macAddress);
      expect(decoded.discoverySources, device.discoverySources);
      expect(decoded.activationState, 'Not activated');
    });

    test('rejects malformed IP addresses in Dart core', () {
      expect(InternetAddress.tryParse('192.168.1.999'), isNull);
      expect(InternetAddress.tryParse('192.168.1.12')?.type, InternetAddressType.IPv4);
    });
  });
}
