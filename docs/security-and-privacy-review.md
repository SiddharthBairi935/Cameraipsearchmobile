# Mobile security and privacy review

**Status:** implementation review for the mobile parity branch. This is not a penetration test, independent security audit or production certification.

## Data handled

| Data | Use | Persistence |
|---|---|---|
| Camera IP/hostname, MAC, manufacturer, model, firmware, serial and ONVIF metadata | Discovery, inventory and UI | Local SQLite |
| ONVIF interface token | Guarded static IPv4 workflow | Local device metadata; excluded from support bundle |
| Camera username/password | HTTP Basic/Digest ONVIF challenge | In-memory session cache only |
| Operation history | Local audit trail | SQLite, maximum 1,000 records |
| Application diagnostics | Troubleshooting | App-support directory, rotating logs |
| Support bundle | User-initiated support sharing | Temporary file after preview and confirmation |

## Implemented protections

- ONVIF XAddr is restricted to HTTP(S), the responding host, and no user-info, query or fragment.
- Contract B responses validate magic, version, command, sequence, sender IP and field types.
- SSDP responses are bounded and sender-IP bound; untrusted LOCATION URLs are never fetched.
- Static IPv4 writes require verified ONVIF interface evidence, local validation, explicit confirmation, SOAP response validation and post-change verification.
- HTTP redirects are disabled for SOAP requests; response bodies and network timeouts are bounded.
- Basic/Digest credentials are session-only by default. Persistent storage requires explicit user opt-in and uses Android Keystore / iOS Keychain via `flutter_secure_storage`.
- Operation history and diagnostics redact common credential/authorization fields, URL user-info and namespaced XML credential elements.
- Support export excludes the SQLite inventory and ONVIF interface tokens; the user previews and confirms sharing.
- SQLite integrity checks run before migration; a failed check aborts opening rather than intentionally replacing the existing database.

## Sensitive data in support bundles

A support bundle may contain local interface addresses, camera IPs/hostnames, device identifiers, model/firmware details, operation timestamps and failure messages. Redaction is best-effort, not a guarantee. Inspect exports before sharing.

## Known security gaps

- Secure-vault integration is implemented in code; physical-device validation of provider lock/unavailable behavior, backup and reinstall semantics remains pending.
- ONVIF WS-Security UsernameToken PasswordDigest is implemented for authentication-related SOAP faults. Each retry uses a fresh cryptographically random nonce and UTC Created value; credentials remain in the in-memory session cache and are persisted only when the user explicitly opts in to the secure vault. Automated deterministic digest and loopback challenge/retry tests cover construction and request flow. Physical-camera nonce/timestamp interoperability remains unverified. UsernameToken PasswordText is not implemented.
- Digest SHA-256 and qop=auth-int are not implemented; supported challenge modes are HTTP Basic and Digest MD5/MD5-sess with qop=auth.
- No signed diagnostic bundle or automatic PII classification.
- No remote user/role management or centralized audit backend.
- iOS multicast discovery requires Apple's multicast entitlement and a correctly provisioned build.
- Reboot and DHCP/DNS writes are implemented through ONVIF with confirmation/read-back behavior; exact-model hardware validation remains pending. Factory reset remains disabled until exact-model/firmware support and recovery behavior are verified. Firmware flashing, activation, password changes, PTZ, NVR channels, stream preview/snapshot and proprietary vendor operations remain unavailable because the desktop source does not provide verified end-to-end implementations for them.

## Security automation

- Flutter CI runs `flutter analyze` and `flutter test`.
- Dependabot checks Pub and GitHub Actions dependencies weekly.
- CodeQL is configured for GitHub Actions workflow files. Dart is not a CodeQL-supported language; this repository does not claim Dart CodeQL coverage.
- Dependency review runs on pull requests only when the repository variable `ENABLE_DEPENDENCY_REVIEW=true` is enabled.

## Release gates

1. Review this document against the final dependency and platform manifests.
2. Inspect generated Android manifest and iOS Info.plist/entitlements in a release build.
3. Validate credential handling and diagnostic redaction with synthetic and real-device errors.
4. Inspect support bundles on Android and iOS before external sharing.
5. Test database upgrade and damaged-database handling on both platforms.
6. Review dependency alerts and license obligations.
7. Record exact device model, firmware and network topology for each real-camera test.

Do not describe this review as a completed security audit until the release gates and independent review are complete.
