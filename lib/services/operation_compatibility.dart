enum OperationEvidenceStatus {
  deviceResponded,
  implementedNotTested,
  serviceAdvertisedNotVerified,
  authenticationNotVerified,
  serviceNotReported,
  notImplemented,
}

class OperationEvidence {
  const OperationEvidence(this.operation, this.status, this.evidence);
  final String operation;
  final OperationEvidenceStatus status;
  final String evidence;

  String get statusLabel => switch (status) {
    OperationEvidenceStatus.deviceResponded => 'Device responded',
    OperationEvidenceStatus.implementedNotTested => 'Implemented; not tested',
    OperationEvidenceStatus.serviceAdvertisedNotVerified => 'Advertised; not implemented',
    OperationEvidenceStatus.authenticationNotVerified => 'Authentication / permission not verified',
    OperationEvidenceStatus.serviceNotReported => 'Service not reported',
    OperationEvidenceStatus.notImplemented => 'Not implemented',
  };
}

class OperationCompatibility {
  const OperationCompatibility._();

  static List<OperationEvidence> evaluate({
    required List<String> discoverySources,
    required List<String> capabilities,
  }) {
    const definitions = <({String label, String service, String response, bool implemented})>[
      (label: 'Read device information', service: 'Device', response: 'ONVIF GetDeviceInformation', implemented: true),
      (label: 'Read capabilities', service: 'Device', response: 'ONVIF GetCapabilities', implemented: true),
      (label: 'Read network interfaces', service: 'Device', response: 'ONVIF GetNetworkInterfaces', implemented: true),
      (label: 'Read DNS configuration', service: 'Device', response: 'ONVIF GetDNS', implemented: true),
      (label: 'Configure static IPv4', service: 'Device', response: '', implemented: true),
      (label: 'Configure DHCP', service: 'Device', response: '', implemented: true),
      (label: 'Configure DNS', service: 'Device', response: '', implemented: true),
      (label: 'Reboot camera', service: 'Device', response: '', implemented: true),
      (label: 'Factory reset', service: 'Device', response: '', implemented: true),
      (label: 'Preview stream / RTSP URI', service: 'Media', response: '', implemented: false),
      (label: 'Capture snapshot', service: 'Media', response: '', implemented: false),
      (label: 'Change camera password', service: 'Device', response: '', implemented: false),
      (label: 'Firmware upgrade', service: 'Device', response: '', implemented: false),
      (label: 'Image settings', service: 'Imaging', response: '', implemented: false),
      (label: 'PTZ controls', service: 'PTZ', response: '', implemented: false),
      (label: 'Events and alarms', service: 'Events', response: '', implemented: false),
      (label: 'NVR channel management', service: 'Recording', response: '', implemented: false),
    ];
    final normalized = capabilities.map((v) => v.toLowerCase().replaceFirst('service: ', '')).toSet();
    return definitions.map((definition) {
      final responded = definition.response.isNotEmpty && discoverySources.contains(definition.response);
      final advertised = normalized.contains(definition.service.toLowerCase());
      late final OperationEvidenceStatus status;
      late final String evidence;
      if (responded) {
        status = OperationEvidenceStatus.deviceResponded;
        evidence = 'A successful response was recorded during discovery or refresh.';
      } else if (!definition.implemented) {
        status = advertised ? OperationEvidenceStatus.serviceAdvertisedNotVerified : OperationEvidenceStatus.notImplemented;
        evidence = advertised
            ? 'The device advertises this service, but the mobile application does not implement this operation.'
            : 'This operation is not implemented by the current mobile adapter.';
      } else if (definition.response.isNotEmpty) {
        status = OperationEvidenceStatus.implementedNotTested;
        evidence = 'The mobile application implements this read request, but no successful device response is recorded.';
      } else if (advertised) {
        status = OperationEvidenceStatus.authenticationNotVerified;
        evidence = 'The service is advertised and a request exists, but authentication, authorization and operation success are not verified.';
      } else {
        status = OperationEvidenceStatus.serviceNotReported;
        evidence = 'The application has an implementation, but the device has not reported this service.';
      }
      return OperationEvidence(definition.label, status, evidence);
    }).toList(growable: false);
  }
}
