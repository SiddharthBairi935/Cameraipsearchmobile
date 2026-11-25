import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ip_search_mobile/models/camera_device.dart';
import 'package:camera_ip_search_mobile/services/device_classifier.dart';

void main() {
  test('ONVIF identity is a verified camera', () {
    final result = DeviceClassifier.classify(const CameraDevice(
      id:'192.0.2.10', ipAddress:'192.0.2.10',
      discoverySources:['ONVIF WS-Discovery'],
    ));
    expect(result.key, 'camera');
    expect(result.confidenceLabel, 'Verified');
  });
  test('explicit NVR descriptor takes precedence', () {
    final result = DeviceClassifier.classify(const CameraDevice(
      id:'192.0.2.11', ipAddress:'192.0.2.11', model:'NVR-8208-PoE',
    ));
    expect(result.key, 'nvr');
    expect(result.confidenceLabel, 'High');
  });
  test('SSDP Internet Gateway Device is a router', () {
    final result = DeviceClassifier.classify(const CameraDevice(
      id:'192.0.2.1', ipAddress:'192.0.2.1',
      model:'urn:schemas-upnp-org:device:InternetGatewayDevice:1',
      discoverySources:['SSDP/UPnP'],
    ));
    expect(result.key, 'router');
  });
  test('multiple printer ports are probable, not verified', () {
    final result = DeviceClassifier.classify(const CameraDevice(
      id:'192.0.2.20', ipAddress:'192.0.2.20',
      isCandidate:true, openPorts:[9100,631],
    ));
    expect(result.key, 'printer');
    expect(result.confidenceLabel, 'Probable');
  });
  test('generic web port does not imply camera', () {
    final result = DeviceClassifier.classify(const CameraDevice(
      id:'192.0.2.30', ipAddress:'192.0.2.30',
      isCandidate:true, openPorts:[80],
    ));
    expect(result.key, 'unknown');
  });
}
