# Mobile credential storage: design and release gate

## Current state

Camera credentials are session-only in the mobile app. There is no persistent credential-vault integration. Do not describe the current behavior as encrypted credential storage or imply that credentials survive an app restart.

## Required platform providers

| Platform | Required provider | Scope |
|---|---|---|
| Android | Android Keystore-backed credential storage (prefer a maintained platform implementation) | App/user scoped; keys non-exportable where supported |
| iOS | Keychain Services | App access group; least-privilege accessibility class |

Do not create a home-grown encryption scheme or store an encryption key beside an encrypted database. If the secure provider is unavailable, locked or denied, continue in session-only mode and tell the user credentials will not persist. Never fall back to plaintext, SQLite, shared preferences, logs, crash reports, support bundles or analytics.

## Credential identity and UX

Use a stable non-secret key derived from normalized protocol, host, port, service path and account name. Never include the password in the key, logs, UI accessibility labels, operation history or diagnostics. Separate accounts and endpoints; never reuse credentials across hosts automatically.

Persistent storage must be opt-in through an explicit “Remember on this device” choice. Explain where the credential is stored and provide a way to remove it. Keep temporary secret buffers short-lived and clear them on a best-effort basis.

## Acceptance tests

- Store/read/delete round trip on supported Android and iOS versions.
- Locked/unavailable/permission-denied provider behavior.
- Unicode usernames and passwords; multiple accounts per endpoint.
- Credential rotation and stale-entry removal.
- No credential in SQLite, preferences, logs, diagnostics, crash output or exported inventory.
- No plaintext fallback when provider access fails.
- App reinstall/restore and OS backup behavior documented and tested.

## Release status

**Not implemented / not validated.** This document is an implementation contract, not evidence of secure-vault support. Keep credentials session-only until platform-specific code and tests pass on physical devices.
