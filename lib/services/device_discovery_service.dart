import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import '../models/camera_device.dart';

class DeviceDiscoveryService extends ChangeNotifier {
  static const projectPort = 9988;
  static const onvifPort = 3702;
  static final InternetAddress onvifGroup = InternetAddress('239.255.255.250');

  final Map<String, CameraDevice> _devices = {};
  final Map<RawDatagramSocket, int> _sequences = {};
  final List<RawDatagramSocket> _sockets = [];
  Timer? _timeout;
  int _sequence = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
  bool _isScanning = false;
  String _status = 'Ready to discover cameras on your local network.';

  List<CameraDevice> get devices => _devices.values.toList()
    ..sort((a, b) => a.ipAddress.compareTo(b.ipAddress));
  bool get isScanning => _isScanning;
  String get status => _status;

  void restoreDevice(CameraDevice device) {
    final key = device.macAddress.isNotEmpty ? device.macAddress : device.ipAddress;
    if (key.isNotEmpty) _devices[key] = device;
  }

  void updateReachability(CameraDevice device, String result) {
    final key = device.macAddress.isNotEmpty ? device.macAddress : device.ipAddress;
    final existing = _devices[key];
    if (existing != null) {
      _devices[key] = existing.copyWith(reachabilityStatus: result);
      notifyListeners();
    }
  }

  void _setStatus(String value) {
    _status = value;
    notifyListeners();
  }

