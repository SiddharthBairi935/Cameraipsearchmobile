# Mobile credential storage

## Implemented behavior

Camera credentials remain session-only by default. Users may explicitly select **Remember on this device** during ONVIF authentication. Opted-in credentials are stored through `flutter_secure_storage`, backed by Android Keystore on Android and Keychain Services on iOS. The app provides a Settings action to list and remove saved camera accounts.

The secure index contains endpoint/account metadata only; passwords are stored under separate SHA-256-derived keys. Credential identity is scoped to the normalized ONVIF endpoint (including port and service path), authentication realm, scheme and username. Credentials are never written to the inventory database, preferences, operation history, logs, diagnostics or exported support bundles.

## Failure behavior

If secure storage is unavailable, locked or denied, the app reports that the credential will be used for the current session only. It does not fall back to plaintext storage. Users can continue without opting in. Removing an account deletes its password entry and index reference.

## Platform requirements and release gate

- Android: verify the plugin's Keystore-backed encryption on supported Android versions and device vendors.
- iOS: verify Keychain access class, app reinstall/backup behavior and entitlement/signing behavior on physical devices.
- Verify store/read/delete round trips, multiple accounts per endpoint, credential rotation and unavailable-provider behavior.
- Inspect database, logs, diagnostic exports and crash output to confirm no secrets are persisted.
- This implementation does not claim vendor certification or physical-device validation. Until platform testing is complete, persistent storage should be treated as implemented in code but not yet hardware-validated.
