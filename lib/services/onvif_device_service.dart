import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'package:xml/xml.dart';

import '../models/camera_device.dart';
import 'network_config_validator.dart';
import 'onvif_wsse.dart';

class OnvifDeviceService {
  OnvifDeviceService({this.requestCredentials});

  final Future<OnvifCredentials?> Function(String host, String realm, String scheme)? requestCredentials;
  final Map<String, OnvifCredentials> _sessionCredentials = {};
  final Map<String, int> _digestNonceCounts = {};
  final Set<HttpClient> _activeClients = {};

  void cancelActive() {
    for (final client in _activeClients.toList()) { client.close(force: true); }
    _activeClients.clear();
  }

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
      final manualDns = _firstElement(dns, 'DNSManual');
      final dhcpDns = _firstElement(dns, 'DNSFromDHCP');
      final manualDnsAddress = manualDns == null ? '' : _text(manualDns, 'IPv4Address');
      final dhcpDnsAddress = dhcpDns == null ? '' : _text(dhcpDns, 'IPv4Address');
      final dnsAddress = manualDnsAddress.isNotEmpty ? manualDnsAddress : dhcpDnsAddress;
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
        .where((e) => e.name.local == 'NetworkInterface' || e.name.local == 'NetworkInterfaces')
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
      final manualAddress = manual == null ? '' : _text(manual, 'Address');
      final dhcpAddress = fromDhcp == null ? '' : _text(fromDhcp, 'Address');
      final linkLocalAddress = linkLocal == null ? '' : _text(linkLocal, 'Address');
      final manualPrefix = manual == null ? '' : _text(manual, 'PrefixLength');
      final dhcpPrefix = fromDhcp == null ? '' : _text(fromDhcp, 'PrefixLength');
      final linkLocalPrefix = linkLocal == null ? '' : _text(linkLocal, 'PrefixLength');
      final gatewayElement = config == null ? null : _firstElement(config, 'Gateway');
      final chosenGateway = gatewayElement == null ? '' : _text(gatewayElement, 'IPv4Address');
      final active = dhcp.toLowerCase() == 'true' || dhcp == '1';
      final address = active
          ? (dhcpAddress.isNotEmpty ? dhcpAddress : (linkLocalAddress.isNotEmpty ? linkLocalAddress : manualAddress))
          : (manualAddress.isNotEmpty ? manualAddress : (linkLocalAddress.isNotEmpty ? linkLocalAddress : dhcpAddress));
      final prefix = active
          ? (dhcpPrefix.isNotEmpty ? dhcpPrefix : (linkLocalPrefix.isNotEmpty ? linkLocalPrefix : manualPrefix))
          : (manualPrefix.isNotEmpty ? manualPrefix : (linkLocalPrefix.isNotEmpty ? linkLocalPrefix : dhcpPrefix));
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

  Future<OnvifWriteResult> setDhcp(CameraDevice device, {required bool enabled}) async {
    if (!isSafeEndpoint(device) || !device.ipv4ConfigurationKnown ||
        device.networkInterfaceToken.isEmpty) {
      throw const OnvifException('A verified ONVIF interface token and current IPv4 profile are required.');
    }
    final body = '<tds:InterfaceToken>${_xml(device.networkInterfaceToken)}</tds:InterfaceToken>'
        '<tds:NetworkInterface><tt:IPv4><tt:Enabled>true</tt:Enabled>'
        '<tt:Config><tt:DHCP>${enabled ? 'true' : 'false'}</tt:DHCP></tt:Config>'
        '</tt:IPv4></tds:NetworkInterface>';
    final response = await _post(device, 'SetNetworkInterfaces', body: body);
    final reboot = _text(response, 'RebootNeeded').toLowerCase();
    if (!const {'true', 'false', '1', '0'}.contains(reboot)) {
      throw const OnvifException('Camera did not return a valid DHCP configuration response.');
    }
    if (reboot == 'true' || reboot == '1') {
      return OnvifWriteResult(device: device, verified: false,
        message: 'Camera accepted the DHCP change but reports that a reboot is required. No reboot was sent; refresh after the camera restarts.');
    }
    final refreshed = await _refreshNetworkInterfaces(device);
    if (!refreshed.ipv4ConfigurationKnown || refreshed.ipv4DhcpEnabled != enabled) {
      throw const OnvifException('Camera accepted the DHCP request, but read-back verification did not confirm the requested state. Inventory was not changed.');
    }
    return OnvifWriteResult(device: refreshed, verified: true,
      message: 'DHCP state verified as ${enabled ? 'enabled' : 'disabled'} on interface ${device.networkInterfaceToken}.');
  }

