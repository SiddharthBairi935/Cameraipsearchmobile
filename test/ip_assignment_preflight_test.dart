import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ip_search_mobile/services/ip_assignment_preflight.dart';
import 'package:camera_ip_search_mobile/services/ip_assignment_planner.dart';

void main() {
  test('blocks occupied addresses and missing or unknown probe backends', () async {
    const preflight = IpAssignmentPreflight();
    const plan = [IpAssignmentTarget(deviceId: 'cam-a', currentAddress: '192.168.1.10', proposedAddress: '192.168.1.20'),
      IpAssignmentTarget(deviceId: 'cam-b', currentAddress: '192.168.1.11', proposedAddress: '192.168.1.21')];
    final result = await preflight.evaluate(plan: plan, inventoryAddresses: {'192.168.1.20'});
    expect(result[0].state, IpAssignmentPreflightState.addressConflict);
    expect(result[1].state, IpAssignmentPreflightState.probeUnavailable);
    final unknown = await preflight.evaluate(plan: plan, probe: (_) async =>
      const IpAddressProbeResult(IpAddressProbeState.unknown, 'No platform ARP backend.'));
    expect(unknown.every((r) => r.state == IpAssignmentPreflightState.probeUnavailable), isTrue);
  });

  test('only explicit clear result makes a target ready', () async {
    final result = await const IpAssignmentPreflight().evaluate(
      plan: const [IpAssignmentTarget(deviceId: 'cam-a', currentAddress: '', proposedAddress: '192.168.1.20')],
      probe: (_) async => const IpAddressProbeResult(IpAddressProbeState.clear, 'DAD reported zero responses.'));
    expect(result.single.state, IpAssignmentPreflightState.ready);
  });
}
