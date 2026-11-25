# Mobile security and privacy review

**Status:** implementation review for the draft mobile parity PR. This is not a penetration test, independent security audit, or production certification.

## Data handled

| Data | Where it is used | Persistence |
|---|---|---|
| Camera IP/hostname, MAC, manufacturer, model, firmware, serial and ONVIF metadata | Discovery, device inventory and UI | Local SQLite inventory |
| ONVIF interface token | Select matching interface for guarded static IPv4 write | Stored with local device metadata; never intentionally included in support bundle |
| Camera username/password | HTTP Basic/Digest ONVIF challenge | In-memory session cache only; not written to SQLite or logs |
| Operation history | Local audit trail | SQLite, maximum 1,000 records |
| Application diagnostics | Troubleshooting | App-support directory, 2 MiB active log plus three archives |
| Support bundle | User-initiated support sharing | Temporary file, shared only after user confirmation and preview |

## Implemented protections

- ONVIF XAddr is restricted to HTTP(S), the responding host, no user-info, query or fragment.
- Contract B responses are checked for magic, version, command, sequence, sender IP and field types.
- Static IPv4 configuration requires a verified ONVIF interface token, local address/mask/gateway validation, explicit confirmation, SOAP response validation and post-change verification.
- HTTP redirects are disabled for SOAP requests.
- ONVIF response bodies are limited to 1 MiB and network requests have bounded timeouts.
- Basic/Digest credentials are held in memory for the app session and are not intentionally persisted.
- Operation history and diagnostics redact common username/password/token/authorization fields, Basic/Bearer/Digest authorization values, URL user-info and namespaced XML credential elements.
- Diagnostic logs rotate at 2 MiB, retain three archives and serialize writes.
- Support export excludes the SQLite inventory database and ONVIF interface tokens. A preview and explicit share action are required.
- SQLite `PRAGMA quick_check` runs before create/upgrade callbacks; a failed integrity check aborts opening rather than intentionally replacing the existing database.

## Sensitive data in support bundles

A support bundle may still contain:
- Local IPv4 interface addresses and camera target IPs/hostnames.
- Device identifiers or model/firmware details.
- Operation timestamps and failure messages.

Redaction is best-effort, not a guarantee. The user is shown the bundle contents before sharing and should inspect it for secrets, customer identifiers and network topology details.

## Known security gaps

- No Android Keystore / iOS Keychain integration for optional credential persistence; credentials are session-only.
- ONVIF WS-Security is not implemented.
- Digest SHA-256 and qop=auth-int are not implemented; supported challenge modes are HTTP Basic and Digest MD5/MD5-sess with qop=auth.
- No signed diagnostic bundle or automatic PII classification.
- No remote user/role management or centralized audit backend in the mobile app.
- iOS multicast discovery requires Apple's multicast entitlement and a correctly provisioned build.
- Camera firmware update, reboot, factory reset, DHCP/DNS writes and vendor-specific configuration remain unavailable because the desktop release candidate does not provide verified contracts and recovery workflows.

## Release gates

1. Review this document against the final dependency and platform manifests.
2. Inspect generated Android manifest and iOS Info.plist / entitlements in a release build.
3. Validate credential handling and diagnostic redaction with synthetic and real device errors.
4. Inspect support bundles on Android and iOS before any external sharing.
5. Test database upgrade and damaged-database handling with a preserved backup on both platforms.
6. Complete dependency vulnerability review and platform permission review.
7. Record exact device model, firmware and network topology for every real-camera test.

Do not describe this review as a completed security audit until the release gates and independent review are complete.
