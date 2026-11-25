import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ip_search_mobile/services/ssdp_discovery_parser.dart';

void main() {
  test('parses UPnP gateway response using sender address only', () {
    final payload = ascii.encode('HTTP/1.1 200 OK\\r\\nST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\\r\\nUSN: uuid:gw-1\\r\\nLOCATION: http://192.0.2.1/root.xml\\r\\n\\r\\n');
    final device = SsdpDiscoveryParser.parseResponse(payload, InternetAddress('192.0.2.1'), 'wlan0');
    expect(device, isNotNull);
    expect(device!.ipAddress, '192.0.2.1');
    expect(device.discoverySources, contains('SSDP/UPnP'));
    expect(device.model, contains('InternetGatewayDevice'));
    expect(device.isCandidate, isTrue);
  });
  test('rejects non-200 response and missing identity', () {
    expect(SsdpDiscoveryParser.parseResponse(ascii.encode('HTTP/1.1 404 Not Found\\r\\nST: x\\r\\n'), InternetAddress('192.0.2.2'), 'wlan0'), isNull);
    expect(SsdpDiscoveryParser.parseResponse(ascii.encode('HTTP/1.1 200 OK\\r\\nCACHE-CONTROL: max-age=10\\r\\n'), InternetAddress('192.0.2.2'), 'wlan0'), isNull);
  });
  test('rejects oversized and loopback responses', () {
    expect(SsdpDiscoveryParser.parseResponse(List<int>.filled(16*1024+1, 120), InternetAddress('192.0.2.3'), 'wlan0'), isNull);
    expect(SsdpDiscoveryParser.parseResponse(ascii.encode('HTTP/1.1 200 OK\\r\\nST: x\\r\\n'), InternetAddress('127.0.0.1'), 'lo'), isNull);
  });
}
