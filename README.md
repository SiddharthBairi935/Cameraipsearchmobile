# Oxita Camera IP Search Mobile

Flutter/Dart Android and iOS companion to the desktop [Camera IP Search](https://github.com/Karishma6543/camera-ip-search).

The mobile app translates the desktop release-candidate workflows into mobile navigation, responsive cards, bottom sheets and confirmation dialogs. It is not a Qt UI copy.

## Desktop source of truth

The parity target is desktop PR #5, branch `release/preproduction-hardening`, stacked on desktop PR #4:
https://github.com/Karishma6543/camera-ip-search/pull/5

The mobile branch includes the PR #4 camera discovery and device-management workflows plus the PR #5 hardening features ported where appropriate to Android/iOS.

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
- Local SQLite inventory with pre-migration `PRAGMA quick_check`, schema migration, persistent Operation History (latest 1,000; latest 250 displayed), CSV export/share, app data path information and session-only ONVIF HTTP Basic/Digest challenge credentials.
- Rotating diagnostic logs (2 MiB active file, three archives), best-effort redaction for key/value secrets, Basic/Bearer authorization, URL user-info and namespaced XML secret elements.
- User-confirmed diagnostic support bundle with OS/app/runtime details, IPv4 interface summary, recent operation history and redacted logs; inventory database and ONVIF interface tokens are excluded. The user can inspect the text before sharing.
- Deterministic mobile test fixtures matching the desktop simulator's Contract B and limited ONVIF response scenarios, including malformed JSON, wrong sequence, invalid port, advertised-IP mismatch, missing MAC, unsafe/multiple XAddrs.
- Discovery, subnet scan and reachability completion/cancellation outcomes are recorded; active scans are cancelled when the app backgrounds.
- Manual inventory entry accepts a valid IP address or hostname, matching the desktop workflow.

## Deliberately unavailable (matches desktop PR #4)

- CP Plus, Hikvision and Prama proprietary adapters.
- Project-camera activation or configuration commands; Contract B currently defines discovery only.
- Firmware upload/update, reboot, NVR channel management and bulk image configuration.
- DHCP toggle and DNS write configuration.
- ONVIF HTTP Basic and Digest (MD5 / MD5-sess with qop=auth) challenge authentication is supported with session-only credentials. Digest SHA-256, qop=auth-int, ONVIF WS-Security and secure OS credential-vault integration are not implemented.
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

Automated Dart tests cover protocol fixtures, redaction, diagnostic log rotation, SQLite integrity checks, version-one schema migration, retention and damaged-database preservation. Flutter CI runs analyze, tests, platform-runner generation and an Android debug APK build. A green workflow is not proof of camera interoperability. Hardware validation must record exact camera model, hardware revision, firmware, network topology and the operations tested.

Desktop PR #4 itself is still a draft release candidate and is **not production ready**: its validation notes say cross-platform build/test, real-camera checks, security review and release packaging remain open. Mobile parity must preserve those same evidence levels rather than overstate support.


## Desktop PR #5 parity boundaries

- Operation History and diagnostics are implemented with mobile-native presentation and local file sharing.
- The desktop Python simulator is not embedded as a background server in the mobile app. Mobile uses deterministic Dart wire fixtures and loopback ONVIF test servers in automated tests; this avoids requiring a rooted phone or binding privileged discovery ports in production.
- Android native interface MTU/link-state reporting and iOS multicast entitlement approval remain platform-specific validation items. iOS discovery is not certified until Apple approves the multicast entitlement and an entitled physical-device build is tested.
- Log redaction is best-effort and does not guarantee that all sensitive data is removed. Inspect support bundles before sharing.
