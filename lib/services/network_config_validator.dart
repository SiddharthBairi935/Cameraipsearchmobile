import 'dart:io';

class NetworkConfigValidator {
  const NetworkConfigValidator._();

  static String? validateStaticIpv4({
    required String address,
    required String subnetMask,
    String gateway = '',
    String dnsServer = '',
  }) {
    final ip = _parseUnicast(address);
    if (ip == null) return 'Enter a valid unicast IPv4 address.';
    final mask = _parseUnicast(subnetMask);
    if (mask == null) return 'Enter a valid IPv4 subnet mask.';
    final maskValue = _toInt(mask);
    if (maskValue == 0 || maskValue == 0xffffffff) return 'Subnet mask is not valid.';
    final inverse = (~maskValue) & 0xffffffff;
    if ((inverse & (inverse + 1)) != 0) return 'Subnet mask bits must be contiguous.';
    final ipValue = _toInt(ip);
    final network = ipValue & maskValue;
    final broadcast = network | inverse;
    if (ipValue == network || ipValue == broadcast) {
      return 'Device address cannot be the network or broadcast address.';
    }

    if (gateway.trim().isNotEmpty) {
      final gatewayBytes = _parseUnicast(gateway);
      if (gatewayBytes == null) return 'Enter a valid unicast IPv4 gateway.';
      final gatewayValue = _toInt(gatewayBytes);
      if ((gatewayValue & maskValue) != network ||
          gatewayValue == network ||
          gatewayValue == broadcast) {
        return 'Gateway must be a usable address in the same subnet.';
      }
      if (gatewayValue == ipValue) return 'Gateway and device address must be different.';
    }
    if (dnsServer.trim().isNotEmpty && _parseUnicast(dnsServer) == null) {
      return 'Enter a valid unicast IPv4 DNS server.';
    }
    return null;
  }

  static List<int>? _parseUnicast(String value) {
    final parsed = InternetAddress.tryParse(value.trim());
    if (parsed == null ||
        parsed.type != InternetAddressType.IPv4 ||
        parsed.isLoopback ||
        parsed.isMulticast ||
        parsed.isLinkLocal ||
        parsed.address == '0.0.0.0') return null;
    return parsed.rawAddress;
  }

  static int _toInt(List<int> bytes) =>
      (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
}

