# Mobile simulator and integration testing

## Purpose

The desktop PR #5 adds a host-side Python simulator for discovery and ONVIF integration testing. The mobile app does not run a permanent camera simulator server. Instead, its automated tests use deterministic Dart wire fixtures and loopback HTTP ONVIF responders so that protocol validation can be tested without privileged ports, root access or a second device.

## Automated test coverage

Run:

```bash
flutter pub get
flutter analyze
flutter test
```

The test suite covers:

- Oxita Contract B UDP response parsing: valid response, malformed JSON, stale sequence, invalid port, advertised-IP mismatch and missing MAC.
- ONVIF ProbeMatch parsing: safe same-host XAddr, multiple XAddrs, wrong-host candidate and unsafe credentials/query parameters.
- ONVIF HTTP/SOAP: identity response, SOAP fault and oversized response rejection.
- HTTP Basic/Digest challenge handling and SOAP request-body replay.
- Manual IP/hostname validation.
- SQLite quick_check, version-one migration, operation history retention and damaged-database preservation.
- Diagnostic log rotation and redaction of usernames, passwords, Basic/Bearer/Digest authorization, URL user-info and XML credential elements.

The fixtures mirror selected desktop simulator cases; they are not a replacement for running the desktop Python simulator against a physical phone.

## Physical Android validation

For each supported Android version and phone vendor:

1. Install a debug or signed test build generated after `bash tool/bootstrap_platforms.sh`.
2. Grant the local-network permission when requested on Android 17/API 37+.
3. Connect the phone and camera to the same Wi-Fi/VLAN.
4. Verify the selected interface name, IPv4 address, MTU and link state.
5. Run ONVIF discovery and Oxita Contract B discovery separately and together.
6. Confirm camera identity, MAC, manufacturer, model and firmware are merged without duplicate devices.
7. Run a bounded subnet scan and verify progress, candidate labeling and cancellation.
8. Run multi-device reachability and verify timestamps and cancellation history.
9. Read ONVIF identity, capabilities, network interfaces and DNS.
10. On a specifically approved test camera, validate static IPv4 apply, reconnect, new-IP verification and gateway partial failure.
11. Export a diagnostic bundle and inspect it for credentials and customer-specific data.

Test both Wi-Fi and Ethernet/USB tethering where the device exposes the interface.

## Physical iOS validation

1. Obtain Apple's multicast networking entitlement and an authorized provisioning profile.
2. Generate the iOS runner and verify `NSLocalNetworkUsageDescription` and the multicast entitlement in the signed app.
3. Install on a physical device; simulator testing is not evidence of multicast behavior.
4. Verify interface link state and document that MTU is not exposed by the current iOS bridge.
5. Run ONVIF multicast and Oxita broadcast discovery on the same subnet as the camera.
6. Repeat device identity, ONVIF read, subnet and reachability checks.
7. Test static IPv4 only on an approved lab camera with a recovery path.
8. Inspect the support bundle before sharing.

Without the entitlement, iOS multicast discovery remains unverified.

## Camera test evidence

Record for each run:

| Field | Evidence |
|---|---|
| Camera model / hardware revision | Exact manufacturer model and board revision |
| Firmware | Exact firmware build |
| Phone | Vendor, model, OS version and app build |
| Network | Wi-Fi AP, VLAN/subnet, DHCP/static, multicast filtering |
| Discovery | ONVIF / Contract B result, response count and duration |
| ONVIF reads | Identity, capabilities, interfaces and DNS |
| Network writes | Proposed values, camera response, reconnect and verification |
| Failure handling | SOAP fault, timeout, malformed response, cancellation |
| Diagnostics | Bundle inspected and sanitized before sharing |

A passing parser fixture proves parser behavior only. A successful Android build proves compilation only. Neither proves camera interoperability or iOS multicast support.
