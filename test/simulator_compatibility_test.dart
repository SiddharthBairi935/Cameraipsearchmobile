import 'dart:io';

import 'package:camera_ip_search_mobile/services/device_discovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/camera_simulator_fixtures.dart';

void main() {
  group('Desktop simulator protocol fixtures', () {
    final parser = DeviceDiscoveryService();

    test('accepts valid Contract B response bound to UDP sender', () {
      final device = parser.parseProjectResponse(
        CameraSimulatorFixtures.contractB(),
        CameraSimulatorFixtures.sequence,
        InternetAddress(CameraSimulatorFixtures.sender),
        'test0',
      );
      expect(device, isNotNull);
      expect(device!.manufacturer, 'Oxita');
      expect(device.macAddress, '02:00:00:00:00:01');
      expect(device.firmwareVersion, 'sim-1.0.0');
    });

    test('rejects malformed JSON and stale sequence', () {
      for (final payload in [
        CameraSimulatorFixtures.contractB(scenario: 'malformed-json'),
        CameraSimulatorFixtures.contractB(scenario: 'wrong-sequence'),
      ]) {
        expect(
          parser.parseProjectResponse(payload, CameraSimulatorFixtures.sequence,
            InternetAddress(CameraSimulatorFixtures.sender), 'test0'),
          isNull,
        );
      }
    });

    test('rejects invalid port and advertised source mismatch', () {
      for (final payload in [
        CameraSimulatorFixtures.contractB(scenario: 'invalid-port'),
        CameraSimulatorFixtures.contractB(scenario: 'advertised-mismatch'),
      ]) {
        expect(
          parser.parseProjectResponse(payload, CameraSimulatorFixtures.sequence,
            InternetAddress(CameraSimulatorFixtures.sender), 'test0'),
          isNull,
        );
      }
    });

    test('allows missing MAC as a valid non-identity fixture', () {
      final device = parser.parseProjectResponse(
        CameraSimulatorFixtures.contractB(scenario: 'missing-mac', includeMac: false),
        CameraSimulatorFixtures.sequence,
        InternetAddress(CameraSimulatorFixtures.sender),
        'test0',
      );
      expect(device, isNotNull);
      expect(device!.macAddress, isEmpty);
    });

    test('selects safe same-host XAddr after a wrong-host candidate', () {
      final device = parser.parseOnvifResponse(
        CameraSimulatorFixtures.onvifProbeMatch(scenario: 'multiple-xaddrs'),
        InternetAddress(CameraSimulatorFixtures.sender),
        'test0',
      );
      expect(device, isNotNull);
      expect(device!.manufacturer, 'Oxita');
      expect(device.deviceServiceUrl, 'http://192.0.2.50:18080/onvif/device_service');
    });

    test('rejects unsafe XAddr containing credentials and query parameters', () {
      final device = parser.parseOnvifResponse(
        CameraSimulatorFixtures.onvifProbeMatch(scenario: 'unsafe-xaddr'),
        InternetAddress(CameraSimulatorFixtures.sender),
        'test0',
      );
      expect(device, isNotNull);
      expect(device!.deviceServiceUrl, isEmpty);
    });
  });
}