class CameraDevice {
  const CameraDevice({
    required this.id,
    required this.ipAddress,
    this.macAddress = '',
    this.manufacturer = 'Unknown',
    this.model = 'Model unknown',
    this.firmwareVersion = '',
    this.activationState = 'Unknown',
    this.discoverySources = const [],
    this.interfaceName = '',
    this.onvifEndpoint = '',
    this.deviceServiceUrl = '',
    this.isCandidate = false,
    this.openPorts = const [],
    this.lastSeen,
    this.reachabilityStatus = 'Not checked',
  });

  final String id;
  final String ipAddress;
  final String macAddress;
  final String manufacturer;
  final String model;
  final String firmwareVersion;
  final String activationState;
  final List<String> discoverySources;
  final String interfaceName;
  final String onvifEndpoint;
  final String deviceServiceUrl;
  final bool isCandidate;
  final List<int> openPorts;
  final DateTime? lastSeen;
  final String reachabilityStatus;

  CameraDevice copyWith({
    String? id, String? ipAddress, String? macAddress, String? manufacturer,
    String? model, String? firmwareVersion, String? activationState,
    List<String>? discoverySources, String? interfaceName,
    String? onvifEndpoint, String? deviceServiceUrl, bool? isCandidate,
    List<int>? openPorts, DateTime? lastSeen, String? reachabilityStatus,
  }) => CameraDevice(
    id: id ?? this.id,
    ipAddress: ipAddress ?? this.ipAddress,
    macAddress: macAddress ?? this.macAddress,
    manufacturer: manufacturer ?? this.manufacturer,
    model: model ?? this.model,
    firmwareVersion: firmwareVersion ?? this.firmwareVersion,
    activationState: activationState ?? this.activationState,
    discoverySources: discoverySources ?? this.discoverySources,
    interfaceName: interfaceName ?? this.interfaceName,
    onvifEndpoint: onvifEndpoint ?? this.onvifEndpoint,
    deviceServiceUrl: deviceServiceUrl ?? this.deviceServiceUrl,
    isCandidate: isCandidate ?? this.isCandidate,
    openPorts: openPorts ?? this.openPorts,
    lastSeen: lastSeen ?? this.lastSeen,
    reachabilityStatus: reachabilityStatus ?? this.reachabilityStatus,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'ipAddress': ipAddress, 'macAddress': macAddress,
    'manufacturer': manufacturer, 'model': model,
    'firmwareVersion': firmwareVersion, 'activationState': activationState,
    'discoverySources': discoverySources, 'interfaceName': interfaceName,
    'onvifEndpoint': onvifEndpoint, 'deviceServiceUrl': deviceServiceUrl,
    'isCandidate': isCandidate, 'openPorts': openPorts,
    'lastSeen': lastSeen?.toIso8601String(),
    'reachabilityStatus': reachabilityStatus,
  };

  factory CameraDevice.fromJson(Map<String, dynamic> json) => CameraDevice(
    id: json['id'] as String? ?? '',
    ipAddress: json['ipAddress'] as String? ?? '',
    macAddress: json['macAddress'] as String? ?? '',
    manufacturer: json['manufacturer'] as String? ?? 'Unknown',
    model: json['model'] as String? ?? 'Model unknown',
    firmwareVersion: json['firmwareVersion'] as String? ?? '',
    activationState: json['activationState'] as String? ?? 'Unknown',
    discoverySources: (json['discoverySources'] as List<dynamic>? ?? []).cast<String>(),
    interfaceName: json['interfaceName'] as String? ?? '',
    onvifEndpoint: json['onvifEndpoint'] as String? ?? '',
    deviceServiceUrl: json['deviceServiceUrl'] as String? ?? '',
    isCandidate: json['isCandidate'] as bool? ?? false,
    openPorts: (json['openPorts'] as List<dynamic>? ?? []).whereType<num>().map((v) => v.toInt()).toList(),
    lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? ''),
    reachabilityStatus: json['reachabilityStatus'] as String? ?? 'Not checked',
  );
}
