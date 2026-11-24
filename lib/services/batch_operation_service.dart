import '../models/camera_device.dart';

enum DeviceBatchOperation { readDeviceInformation, readCapabilities, readNetworkInterfaces, configureStaticIpv4, reboot, updateFirmware }
enum BatchTargetState { ready, missingIdentity, duplicateTarget, duplicateAddress, noCompatibleAdapter, unsupportedOperation, succeeded, executionFailed, cancelled }

class BatchTargetResult {
  const BatchTargetResult({required this.device, required this.state, required this.message, this.adapterId = ''});
  final CameraDevice device;
  final BatchTargetState state;
  final String message;
  final String adapterId;
  BatchTargetResult withOutcome(BatchTargetState value, String detail) =>
      BatchTargetResult(device: device, state: value, message: detail, adapterId: adapterId);
}

class BatchOperationPreflight {
  const BatchOperationPreflight();

  List<BatchTargetResult> build(List<CameraDevice> devices, DeviceBatchOperation operation) {
    final idCounts = <String, int>{};
    final addressCounts = <String, int>{};
    for (final device in devices) {
      final id = device.id.trim();
      final address = _canonicalIpv4(device.ipAddress);
      if (id.isNotEmpty) idCounts.update(id, (v) => v + 1, ifAbsent: () => 1);
      if (address.isNotEmpty) addressCounts.update(address, (v) => v + 1, ifAbsent: () => 1);
    }
    return List.unmodifiable(devices.map((device) {
      final id = device.id.trim();
      final address = _canonicalIpv4(device.ipAddress);
      if (id.isEmpty) return BatchTargetResult(device: device, state: BatchTargetState.missingIdentity, message: 'Device has no stable inventory ID.');
      if (idCounts[id]! > 1) return BatchTargetResult(device: device, state: BatchTargetState.duplicateTarget, message: 'Device ID occurs more than once in the batch.');
      if (address.isNotEmpty && addressCounts[address]! > 1) return BatchTargetResult(device: device, state: BatchTargetState.duplicateAddress, message: 'IPv4 address occurs more than once in the batch.');
      final adapter = _adapterFor(device);
      if (adapter == null) return BatchTargetResult(device: device, state: BatchTargetState.noCompatibleAdapter, message: 'No compatible verified adapter.');
      final supported = switch (operation) {
        DeviceBatchOperation.readDeviceInformation => device.capabilities.contains('GetDeviceInformation') || device.discoverySources.any((s) => s.startsWith('ONVIF')),
        DeviceBatchOperation.readCapabilities => device.capabilities.contains('GetCapabilities') || device.discoverySources.any((s) => s.startsWith('ONVIF')),
        DeviceBatchOperation.readNetworkInterfaces => true,
        DeviceBatchOperation.configureStaticIpv4 => device.ipv4ConfigurationKnown && device.networkInterfaceToken.isNotEmpty && device.deviceServiceUrl.isNotEmpty,
        DeviceBatchOperation.reboot || DeviceBatchOperation.updateFirmware => false,
      };
      return BatchTargetResult(device: device,
        state: supported ? BatchTargetState.ready : BatchTargetState.unsupportedOperation,
        message: supported ? 'Verified adapter advertises this operation.' : 'Adapter does not support this operation.',
        adapterId: adapter);
    }));
  }

  String? _adapterFor(CameraDevice device) {
    final uri = Uri.tryParse(device.deviceServiceUrl);
    if (uri == null || !uri.hasAuthority || (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
        uri.host.toLowerCase() != device.ipAddress.toLowerCase() ||
        !(device.discoverySources.any((s) => s.startsWith('ONVIF')) ||
          device.onvifEndpoint.isNotEmpty || device.discoverySources.contains('ONVIF GetDeviceInformation'))) {
      return null;
    }
    return 'onvif';
  }

  String _canonicalIpv4(String value) {
    final parsed = Uri.tryParse('http://$value');
    if (parsed == null || parsed.host.isEmpty || parsed.host.contains(':')) return '';
    final parts = parsed.host.split('.');
    if (parts.length != 4) return '';
    final nums = parts.map(int.tryParse).toList();
    if (nums.any((v) => v == null || v < 0 || v > 255)) return '';
    return nums.join('.');
  }
}

typedef BatchOperationHandler = Future<String?> Function(CameraDevice device, DeviceBatchOperation operation);

class BatchOperationRunner {
  bool _running = false;
  bool _cancelRequested = false;
  int _completed = 0;
  List<BatchTargetResult> _results = const [];

  bool get isRunning => _running;
  int get completedCount => _completed;
  int get totalCount => _results.length;
  List<BatchTargetResult> get results => List.unmodifiable(_results);

  Future<List<BatchTargetResult>> start({
    required List<CameraDevice> devices,
    required DeviceBatchOperation operation,
    required BatchOperationHandler handler,
  }) async {
    if (_running || devices.isEmpty) throw StateError('A batch must be idle and contain at least one target.');
    _results = BatchOperationPreflight().build(devices, operation);
    _completed = 0;
    _cancelRequested = false;
    _running = true;
    try {
      for (var index = 0; index < _results.length; index++) {
        final initial = _results[index];
        if (_cancelRequested) {
          if (initial.state == BatchTargetState.ready) {
            _results[index] = initial.withOutcome(BatchTargetState.cancelled, 'Cancelled before execution.');
          }
        } else if (initial.state == BatchTargetState.ready) {
          try {
            final detail = await handler(initial.device, operation);
            _results[index] = initial.withOutcome(detail == null ? BatchTargetState.succeeded : BatchTargetState.executionFailed,
              detail ?? 'Operation completed.');
          } catch (error) {
            _results[index] = initial.withOutcome(BatchTargetState.executionFailed, error.toString());
          }
        }
        _completed++;
        if (_cancelRequested) {
          for (var rest = index + 1; rest < _results.length; rest++) {
            if (_results[rest].state == BatchTargetState.ready) {
              _results[rest] = _results[rest].withOutcome(BatchTargetState.cancelled, 'Cancelled before execution.');
            }
            _completed++;
          }
          break;
        }
      }
      return results;
    } finally {
      _running = false;
    }
  }

  void cancel() => _cancelRequested = true;
}
