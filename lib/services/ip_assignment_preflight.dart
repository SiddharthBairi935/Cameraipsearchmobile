import 'ip_assignment_planner.dart';

enum IpAddressProbeState { clear, conflict, unknown }
enum IpAssignmentPreflightState { ready, addressConflict, probeUnavailable, invalidPlan }

class IpAddressProbeResult {
  const IpAddressProbeResult(this.state, this.evidence);
  final IpAddressProbeState state;
  final String evidence;
}

class IpAssignmentPreflightResult {
  const IpAssignmentPreflightResult({
    required this.target,
    required this.state,
    required this.message,
  });
  final IpAssignmentTarget target;
  final IpAssignmentPreflightState state;
  final String message;
}

typedef IpAddressProbe = Future<IpAddressProbeResult> Function(String address);

class IpAssignmentPreflight {
  const IpAssignmentPreflight();

  Future<List<IpAssignmentPreflightResult>> evaluate({
    required List<IpAssignmentTarget> plan,
    Set<String> inventoryAddresses = const {},
    Set<String> localReservedAddresses = const {},
    IpAddressProbe? probe,
  }) async {
    final occupied = {...inventoryAddresses, ...localReservedAddresses}.map((v) => v.trim()).toSet();
    final ids = <String>{};
    final addresses = <String>{};
    var structurallyValid = plan.isNotEmpty;
    for (final target in plan) {
      if (target.deviceId.trim().isEmpty || !ids.add(target.deviceId.trim()) ||
          !_validIpv4(target.proposedAddress) || !addresses.add(target.proposedAddress.trim())) {
        structurallyValid = false;
      }
    }
    final results = <IpAssignmentPreflightResult>[];
    for (final target in plan) {
      if (!structurallyValid) {
        results.add(IpAssignmentPreflightResult(target: target, state: IpAssignmentPreflightState.invalidPlan,
          message: 'Plan contains missing/duplicate IDs, invalid IPv4 values or duplicate target addresses.'));
      } else if (occupied.contains(target.proposedAddress.trim())) {
        results.add(IpAssignmentPreflightResult(target: target, state: IpAssignmentPreflightState.addressConflict,
          message: 'Proposed address is reserved by inventory or local network configuration.'));
      } else if (probe == null) {
        results.add(IpAssignmentPreflightResult(target: target, state: IpAssignmentPreflightState.probeUnavailable,
          message: 'No validated live conflict-probe backend is available on this platform. Assignment is blocked.'));
      } else {
        final result = await probe(target.proposedAddress);
        switch (result.state) {
          case IpAddressProbeState.clear:
            results.add(IpAssignmentPreflightResult(target: target, state: IpAssignmentPreflightState.ready,
              message: result.evidence.isEmpty ? 'No conflict detected by the configured probe.' : result.evidence));
          case IpAddressProbeState.conflict:
            results.add(IpAssignmentPreflightResult(target: target, state: IpAssignmentPreflightState.addressConflict,
              message: result.evidence.isEmpty ? 'A live probe detected an address conflict.' : result.evidence));
          case IpAddressProbeState.unknown:
            results.add(IpAssignmentPreflightResult(target: target, state: IpAssignmentPreflightState.probeUnavailable,
              message: result.evidence.isEmpty ? 'Address availability could not be verified.' : result.evidence));
        }
      }
    }
    return List.unmodifiable(results);
  }

  bool _validIpv4(String value) {
    final parts = value.trim().split('.');
    if (parts.length != 4) return false;
    return parts.every((part) {
      final number = int.tryParse(part);
      return number != null && number >= 0 && number <= 255 && part == number.toString();
    });
  }
}
