class SensitiveDataRedactor {
  static final _keyValue = RegExp(
    r'''((?:password|passwd|pwd|username|user_name|authorization|proxy-authorization|token|access_token|refresh_token|api[_-]?key|credential|secret|nonce|cookie|set-cookie)\s*[:=]\s*)("[^"]*"|'[^']*'|[^\s,;]+)''',
    caseSensitive: false,
  );
  static final _bearer = RegExp(r'\bBearer\s+[A-Za-z0-9._~+/-]+=*', caseSensitive: false);
  static final _basic = RegExp(r'\bBasic\s+[A-Za-z0-9+/]+=*', caseSensitive: false);
  static final _digest = RegExp(r'\bDigest\s+[^\r\n]+', caseSensitive: false);
  static final _urlUserInfo = RegExp(r'(https?://)[^/@\s:]+:[^/@\s]+@', caseSensitive: false);
  static final _headerSecret = RegExp(
    r'^(authorization|proxy-authorization|cookie|set-cookie)\s*:\s*[^\r\n]*',
    caseSensitive: false,
    multiLine: true,
  );
  static final _jsonSecret = RegExp(
    r'''("(?:password|passwd|pwd|username|user_name|token|access_token|refresh_token|api[_-]?key|credential|secret|nonce)"\s*:\s*)"[^"]*"''',
    caseSensitive: false,
  );
  static final _querySecret = RegExp(
    r'([?&](?:password|passwd|pwd|username|user_name|token|access_token|refresh_token|api[_-]?key|credential|secret|nonce)=)[^&#\s]*',
    caseSensitive: false,
  );
  static final _xmlSecret = RegExp(
    r'<(?:[A-Za-z0-9_.-]+:)?(Password|Username|Token|AccessToken|Nonce|Secret|BinarySecurityToken)(?:\s[^>]*)?>.*?</(?:[A-Za-z0-9_.-]+:)?\1>',
    caseSensitive: false,
    dotAll: true,
  );

  static String redact(String input, {int maxLength = 8192}) {
    var value = input
      .replaceAll(_headerSecret, '[REDACTED]')
      .replaceAll(_bearer, 'Bearer [REDACTED]')
      .replaceAll(_basic, 'Basic [REDACTED]')
      .replaceAll(_digest, 'Digest [REDACTED]')
      .replaceAllMapped(_keyValue, (m) => '${m[1]}[REDACTED]')
      .replaceAllMapped(_jsonSecret, (m) => '${m[1]}"[REDACTED]"')
      .replaceAllMapped(_querySecret, (m) => '${m[1]}[REDACTED]')
      .replaceAllMapped(_urlUserInfo, (m) => '${m[1]}[REDACTED]@')
      .replaceAll(_xmlSecret, '<REDACTED>');
    if (value.length > maxLength) value = '${value.substring(0, maxLength)}…[TRUNCATED]';
    return value;
  }
}