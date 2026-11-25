import '../models/camera_device.dart';

enum DeviceType { camera, nvr, router, switchDevice, printer, computer, unknown }
enum DeviceConfidence { verified, high, probable, unverified }

class DeviceClassification {
  const DeviceClassification(this.type, this.confidence, this.reason);
  final DeviceType type;
  final DeviceConfidence confidence;
  final String reason;
  String get key => switch (type) {
    DeviceType.camera => 'camera', DeviceType.nvr => 'nvr',
    DeviceType.router => 'router', DeviceType.switchDevice => 'switch',
    DeviceType.printer => 'printer', DeviceType.computer => 'computer',
    DeviceType.unknown => 'unknown',
  };
  String get label => switch (type) {
    DeviceType.camera => 'Camera', DeviceType.nvr => 'NVR',
    DeviceType.router => 'Router', DeviceType.switchDevice => 'Switch',
    DeviceType.printer => 'Printer', DeviceType.computer => 'Computer',
    DeviceType.unknown => 'Unknown',
  };
  String get confidenceLabel => switch (confidence) {
    DeviceConfidence.verified => 'Verified', DeviceConfidence.high => 'High',
    DeviceConfidence.probable => 'Probable', DeviceConfidence.unverified => 'Unverified',
  };
}

class DeviceClassifier {
  const DeviceClassifier._();
  static bool _has(String value, List<String> words) {
    final normalized = value.toLowerCase();
    return words.any(normalized.contains);
  }
  static DeviceClassification classify(CameraDevice device) {
    final identity = '${device.manufacturer} ${device.model} ${device.hardwareId}'.toLowerCase();
    final sources = device.discoverySources.map((s) => s.toLowerCase()).toList();
    final ports = device.openPorts.toSet();
    final onvif = sources.any((s) => s.contains('onvif'));
    final oxita = device.manufacturer.toLowerCase() == 'oxita' ||
        sources.any((s) => s.contains('oxita') || s.contains('project udp 9988'));
    final ssdp = sources.contains('ssdp/upnp');
    if (ssdp && _has(identity, ['internetgatewaydevice','wanconnectiondevice','wandevice'])) {
      return const DeviceClassification(DeviceType.router, DeviceConfidence.high, 'SSDP identifies an Internet Gateway Device');
    }
    if (ssdp && _has(identity, ['urn:schemas-upnp-org:device:printer', ':printer'])) {
      return const DeviceClassification(DeviceType.printer, DeviceConfidence.high, 'SSDP identifies a UPnP printer');
    }
    if (_has(identity, ['nvr','dvr','xvr','video recorder','network video recorder'])) {
      return const DeviceClassification(DeviceType.nvr, DeviceConfidence.high, 'Manufacturer or model identifies a video recorder');
    }
    if (onvif || oxita) {
      return DeviceClassification(DeviceType.camera, DeviceConfidence.verified,
        onvif ? 'Identified through ONVIF discovery' : 'Identified through Oxita device discovery');
    }
    if (_has(identity, ['printer','laserjet','deskjet','officejet','imageclass','workcentre'])) {
      return const DeviceClassification(DeviceType.printer, DeviceConfidence.high, 'Manufacturer or model identifies a printer');
    }
    if (_has(identity, ['wireless router','router','gateway','firewall'])) {
      return const DeviceClassification(DeviceType.router, DeviceConfidence.high, 'Manufacturer or model identifies a router or gateway');
    }
    if (_has(identity, ['network switch','ethernet switch','poe switch','switch'])) {
      return const DeviceClassification(DeviceType.switchDevice, DeviceConfidence.high, 'Manufacturer or model identifies a network switch');
    }
    if (_has(identity, ['workstation','desktop pc','laptop','windows pc'])) {
      return const DeviceClassification(DeviceType.computer, DeviceConfidence.high, 'Manufacturer or model identifies a computer');
    }
    final printerSignals = [9100,631,515].where(ports.contains).length;
    if (printerSignals >= 2) return const DeviceClassification(DeviceType.printer, DeviceConfidence.probable, 'Multiple printer service ports responded');
    if (ports.contains(53) && [80,443,7547].any(ports.contains)) {
      return const DeviceClassification(DeviceType.router, DeviceConfidence.probable, 'DNS and gateway-management service ports responded');
    }
    if (ports.contains(445) && ports.contains(3389) || (ports.contains(135) && ports.contains(139))) {
      return const DeviceClassification(DeviceType.computer, DeviceConfidence.probable, 'File-sharing or remote-desktop service ports responded');
    }
    if (ports.contains(554) && [80,443,8000,8080].any(ports.contains)) {
      return const DeviceClassification(DeviceType.camera, DeviceConfidence.probable, 'RTSP and web-management ports responded; camera identity is unverified');
    }
    return DeviceClassification(DeviceType.unknown, DeviceConfidence.unverified,
      device.isCandidate ? 'Only generic network reachability has been established' : 'Not enough reliable identity evidence is available');
  }
}
