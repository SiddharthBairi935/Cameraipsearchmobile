# Oxita Camera IP Search Mobile

Flutter/Dart Android and iOS companion to the [Oxita Camera IP Search desktop application](https://github.com/Karishma6543/camera-ip-search).

The mobile app uses native mobile navigation and local-first networking. Discovery, inventory, and supported camera operations run on the phone against the user's local network. There is no hosted backend or cloud service required for local discovery.

## Desktop source of truth

Mobile parity is tracked against the latest merged desktop `main`. The current desktop baseline includes PR #17, merged as `9cefa43b65337ce7707362488279606d3794f858` on 25 November 2026. This merge introduced the focused device workspace: compact inventory, a single Details / Configure / History inspector, and the dark Oxita graphite/charcoal palette with restrained red accents.

The desktop app is C++20 / Qt 6 with local SQLite storage. The mobile app is a separate Flutter/Dart implementation; desktop Qt code and UI are not reused. The mobile layout follows native phone patterns while preserving the desktop workspace hierarchy.

## Implemented mobile capabilities

- ONVIF WS-Discovery and Oxita Contract B UDP discovery.
- SSDP/UPnP M-SEARCH parsing with bounded response size, sender-IP binding, and no fetching of untrusted LOCATION URLs.
- Evidence-based device classification (Camera, NVR, Router, Switch, Printer, Computer, Unknown) with confidence labels.
- Selectable active IPv4 interfaces, subnet scanning, TCP reachability checks, progress and cancellation.
- Full scan for subnets up to 4,096 hosts; a 256-address window around the selected interface for larger subnets.
- ONVIF device-information/capability/network-interface enrichment.
- Local SQLite inventory, search and filters, operation history, CSV export, backup/restore and diagnostics.
- Guarded single-camera ONVIF static-IPv4 workflow with validation and confirmation. Platform conflict preflight remains fail-closed; unknown results block writes.
- Mobile-native navigation, responsive layouts, dialogs and confirmation flows.
- Dark Oxita graphite workspace theme, compact device inventory, and a selected-device bottom-sheet inspector with Details, Configure (Device / Network / Storage) and History tabs.
- Device inventory is the default landing screen; discovery, interface selection, subnet scan and reachability controls are available directly above the list.

### Known mobile parity gaps

- Desktop supports sequential bulk static-IPv4 assignment with per-camera validation and result/history reporting. Mobile currently exposes guarded single-camera static-IPv4 configuration only; bulk assignment is not implemented.
- Desktop uses a resizable side-by-side inventory/inspector. Mobile intentionally uses a touch-friendly bottom-sheet inspector instead.
- Desktop's native desktop workflows and OS integrations are not copied verbatim into Flutter.

Ported classification and discovery are triage features, not vendor certification. TCP-only scans can miss UDP-only devices. Link-local discovery does not cross routers or VLANs.

## Security and credential handling

- Camera credentials are session-only and are not intentionally persisted.
- No Android Keystore or iOS Keychain credential-vault provider is implemented.
- No plaintext fallback is permitted if a future secure-vault provider is unavailable.
- Diagnostic redaction is best-effort; users must inspect support bundles before sharing.
- See [mobile security and privacy review](docs/security-and-privacy-review.md) and [credential-storage design](docs/credential-storage-mobile.md).

## Platform requirements and limitations

### Android
The bootstrap script generates the Android runner and local-network permission bridge. It requests Android 17/API 37 local-network permission when applicable and manages a Wi-Fi multicast lock. Physical-device testing is still required across Android versions, phone vendors, Wi-Fi access points, Ethernet adapters and VLAN/firewall configurations.

### iOS
The bootstrap script adds the local-network usage description. ONVIF/SSDP multicast discovery requires Apple's multicast networking entitlement and a correctly provisioned build. Entitlement approval and physical-device validation remain release gates.

## Setup

Requirements: Flutter stable, Android Studio for Android, and macOS/Xcode for iOS.

```bash
bash tool/bootstrap_platforms.sh
flutter pub get
flutter analyze
flutter test
flutter run
```

## CI and artifacts

Flutter CI runs dependency resolution, static analysis, tests, Android/iOS runner generation and an Android debug APK build. The debug APK is uploaded as a short-lived CI artifact for manual device testing; it is not a signed production release.

The manual/tag-triggered mobile artifact workflow creates an Android debug APK and an unsigned iOS simulator app bundle for evaluation. These are preview artifacts only—not Play Store/App Store submissions, signed releases, or production installers. See [mobile release engineering](docs/release-engineering-mobile.md).

The desktop PR #15 security workflow introduced CodeQL and dependency-review gates. CodeQL does not currently analyze Dart source; mobile CI therefore relies on Flutter analysis/tests, dependency automation/review and explicit platform-security review rather than claiming Dart CodeQL coverage.

## Validation status

Automated Flutter analysis/tests and Android debug builds are CI-validated on the exact commit shown in the Actions run. Green CI is not proof of camera interoperability. Physical Android/iOS discovery, iOS multicast entitlement, real-camera ONVIF behavior, network-changing operations, credential-vault implementation, signing and release certification remain separate gates.

See [desktop-to-mobile parity](docs/desktop-main-parity.md), [security review](docs/security-and-privacy-review.md), and [mobile release engineering](docs/release-engineering-mobile.md).
