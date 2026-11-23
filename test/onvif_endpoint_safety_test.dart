import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ip_search_mobile/models/camera_device.dart';
import 'package:camera_ip_search_mobile/services/onvif_device_service.dart';

void main() {
  group('ONVIF endpoint safety', () {
    final service = OnvifDeviceService();

    test('accepts same-host HTTP device service URL', () {
      final device = CameraDevice(
        id: '192.168.1.20',
        ipAddress: '192.168.1.20',
        deviceServiceUrl: 'http://192.168.1.20/onvif/device_service',
        discoverySources: const ['ONVIF WS-Discovery'],
      );
      expect(service.isSafeEndpoint(device), isTrue);
    });

    test('rejects endpoint on a different host', () {
      final device = CameraDevice(
        id: '192.168.1.20',
        ipAddress: '192.168.1.20',
        deviceServiceUrl: 'http://192.168.1.21/onvif/device_service',
      );
      expect(service.isSafeEndpoint(device), isFalse);
    });

    test('rejects embedded credentials, query and fragment', () {
      for (final url in [
        'http://user:pass@192.168.1.20/onvif/device_service',
        'http://192.168.1.20/onvif/device_service?next=example',
        'http://192.168.1.20/onvif/device_service#fragment',
        'ftp://192.168.1.20/onvif/device_service',
      ]) {
        final device = CameraDevice(id: '192.168.1.20', ipAddress: '192.168.1.20', deviceServiceUrl: url);
        expect(service.isSafeEndpoint(device), isFalse, reason: url);
      }
    });
  });
}
