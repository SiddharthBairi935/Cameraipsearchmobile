import 'dart:convert';
import 'dart:io';
import '../models/camera_device.dart';

class SsdpDiscoveryParser {
  const SsdpDiscoveryParser._();

  static CameraDevice? parseResponse(List<int> payload, InternetAddress sender, String interfaceName) {
    if (payload.isEmpty || payload.length > 16 * 1024 ||
        sender.type != InternetAddressType.IPv4 || sender.isLoopback ||
        sender.isMulticast || sender.address == '0.0.0.0') {
      return null;
    }
    final text = latin1.decode(payload, allowInvalid: true);
    final lines = text.split(RegExp(r'\r?\n'));
    if (lines.isEmpty ||
        !RegExp(r'^HTTP/1\.[01] 200(?: |$)', caseSensitive: false).hasMatch(lines.first.trim())) {
      return null;
    }
    final headers = <String, String>{};
    for (final line in lines.skip(1).take(128)) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim().toLowerCase();
      if (key.isEmpty || headers.containsKey(key)) continue;
      final value = line.substring(separator + 1).trim();
      headers[key] = value.length > 2048 ? value.substring(0, 2048) : value;
    }
    final st = headers['st'] ?? '';
    final usn = headers['usn'] ?? '';
    final server = headers['server'] ?? '';
    if (st.isEmpty && usn.isEmpty && server.isEmpty) return null;
    // LOCATION is deliberately treated as untrusted metadata and never fetched.
    return CameraDevice(
      id: sender.address,
      ipAddress: sender.address,
      manufacturer: 'Unknown',
      model: st.isNotEmpty ? st : server,
      hardwareId: usn.length > 256 ? usn.substring(0, 256) : usn,
      userLabel: 'UPnP network device',
      activationState: 'Unknown',
      discoverySources: const ['SSDP/UPnP'],
      interfaceName: interfaceName,
      isCandidate: true,
      lastSeen: DateTime.now(),
    );
  }
}
