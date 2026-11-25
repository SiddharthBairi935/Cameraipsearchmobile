import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ip_search_mobile/services/network_config_validator.dart';

void main() {
  group('NetworkConfigValidator', () {
    test('accepts valid static IPv4 configuration', () {
      expect(NetworkConfigValidator.validateStaticIpv4(
        address: '192.168.1.50',
        subnetMask: '255.255.255.0',
        gateway: '192.168.1.1',
        dnsServer: '1.1.1.1',
      ), isNull);
    });

    test('rejects invalid device address', () {
      expect(NetworkConfigValidator.validateStaticIpv4(
        address: '192.168.1.999',
        subnetMask: '255.255.255.0',
      ), isNotNull);
    });

    test('rejects non-contiguous subnet mask', () {
      expect(NetworkConfigValidator.validateStaticIpv4(
        address: '192.168.1.50',
        subnetMask: '255.0.255.0',
      ), contains('contiguous'));
    });

    test('rejects gateway outside subnet', () {
      expect(NetworkConfigValidator.validateStaticIpv4(
        address: '192.168.1.50',
        subnetMask: '255.255.255.0',
        gateway: '192.168.2.1',
      ), contains('same subnet'));
    });

    test('rejects unspecified and limited-broadcast addresses', () {
      expect(NetworkConfigValidator.validateStaticIpv4(
        address: '0.0.0.0', subnetMask: '255.255.255.0',
      ), isNotNull);
      expect(NetworkConfigValidator.validateStaticIpv4(
        address: '255.255.255.255', subnetMask: '255.255.255.0',
      ), isNotNull);
    });

    test('rejects network and broadcast host addresses', () {
      expect(NetworkConfigValidator.validateStaticIpv4(
        address: '192.168.1.0', subnetMask: '255.255.255.0',
      ), contains('network or broadcast'));
      expect(NetworkConfigValidator.validateStaticIpv4(
        address: '192.168.1.255', subnetMask: '255.255.255.0',
      ), contains('network or broadcast'));
    });

    test('allows omitted gateway and DNS', () {
      expect(NetworkConfigValidator.validateStaticIpv4(
        address: '10.0.0.12',
        subnetMask: '255.255.255.0',
      ), isNull);
    });
  });
}
