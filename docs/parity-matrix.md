# Desktop PR #5 → Mobile parity matrix (historical baseline)

The current source of truth has moved to desktop `main`. See [desktop-main-parity.md](desktop-main-parity.md) for the current feature mapping, including IP assignment planning, batch preflight/runner and firmware candidate validation.

Source of truth: https://github.com/Karishma6543/camera-ip-search/pull/5 (`release/preproduction-hardening`), stacked on PR #4.

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
| Local SQLite inventory | Implemented | Device records persisted locally; `PRAGMA quick_check` before schema callbacks; invalid DB is not intentionally overwritten |
| Persistent Operation History | Implemented | Latest 1,000 events retained; latest 250 shown; sensitive-looking values redacted |
| Rotating application logs | Implemented | 2 MiB active log, three archives; best-effort credential redaction |
| User-confirmed diagnostic bundle | Implemented | OS/runtime, interface summary, recent history and redacted logs; no DB file or ONVIF interface tokens; preview before share |
| Simulator protocol fixtures | Implemented in tests | Dart fixtures mirror desktop Contract B and limited ONVIF scenarios; no production simulator server embedded |
| Cancellation history | Implemented | Discovery, subnet scan and reachability record Completed/Cancelled outcomes |
| Background cancellation | Implemented | App cancels active scans when it becomes inactive/paused/detached |
| Manual IP / hostname entry | Implemented | Validated IP addresses and DNS hostnames |
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
| ONVIF WS-Security / OS credential vault | Not implemented | Session-only HTTP Basic and Digest MD5/MD5-sess qop=auth challenge credentials; Digest SHA-256, auth-int and WS-Security are not implemented |

## Platform-specific parity gaps

- Android local-network permission, multicast lock, MTU and link-state diagnostics are bridged in the generated runner; verify targetSdk/API 37 behavior on real devices.
- iOS adds the local-network usage description, but Apple's multicast entitlement is still required for UDP multicast/broadcast. Until approved and tested, iOS discovery is not confirmed.
- Native interface diagnostics are bridged from Android (MTU and link state) and iOS (link state; MTU is not exposed by the current bridge). Interface address/prefix/broadcast remain subject to what the OS exposes through Dart. Validate all fields on physical devices.

## Quality gates

1. `flutter pub get`, `flutter analyze`, `flutter test`, Android debug APK compilation.
2. Parser fixtures for ONVIF ProbeMatch and Contract B malformed/host-mismatch cases.
3. Android real-device discovery across Wi-Fi and Ethernet/USB tethering where supported.
4. iOS entitled physical-device discovery.
5. ONVIF read operations on exact camera models/firmware.
6. Static IPv4 writes on supported models, including rejected writes, reboot-needed responses, address verification and gateway partial failure.
7. Verify SQLite migration/integrity on upgrade and corrupted-database scenarios on physical Android/iOS devices.
8. Inspect diagnostic exports on both platforms and run a manual secret-redaction review.
9. Record model, hardware revision, firmware, topology and test evidence. A code path alone is not hardware support.


## PR #5 hardening parity

- Mobile Operation History stores the last 1,000 local operations and displays the latest 250.
- Mobile diagnostics rotate the active log at 2 MiB and retain three archives. The support bundle excludes the inventory database and ONVIF interface tokens and is previewed before sharing.
- SQLite integrity is checked with `PRAGMA quick_check` in the connection configuration before create/upgrade callbacks. Version 1 inventory databases are upgraded to add history without deleting device rows.
- Desktop Python simulator scenarios are represented by deterministic Dart wire fixtures and parser tests. A production embedded simulator is intentionally not included in the mobile app.
- Application lifecycle transitions cancel active discovery, subnet scanning and reachability work; outcomes are written to history when the asynchronous operation completes.
