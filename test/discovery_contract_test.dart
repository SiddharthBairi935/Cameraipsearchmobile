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
        userLabel: 'Front gate',
        serialNumber: 'SERIAL-01',
        hardwareId: 'HW-01',
        capabilities: const ['Device', 'Media'],
        networkSummary: 'eth0 | 192.168.1.253',
        networkInterfaceToken: 'if-1',
        ipv4Address: '192.168.1.253',
        ipv4SubnetMask: '255.255.255.0',
        ipv4Gateway: '192.168.1.1',
        ipv4DnsServer: '1.1.1.1',
        ipv4DhcpEnabled: true,
        ipv4ConfigurationKnown: true,
        openPorts: const [80, 554],
        reachabilityStatus: 'Reachable',
        reachabilityCheckedAt: '2026-11-23T10:00:00Z',
        lastSuccessfulResponseAt: '2026-11-23T10:00:00Z',
      );
      final decoded = CameraDevice.fromJson(jsonDecode(jsonEncode(device.toJson())) as Map<String, dynamic>);
      expect(decoded.ipAddress, device.ipAddress);
      expect(decoded.macAddress, device.macAddress);
      expect(decoded.discoverySources, device.discoverySources);
      expect(decoded.activationState, 'Not activated');
      expect(decoded.userLabel, 'Front gate');
      expect(decoded.serialNumber, 'SERIAL-01');
      expect(decoded.capabilities, ['Device', 'Media']);
      expect(decoded.networkInterfaceToken, 'if-1');
      expect(decoded.ipv4ConfigurationKnown, isTrue);
      expect(decoded.openPorts, [80, 554]);
      expect(decoded.reachabilityStatus, 'Reachable');
    });

    test('rejects malformed IP addresses in Dart core', () {
      expect(InternetAddress.tryParse('192.168.1.999'), isNull);
      expect(InternetAddress.tryParse('192.168.1.12')?.type, InternetAddressType.IPv4);
    });
  });
}