  Future<OnvifWriteResult> setDns(CameraDevice device, {required bool fromDhcp, List<String> servers = const []}) async {
    if (!isSafeEndpoint(device)) throw const OnvifException('A verified ONVIF endpoint is required.');
    final normalized = servers.map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
    if (fromDhcp && normalized.isNotEmpty) {
      throw const OnvifException('Do not supply manual DNS servers when selecting DHCP-provided DNS.');
    }
    if (!fromDhcp && (normalized.isEmpty || normalized.length > 2 ||
        normalized.any((v) { final ip = InternetAddress.tryParse(v); return ip == null || ip.type != InternetAddressType.IPv4; }))) {
      throw const OnvifException('Enter one or two valid IPv4 DNS server addresses.');
    }
    final dnsXml = normalized.map((ip) =>
      '<tds:DNSManual><tt:Type>IPv4</tt:Type><tt:IPv4Address>${_xml(ip)}</tt:IPv4Address></tds:DNSManual>').join();
    final body = '<tds:FromDHCP>${fromDhcp ? 'true' : 'false'}</tds:FromDHCP>$dnsXml';
    await _post(device, 'SetDNS', body: body);
    final verify = await _post(device, 'GetDNS');
    final fromDhcpElement = _firstElement(verify, 'FromDHCP');
    final dhcpState = fromDhcpElement?.innerText.trim().toLowerCase();
    final manual = verify.descendants.whereType<XmlElement>()
        .where((e) => e.name.local == 'DNSManual')
        .map((e) => _text(e, 'IPv4Address')).where((v) => v.isNotEmpty).toList();
    final dhcp = verify.descendants.whereType<XmlElement>()
        .where((e) => e.name.local == 'DNSFromDHCP')
        .map((e) => _text(e, 'IPv4Address')).where((v) => v.isNotEmpty).toList();
    final actual = fromDhcp ? dhcp : manual;
    final verified = (dhcpState == 'true' || dhcpState == '1') == fromDhcp &&
        (fromDhcp || normalized.every(actual.contains));
    if (!verified) throw const OnvifException('Camera accepted the DNS request, but read-back verification did not match. Inventory was not changed.');
    final updated = device.copyWith(
      ipv4DnsServer: actual.isEmpty ? '' : actual.first,
      discoverySources: _append(device.discoverySources, 'ONVIF GetDNS'),
    );
    return OnvifWriteResult(device: updated, verified: true,
      message: fromDhcp ? 'DHCP-provided DNS mode verified.' : 'Manual DNS server(s) verified: ${normalized.join(', ')}.');
  }

  Future<String> reboot(CameraDevice device) async {
    if (!isSafeEndpoint(device) ||
        !(device.discoverySources.any((source) => source.startsWith('ONVIF')) || device.onvifEndpoint.isNotEmpty)) {
      throw const OnvifException('Reboot requires a verified ONVIF device-service endpoint.');
    }
    await _post(device, 'SystemReboot');
    return 'Camera accepted the ONVIF reboot request. Connectivity will be interrupted; rediscover the camera after it restarts.';
  }