  Future<void> startDiscovery() async {
    if (_isScanning) return;
    await cancelDiscovery(notify: false);
    _devices.clear();
    _isScanning = true;
    _setStatus('Checking active IPv4 network interfaces…');

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      var interfaceCount = 0;
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.type != InternetAddressType.IPv4 ||
              address.isLoopback ||
              address.isLinkLocal) continue;
          await _openInterface(interface, address);
          interfaceCount++;
        }
      }
      if (_sockets.isEmpty) {
        _isScanning = false;
        _setStatus('No usable IPv4 network interface was available.');
        return;
      }
      _setStatus('Sending ONVIF and project-camera probes on $interfaceCount interface address(es)…');
      _timeout = Timer(const Duration(seconds: 6), _finishDiscovery);
    } on SocketException catch (error) {
      _isScanning = false;
      _setStatus('Local network discovery failed: ${error.message}');
    } catch (error) {
      _isScanning = false;
      _setStatus('Could not start discovery: $error');
    }
  }

  Future<void> _openInterface(NetworkInterface interface, InternetAddress localAddress) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(localAddress, 0, reuseAddress: true);
      socket.broadcastEnabled = true;
      socket.multicastHops = 1;
      socket.joinMulticast(onvifGroup, interface);
      final sequence = ++_sequence;
      _sockets.add(socket);
      _sequences[socket] = sequence;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = socket!.receive()) != null) {
          _handleDatagram(datagram!, sequence, interface.name);
        }
      }, onError: (Object error) {
        _setStatus('Socket error on ${interface.name}: $error');
      });
      _sendOnvifProbe(socket);
      _sendProjectProbe(socket, sequence);
    } on SocketException catch (error) {
      socket?.close();
      _setStatus('Could not bind ${interface.name}: ${error.message}');
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

  void _handleDatagram(Datagram datagram, int expectedSequence, String interfaceName) {
    if (datagram.data.length > 65507) return;
    final payload = utf8.decode(datagram.data, allowMalformed: true);
    if (payload.contains('CAM_DISCOVER')) {
      final device = _parseProjectResponse(payload, expectedSequence, datagram.address, interfaceName);
      if (device != null) _merge(device);
    } else if (payload.contains('ProbeMatch')) {
      final device = _parseOnvifResponse(payload, datagram.address, interfaceName);
      if (device != null) _merge(device);
    }
  }

  CameraDevice? _parseProjectResponse(String payload, int expectedSequence,
      InternetAddress sender, String interfaceName) {
    try {
      final root = jsonDecode(payload);
      if (root is! Map<String, dynamic> ||
          root['magic'] != 'CAM_DISCOVER' ||
          root['version'] != 1 ||
          root['seq'] != expectedSequence ||
          root['cmd'] != 'PROBE_RESPONSE' ||
          root['device'] is! Map<String, dynamic>) return null;
      final device = root['device'] as Map<String, dynamic>;
      for (final key in ['mac', 'ipv4', 'netmask', 'gateway', 'dns', 'soc', 'firmware_version']) {
        if (device[key] != null && device[key] is! String) return null;
      }
      for (final key in ['http_port', 'rtsp_port']) {
        final value = device[key];
        if (value != null && (value is! num || value < 1 || value > 65535 || value % 1 != 0)) return null;
      }
      if (device['activated'] != null && device['activated'] is! bool) return null;
      if (device['dhcp'] != null && device['dhcp'] is! bool) return null;
      final rawMac = (device['mac'] as String? ?? '').trim().toUpperCase().replaceAll('-', ':');
      final mac = RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){5}$').hasMatch(rawMac) ? rawMac : '';
      final advertisedIp = InternetAddress.tryParse(device['ipv4'] as String? ?? '');
      final ip = advertisedIp?.type == InternetAddressType.IPv4 &&
              !advertisedIp!.isLoopback && !advertisedIp.isMulticast
          ? advertisedIp.address : sender.address;
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

  CameraDevice? _parseOnvifResponse(String payload, InternetAddress sender, String interfaceName) {
    try {
      if (payload.length > 65507) return null;
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
        final firstXAddr = xaddrParts.isEmpty ? '' : xaddrParts.first;
        final uri = Uri.tryParse(firstXAddr);
        final serviceUrl = uri != null &&
                (uri.scheme == 'http' || uri.scheme == 'https') &&
                uri.host == sender.address
            ? uri.toString() : '';
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

  void _merge(CameraDevice incoming) {
    final key = incoming.macAddress.isNotEmpty ? incoming.macAddress : incoming.ipAddress;
    String? matchedKey;
    for (final entry in _devices.entries) {
      final sameMac = incoming.macAddress.isNotEmpty &&
          entry.value.macAddress.isNotEmpty &&
          entry.value.macAddress == incoming.macAddress;
      final sameIp = incoming.ipAddress.isNotEmpty &&
          entry.value.ipAddress == incoming.ipAddress;
      if (sameMac || sameIp) {
        matchedKey = entry.key;
        break;
      }
    }
    final existing = matchedKey == null ? null : _devices.remove(matchedKey);
    if (existing == null) {
      _devices[key] = incoming;
    } else {
      _devices[key] = existing.copyWith(
        id: key,
        ipAddress: incoming.ipAddress.isNotEmpty ? incoming.ipAddress : existing.ipAddress,
        macAddress: existing.macAddress.isEmpty ? incoming.macAddress : existing.macAddress,
        manufacturer: existing.manufacturer.startsWith('ONVIF') ? incoming.manufacturer : existing.manufacturer,
        model: existing.model == 'Model unknown' ? incoming.model : existing.model,
        firmwareVersion: existing.firmwareVersion.isEmpty ? incoming.firmwareVersion : existing.firmwareVersion,
        discoverySources: {...existing.discoverySources, ...incoming.discoverySources}.toList(),
        onvifEndpoint: existing.onvifEndpoint.isEmpty ? incoming.onvifEndpoint : existing.onvifEndpoint,
        deviceServiceUrl: existing.deviceServiceUrl.isEmpty ? incoming.deviceServiceUrl : existing.deviceServiceUrl,
        lastSeen: DateTime.now(),
      );
    }
    notifyListeners();
  }

  Future<void> addManualDevice(String address) async {
    final parsed = InternetAddress.tryParse(address.trim());
    if (parsed == null || parsed.type != InternetAddressType.IPv4 || parsed.isLoopback || parsed.isMulticast) {
      throw const FormatException('Enter a valid unicast IPv4 address.');
    }
    _merge(CameraDevice(
      id: parsed.address,
      ipAddress: parsed.address,
      discoverySources: const ['Manual'],
      lastSeen: DateTime.now(),
    ));
  }

  Future<void> scanSubnet(InternetAddress localAddress, InternetAddress mask) async {
    final ip = localAddress.rawAddress;
    final maskBytes = mask.rawAddress;
    if (ip.length != 4 || maskBytes.length != 4) throw const FormatException('IPv4 only.');
    var network = 0, broadcast = 0, own = 0;
    for (var i = 0; i < 4; i++) {
      network = (network << 8) | (ip[i] & maskBytes[i]);
      broadcast = (broadcast << 8) | ((ip[i] & maskBytes[i]) | (~maskBytes[i] & 255));
      own = (own << 8) | ip[i];
    }
    final first = network + 1;
    final last = broadcast - 1;
    if (last < first) throw const FormatException('Invalid subnet.');
    final end = last < first + 255 ? last : first + 255;
    final hosts = <int>[];
    for (var host = first; host <= end; host++) {
      if (host != own) hosts.add(host);
    }
    const ports = [80, 443, 554, 8000, 8080, 8899, 34567];
    var completed = 0;
    var candidates = 0;
    _setStatus('Scanning a bounded range of ${hosts.length} local IPv4 hosts…');
    final tasks = <Future<void>>[];
    final semaphore = _AsyncSemaphore(24);
    for (final host in hosts) {
      final address = InternetAddress.fromRawAddress([
        (host >> 24) & 255, (host >> 16) & 255, (host >> 8) & 255, host & 255,
      ]);
      tasks.add(() async {
        await semaphore.acquire();
        try {
          final openPorts = <int>[];
          for (final port in ports) {
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
          if (openPorts.isNotEmpty) {
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
          semaphore.release();
        }
      }());
    }
    await Future.wait(tasks);
    _setStatus('Subnet scan complete. $candidates unverified candidate(s) found from $completed host(s).');
  }

  Future<String> checkReachability(CameraDevice device) async {
    const ports = [80, 443, 554, 8000, 8080, 8899, 34567];
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

  void _finishDiscovery() {
    _timeout = null;
    _isScanning = false;
    _closeSockets();
    _setStatus('Discovery finished. ${_devices.length} device(s) found.');
  }

  Future<void> cancelDiscovery({bool notify = true}) async {
    _timeout?.cancel();
    _timeout = null;
    _isScanning = false;
    _closeSockets();
    if (notify) _setStatus('Discovery cancelled.');
  }

  void _closeSockets() {
    for (final socket in _sockets) {
      _sequences.remove(socket);
      socket.close();
    }
    _sockets.clear();
  }

  @override
  void dispose() {
    _timeout?.cancel();
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
