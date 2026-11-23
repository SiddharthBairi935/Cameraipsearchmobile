import 'dart:async';
import 'dart:io';

import 'package:xml/xml.dart';

import '../models/camera_device.dart';
import 'network_config_validator.dart';

class OnvifDeviceService {
  OnvifDeviceService({this.requestCredentials});

  final Future<OnvifCredentials?> Function(String host, String realm)? requestCredentials;
  final Map<String, OnvifCredentials> _sessionCredentials = {};

  static const _deviceNamespace = 'http://www.onvif.org/ver10/device/wsdl';
  static const _soapNamespace = 'http://www.w3.org/2003/05/soap-envelope';

  bool isSafeEndpoint(CameraDevice device) {
    final uri = Uri.tryParse(device.deviceServiceUrl);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        uri.host == device.ipAddress &&
        uri.userInfo.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty;
  }

  Future<CameraDevice> refresh(CameraDevice device) async {
    if (!isSafeEndpoint(device)) {
      throw const OnvifException('No verified ONVIF service endpoint is available for this device.');
    }
    var updated = device;
    final info = await _post(updated, 'GetDeviceInformation');
    final manufacturer = _text(info, 'Manufacturer');
    final model = _text(info, 'Model');
    final firmware = _text(info, 'FirmwareVersion');
    final serial = _text(info, 'SerialNumber');
    final hardware = _text(info, 'HardwareId');
    updated = updated.copyWith(
      manufacturer: manufacturer.isNotEmpty ? manufacturer : updated.manufacturer,
      model: model.isNotEmpty ? model : updated.model,
      firmwareVersion: firmware.isNotEmpty ? firmware : updated.firmwareVersion,
      serialNumber: serial.isNotEmpty ? serial : updated.serialNumber,
      hardwareId: hardware.isNotEmpty ? hardware : updated.hardwareId,
      discoverySources: _append(updated.discoverySources, 'ONVIF GetDeviceInformation'),
    );

    try {
      final capabilities = await _post(updated, 'GetCapabilities',
          body: '<tds:Category>All</tds:Category>');
      final names = capabilities.descendants
          .whereType<XmlElement>()
          .map((e) => e.name.local)
          .where((name) => const {'Analytics', 'Device', 'Events', 'Imaging', 'Media', 'PTZ', 'Extension'}.contains(name))
          .toSet()
          .toList()
        ..sort();
      updated = updated.copyWith(
        capabilities: names,
        discoverySources: _append(updated.discoverySources, 'ONVIF GetCapabilities'),
      );
    } on OnvifException {
      // Capabilities are optional on some partially compliant cameras.
    }

    try {
      updated = await _refreshNetworkInterfaces(updated);
    } on OnvifException {
      // Keep device information even if this optional query is unsupported.
    }

    try {
      final dns = await _post(updated, 'GetDNS');
      final dnsAddress = _firstText(dns, const {'IPv4Address', 'IPv4'});
      if (dnsAddress.isNotEmpty) {
        updated = updated.copyWith(
          ipv4DnsServer: dnsAddress,
          discoverySources: _append(updated.discoverySources, 'ONVIF GetDNS'),
        );
      }
    } on OnvifException {
      // DNS reporting is optional and must not invalidate other ONVIF data.
    }
    return updated;
  }

  Future<CameraDevice> _refreshNetworkInterfaces(CameraDevice device) async {
    final response = await _post(device, 'GetNetworkInterfaces');
    final responseElement = _firstElement(response, 'GetNetworkInterfacesResponse');
    if (responseElement == null) throw const OnvifException('Incomplete GetNetworkInterfaces response.');

    final interfaces = responseElement.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'NetworkInterface')
        .toList();
    final summaries = <String>[];
    XmlElement? selected;
    String selectedAddress = '';
    String selectedPrefix = '';
    String selectedDhcp = '';
    String selectedGateway = '';
    for (final item in interfaces) {
      final token = item.getAttribute('token') ?? '';
      final name = _text(item, 'Name');
      final mac = _text(item, 'HwAddress');
      final ipv4 = _firstElement(item, 'IPv4');
      final config = ipv4 == null ? null : _firstElement(ipv4, 'Config');
      final dhcp = config == null ? '' : _text(config, 'DHCP');
      final manual = config == null ? null : _firstElement(config, 'Manual');
      final fromDhcp = config == null ? null : _firstElement(config, 'FromDHCP');
      final linkLocal = config == null ? null : _firstElement(config, 'LinkLocal');
      final gateway = config == null ? '' : _text(config, 'IPv4Address');
      final active = dhcp.toLowerCase() == 'true' || dhcp == '1';
      final source = active ? (fromDhcp ?? linkLocal ?? manual) : (manual ?? linkLocal ?? fromDhcp);
      final address = source == null ? '' : _text(source, 'Address');
      final prefix = source == null ? '' : _text(source, 'PrefixLength');
      final chosenGateway = gateway.isNotEmpty ? gateway : _text(config ?? item, 'IPv4Address');
      final summary = [name, address, mac].where((s) => s.isNotEmpty).join(' | ');
      if (summary.isNotEmpty) summaries.add(summary);
      if (selected == null && token.isNotEmpty && address == device.ipAddress) {
        selected = item;
        selectedAddress = address;
        selectedPrefix = prefix;
        selectedDhcp = dhcp;
        selectedGateway = chosenGateway;
      }
    }

