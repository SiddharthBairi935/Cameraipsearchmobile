# Oxita Camera IP Search Mobile

Flutter/Dart Android and iOS companion to the desktop [Camera IP Search](https://github.com/Karishma6543/camera-ip-search).

The mobile app translates the desktop release-candidate workflows into mobile navigation, responsive cards, bottom sheets and confirmation dialogs. It is not a Qt UI copy.

## Desktop source of truth

The parity target is desktop PR #4, branch `release/oxita-production-ready`:
https://github.com/Karishma6543/camera-ip-search/pull/4

Do not use desktop `main` or the older UI-only PR #2 as the current parity baseline.

## Ported desktop capabilities

- ONVIF WS-Discovery and Oxita Contract B UDP discovery (port 9988).
- Selectable active IPv4 interface for discovery.
- ONVIF XAddr validation: HTTP(S), same responding host, no user info, query or fragment.
- Project response validation: magic, version, command, sequence, field types and sender-IP binding; supports the explicit unconfigured-camera 0.0.0.0 sender case.
- Device identity matching using MAC, ONVIF endpoint, serial + known manufacturer, and guarded IP fallback; conflicting MAC addresses are not merged.
- Candidate scan observations cannot overwrite verified device identity or IP details.
- ONVIF GetDeviceInformation, GetCapabilities, GetNetworkInterfaces and GetDNS enrichment.
- Select the ONVIF interface whose active IPv4 address matches the discovered camera before enabling static-IP writes.
- Bounded opt-in TCP subnet scan (maximum 256 IPv4 hosts, with a window around the selected host on larger networks), common camera ports, candidate provenance, progress and cancellation.
- TCP reachability checks with per-device timestamps, multi-select priority and cancellation.
- Manual IPv4 inventory entry, labels, search, manufacturer/status filters and device detail profile.
- Guarded ONVIF static IPv4 write: local validation, explicit confirmation, SOAP response validation, new-IP verification and separate gateway result handling.
- Local SQLite inventory, CSV export/share, app data path information and session-only ONVIF HTTP credentials.

## Deliberately unavailable (matches desktop PR #4)

- CP Plus, Hikvision and Prama proprietary adapters.
- Project-camera activation or configuration commands; Contract B currently defines discovery only.
- Firmware upload/update, reboot, NVR channel management and bulk image configuration.
- DHCP toggle and DNS write configuration.
- ONVIF WS-Security and secure OS credential-vault integration.
- Any write operation without a verified adapter contract and recovery path.

Unavailable desktop features are represented as unavailable in the mobile app, not as fake active controls.

## Platform requirements

### Android
Run `bash tool/bootstrap_platforms.sh` to generate standard Android/iOS runners and the Android local-network permission bridge. The bridge requests `ACCESS_LOCAL_NETWORK` when running on Android 17/API 37 and manages the Wi-Fi multicast lock. Confirm targetSdk and test discovery on physical Android devices and different Wi-Fi access points.

### iOS
The bootstrap script adds `NSLocalNetworkUsageDescription`. ONVIF UDP multicast/broadcast also requires Apple's multicast networking entitlement and an authorized provisioning profile. Request the entitlement from Apple and validate an entitled physical-device build before claiming iOS discovery parity. Without it, iOS may not receive ONVIF multicast replies.

## Setup

Requirements: Flutter stable, Android Studio for Android, Xcode/macOS for iOS.

```bash
bash tool/bootstrap_platforms.sh
flutter pub get
flutter analyze
flutter test
flutter run
```

## Validation status

Automated Dart tests and Flutter CI are configured. A green workflow is not proof of camera interoperability. Hardware validation must record exact camera model, hardware revision, firmware, network topology and the operations tested.

Desktop PR #4 itself is still a draft release candidate and is **not production ready**: its validation notes say cross-platform build/test, real-camera checks, security review and release packaging remain open. Mobile parity must preserve those same evidence levels rather than overstate support.
