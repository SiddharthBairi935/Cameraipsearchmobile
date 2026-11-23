# Camera IP Search Mobile

Flutter mobile companion to the Camera IP Search desktop application.

The mobile app is a separate Android/iOS client. It must preserve the desktop discovery and device-management contracts while using mobile-native interaction patterns.

## Reference implementation

- Desktop repository: https://github.com/Karishma6543/camera-ip-search
- ONVIF WS-Discovery: UDP multicast `239.255.255.250:3702`
- Project firmware discovery: UDP broadcast port `9988`, Contract B version 1
- Candidate scanning: bounded, opt-in local IPv4 scan; open ports are candidates, not confirmed cameras

## Mobile stack

- Flutter / Dart
- Dart UDP/TCP sockets for local-network discovery
- XML parsing for ONVIF ProbeMatch
- Persistent device inventory

## Platform constraints

- Android local-network access is subject to platform permission requirements. Android 17 (API 37) targeting requires `ACCESS_LOCAL_NETWORK` for direct LAN traffic.
- iOS requires `NSLocalNetworkUsageDescription`; UDP multicast/broadcast also requires Apple's `com.apple.developer.networking.multicast` entitlement and provisioning approval.
- iOS broadcast/multicast must be validated on entitled physical-device builds before claiming feature parity.

## Status

Repository bootstrap and architecture baseline. Feature parity is implemented incrementally and must be tested against protocol fixtures and physical cameras. Unsupported or unverified device operations must remain disabled and clearly labelled.