    if (selected == null) {
      return device.copyWith(
        networkSummary: summaries.join('; '),
        networkInterfaceToken: '',
        ipv4ConfigurationKnown: false,
        ipv4Address: '',
        ipv4SubnetMask: '',
        ipv4Gateway: '',
        ipv4DhcpEnabled: false,
        discoverySources: _append(device.discoverySources, 'ONVIF GetNetworkInterfaces'),
      );
    }

    final prefix = int.tryParse(selectedPrefix);
    final mask = prefix != null && prefix >= 1 && prefix <= 32
        ? _prefixToMask(prefix) : '';
    final dhcpEnabled = selectedDhcp.toLowerCase() == 'true' || selectedDhcp == '1';
    final known = selectedAddress.isNotEmpty && mask.isNotEmpty &&
        (selectedDhcp.toLowerCase() == 'true' || selectedDhcp.toLowerCase() == 'false' ||
         selectedDhcp == '1' || selectedDhcp == '0');
    return device.copyWith(
      networkSummary: summaries.join('; '),
      networkInterfaceToken: known ? (selected.getAttribute('token') ?? '') : '',
      ipv4Address: selectedAddress,
      ipv4SubnetMask: mask,
      ipv4Gateway: selectedGateway,
      ipv4DhcpEnabled: dhcpEnabled,
      ipv4ConfigurationKnown: known,
      discoverySources: _append(device.discoverySources, 'ONVIF GetNetworkInterfaces'),
    );
  }

  Future<OnvifWriteResult> applyStaticIpv4(
    CameraDevice device, {
    required String address,
    required String subnetMask,
    String gateway = '',
  }) async {
    final validation = NetworkConfigValidator.validateStaticIpv4(
      address: address, subnetMask: subnetMask, gateway: gateway,
    );
    if (validation != null) throw OnvifException(validation);
    if (!isSafeEndpoint(device) || device.networkInterfaceToken.isEmpty ||
        !device.ipv4ConfigurationKnown) {
      throw const OnvifException('A verified ONVIF interface token and current IPv4 configuration are required.');
    }
    final uri = Uri.parse(device.deviceServiceUrl);
    if (uri.host != device.ipAddress) {
      throw const OnvifException('The ONVIF service URL does not match the current camera IP.');
    }
    final prefix = _maskToPrefix(subnetMask);
    final body = '<tds:InterfaceToken>${_xml(device.networkInterfaceToken)}</tds:InterfaceToken>'
        '<tds:NetworkInterface><tt:IPv4><tt:Enabled>true</tt:Enabled><tt:DHCP>false</tt:DHCP>'
        '<tt:Manual><tt:Address>${_xml(address.trim())}</tt:Address><tt:PrefixLength>$prefix</tt:PrefixLength>'
        '</tt:Manual></tt:IPv4></tds:NetworkInterface>';
    final response = await _post(device, 'SetNetworkInterfaces', body: body);
    final reboot = _text(response, 'RebootNeeded').toLowerCase();
    if (reboot != 'true' && reboot != 'false' && reboot != '1' && reboot != '0') {
      throw const OnvifException('Camera did not return a valid SetNetworkInterfaces response.');
    }
    if (reboot == 'true' || reboot == '1') {
      throw const OnvifException('Camera reports that a reboot is required. The app will not reboot it automatically; inventory remains unchanged.');
    }

    final newUri = uri.replace(host: address.trim());
    final verifyDevice = device.copyWith(ipAddress: address.trim(), deviceServiceUrl: newUri.toString());
    final verify = await _post(verifyDevice, 'GetNetworkInterfaces');
    final verified = _verifyInterfaceAddress(verify, device.networkInterfaceToken, address.trim());
    if (!verified) {
      throw const OnvifException('The camera accepted the request, but the new interface address could not be verified. Inventory was not updated.');
    }

    var gatewayApplied = gateway.trim().isEmpty;
    if (gateway.trim().isNotEmpty) {
      try {
        final gatewayResponse = await _post(verifyDevice, 'SetNetworkDefaultGateway',
            body: '<tds:IPv4Address>${_xml(gateway.trim())}</tds:IPv4Address>');
        gatewayApplied = _firstElement(gatewayResponse, 'SetNetworkDefaultGatewayResponse') != null;
      } on OnvifException {
        gatewayApplied = false;
      }
    }
    final updated = verifyDevice.copyWith(
      ipv4Address: address.trim(),
      ipv4SubnetMask: subnetMask.trim(),
      ipv4Gateway: gatewayApplied && gateway.trim().isNotEmpty ? gateway.trim() : device.ipv4Gateway,
      ipv4DhcpEnabled: false,
      ipv4ConfigurationKnown: true,
      discoverySources: _append(device.discoverySources, 'ONVIF GetNetworkInterfaces'),
    );
    return OnvifWriteResult(
      device: updated,
      verified: gatewayApplied,
      message: gatewayApplied
          ? 'Static IPv4 address verified at ${address.trim()}${gateway.trim().isEmpty ? '' : '; gateway was also applied'}.'
          : 'The new IP address was verified, but the gateway change was not confirmed. Inventory now records the new IP and retains the previous gateway.',
    );
  }

  Future<XmlDocument> _post(CameraDevice device, String operation, {String body = ''}) async {
    final uri = Uri.tryParse(device.deviceServiceUrl);
    if (uri == null || !isSafeEndpoint(device)) throw const OnvifException('Unsafe or invalid ONVIF service URL.');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    final cached = _sessionCredentials[uri.host];
    if (cached != null) {
      client.addCredentials(uri, cached.realm, HttpClientBasicCredentials(cached.username, cached.password));
    }
    client.authenticate = (url, scheme, realm) async {
      final credentials = _sessionCredentials[url.host] ??
          await requestCredentials?.call(url.host, realm ?? '');
      if (credentials == null) return false;
      _sessionCredentials[url.host] = credentials;
      client.addCredentials(url, credentials.realm, HttpClientBasicCredentials(credentials.username, credentials.password));
      return true;
    };
    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 5));
      request.followRedirects = false;
      request.headers.contentType = ContentType('application', 'soap+xml', charset: 'utf-8');
      request.write(_envelope(operation, body));
      final response = await request.close().timeout(const Duration(seconds: 5));
      final bytes = await response.fold<List<int>>(<int>[], (all, chunk) {
        if (all.length + chunk.length > 1024 * 1024) throw const OnvifException('ONVIF response exceeds 1 MB.');
        return all..addAll(chunk);
      }).timeout(const Duration(seconds: 5));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OnvifException('ONVIF $operation failed with HTTP ${response.statusCode}. Authentication may be required or the operation may be unsupported.');
      }
      final document = XmlDocument.parse(String.fromCharCodes(bytes));
      if (_firstElement(document, 'Fault') != null) throw OnvifException('Camera returned a SOAP fault for $operation.');
      if (_firstElement(document, '${operation}Response') == null) {
        throw OnvifException('Camera returned an unexpected response for $operation.');
      }
      return document;
    } on TimeoutException {
      throw OnvifException('ONVIF $operation timed out.');
    } on SocketException catch (error) {
      throw OnvifException('ONVIF $operation network error: ${error.message}');
    } on FormatException {
      throw OnvifException('Camera returned malformed XML for $operation.');
    } finally {
      client.close(force: true);
    }
  }

  static String _envelope(String operation, String body) =>
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<s:Envelope xmlns:s="$_soapNamespace" xmlns:tds="$_deviceNamespace" '
      'xmlns:tt="http://www.onvif.org/ver10/schema"><s:Body><tds:$operation>$body</tds:$s:Body></s:Envelope>';

  static XmlElement? _firstElement(XmlNode root, String localName) =>
      root.descendants.whereType<XmlElement>().where((e) => e.name.local == localName).firstOrNull;

  static String _text(XmlNode root, String localName) =>
      _firstElement(root, localName)?.innerText.trim() ?? '';

  static String _firstText(XmlNode root, Set<String> names) {
    for (final element in root.descendants.whereType<XmlElement>()) {
      if (names.contains(element.name.local) && element.innerText.trim().isNotEmpty) {
        return element.innerText.trim();
      }
    }
    return '';
  }

  static List<String> _append(List<String> values, String value) =>
      values.contains(value) ? values : [...values, value];

  static String _xml(String value) => value
      .replaceAll('&', '&amp;').replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;').replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _prefixToMask(int prefix) {
    final value = (0xffffffff << (32 - prefix)) & 0xffffffff;
    return [24, 16, 8, 0].map((shift) => (value >> shift) & 255).join('.');
  }

  static int _maskToPrefix(String mask) {
    final bytes = InternetAddress.tryParse(mask)!.rawAddress;
    var value = 0;
    for (final byte in bytes) value = (value << 8) | byte;
    var count = 0;
    var zeroSeen = false;
    for (var bit = 31; bit >= 0; bit--) {
      final set = (value & (1 << bit)) != 0;
      if (set && zeroSeen) throw const OnvifException('Subnet mask bits must be contiguous.');
      if (set) { count++; } else { zeroSeen = true; }
    }
    return count;
  }

  static bool _verifyInterfaceAddress(XmlDocument doc, String token, String address) {
    for (final item in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'NetworkInterface')) {
      if ((item.getAttribute('token') ?? '') != token) continue;
      final actual = _firstText(item, {'Address', 'IPv4Address'});
      return actual == address;
    }
    return false;
  }
}

class OnvifCredentials {
  const OnvifCredentials(this.username, this.password, {this.realm = ''});
  final String username, password, realm;
}

class OnvifWriteResult {
  const OnvifWriteResult({required this.device, required this.verified, required this.message});
  final CameraDevice device;
  final bool verified;
  final String message;
}

class OnvifException implements Exception {
  const OnvifException(this.message);
  final String message;
  @override
  String toString() => message;
}
