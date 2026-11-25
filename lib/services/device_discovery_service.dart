import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

import '../models/camera_device.dart';
import 'onvif_device_service.dart';
import 'ssdp_discovery_parser.dart';

class DeviceDiscoveryService extends ChangeNotifier {
  DeviceDiscoveryService({OnvifDeviceService? onvifService, this.onOperation})
      : _onvif = onvifService ?? OnvifDeviceService();

  final void Function(String operation, String target, String outcome, String details)? onOperation;

  final OnvifDeviceService _onvif;
  bool _cancelSubnet = false;
  bool _isSubnetScanning = false;
  bool get isSubnetScanning => _isSubnetScanning;
  bool _cancelReachability = false;
  int _discoveryGeneration = 0;
  String _selectedInterfaceName = '';
  String get selectedInterfaceName => _selectedInterfaceName;
  static const projectPort = 9988;
  static const onvifPort = 3702;
  static const ssdpPort = 1900;
  static final InternetAddress ssdpGroup = InternetAddress('239.255.255.250');
  static final InternetAddress onvifGroup = InternetAddress('239.255.255.250');

  final Map<String, CameraDevice> _devices = {};
  final List<RawDatagramSocket> _sockets = [];
  Timer? _timeout;
  int _sequence = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
  bool _isScanning = false;
  bool _disposed = false;
  String _status = 'Ready to discover cameras on your local network.';

  List<CameraDevice> get devices => _devices.values.toList()
    ..sort((a, b) => a.ipAddress.compareTo(b.ipAddress));
  bool get isScanning => _isScanning;
  String get status => _status;

  void updateDevice(CameraDevice device) {
    if (_disposed) return;
    final matched = _matchingKey(device);
    final key = matched ?? (device.macAddress.isNotEmpty ? device.macAddress : device.id);
    if (key.isEmpty) return;
    if (matched != null && matched != key) _devices.remove(matched);
    _devices[key] = device;
    notifyListeners();
  }

  void restoreDevice(CameraDevice device) {
    if (_disposed) return;
    final key = device.macAddress.isNotEmpty ? device.macAddress : device.ipAddress;
    if (key.isNotEmpty) _devices[key] = device;
  }

  void replaceInventory(List<CameraDevice> devices) {
    if (_disposed) return;
    _devices.clear();
    for (final device in devices) {
      final key = device.macAddress.isNotEmpty ? device.macAddress : device.ipAddress;
      if (key.isNotEmpty) _devices[key] = device;
    }
    notifyListeners();
  }

  void updateReachability(CameraDevice device, String result) {
    if (_disposed) return;
    final key = device.macAddress.isNotEmpty ? device.macAddress : device.ipAddress;
    final existing = _devices[key];
    if (existing != null) {
      _devices[key] = existing.copyWith(reachabilityStatus: result);
      notifyListeners();
    }
  }

  void _setStatus(String value) {
    _status = value;
    if (!_disposed) notifyListeners();
  }

