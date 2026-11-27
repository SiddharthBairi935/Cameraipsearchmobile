# Desktop main → mobile parity

**Desktop source of truth:** `Karishma6543/camera-ip-search` main. Latest workspace redesign merged as commit `9cefa43b65337ce7707362488279606d3794f858` (desktop PR #17, 25 November 2026). This is the current source for the compact inventory, consolidated inspector and dark Oxita desktop theme.

## Functional parity

| Desktop capability | Mobile implementation | State / limitation |
|---|---|---|
| ONVIF WS-Discovery and Oxita Contract B | Flutter/Dart UDP discovery and parsers | Implemented in code; physical-device validation pending |
| SSDP/UPnP discovery | Bounded SSDP response parser and M-SEARCH probe | Implemented in code; Android/iOS multicast validation pending |
| Evidence-based device classification | Camera/NVR/router/switch/printer/computer/unknown with confidence | Implemented as triage; not vendor certification |
| Expanded TCP services and subnet scanning | Mobile TCP probes; full scan up to 4,096 hosts, 256-address window on larger subnets | Implemented in code; TCP-only and local-link limitations |
| All-active-interface discovery | Interface selection and discovery on eligible active interfaces | Implemented in code; platform/network validation pending |
| Static-IP collision checks | Local-interface and inventory IP/gateway/DNS checks | Implemented; not a live ARP/DAD reservation proof; fail-closed write preflight remains |
| Single-camera static IPv4 | Guarded ONVIF configuration with validation and confirmation | Implemented in code; real-camera verification pending |
| ONVIF WS-Security UsernameToken PasswordDigest | Fresh nonce/Created digest retry after authentication SOAP faults | Implemented with deterministic and loopback tests; physical-camera interoperability pending |
| ONVIF service inventory | GetServices response is parsed into service evidence and recorded as a successful read | Implemented in mobile code; camera response validation pending |
| DHCP configuration | ONVIF SetNetworkInterfaces with DHCP flag and GetNetworkInterfaces read-back verification | Implemented in mobile code; physical-camera validation pending; if camera reports reboot-needed, no automatic reboot is sent |
| DNS configuration | ONVIF SetDNS followed by GetDNS read-back verification | Implemented in mobile code for DHCP-provided DNS or up to two manual IPv4 servers; physical-camera validation pending |
| Reboot | ONVIF SystemReboot with explicit user confirmation | Implemented in mobile code; accepted request is not proof the camera completed reboot |
| Operation-level compatibility evidence | Desktop reports responded / implemented / advertised / auth-unverified / not-reported / not-implemented states | Implemented in mobile Maintenance workspace; based on recorded response sources and advertised service names, not certification |
| Sequential bulk static IPv4 | Mobile has range planner, full-batch preview, explicit confirmation, sequential ONVIF writes, per-camera immediate re-probe, post-write address verification and per-target history | **Execution remains fail-closed**: the generated Android probe reports conflict when responsive and unknown when silent; iOS has no live probe. Neither platform currently produces a positive clear result, so the apply action stays disabled until a validated ARP/DAD backend is implemented and physically verified |
| Local inventory, operation history, backup/restore and diagnostics | SQLite and mobile-native file sharing | Implemented in code; inspect exports before sharing |
| Factory reset | UI action intentionally disabled, matching desktop | Do not enable from ONVIF discovery alone; exact model/firmware and recovery evidence are required |
| Inventory CSV export | Complete saved inventory | Includes device identity, capabilities and network fields |
| Desktop focused workspace | Inventory-first mobile screen and selected-device Details / Configure / History bottom sheet | Implemented as a mobile-native adaptation |
| Desktop Configure groups | Device / Network / Storage sections inside mobile Configure tab | Implemented in code |
| Dark Oxita graphite/charcoal palette | Dark mobile surfaces with restrained red accent | Implemented in code; visual review on physical phone remains |
| Security analysis / CodeQL | Flutter analyze/tests; CodeQL for GitHub Actions workflow configuration only | Dart is not a supported CodeQL language; do not claim Dart CodeQL coverage |
| Dependency review / updates | Dependabot for pub packages and GitHub Actions; optional PR dependency review | Configured; review findings and lockfile availability |
| Release artifacts | CI debug APK; manual/tag preview APK and unsigned iOS simulator bundle | Evaluation only; no signed store-ready release |
| Credential storage | Opt-in `flutter_secure_storage`; endpoint/realm/scheme/account-scoped entries; Settings removal | Android Keystore/iOS Keychain implementation in code; physical-device and backup behavior validation pending |

## Desktop PR #17 workspace changes and mobile treatment

1. **Inventory-first layout:** mobile opens on the device inventory rather than a dashboard metrics page.
2. **Discovery controls:** interface selection, Discover, Subnet scan, reachability, search and filters are kept close to the inventory.
3. **Compact inventory:** mobile rows are denser and retain device classification, confidence and reachability/candidate state.
4. **Consolidated inspector:** desktop Details / Configure / History becomes a native mobile bottom sheet with the same three functional areas.
5. **Configure organization:** Device, Network and Storage workflows are grouped inside Configure. Mobile keeps its native scrolling and touch interactions.
6. **Theme:** dark graphite/charcoal surfaces, readable neutral text and restrained Oxita-red primary/focus accent.
7. **Responsive behavior:** the desktop's resizable side-by-side splitter is intentionally represented by a bottom sheet on phones, not copied pixel-for-pixel.

## Safety boundaries

- SSDP LOCATION is untrusted metadata and is never dereferenced. Sender IP is authoritative for the discovered candidate.
- Port-derived classifications remain Probable; ambiguous devices remain Unknown.
- TCP scans do not discover UDP-only services. Local discovery does not cross routers or VLANs.
- Bulk static-IP assignment is sequential and repeats a conflict probe immediately before each camera write. Current mobile native probes intentionally never interpret silence as free: Android returns unknown when no response is received, and iOS returns unknown because no interface-scoped backend exists. Consequently the bulk apply path is implemented but cannot proceed on current platform builds until a validated ARP/DAD backend can positively establish a clear result. Never weaken this fail-closed rule.
- iOS multicast requires Apple's multicast entitlement and a correctly provisioned physical-device build.
- Camera credentials are session-only by default. Persistent storage requires explicit opt-in and uses Android Keystore / iOS Keychain; never store credentials in SQLite, preferences, logs, diagnostics or exports. HTTP Basic/Digest and WS-Security PasswordDigest credentials remain in memory unless the user opts in.
- Factory reset and reboot require a compatible ONVIF endpoint and explicit confirmation; reboot acceptance is not proof of successful restart. Firmware flashing, activation and proprietary vendor operations remain unavailable unless a verified adapter contract, authorization and recovery path are implemented.

## Release validation still required

- Physical Android testing across supported Android versions, manufacturers, Wi-Fi access points and Ethernet adapters.
- iOS multicast entitlement approval and physical-device validation.
- Real ONVIF/SSDP/Oxita device testing with exact model, hardware revision and firmware evidence.
- Physical Android/iOS secure-vault validation, including lock/unavailable behavior, reinstall/backup semantics and no-secret leakage checks.
- Implement and physically validate interface-scoped ARP/DAD probing on Android and iOS; only then can the existing sequential bulk static-IPv4 apply path execute. Validate address conflict, no-response, permissions, wrong-interface and VLAN cases.
- Signed Android/iOS distribution builds, privacy review, dependency/license review and store-release acceptance.

A passing Flutter CI run or a generated APK is not production certification.
