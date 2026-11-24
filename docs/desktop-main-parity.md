# Desktop main → mobile parity

**Desktop source of truth:** `Karishma6543/camera-ip-search` main, inspected at commit `2d91d61d76f1b8c8f9c1faff795f7b67cfadf4fc` (branding/release-status refresh, after main CI commit `47b99f2`).

This matrix intentionally excludes desktop PR #10 because it is still an unmerged pull request, not part of desktop main.

## Desktop-main capabilities and mobile implementation

| Desktop main capability | Mobile implementation | State / limitation |
|---|---|---|
| ONVIF WS-Discovery and enrichment | Dart UDP/XML and ONVIF HTTP/SOAP services | Implemented in code; physical-device validation pending |
| Oxita Contract B UDP 9988 | Dart parser and broadcast discovery | Implemented in code; physical-device validation pending |
| Interface selection, bounded subnet scan, reachability and cancellation | Flutter network tools | Implemented in code; OS/VLAN/firewall behavior needs hardware testing |
| SQLite inventory, operation history, diagnostics, redaction and rotating logs | Existing mobile services | Implemented in code; privacy/security review remains open |
| Guarded single-camera static IPv4 | ONVIF read/validation/apply/reconnect path | Implemented in code; model/firmware hardware tests required |
| Sequential batch operation preflight and runner | Dart preflight/runner; Tools exposes sequential read-only ONVIF refresh | Implemented for read-only refresh; no batch writes are enabled |
| Batch identity/address duplicate checks and adapter capability gating | Dart batch preflight | Implemented; unsupported operations fail closed |
| IPv4 assignment range planner | Dart dry-run planner and selected-device mapping | Implemented; bounded to 65,536 addresses and max 256 devices |
| Inventory/local reservation checks for IP assignment | Planner reserves all known inventory IPs, gateways, DNS and local interface IPs | Implemented |
| Live ARP duplicate-address preflight | Preflight state model is implemented | **Blocked on mobile:** no validated interface-scoped ARP/DAD backend. Missing/unknown result blocks assignment; no writes are enabled |
| Firmware package metadata and SHA-256 candidate validator | Dart validator and file-picker workflow for JSON manifest + package | Implemented; max 64 MiB package size in mobile UI |
| Firmware signature verification / authorized update transport / recovery | Not present in desktop main | Not implemented; flashing stays disabled |
| Vendor-specific adapters and activation/reboot/NVR/bulk image operations | Not present as verified implementations in desktop main | Not implemented; remains disabled |
| Inventory backup/restore from desktop PR #10 | Not part of desktop main | Excluded until PR #10 is merged and reviewed |

## Safety behavior

- Assignment planning is a dry run only. Every current inventory address, selected device address, gateway, DNS address and local interface address is reserved.
- Assignment preflight requires a live probe to explicitly return `clear`. A missing backend, timeout, ambiguous response or unknown result is not treated as free.
- The mobile build currently has no validated interface-scoped ARP/DAD backend on Android or iOS. It reports `probeUnavailable`; this blocks assignment. Do not bypass this state.
- Batch refresh executes sequentially and only for targets with stable IDs, unique addresses and a safe same-host ONVIF endpoint. Reboot, firmware and unverified write operations are unsupported.
- Firmware validation compares vendor, series, model, hardware revision and region, then verifies SHA-256. This does not prove authenticity or authorization; it does not flash or transfer the package.
- Firmware target series, hardware revision and region are operator-entered because the current inventory schema does not reliably expose all three fields. Verify them from the physical device label/vendor documentation before trusting the comparison.

## Remaining validation and release gates

1. Run `flutter pub get`, `flutter analyze`, `flutter test` and Android debug APK build on this branch.
2. Add/validate a native Android interface-scoped ARP/DAD backend before enabling IP assignment. Keep iOS blocked until a documented and entitlement-compatible backend is validated.
3. Test batch refresh and cancellation against multiple real ONVIF cameras, including timeouts and authentication failures.
4. Validate package manifest parsing and large-file handling on Android and iOS; inspect real vendor manifests before standardizing the JSON schema.
5. Run discovery, ONVIF reads and static-IP writes on exact camera models/firmware on physical devices.
6. Complete iOS multicast entitlement and physical-device validation.
7. Perform security review, dependency review and support-bundle privacy inspection.

A passing unit test or Android build is not proof of camera interoperability. This branch is a pre-production parity implementation, not production certification.
