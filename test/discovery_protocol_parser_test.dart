import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ip_search_mobile/services/device_discovery_service.dart';

void main() {
  late DeviceDiscoveryService service;

  setUp(() => service = DeviceDiscoveryService());
  tearDown(() => service.dispose());

  group('Project Contract B response parser', () {
    String response({int seq = 17, String ip = '192.168.1.40', Object? mac = 'AA:BB:CC:DD:EE:40'}) =>
        jsonEncode({
          'magic': 'CAM_DISCOVER',
          'version': 1,
          'seq': seq,
          'cmd': 'PROBE_RESPONSE',
          'device': {'ipv4': ip, 'mac': mac, 'soc': 'AmebaPro2', 'firmware_version': '1.2.0', 'activated': true},
        });

    test('accepts matching response and binds address to UDP sender', () {
      final device = service.parseProjectResponse(
        response(), 17, InternetAddress('192.168.1.40'), 'wlan0',
      );
      expect(device, isNotNull);
      expect(device!.ipAddress, '192.168.1.40');
      expect(device.macAddress, 'AA:BB:CC:DD:EE:40');
      expect(device.model, 'AmebaPro2');
      expect(device.activationState, 'Activated');
    });

    test('rejects sequence mismatch and sender address spoofing', () {
      expect(service.parseProjectResponse(response(seq: 18), 17, InternetAddress('192.168.1.40'), 'wlan0'), isNull);
      expect(service.parseProjectResponse(response(ip: '192.168.1.99'), 17, InternetAddress('192.168.1.40'), 'wlan0'), isNull);
    });

    test('rejects malformed field types', () {
      expect(service.parseProjectResponse(response(mac: 123), 17, InternetAddress('192.168.1.40'), 'wlan0'), isNull);
    });

    test('supports explicitly unconfigured camera sender fallback', () {
      final device = service.parseProjectResponse(
        response(ip: '192.168.1.50'), 17, InternetAddress('0.0.0.0'), 'eth0',
      );
      expect(device?.ipAddress, '192.168.1.50');
    });
  });

  group('ONVIF ProbeMatch parser', () {
    const xml = '''
      <e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope"
        xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"
        xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing">
        <e:Body><d:ProbeMatches><d:ProbeMatch>
          <wsa:EndpointReference><wsa:Address>urn:uuid:camera-40</wsa:Address></wsa:EndpointReference>
          <d:XAddrs>http://192.168.1.99/foreign http://192.168.1.40/onvif/device_service</d:XAddrs>
          <d:Scopes>onvif://www.onvif.org/manufacturer/Oxita onvif://www.onvif.org/name/Camera%20A</d:Scopes>
        </d:ProbeMatch></d:ProbeMatches></e:Body>
      </e:Envelope>
    ''';

    test('selects a same-host XAddr and decodes identity scopes', () {
      final device = service.parseOnvifResponse(xml, InternetAddress('192.168.1.40'), 'wlan0');
      expect(device, isNotNull);
      expect(device!.deviceServiceUrl, 'http://192.168.1.40/onvif/device_service');
      expect(device.manufacturer, 'Oxita');
      expect(device.model, 'Camera A');
    });

    test('does not accept a foreign-host service endpoint', () {
      const foreign = '<ProbeMatch><Address>urn:uuid:cam</Address><XAddrs>http://192.168.1.99/device</XAddrs></ProbeMatch>';
      final device = service.parseOnvifResponse(foreign, InternetAddress('192.168.1.40'), 'wlan0');
      expect(device, isNotNull);
      expect(device!.deviceServiceUrl, isEmpty);
    });
  });
}
