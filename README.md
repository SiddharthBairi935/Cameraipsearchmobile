# Camera IP Search Mobile

Flutter-based Android/iOS companion to the Camera IP Search desktop application.

The mobile client uses mobile-native navigation and layouts while preserving the desktop discovery contracts. It is a separate app, not a Qt-to-mobile UI port.

## Reference desktop repository

https://github.com/Karishma6543/camera-ip-search

The desktop reference currently uses C++20 and Qt 6. The mobile implementation is translating its protocol behavior and device model into Dart.

## Implemented in the initial mobile foundation

- ONVIF WS-Discovery probe to 239.255.255.250:3702.
- Project firmware Contract B probe on UDP port 9988.
- Strict response checks for magic, version, sequence, command and field types.
- Multi-interface IPv4 discovery and device-source merging.
- Local device inventory persistence.
- Manual IPv4 device entry.
- Bounded, opt-in CIDR scan (maximum 256 hosts; common camera service ports).
- Candidate classification: an open port is not treated as proof of a camera.
- TCP reachability check, search, device details and open-web-UI action.
- Dark mobile-first dashboard and Flutter CI workflow.

See [the parity matrix](docs/parity-matrix.md) for what is not implemented yet.

## Setup

Requirements: Flutter stable SDK and Android Studio / Xcode for the relevant target.

The initial repository contains the Dart application layer. Generate standard Android and iOS runner projects once:

```bash
bash tool/bootstrap_platforms.sh
flutter pub get
flutter analyze
flutter test
flutter run
```

The bootstrap script generates platform runner folders without replacing the app's pubspec or Dart source.

## Platform networking requirements

- Android: the platform bootstrap script adds the ACCESS_LOCAL_NETWORK manifest declaration and a native runtime request bridge for Android 17 (API 37), plus the Wi-Fi multicast lock. Confirm targetSdk is set appropriately before shipping against API 37. Test Wi-Fi broadcast/multicast on physical devices.
- iOS: add NSLocalNetworkUsageDescription to Runner/Info.plist. UDP multicast and broadcast require Apple's com.apple.developer.networking.multicast entitlement and an authorized provisioning profile. The entitlement must be requested from Apple; it cannot be assumed.
- Until these platform-specific requirements are satisfied and tested, do not claim feature parity on iOS.

## Safety and compatibility

- Discovery is limited to directly connected IPv4 interfaces.
- Subnet scanning is user initiated, bounded and non-intrusive.
- Unknown devices and TCP scan candidates are labelled honestly.
- No default passwords, credential guessing or undocumented vendor commands.
- Network configuration, activation, batch operations and firmware updates stay unavailable until their exact protocol, authentication, confirmation and verification flows are implemented and hardware-tested.

## Quality gates

CI runs `flutter analyze` and `flutter test`. Physical-camera compatibility is tracked separately from automated tests. A feature is hardware-tested only when the exact model, hardware revision and firmware version are recorded.
