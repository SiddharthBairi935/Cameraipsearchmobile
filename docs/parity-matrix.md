# Desktop-to-mobile parity matrix

This is a capability-by-capability implementation record, not a blanket compatibility promise.

| Desktop capability | Mobile status | Notes |
|---|---|---|
| ONVIF WS-Discovery | Initial implementation | Multicast 239.255.255.250:3702; validate on physical devices |
| Project Contract B discovery | Initial implementation | UDP broadcast port 9988; checks magic, version, sequence, command and field types |
| Device inventory | Initial implementation | Local preferences persistence; migrate to SQLite for larger histories |
| Duplicate merge / source provenance | Initial implementation | MAC preferred, IP fallback |
| Manual device entry | Initial implementation | IPv4 only |
| Candidate subnet scan | Initial implementation | User-entered CIDR, max 256 hosts, bounded common-port checks |
| Reachability check | Initial implementation | TCP connection checks on common camera ports |
| Search and device details | Initial implementation | Mobile-native list and details sheet |
| CSV export | Not implemented | Planned |
| ONVIF GetDeviceInformation / capabilities | Not implemented | Requires SOAP client and session-scoped authentication |
| ONVIF network interface discovery | Not implemented | Must read interface tokens/capabilities before changes |
| Static IP / DHCP configuration | Not implemented | Must port validation, auth, confirmation and post-change verification |
| Batch configuration | Not implemented | Requires preview and per-device outcomes |
| Firmware update | Not implemented | Requires verified vendor contracts and recovery plan |
| NVR channels | Not implemented | Separate capability milestone |
| Vendor-specific adapters | Not implemented | Exact model/firmware and official SDK/protocol evidence required |

## Protocol rules

- ONVIF discovery is separate from the proprietary project camera protocol.
- Project firmware discovery uses UDP port 9988 and Contract B version 1 only.
- An open TCP port is a candidate signal, not proof of camera identity.
- Unknown and unsupported capabilities must remain unavailable.
- Never guess credentials or invent undocumented device commands.

## Platform requirements

### Android
Local-network UDP/TCP access is subject to Android's local-network protections. Apps targeting Android 17 (API 37) must declare and request ACCESS_LOCAL_NETWORK for direct LAN operations. Add the runtime permission flow before raising targetSdk to 37. Wi-Fi multicast behavior must be validated on physical devices.

### iOS
Add NSLocalNetworkUsageDescription to Info.plist. UDP multicast and broadcast additionally require Apple's com.apple.developer.networking.multicast entitlement and an authorized provisioning profile. Until Apple grants the entitlement and an entitled physical-device build is tested, iOS discovery parity is unverified.

## Validation gates

1. Run flutter pub get, flutter analyze and flutter test.
2. Test parsers against deterministic ONVIF and Contract B fixtures.
3. Test Android on physical devices and different access points/subnets.
4. Request the Apple multicast entitlement and validate an entitled ad-hoc/TestFlight build.
5. Test the exact models and firmware recorded in the desktop compatibility matrix.
6. Mark hardware-tested only when exact model, hardware revision and firmware are recorded.
