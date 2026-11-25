# Desktop main → mobile parity

**Desktop source of truth:** `Karishma6543/camera-ip-search` main. Latest merged commit: `c1f6c6db74f4dd6a80e6e03667bcc72a2a60a749` (PR #15, 25 November 2026). PR #15 follows PR #14's SSDP discovery, device classification and expanded scan scope. Desktop PR #17 (`ff9aacb5bcbc41db36625fc7b68947ba4a5c6480`) is still a draft and has not been merged; this mobile branch separately adapts its workspace/UI direction without treating the desktop PR as a merged functional source.

## Functional parity

| Desktop main capability | Mobile implementation | State / limitation |
|---|---|---|
| ONVIF WS-Discovery and Oxita Contract B | Flutter/Dart UDP discovery and parsers | Implemented in code; physical-device validation pending |
| SSDP/UPnP discovery | Bounded SSDP response parser and M-SEARCH probe | Implemented in code; Android/iOS multicast validation pending |
| Evidence-based device classification | Camera/NVR/router/switch/printer/computer/unknown with confidence | Implemented as triage; not vendor certification |
| Expanded TCP services and subnet scanning | Mobile TCP probes; full scan up to 4,096 hosts, 256-address window on larger subnets | Implemented in code; TCP-only and local-link limitations |
| All-active-interface discovery | Interface selection and discovery on eligible active interfaces | Implemented in code; platform/network validation pending |
| Static-IP collision checks | Local-interface and inventory IP/gateway/DNS checks | Implemented; not a live ARP/DAD reservation proof; fail-closed write preflight remains |
| Local inventory, operation history, backup/restore and diagnostics | SQLite and mobile-native file sharing | Implemented in code; inspect exports before sharing |
| Security analysis / CodeQL | Flutter analyze/tests; CodeQL for GitHub Actions workflow configuration only | Dart is not a supported CodeQL language; do not claim Dart CodeQL coverage |
| Dependency review / updates | Dependabot for pub packages and GitHub Actions; optional PR dependency review | Configured; review findings and lockfile availability |
| Release artifacts | CI debug APK; manual/tag preview APK and unsigned iOS simulator bundle | Evaluation only; no signed store-ready release |
| Credential storage design | Session-only credentials; documented Android Keystore/iOS Keychain requirements | Persistent secure-vault integration not implemented |

## Desktop PR #15 changes and mobile treatment

1. **Security analysis:** desktop adds C++/Python CodeQL and conditional dependency review. Mobile adds workflow-configuration analysis and dependency-review wiring. Dart is not represented as CodeQL-covered.
2. **Dependabot:** mobile tracks Flutter/Dart `pub` dependencies and GitHub Actions weekly.
3. **Packaging:** mobile produces evaluation artifacts appropriate to Flutter platforms. Android debug APKs are suitable for sideloaded testing; iOS simulator bundles are not installable on physical iPhones. Neither is a signed production release.
4. **Credential-vault requirements:** mobile credentials remain session-only. Android Keystore and iOS Keychain integration require a dedicated implementation and platform tests. No plaintext/SQLite fallback is allowed.
5. **Release evidence:** CI results must be tied to the exact commit. CI does not establish real-camera interoperability, signing, entitlement approval or production readiness.

## Safety boundaries

- SSDP LOCATION is untrusted metadata and is never dereferenced. Sender IP is authoritative for the discovered candidate.
- Port-derived classifications remain Probable; ambiguous devices remain Unknown.
- TCP scans do not discover UDP-only services. Local discovery does not cross routers or VLANs.
- Static-IP collision checks are based on local-interface and inventory evidence, not a live duplicate-address proof. Unknown conflict-probe results block writes.
- iOS multicast requires Apple's multicast entitlement and a correctly provisioned physical-device build.
- Camera credentials are session-only; do not store them in SQLite, preferences, logs, diagnostics or exports.
- Factory reset, firmware flashing, activation, reboot, DHCP/DNS writes and proprietary vendor operations remain unavailable unless a verified adapter contract and recovery path are implemented.

## Release validation still required

- Physical Android testing across supported Android versions, manufacturers, Wi-Fi access points and Ethernet adapters.
- iOS multicast entitlement approval and physical-device validation.
- Real ONVIF/SSDP/Oxita device testing with exact model, hardware revision and firmware evidence.
- Platform-specific credential-vault implementation and no-plaintext-fallback tests before offering persistent credential storage.
- Signed Android/iOS distribution builds, privacy review, dependency/license review and store-release acceptance.

A passing Flutter CI run or a generated APK is not production certification.


## Desktop PR #17 workspace UX adaptation (provisional)

| Desktop UX direction | Mobile adaptation | State |
|---|---|---|
| Inventory is the primary full-height workspace | Device inventory is the default landing screen | Implemented in this branch |
| Discovery toolbar above the inventory | Interface selector, Discover, Subnet scan and Reachability controls directly above the list | Implemented in this branch |
| Remove redundant metric-card row | No dashboard metric-card strip; network status and interface context remain available in Overview | Implemented in this branch |
| Compact inventory rows | Denser device rows with device classification and confidence/status pills | Implemented in this branch |
| Details / Configure / History in one inspector | Native bottom-sheet inspector with Details, Configure and History tabs | Implemented in this branch |
| Configure divided into Device / Network / Storage | Grouped device maintenance, guarded IPv4 workflows and local inventory backup/restore | Implemented in this branch |
| Dark Oxita graphite palette with restrained red | Dark mobile theme, high-contrast surfaces and red primary/focus accent | Implemented in this branch |

This is a mobile-native interpretation, not a pixel-for-pixel Qt port. Desktop PR #17 remains draft; its cross-platform CI and visual review are independent desktop release gates. Functional parity continues to follow merged desktop main. No unsupported vendor operations, flashing or unverified network actions are introduced by this UI adaptation.