  Future<String> factoryReset(CameraDevice device, {required String factoryDefaultType}) async {
    final mode = factoryDefaultType.trim();
    if (mode != 'Soft' && mode != 'Hard') {
      throw const OnvifException('Choose a supported ONVIF factory-default mode.');
    }
    if (!isSafeEndpoint(device) ||
        !(device.discoverySources.any((source) => source.startsWith('ONVIF')) ||
          device.onvifEndpoint.isNotEmpty)) {
      throw const OnvifException('Factory reset requires a verified ONVIF device-service endpoint.');
    }
    await _post(
      device,
      'SetSystemFactoryDefault',
      body: '<tds:FactoryDefault>${_xml(mode)}</tds:FactoryDefault>',
    );
    return 'The camera accepted the ONVIF $mode factory-default request. It may reboot, erase settings and change its IP address. Rediscover the camera before further configuration.';
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
    _activeClients.add(client);
    try {
      String? authorization;
      var response = await _sendSoap(client, uri, operation, body);
      if (response.statusCode == HttpStatus.unauthorized) {
        final challenges = response.headers[HttpHeaders.wwwAuthenticateHeader] ?? const <String>[];
        await response.drain<void>();
        final challenge = _selectChallenge(challenges);
        if (challenge == null) throw const OnvifException('Camera requested an unsupported HTTP authentication scheme.');
        final scheme = challenge.substring(0, challenge.indexOf(' ')).toLowerCase();
        final parameters = _parseAuthParameters(challenge);
        final realm = parameters['realm'] ?? '';
        final credentials = _sessionCredentials[uri.host] ??
            await requestCredentials?.call(uri.host, realm, scheme);
        if (credentials == null) {
          throw const OnvifException('Camera authentication was cancelled. No credentials were stored.');
        }
        _sessionCredentials[uri.host] = credentials;
        authorization = _authorizationHeader(
          uri: uri, method: 'POST', scheme: scheme, challenge: parameters, credentials: credentials,
        );
        response = await _sendSoap(client, uri, operation, body, authorization: authorization);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw OnvifException('ONVIF $operation failed with HTTP ${response.statusCode}. Authentication may be required or the operation may be unsupported.');
      }
      final bytes = await response.fold<List<int>>(<int>[], (all, chunk) {
        if (all.length + chunk.length > 1024 * 1024) throw const OnvifException('ONVIF response exceeds 1 MB.');
        return all..addAll(chunk);
      }).timeout(const Duration(seconds: 10));
      var document = XmlDocument.parse(utf8.decode(bytes));
      if (_firstElement(document, 'Fault') != null && _isAuthenticationFault(document)) {
        final credentials = _sessionCredentials[uri.host] ??
            await requestCredentials?.call(uri.host, 'ONVIF WS-Security', 'wsse');
        if (credentials != null) {
          _sessionCredentials[uri.host] = credentials;
          response = await _sendSoap(client, uri, operation, body,
              authorization: authorization, wsseCredentials: credentials);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            await response.drain<void>();
            throw OnvifException('ONVIF $operation WS-Security retry failed with HTTP ${response.statusCode}.');
          }
          final retryBytes = await response.fold<List<int>>(<int>[], (all, chunk) {
            if (all.length + chunk.length > 1024 * 1024) throw const OnvifException('ONVIF response exceeds 1 MB.');
            return all..addAll(chunk);
          }).timeout(const Duration(seconds: 10));
          document = XmlDocument.parse(utf8.decode(retryBytes));
        }
      }
      if (_firstElement(document, 'Fault') != null) throw OnvifException('Camera returned a SOAP fault for $operation.');
      if (_firstElement(document, '${operation}Response') == null) {
        throw OnvifException('Camera returned an unexpected response for $operation.');
      }
      return document;
    } on TimeoutException {
      throw OnvifException('ONVIF $operation timed out.');
    } on SocketException catch (error) {
      throw OnvifException('ONVIF $operation network error: ${error.message}');
    } on HttpException catch (error) {
      throw OnvifException('ONVIF $operation HTTP transport error: ${error.message}');
    } on FormatException {
      throw OnvifException('Camera returned malformed XML for $operation.');
    } on OnvifException {
      rethrow;
    } on Exception catch (error) {
      throw OnvifException('Could not parse ONVIF $operation response: $error');
    } finally {
      _activeClients.remove(client);
      client.close(force: true);
    }
  }

  Future<HttpClientResponse> _sendSoap(
    HttpClient client, Uri uri, String operation, String body,
    {String? authorization, OnvifCredentials? wsseCredentials}
  ) async {
    final request = await client.postUrl(uri).timeout(const Duration(seconds: 5));
    request.followRedirects = false;
    request.headers.contentType = ContentType('application', 'soap+xml', charset: 'utf-8');
    if (authorization != null) request.headers.set(HttpHeaders.authorizationHeader, authorization);
    var envelope = _envelope(operation, body);
    if (wsseCredentials != null) {
      final nonce = List<int>.generate(20, (_) => math.Random.secure().nextInt(256));
      final created = DateTime.now().toUtc().toIso8601String();
      envelope = OnvifWsse.addUsernameToken(envelope, username: wsseCredentials.username,
          password: wsseCredentials.password, nonce: nonce, createdUtc: created);
    }
    request.write(envelope);
    return request.close().timeout(const Duration(seconds: 45));
  }

  static bool _isAuthenticationFault(XmlDocument document) {
    final fault = _firstElement(document, 'Fault');
    if (fault == null) return false;
    final detail = fault.innerText.toLowerCase();
    return detail.contains('notauthorized') || detail.contains('failedauthentication') ||
        detail.contains('invalidsecurity') || detail.contains('securitytoken') ||
        detail.contains('authentication') || detail.contains('username');
  }

  static String? _selectChallenge(List<String> challenges) {
    for (final challenge in challenges) {
      if (challenge.trimLeft().toLowerCase().startsWith('digest ')) return challenge.trim();
    }
    for (final challenge in challenges) {
      if (challenge.trimLeft().toLowerCase().startsWith('basic ')) return challenge.trim();
    }
    return null;
  }

  static Map<String, String> _parseAuthParameters(String challenge) {
    final parameters = <String, String>{};
    final separator = challenge.indexOf(' ');
    if (separator < 0) return parameters;
    final pattern = RegExp(r'(\w+)\s*=\s*("[^"]*"|[^,]+)');
    for (final match in pattern.allMatches(challenge.substring(separator + 1))) {
      var value = (match.group(2) ?? '').trim();
      if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
        value = value.substring(1, value.length - 1);
      }
      parameters[(match.group(1) ?? '').toLowerCase()] = value;
    }
    return parameters;
  }

  String _authorizationHeader({
    required Uri uri, required String method, required String scheme,
    required Map<String, String> challenge, required OnvifCredentials credentials,
  }) {
    if (scheme == 'basic') {
      final token = base64Encode(utf8.encode('${credentials.username}:${credentials.password}'));
      return 'Basic $token';
    }
    if (scheme != 'digest') throw const OnvifException('Only HTTP Basic and Digest authentication are supported.');
    final realm = challenge['realm'] ?? '';
    final nonce = challenge['nonce'] ?? '';
    if (nonce.isEmpty) throw const OnvifException('Digest challenge did not contain a nonce.');
    final algorithm = (challenge['algorithm'] ?? 'MD5').toUpperCase();
    if (algorithm != 'MD5' && algorithm != 'MD5-SESS') {
      throw OnvifException('Unsupported Digest algorithm: $algorithm.');
    }
    final qops = (challenge['qop'] ?? '').split(',').map((v) => v.trim().toLowerCase()).where((v) => v.isNotEmpty).toList();
    if (qops.isNotEmpty && !qops.contains('auth')) {
      throw const OnvifException('Camera Digest challenge requires unsupported qop; only qop=auth is supported.');
    }
    final path = uri.path.isEmpty ? '/' : uri.path;
    final cnonce = List<int>.generate(16, (_) => math.Random.secure().nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    var ha1 = _md5('${credentials.username}:$realm:${credentials.password}');
    if (algorithm == 'MD5-SESS') ha1 = _md5('$ha1:$nonce:$cnonce');
    final ha2 = _md5('$method:$path');
    final qop = qops.contains('auth') ? 'auth' : '';
    var nc = '';
    late final String digestResponse;
    if (qop.isNotEmpty) {
      final countKey = '${uri.host}:$nonce';
      final count = (_digestNonceCounts[countKey] ?? 0) + 1;
      _digestNonceCounts[countKey] = count;
      nc = count.toRadixString(16).padLeft(8, '0');
      digestResponse = _md5('$ha1:$nonce:$nc:$cnonce:$qop:$ha2');
    } else {
      digestResponse = _md5('$ha1:$nonce:$ha2');
    }
    String quote(String value) {
      final slash = String.fromCharCode(92);
      final escaped = value.replaceAll(slash, '$slash$slash').replaceAll('"', '$slash"');
      return '"$escaped"';
    }
    final fields = <String>[
      'username=${quote(credentials.username)}',
      'realm=${quote(realm)}',
      'nonce=${quote(nonce)}',
      'uri=${quote(path)}',
      'response=${quote(digestResponse)}',
      'algorithm=$algorithm',
    ];
    if (qop.isNotEmpty) {
      fields.add('qop=$qop');
      fields.add('nc=$nc');
      fields.add('cnonce=${quote(cnonce)}');
    } else if (algorithm == 'MD5-SESS') {
      fields.add('cnonce=${quote(cnonce)}');
    }
    if ((challenge['opaque'] ?? '').isNotEmpty) fields.add('opaque=${quote(challenge['opaque']!)}');
    return 'Digest ${fields.join(', ')}';
  }

  static String _md5(String value) => md5.convert(utf8.encode(value)).toString();

  static String _envelope(String operation, String body) =>
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<s:Envelope xmlns:s="$_soapNamespace" xmlns:tds="$_deviceNamespace" '
      'xmlns:tt="http://www.onvif.org/ver10/schema"><s:Body><tds:$operation>$body</tds:$operation></s:Body></s:Envelope>';

  static XmlElement? _firstElement(XmlNode root, String localName) {
    for (final element in root.descendants.whereType<XmlElement>()) {
      if (element.name.local == localName) return element;
    }
    return null;
  }

  static String _text(XmlNode root, String localName) =>
      _firstElement(root, localName)?.innerText.trim() ?? '';

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
    for (final byte in bytes) { value = (value << 8) | byte; }
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
    for (final item in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'NetworkInterface' || e.name.local == 'NetworkInterfaces')) {
      if ((item.getAttribute('token') ?? '') != token) continue;
      final addresses = item.descendants.whereType<XmlElement>()
          .where((e) => e.name.local == 'Address' || e.name.local == 'IPv4Address')
          .map((e) => e.innerText.trim());
      return addresses.contains(address);
    }
    return false;
  }
}

class OnvifCredentials {
  const OnvifCredentials(this.username, this.password, {this.realm = '', this.scheme = 'basic'});
  final String username, password, realm, scheme;
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
