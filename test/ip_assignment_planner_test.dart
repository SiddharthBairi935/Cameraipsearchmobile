import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ip_search_mobile/services/ip_assignment_planner.dart';

void main() {
  group('IpAssignmentPlanner', () {
    test('creates sequential plan and maps selected devices', () {
      final result = IpAssignmentPlanner.build(
        startAddress: '192.168.1.10', endAddress: '192.168.1.20', subnetMask: '255.255.255.0',
        selectedDevices: const [
          IpAssignmentTarget(deviceId: 'cam-a', currentAddress: '192.168.1.10'),
          IpAssignmentTarget(deviceId: 'cam-b', currentAddress: '192.168.1.11'),
        ],
      );
      expect(result.targets.map((t) => t.proposedAddress), ['192.168.1.12', '192.168.1.13']);
    });

    test('skips all reserved inventory addresses', () {
      final result = IpAssignmentPlanner.build(
        startAddress: '192.168.1.20', endAddress: '192.168.1.24', subnetMask: '255.255.255.0',
        selectedDevices: const [IpAssignmentTarget(deviceId: 'a', currentAddress: '10.0.0.2')],
        reservedAddresses: {'192.168.1.20', '192.168.1.22'},
      );
      expect(result.targets.single.proposedAddress, '192.168.1.21');
    });

    test('rejects invalid, cross-subnet, network/broadcast and oversized ranges', () {
      for (final values in [
        ['bad', '192.168.1.20', '255.255.255.0'],
        ['192.168.1.250', '192.168.2.10', '255.255.255.0'],
        ['192.168.1.0', '192.168.1.20', '255.255.255.0'],
        ['192.168.1.20', '192.168.1.255', '255.255.255.0'],
        ['10.0.0.1', '10.1.0.1', '255.0.0.0'],
      ]) {
        expect(() => IpAssignmentPlanner.build(
          startAddress: values[0], endAddress: values[1], subnetMask: values[2],
          selectedDevices: const [IpAssignmentTarget(deviceId: 'a', currentAddress: '')],
        ), throwsFormatException);
      }
    });

    test('rejects duplicate IDs and insufficient free addresses', () {
      expect(() => IpAssignmentPlanner.build(
        startAddress: '192.168.1.10', endAddress: '192.168.1.20', subnetMask: '255.255.255.0',
        selectedDevices: const [
          IpAssignmentTarget(deviceId: 'same', currentAddress: ''),
          IpAssignmentTarget(deviceId: 'same', currentAddress: ''),
        ],
      ), throwsFormatException);
      expect(() => IpAssignmentPlanner.build(
        startAddress: '192.168.1.10', endAddress: '192.168.1.10', subnetMask: '255.255.255.0',
        selectedDevices: const [IpAssignmentTarget(deviceId: 'a', currentAddress: '')],
        reservedAddresses: {'192.168.1.10'},
      ), throwsFormatException);
    });
  });
}
