# Mobile release engineering and distribution

## Current CI artifact

Flutter CI builds an Android debug APK and uploads it as a short-lived workflow artifact for manual testing. It is an evaluation build, not a signed production release.

## Preview artifact workflow

The manual/tag-triggered workflow builds:
- Android debug APK for sideloaded functional testing.
- Unsigned iOS simulator app bundle for simulator evaluation.

The iOS simulator artifact is not installable on a physical iPhone. The Android debug artifact is not a Play Store release. Neither artifact is signed with organization release credentials or suitable for public production distribution.

## Production release gates

Before publishing:
1. Build from an immutable version tag and record the exact commit SHA.
2. Run Flutter analyze/tests and Android/iOS build validation for that exact commit.
3. Review Dependabot and dependency-review findings; pin and review dependency updates.
4. Review Android manifest permissions, iOS Info.plist and multicast entitlements.
5. Complete physical-device discovery and real-camera compatibility testing.
6. Implement and validate Android Keystore/iOS Keychain credential storage before claiming persistent credential support.
7. Generate an SBOM and review third-party licenses and privacy disclosures.
8. Configure Android signing and iOS signing/provisioning through protected GitHub environments or a release service. Never commit signing keys or provisioning profiles.
9. Test install, upgrade, data preservation, uninstall and rollback on supported devices.
10. Publish checksums, release notes, privacy notice, support policy and tested device/firmware matrix.

A green CI run, debug APK or simulator bundle is not a production release approval. iOS multicast entitlement approval is a separate external gate.
