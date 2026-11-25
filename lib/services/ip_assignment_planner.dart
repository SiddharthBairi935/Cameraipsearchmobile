import 'dart:io';

class IpAssignmentTarget {
  const IpAssignmentTarget({
    required this.deviceId,
    required this.currentAddress,
    this.proposedAddress = '',
  });

  final String deviceId;
  final String currentAddress;
  final String proposedAddress;

  IpAssignmentTarget withAddress(String value) => IpAssignmentTarget(
    deviceId: deviceId,
    currentAddress: currentAddress,
    proposedAddress: value,
  );
}

class IpAssignmentPlan {
  const IpAssignmentPlan({required this.targets, required this.start, required this.end, required this.subnetMask});
  final List<IpAssignmentTarget> targets;
  final String start;
  final String end;
  final String subnetMask;
}

class IpAssignmentPlanner {
  const IpAssignmentPlanner._();

  static IpAssignmentPlan build({
    required String startAddress,
    required String endAddress,
    required String subnetMask,
    required List<IpAssignmentTarget> selectedDevices,
    Set<String> reservedAddresses = const {},
    int maximumRangeAddresses = 65536,
  }) {
    if (selectedDevices.isEmpty || selectedDevices.length > 256) {
      throw const FormatException('Select between 1 and 256 devices.');
    }
    final ids = <String>{};
    final reserved = <int>{};
    for (final value in reservedAddresses) {
      final parsed = _ipv4(value);
      if (parsed == null) throw const FormatException('Reserved address list contains an invalid IPv4 address.');
      reserved.add(parsed);
    }
    for (final device in selectedDevices) {
      final id = device.deviceId.trim();
      if (id.isEmpty || !ids.add(id)) {
        throw const FormatException('Every selected device must have a non-empty, unique inventory ID.');
      }
      if (device.currentAddress.trim().isNotEmpty) {
        final current = _ipv4(device.currentAddress);
        if (current == null) throw const FormatException('A selected device has an invalid current IPv4 address.');
        reserved.add(current);
      }
    }

    final start = _ipv4(startAddress);
    final end = _ipv4(endAddress);
    final mask = _ipv4(subnetMask);
    if (start == null || end == null || mask == null) {
      throw const FormatException('Start, end and subnet mask must be valid IPv4 values.');
    }
    if (mask == 0 || mask == 0xffffffff || !_isContiguousMask(mask)) {
      throw const FormatException('Subnet mask must be a valid contiguous IPv4 mask.');
    }
    if (start > end) throw const FormatException('Range start must not be greater than range end.');
    if (end - start + 1 > maximumRangeAddresses) {
      throw FormatException('Assignment range exceeds the mobile safety limit of $maximumRangeAddresses addresses.');
    }
    final network = start & mask;
    final broadcast = network | (~mask & 0xffffffff);
    if ((end & mask) != network) {
      throw const FormatException('The complete assignment range must stay within one subnet.');
    }
    if (start <= network || end >= broadcast) {
      throw const FormatException('Network and broadcast addresses cannot be assigned.');
    }

    final planned = <String>[];
    for (var value = start; value <= end && planned.length < selectedDevices.length; value++) {
      if (!reserved.contains(value)) planned.add(_formatIpv4(value));
    }
    if (planned.length != selectedDevices.length) {
      throw FormatException('Range has only ${planned.length} free address(es); ${selectedDevices.length} required.');
    }
    return IpAssignmentPlan(
      start: _formatIpv4(start), end: _formatIpv4(end), subnetMask: _formatIpv4(mask),
      targets: List.unmodifiable(List.generate(selectedDevices.length,
        (index) => selectedDevices[index].withAddress(planned[index]))),
    );
  }

  static int? _ipv4(String value) {
    final parsed = InternetAddress.tryParse(value.trim());
    if (parsed == null || parsed.type != InternetAddressType.IPv4) return null;
    final bytes = parsed.rawAddress;
    return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  }

  static bool _isContiguousMask(int mask) {
    final inverse = (~mask) & 0xffffffff;
    return (inverse & (inverse + 1)) == 0;
  }

  static String _formatIpv4(int value) =>
      '${(value >> 24) & 255}.${(value >> 16) & 255}.${(value >> 8) & 255}.${value & 255}';
}
