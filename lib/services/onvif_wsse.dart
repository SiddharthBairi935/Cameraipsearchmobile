import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Builds the ONVIF WS-Security UsernameToken PasswordDigest header.
///
/// This proves only that the client can construct the standard token. Camera
/// clock tolerance, nonce policy and vendor interoperability still require
/// physical-device validation.
class OnvifWsse {
  const OnvifWsse._();

  static const _securityNamespace =
      'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd';
  static const _utilityNamespace =
      'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd';
  static const _passwordDigestType =
      'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest';
  static const _nonceEncoding =
      'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary';

  static String addUsernameToken(
    String envelope, {
    required String username,
    required String password,
    required List<int> nonce,
    required String createdUtc,
  }) {
    if (username.isEmpty || nonce.isEmpty || createdUtc.isEmpty ||
        !envelope.contains('<s:Envelope') || !envelope.contains('<s:Body>')) {
      throw const FormatException('Cannot add WS-Security token to an invalid SOAP envelope.');
    }
    final digestInput = <int>[...nonce, ...utf8.encode(createdUtc), ...utf8.encode(password)];
    final digest = base64Encode(sha1.convert(digestInput).bytes);
    final header = '<s:Header><wsse:Security xmlns:wsse="$_securityNamespace" '
        'xmlns:wsu="$_utilityNamespace" s:mustUnderstand="1">'
        '<wsse:UsernameToken><wsse:Username>${_xml(username)}</wsse:Username>'
        '<wsse:Password Type="$_passwordDigestType">$digest</wsse:Password>'
        '<wsse:Nonce EncodingType="$_nonceEncoding">${base64Encode(nonce)}</wsse:Nonce>'
        '<wsu:Created>${_xml(createdUtc)}</wsu:Created>'
        '</wsse:UsernameToken></wsse:Security></s:Header>';
    return envelope.replaceFirst('<s:Body>', '$header<s:Body>');
  }

  static String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
