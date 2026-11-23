class SensitiveDataRedactor {
  static final _keyValue = RegExp(
    r'''((?:password|passwd|authorization|proxy-authorization|token|credential|secret|cookie|set-cookie)\s*[:=]\s*)("[^"]*"|'[^']*'|[^\s,;]+)''',
    caseSensitive: false,
  );
  static final _bearer = RegExp(r'\bBearer\s+[A-Za-z0-9._~+/-]+=*', caseSensitive: false);
  static final _basic = RegExp(r'\bBasic\s+[A-Za-z0-9+/]+=*', caseSensitive: false);
  static final _digest = RegExp(r'\bDigest\s+[^\r\n]+', caseSensitive: false);
  static final _urlUserInfo = RegExp(r'(https?://)[^/@\s:]+:[^/@\s]+@', caseSensitive: false);
  static final _xmlSecret = RegExp(
    r'<(?:[A-Za-z0-9_.-]+:)?(Password|Username|Token|UsernameToken|BinarySecurityToken)(?:\s[^>]*)?>.*?</(?:[A-Za-z0-9_.-]+:)?\1>',
    caseSensitive: false,
    dotAll: true,
  );

  static String redact(String input, {int maxLength = 8192}) {
    var value = input
      .replaceAll(_bearer, 'Bearer [REDACTED]')
      .replaceAll(_basic, 'Basic [REDACTED]')
      .replaceAllMapped(_keyValue, (m) => '${m[1]}[REDACTED]')
      .replaceAll(_digest, 'Digest [REDACTED]')
      .replaceAllMapped(_urlUserInfo, (m) => '${m[1]}[REDACTED]@')
      .replaceAll(_xmlSecret, '<REDACTED>');
    if (value.length > maxLength) value = '${value.substring(0, maxLength)}…[TRUNCATED]';
    return value;
  }
}