  Future<void> startDiscovery({String interfaceName = ''}) async {
    if (_disposed || _isScanning) return;
    if (!await _ensureLocalNetworkAccess()) {
      if (!_disposed) _setStatus('Local network permission is required to discover cameras.');
      onOperation?.call('Discovery', interfaceName, 'Failed', 'Local network permission was not granted.');
      return;
    }
    if (_disposed) return;
    await cancelDiscovery(notify: false);
    _selectedInterfaceName = interfaceName;
    final generation = ++_discoveryGeneration;
    _isScanning = true;
    _setStatus('Checking active IPv4 network interfaces…');

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: true,
        includeLoopback: false,
      );
      if (generation != _discoveryGeneration) { return; }
      await _acquireMulticastLock();
      if (generation != _discoveryGeneration) { _closeSockets(); return; }
      for (final interface in interfaces) {
        if (generation != _discoveryGeneration) { return; }
        if (interfaceName.isNotEmpty && interface.name != interfaceName) { continue; }
        for (final address in interface.addresses) {
          if (generation != _discoveryGeneration) { return; }
          if (address.type != InternetAddressType.IPv4 ||
              address.isLoopback) { continue; }
          await _openInterface(interface, address, generation);
          if (generation != _discoveryGeneration) { _closeSockets(); return; }
        }
      }
      if (_sockets.isEmpty) {
        _closeSockets();
        _isScanning = false;
        _setStatus('No usable IPv4 socket could be opened on the active interfaces.');
        onOperation?.call('Discovery', interfaceName, 'Failed', 'No usable IPv4 socket could be opened.');
        return;
      }
      final interfaceCount = _sockets.length;
      _setStatus('Sending ONVIF, Oxita and SSDP/UPnP probes on $interfaceCount interface address(es)…');
      _timeout = Timer(const Duration(seconds: 6), () { if (generation == _discoveryGeneration) _finishDiscovery(); });
    } on SocketException catch (error) {
      _closeSockets();
      _isScanning = false;
      _setStatus('Local network discovery failed: ${error.toString()}');
      onOperation?.call('Discovery', interfaceName, 'Failed', error.toString());
    } catch (error) {
      _closeSockets();
      _isScanning = false;
      _setStatus('Could not start discovery: $error');
      onOperation?.call('Discovery', interfaceName, 'Failed', error.toString());
    }
  }

  Future<void> _openInterface(NetworkInterface interface, InternetAddress localAddress, int generation) async {
    RawDatagramSocket? socket;
    try {
      final openedSocket = await RawDatagramSocket.bind(localAddress, 0, reuseAddress: true);
      socket = openedSocket;
      if (generation != _discoveryGeneration) { openedSocket.close(); return; }
      openedSocket.broadcastEnabled = true;
      openedSocket.multicastHops = 1;
      try {
        openedSocket.joinMulticast(onvifGroup, interface);
      } catch (error) {
        // Some mobile builds (notably iOS without Apple's multicast entitlement)
        // cannot join multicast. Keep the socket alive for any permitted unicast
        // or project probe path and report the platform limitation.
        _setStatus('ONVIF multicast unavailable on ${interface.name}: $error');
      }
      final sequence = ++_sequence;
      _sockets.add(openedSocket);
      openedSocket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = openedSocket.receive()) != null) {
          _handleDatagram(datagram!, sequence, interface.name);
        }
      }, onError: (Object error) {
        _setStatus('Socket error on ${interface.name}: $error');
      });
      try {
        _sendOnvifProbe(openedSocket);
      } catch (error) {
        _setStatus('ONVIF multicast send unavailable on ${interface.name}: $error');
      }
      try {
        _sendProjectProbe(openedSocket, sequence);
      } catch (error) {
        _setStatus('Oxita UDP probe unavailable on ${interface.name}: $error');
      }
      try {
        _sendSsdpProbe(openedSocket);
      } catch (error) {
        _setStatus('SSDP/UPnP probe unavailable on ${interface.name}: $error');
      }
    } on SocketException catch (error) {
      if (socket != null) { _sockets.remove(socket); socket.close(); }
      _setStatus('Could not bind ${interface.name}: ${error.message}');
    } catch (error) {
      if (socket != null) { _sockets.remove(socket); socket.close(); }
      _setStatus('Could not initialize ${interface.name}: $error');
    }
  }

  void _sendOnvifProbe(RawDatagramSocket socket) {
    final id = 'urn:uuid:${DateTime.now().microsecondsSinceEpoch}-$_sequence';
    final payload = '''<?xml version="1.0" encoding="UTF-8"?>
<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope"
 xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing"
 xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"
 xmlns:dn="http://www.onvif.org/ver10/network/wsdl">
 <e:Header><w:MessageID>$id</w:MessageID>
 <w:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>
 <w:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action></e:Header>
 <e:Body><d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types></d:Probe></e:Body>
</e:Envelope>''';
    socket.send(utf8.encode(payload), onvifGroup, onvifPort);
  }

  void _sendProjectProbe(RawDatagramSocket socket, int sequence) {
    final payload = jsonEncode({
      'magic': 'CAM_DISCOVER',
      'version': 1,
      'seq': sequence,
      'cmd': 'PROBE_REQUEST',
    });
    socket.send(utf8.encode(payload), InternetAddress('255.255.255.255'), projectPort);
  }

  void _sendSsdpProbe(RawDatagramSocket socket) {
    const probe = 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:1900\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 2\r\n'
        'ST: ssdp:all\r\n\r\n';
    socket.send(ascii.encode(probe), ssdpGroup, ssdpPort);
  }

  void _handleDatagram(Datagram datagram, int expectedSequence, String interfaceName) {
    if (datagram.data.length > 65507) return;
    final payload = utf8.decode(datagram.data, allowMalformed: true);
    if (payload.length <= 16 * 1024 && payload.toUpperCase().startsWith('HTTP/1.')) {
      final device = SsdpDiscoveryParser.parseResponse(datagram.data, datagram.address, interfaceName);
      if (device != null) _merge(device);
    } else if (payload.contains('CAM_DISCOVER')) {
      final device = parseProjectResponse(payload, expectedSequence, datagram.address, interfaceName);
      if (device != null) _merge(device);
    } else if (payload.contains('ProbeMatch')) {
      final device = parseOnvifResponse(payload, datagram.address, interfaceName);
      if (device != null) _merge(device);
    }
  }

  CameraDevice? parseProjectResponse(String payload, int expectedSequence,
      InternetAddress sender, String interfaceName) {
    try {
      if (utf8.encode(payload).length > 65507 || sender.type != InternetAddressType.IPv4) { return null; }
      final root = jsonDecode(payload);
      if (root is! Map<String, dynamic> ||
          root['magic'] != 'CAM_DISCOVER' ||
          root['version'] != 1 ||
          root['seq'] != expectedSequence ||
          root['cmd'] != 'PROBE_RESPONSE' ||
          root['device'] is! Map<String, dynamic>) { return null; }
      final device = root['device'] as Map<String, dynamic>;
      for (final key in ['mac', 'ipv4', 'netmask', 'gateway', 'dns', 'soc', 'firmware_version']) {
        if (device[key] != null && device[key] is! String) { return null; }
      }
      for (final key in ['http_port', 'rtsp_port']) {
        final value = device[key];
        if (value != null && (value is! num || value < 1 || value > 65535 || value % 1 != 0)) { return null; }
      }
      if (device['activated'] != null && device['activated'] is! bool) return null;
      if (device['dhcp'] != null && device['dhcp'] is! bool) return null;
      final rawMac = (device['mac'] as String? ?? '').trim().toUpperCase().replaceAll('-', ':');
      final mac = RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){5}$').hasMatch(rawMac) ? rawMac : '';
      final advertisedIp = InternetAddress.tryParse(device['ipv4'] as String? ?? '');
      final usableAdvertised = advertisedIp != null && advertisedIp.type == InternetAddressType.IPv4 &&
          !advertisedIp.isLoopback && !advertisedIp.isMulticast &&
          advertisedIp.address != '0.0.0.0' && advertisedIp.address != '255.255.255.255';
      final senderIsUnconfigured = sender.address == '0.0.0.0';
      if (!senderIsUnconfigured && usableAdvertised && advertisedIp.address != sender.address) return null;
      final ip = senderIsUnconfigured ? (usableAdvertised ? advertisedIp.address : '') : sender.address;
      if (ip.isEmpty || ip == '0.0.0.0' || ip == '255.255.255.255') return null;
      return CameraDevice(
        id: mac.isNotEmpty ? mac : ip,
        ipAddress: ip,
        macAddress: mac,
        manufacturer: 'Oxita',
        model: (device['soc'] as String? ?? 'Model unknown').trim(),
        firmwareVersion: (device['firmware_version'] as String? ?? '').trim(),
        activationState: device['activated'] == true ? 'Activated' :
            device['activated'] == false ? 'Not activated' : 'Unknown',
        discoverySources: const ['Project UDP 9988'],
        interfaceName: interfaceName,
        lastSeen: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  CameraDevice? parseOnvifResponse(String payload, InternetAddress sender, String interfaceName) {
    try {
      if (utf8.encode(payload).length > 65507 || sender.type != InternetAddressType.IPv4) return null;
      final document = XmlDocument.parse(payload);
      final probeMatches = document.descendants.where((node) => node is XmlElement && node.name.local == 'ProbeMatch');
      for (final match in probeMatches) {
        final elements = (match as XmlElement).descendants.whereType<XmlElement>();
        String textOf(String name) => elements
            .where((element) => element.name.local == name)
            .map((element) => element.innerText.trim())
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
        final endpoint = textOf('Address');
        final xaddrs = textOf('XAddrs');
        final scopes = textOf('Scopes');
        if (endpoint.isEmpty && xaddrs.isEmpty) continue;
        final xaddrParts = xaddrs.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
        var serviceUrl = '';
        for (final candidate in xaddrParts) {
          final uri = Uri.tryParse(candidate);
          if (uri != null &&
              (uri.scheme == 'http' || uri.scheme == 'https') &&
              uri.host == sender.address &&
              uri.userInfo.isEmpty && uri.query.isEmpty && uri.fragment.isEmpty) {
            serviceUrl = uri.toString();
            break;
          }
        }
        var manufacturer = 'ONVIF device (manufacturer unknown)';
        var model = 'Model unknown';
        for (final scope in scopes.split(RegExp(r'\s+'))) {
          if (scope.startsWith('onvif://www.onvif.org/manufacturer/')) {
            manufacturer = Uri.decodeComponent(scope.substring('onvif://www.onvif.org/manufacturer/'.length));
          } else if (scope.startsWith('onvif://www.onvif.org/name/')) {
            model = Uri.decodeComponent(scope.substring('onvif://www.onvif.org/name/'.length));
          } else if (model == 'Model unknown' && scope.startsWith('onvif://www.onvif.org/hardware/')) {
            model = Uri.decodeComponent(scope.substring('onvif://www.onvif.org/hardware/'.length));
          }
        }
        return CameraDevice(
          id: endpoint.isNotEmpty ? endpoint : sender.address,
          ipAddress: sender.address,
          manufacturer: manufacturer,
          model: model,
          discoverySources: const ['ONVIF WS-Discovery'],
          interfaceName: interfaceName,
          onvifEndpoint: endpoint,
          deviceServiceUrl: serviceUrl,
          lastSeen: DateTime.now(),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _normalizedMac(String value) => value.trim().toUpperCase().replaceAll('-', ':');

  String? _matchingKey(CameraDevice observation) {
    final mac = _normalizedMac(observation.macAddress);
    if (mac.isNotEmpty) {
      for (final entry in _devices.entries) {
        if (_normalizedMac(entry.value.macAddress) == mac) return entry.key;
      }
    }
    if (observation.onvifEndpoint.isNotEmpty) {
      for (final entry in _devices.entries) {
        final known = entry.value;
        final conflict = mac.isNotEmpty && known.macAddress.isNotEmpty &&
            mac != _normalizedMac(known.macAddress);
        if (!conflict && known.onvifEndpoint.toLowerCase() == observation.onvifEndpoint.toLowerCase()) { return entry.key; }
      }
    }
    if (observation.serialNumber.isNotEmpty && _known(observation.manufacturer)) {
      for (final entry in _devices.entries) {
        final known = entry.value;
        final conflict = mac.isNotEmpty && known.macAddress.isNotEmpty &&
            mac != _normalizedMac(known.macAddress);
        if (!conflict && known.serialNumber.toLowerCase() == observation.serialNumber.toLowerCase() &&
            known.manufacturer.toLowerCase() == observation.manufacturer.toLowerCase()) { return entry.key; }
      }
    }
    for (final entry in _devices.entries) {
      final known = entry.value;
      final conflict = mac.isNotEmpty && known.macAddress.isNotEmpty &&
          mac != _normalizedMac(known.macAddress);
      if (!conflict && observation.ipAddress.isNotEmpty &&
          known.ipAddress == observation.ipAddress) { return entry.key; }
    }
    return null;
  }

  bool _known(String value) {
    final v = value.trim().toLowerCase();
    return v.isNotEmpty && v != 'n/a' && !v.contains('unknown') && !v.contains('unverified');
  }

  void _merge(CameraDevice incoming) {
    final matchedKey = _matchingKey(incoming);
    final key = matchedKey ?? (incoming.macAddress.isNotEmpty
        ? incoming.macAddress : (incoming.ipAddress.isNotEmpty ? incoming.ipAddress : incoming.onvifEndpoint));
    if (key.isEmpty) return;
    final existing = matchedKey == null ? null : _devices.remove(matchedKey);
    if (existing == null) {
      _devices[key] = incoming;
    } else {
      final verified = !incoming.isCandidate &&
          incoming.discoverySources.any((s) => s == 'ONVIF WS-Discovery' ||
              s == 'ONVIF GetDeviceInformation' || s == 'Project UDP 9988');
      final networkRefreshed = incoming.discoverySources.contains('ONVIF GetNetworkInterfaces');
      final capsRefreshed = incoming.discoverySources.contains('ONVIF GetCapabilities');
      _devices[key] = existing.copyWith(
        id: key,
        userLabel: existing.userLabel.isNotEmpty ? existing.userLabel : incoming.userLabel,
        ipAddress: verified && incoming.ipAddress.isNotEmpty ? incoming.ipAddress : existing.ipAddress,
        macAddress: existing.macAddress.isEmpty ? incoming.macAddress : existing.macAddress,
        manufacturer: !_known(existing.manufacturer) && _known(incoming.manufacturer) ? incoming.manufacturer : existing.manufacturer,
        model: !_known(existing.model) && _known(incoming.model) ? incoming.model : existing.model,
        firmwareVersion: verified && incoming.firmwareVersion.isNotEmpty ? incoming.firmwareVersion : existing.firmwareVersion,
        hardwareId: existing.hardwareId.isEmpty ? incoming.hardwareId : existing.hardwareId,
        serialNumber: existing.serialNumber.isEmpty ? incoming.serialNumber : existing.serialNumber,
        activationState: verified && _known(incoming.activationState) ? incoming.activationState : existing.activationState,
        discoverySources: {...existing.discoverySources, ...incoming.discoverySources}.toList(),
        capabilities: capsRefreshed ? incoming.capabilities : {...existing.capabilities, ...incoming.capabilities}.toList(),
        interfaceName: verified && incoming.interfaceName.isNotEmpty ? incoming.interfaceName : existing.interfaceName,
        onvifEndpoint: verified && incoming.onvifEndpoint.isNotEmpty ? incoming.onvifEndpoint : existing.onvifEndpoint,
        deviceServiceUrl: verified && incoming.deviceServiceUrl.isNotEmpty ? incoming.deviceServiceUrl : existing.deviceServiceUrl,
        networkSummary: networkRefreshed ? incoming.networkSummary : (existing.networkSummary.isEmpty ? incoming.networkSummary : existing.networkSummary),
        networkInterfaceToken: networkRefreshed ? incoming.networkInterfaceToken : (existing.networkInterfaceToken.isEmpty ? incoming.networkInterfaceToken : existing.networkInterfaceToken),
        ipv4Address: networkRefreshed ? incoming.ipv4Address : (existing.ipv4Address.isEmpty ? incoming.ipv4Address : existing.ipv4Address),
        ipv4SubnetMask: networkRefreshed ? incoming.ipv4SubnetMask : (existing.ipv4SubnetMask.isEmpty ? incoming.ipv4SubnetMask : existing.ipv4SubnetMask),
        ipv4Gateway: networkRefreshed ? incoming.ipv4Gateway : (existing.ipv4Gateway.isEmpty ? incoming.ipv4Gateway : existing.ipv4Gateway),
        ipv4DnsServer: incoming.discoverySources.contains('ONVIF GetDNS') ? incoming.ipv4DnsServer : (existing.ipv4DnsServer.isEmpty ? incoming.ipv4DnsServer : existing.ipv4DnsServer),
        ipv4DhcpEnabled: networkRefreshed ? incoming.ipv4DhcpEnabled : existing.ipv4DhcpEnabled,
        ipv4ConfigurationKnown: networkRefreshed ? incoming.ipv4ConfigurationKnown : existing.ipv4ConfigurationKnown,
        isCandidate: verified ? false : existing.isCandidate,
        openPorts: {...existing.openPorts, ...incoming.openPorts}.toList()..sort(),
        lastSeen: incoming.lastSeen ?? DateTime.now(),
        reachabilityStatus: incoming.reachabilityCheckedAt.isNotEmpty ? incoming.reachabilityStatus : existing.reachabilityStatus,
        reachabilityCheckedAt: incoming.reachabilityCheckedAt.isNotEmpty ? incoming.reachabilityCheckedAt : existing.reachabilityCheckedAt,
        lastSuccessfulResponseAt: incoming.lastSuccessfulResponseAt.isNotEmpty ? incoming.lastSuccessfulResponseAt : existing.lastSuccessfulResponseAt,
      );
    }
    notifyListeners();
    final merged = _devices[key]!;
    if (merged.deviceServiceUrl.isNotEmpty && !merged.isCandidate &&
        !merged.discoverySources.contains('ONVIF GetDeviceInformation') &&
        !_refreshing.contains(key)) {
      unawaited(refreshDeviceInfo(merged));
    }
  }

  final Set<String> _refreshing = {};

  Future<void> refreshDeviceInfo(CameraDevice device) async {
    if (_disposed) return;
    final key = _matchingKey(device) ?? (device.macAddress.isNotEmpty ? device.macAddress : device.ipAddress);
    if (key.isEmpty || !_refreshing.add(key)) return;
    _setStatus('Refreshing ONVIF information for ${device.ipAddress}…');
    try {
      final generation = _discoveryGeneration;
      final updated = await _onvif.refresh(device);
      if (generation != _discoveryGeneration) return;
      _merge(updated);
      _setStatus('ONVIF information refreshed for ${device.ipAddress}.');
      onOperation?.call('Device information refresh', device.ipAddress, 'Completed', 'ONVIF identity, capabilities and available network details refreshed.');
    } on OnvifException catch (error) {
      _setStatus('ONVIF refresh failed for ${device.ipAddress}: ${error.message}');
      onOperation?.call('Device information refresh', device.ipAddress, 'Failed', error.message);
    } finally {
      _refreshing.remove(key);
    }
  }

  Future<String> factoryReset(CameraDevice device, {required String factoryDefaultType}) async {
    final message = await _onvif.factoryReset(device, factoryDefaultType: factoryDefaultType);
    _setStatus(message);
    onOperation?.call('Factory reset', device.ipAddress, 'Accepted', message);
    return message;
  }

  Future<OnvifWriteResult> applyStaticIpv4(CameraDevice device, {
    required String address, required String subnetMask, String gateway = '',
  }) async {
    final result = await _onvif.applyStaticIpv4(device, address: address, subnetMask: subnetMask, gateway: gateway);
    _merge(result.device);
    _setStatus(result.message);
    return result;
  }

  Future<void> addManualDevice(String address) async {
    final value = address.trim();
    final parsed = InternetAddress.tryParse(value);
    final validIp = parsed != null &&
        !parsed.isLoopback &&
        !parsed.isMulticast &&
        parsed.address != '0.0.0.0' &&
        parsed.address != '255.255.255.255' &&
        parsed.address != '::';
    final hostname = value.endsWith('.') ? value.substring(0, value.length - 1) : value;
    final labels = hostname.split('.');
    final validHostname = hostname.isNotEmpty &&
        hostname.length <= 253 &&
        labels.every((label) =>
            label.isNotEmpty &&
            label.length <= 63 &&
            RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$')
                .hasMatch(label));
    if (!validIp && !validHostname) {
      throw const FormatException(
        'Enter a valid IP address or hostname (for example, 192.168.1.100 or camera.local).',
      );
    }
    final normalized = parsed?.address ?? hostname.toLowerCase();
    _merge(CameraDevice(
      id: normalized,
      ipAddress: normalized,
      discoverySources: const ['Manual'],
      lastSeen: DateTime.now(),
    ));
  }

  Future<void> scanSubnet(InternetAddress localAddress, InternetAddress mask, {String interfaceName = '', bool fullSubnet = false, void Function(int completed, int total, int candidates)? onProgress}) async {
    if (_disposed || _isSubnetScanning) return;
    if (!await _ensureLocalNetworkAccess()) {
      if (!_disposed) _setStatus('Local network permission is required to scan this subnet.');
      onOperation?.call('Subnet scan', interfaceName, 'Failed', 'Local network permission was not granted.');
      return;
    }
    if (_disposed) return;
    _cancelSubnet = false;
    if (interfaceName.isNotEmpty) _selectedInterfaceName = interfaceName;
    if (localAddress.type != InternetAddressType.IPv4 || localAddress.isLoopback || localAddress.isMulticast) {
      throw const FormatException('A usable local IPv4 address is required.');
    }
    final ip = localAddress.rawAddress;
    final maskBytes = mask.rawAddress;
    if (ip.length != 4 || maskBytes.length != 4) throw const FormatException('IPv4 only.');
    var network = 0, broadcast = 0, own = 0;
    for (var i = 0; i < 4; i++) {
      network = (network << 8) | (ip[i] & maskBytes[i]);
      broadcast = (broadcast << 8) | ((ip[i] & maskBytes[i]) | (~maskBytes[i] & 255));
      own = (own << 8) | ip[i];
    }
    final maskValue = (maskBytes[0] << 24) | (maskBytes[1] << 16) | (maskBytes[2] << 8) | maskBytes[3];
    final inverse = (~maskValue) & 0xffffffff;
    if (maskValue == 0 || maskValue == 0xffffffff || (inverse & (inverse + 1)) != 0) {
      throw const FormatException('Subnet mask must be a contiguous IPv4 mask from /1 through /30.');
    }
    final first = network + 1;
    final last = broadcast - 1;
    if (last < first) throw const FormatException('Invalid subnet.');
    final hostCount = last - first + 1;
    if (hostCount > 4096 && fullSubnet) {
      throw const FormatException('Full subnet scans are limited to 4,096 hosts. Use the 256-address window on larger networks.');
    }
    final scanAll = hostCount <= 4096;
    _isSubnetScanning = true;
    final end = scanAll ? last : (own + 128 < last ? own + 128 : last);
    final start = scanAll ? first : (own - 127 > first ? own - 127 : first);
    final hosts = <int>[];
    for (var host = start; host <= end; host++) {
      if (host != own) hosts.add(host);
    }
    const ports = [22, 23, 53, 80, 135, 139, 443, 445, 515, 554, 631, 1900, 2869, 3389, 5000, 5357, 7547, 8000, 8080, 8443, 8899, 9100, 34567];
    var completed = 0;
    var candidates = 0;
    _setStatus(scanAll ? 'Scanning all $hostCount usable local IPv4 hosts…' : 'Scanning a 256-address window (${hosts.length} hosts) on a larger subnet…');
    final tasks = <Future<void>>[];
    final semaphore = _AsyncSemaphore(24);
    for (final host in hosts) {
      final address = InternetAddress.fromRawAddress(Uint8List.fromList([
        (host >> 24) & 255, (host >> 16) & 255, (host >> 8) & 255, host & 255,
      ]));
      tasks.add(() async {
        await semaphore.acquire();
        try {
          final openPorts = <int>[];
          for (final port in ports) {
            if (_cancelSubnet) break;
            try {
              final socket = await Socket.connect(address, port, timeout: const Duration(milliseconds: 450));
              socket.destroy();
              openPorts.add(port);
            } on SocketException {
              // Closed or filtered port; continue with the next bounded probe.
            } on TimeoutException {
              // A timeout is not evidence that the device is absent.
            }
          }
          if (!_cancelSubnet && openPorts.isNotEmpty) {
            candidates++;
            _merge(CameraDevice(
              id: address.address,
              ipAddress: address.address,
              manufacturer: 'Unknown',
              model: 'Unverified network device',
              activationState: 'Unverified',
              discoverySources: const ['Local subnet TCP scan'],
              isCandidate: true,
              openPorts: openPorts,
              lastSeen: DateTime.now(),
            ));
          }
        } finally {
          completed++;
          onProgress?.call(completed, hosts.length, candidates);
          semaphore.release();
        }
      }());
    }
    await Future.wait(tasks);
    _isSubnetScanning = false;
    final cancelled = _cancelSubnet;
    _setStatus(cancelled ? 'Subnet scan cancelled after $completed host(s).' : 'Subnet scan complete. $candidates unverified candidate(s) found from $completed host(s).');
    onOperation?.call('Subnet scan', _selectedInterfaceName, cancelled ? 'Cancelled' : 'Completed', '$completed host(s) checked; $candidates unverified candidate(s) found.');
  }

  void cancelSubnetScan() { _cancelSubnet = true; _setStatus('Cancelling subnet scan…'); }

  Future<String> checkReachability(CameraDevice device) async {
    if (!await _ensureLocalNetworkAccess()) return 'Permission required';
    return _checkDevice(device);
  }

  Future<String> _checkDevice(CameraDevice device) async {
    const ports = [22, 23, 53, 80, 135, 139, 443, 445, 515, 554, 631, 1900, 2869, 3389, 5000, 5357, 7547, 8000, 8080, 8443, 8899, 9100, 34567];
    for (final port in {...device.openPorts, ...ports}) {
      try {
        final socket = await Socket.connect(device.ipAddress, port, timeout: const Duration(milliseconds: 550));
        socket.destroy();
        return 'Reachable';
      } on SocketException {
        // Try next supported service port.
      } on TimeoutException {
        // Continue with bounded attempts.
      }
    }
    return 'No response';
  }

  Future<int> checkReachabilityBatch(
    List<CameraDevice> devices, {
    void Function(int completed, int total, CameraDevice current)? onProgress,
  }) async {
    if (!await _ensureLocalNetworkAccess()) {
      onOperation?.call('Reachability', '', 'Failed', 'Local network permission was not granted.');
      return 0;
    }
    _cancelReachability = false;
    var completed = 0;
    for (final device in devices) {
      if (_cancelReachability) break;
      onProgress?.call(completed, devices.length, device);
      final result = await _checkDevice(device);
      final checkedAt = DateTime.now().toIso8601String();
      _merge(device.copyWith(
        reachabilityStatus: result,
        reachabilityCheckedAt: checkedAt,
        lastSuccessfulResponseAt: result == 'Reachable' ? checkedAt : device.lastSuccessfulResponseAt,
      ));
      completed++;
      onProgress?.call(completed, devices.length, device);
    }
    final cancelled = _cancelReachability;
    _setStatus(cancelled
        ? 'Reachability check cancelled after $completed device(s).'
        : 'Reachability check complete for $completed device(s).');
    onOperation?.call('Reachability', '', cancelled ? 'Cancelled' : 'Completed', '$completed of ${devices.length} device(s) checked.');
    return completed;
  }

  void cancelReachability() {
    _cancelReachability = true;
    _setStatus('Cancelling reachability checks…');
  }

  Future<void> _acquireMulticastLock() async {
    if (!Platform.isAndroid) return;
    try {
      const channel = MethodChannel('com.oxita.camera_ip_search_mobile/local_network');
      await channel.invokeMethod<void>('acquireMulticastLock');
    } on PlatformException catch (error) {
      _setStatus('Android multicast lock unavailable: ${error.message ?? error.code}');
    } on MissingPluginException {
      _setStatus('Android platform runner is not initialized.');
    }
  }

  Future<bool> _ensureLocalNetworkAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      const channel = MethodChannel('com.oxita.camera_ip_search_mobile/local_network');
      return await channel.invokeMethod<bool>('requestLocalNetworkPermission') ?? false;
    } on PlatformException catch (error) {
      _setStatus('Could not request local network permission: ${error.message ?? error.code}');
      return false;
    } on MissingPluginException {
      // Android runner must be generated with tool/bootstrap_platforms.sh.
      return false;
    }
  }

  void _finishDiscovery() {
    _timeout = null;
    _isScanning = false;
    _closeSockets();
    _setStatus('Discovery finished. ${_devices.length} device(s) found.');
    onOperation?.call('Discovery', _selectedInterfaceName, 'Completed', '${_devices.length} device(s) in local inventory.');
  }

  Future<void> cancelDiscovery({bool notify = true}) async {
    if (_disposed) return;
    _discoveryGeneration++;
    _onvif.cancelActive();
    _timeout?.cancel();
    _timeout = null;
    _isScanning = false;
    _closeSockets();
    if (notify) {
      _setStatus('Discovery cancelled.');
      onOperation?.call('Discovery', _selectedInterfaceName, 'Cancelled', '${_devices.length} device(s) retained.');
    }
  }

  void _closeSockets() {
    if (Platform.isAndroid) {
      const channel = MethodChannel('com.oxita.camera_ip_search_mobile/local_network');
      unawaited(channel.invokeMethod<void>('releaseMulticastLock').catchError((Object _) {}));
    }
    for (final socket in _sockets) {
      socket.close();
    }
    _sockets.clear();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelSubnet = true;
    _cancelReachability = true;
    _isScanning = false;
    _isSubnetScanning = false;
    _discoveryGeneration++;
    _timeout?.cancel();
    _onvif.cancelActive();
    _closeSockets();
    super.dispose();
  }
}

class _AsyncSemaphore {
  _AsyncSemaphore(this._limit);
  final int _limit;
  int _active = 0;
  final List<Completer<void>> _waiters = [];

  Future<void> acquire() async {
    if (_active < _limit) {
      _active++;
      return;
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    await waiter.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _active--;
    }
  }
}
