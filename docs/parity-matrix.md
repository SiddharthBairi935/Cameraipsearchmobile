# Desktop PR #4 → Mobile parity matrix

Source of truth: https://github.com/Karishma6543/camera-ip-search/pull/4 (`release/oxita-production-ready`).

Status distinguishes a mobile code path from verified physical-device behavior.

| Desktop PR #4 capability | Mobile status | Notes |
|---|---|---|
| ONVIF WS-Discovery | Implemented; hardware validation pending | UDP multicast requires platform permission/entitlement |
| Project Contract B UDP 9988 | Implemented; hardware validation pending | Sequence and schema validation |
| Active IPv4 interface selection | Implemented | Interface dropdown filters discovery |
| ONVIF XAddr safety | Implemented | Same host, HTTP(S), no credentials/query/fragment |
| Project response source binding | Implemented | Source IP authoritative; 0.0.0.0 unconfigured fallback |
| Stable device identity | Implemented | MAC, endpoint, serial+manufacturer, guarded IP |
| ONVIF GetDeviceInformation | Implemented | Manufacturer, model, firmware, serial, hardware ID |
| ONVIF GetCapabilities | Implemented | Device, Media, PTZ, Imaging, Events, Analytics, Extension |
| ONVIF GetNetworkInterfaces | Implemented | Match current camera IP before exposing write token |
| ONVIF GetDNS | Implemented | Read-only DNS reporting |
| Local SQLite inventory | Implemented | Device records persisted locally |
| Manual device entry / labels | Implemented | IPv4 manual entry and user label |
| Search and filters | Implemented | IP/MAC/model/serial/label, manufacturer and status |
| CSV export | Implemented | Shares filtered inventory with extended device columns |
| Bounded TCP candidate scan | Implemented | Up to 256 hosts, common ports, candidates remain unverified |
| Scan progress / cancellation | Implemented | Cancellation waits for current bounded socket attempt |
| Multi-device reachability | Implemented | Selected devices first; otherwise current filtered inventory |
| Reachability timestamps | Implemented | Checked-at and last-success fields |
| Static IPv4 validation | Implemented | Address, contiguous mask, gateway/subnet checks |
| ONVIF SetNetworkInterfaces | Implemented in code | Requires verified matching interface token |
| New-IP post-change verification | Implemented in code | Inventory updates only after matching token/address is verified |
| SetNetworkDefaultGateway | Implemented in code | Partial result retains verified new IP if gateway step fails |
| Device Info / Maintenance / Bulk / NVR workspaces | Mobile detail/tools adaptation | Unimplemented desktop operations remain disabled/labelled |
| CP Plus / Hikvision / Prama adapters | Not implemented | No verified desktop adapters |
| Project activation/configuration | Not implemented | No wire contract |
| Firmware update / reboot / NVR / bulk config | Not implemented | Same as desktop PR #4 |
| ONVIF WS-Security / OS credential vault | Not implemented | Session HTTP challenge credentials only |

## Platform-specific parity gaps

- Android local-network permission and multicast lock are bridged in the generated runner; verify targetSdk/API 37 behavior on real devices.
- iOS adds the local-network usage description, but Apple's multicast entitlement is still required for UDP multicast/broadcast. Until approved and tested, iOS discovery is not confirmed.
- Dart's network interface API exposes fewer link diagnostics than Qt's desktop API. Interface name and IPv4 addresses are available; desktop MTU/broadcast/link-state parity requires native per-platform work.

## Quality gates

1. `flutter pub get`, `flutter analyze`, `flutter test`.
2. Parser fixtures for ONVIF ProbeMatch and Contract B malformed/host-mismatch cases.
3. Android real-device discovery across Wi-Fi and Ethernet/USB tethering where supported.
4. iOS entitled physical-device discovery.
5. ONVIF read operations on exact camera models/firmware.
6. Static IPv4 writes on supported models, including rejected writes, reboot-needed responses, address verification and gateway partial failure.
7. Record model, hardware revision, firmware, topology and test evidence. A code path alone is not hardware support.
