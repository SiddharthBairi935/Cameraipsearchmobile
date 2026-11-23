import 'package:camera_ip_search_mobile/services/sensitive_data_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SensitiveDataRedactor', () {
    test('redacts common key-value secrets', () {
      final result = SensitiveDataRedactor.redact(
        'password=hunter2 authorization: Bearer abc123 token=xyz',
      );
      expect(result, isNot(contains('hunter2')));
      expect(result, isNot(contains('abc123')));
      expect(result, isNot(contains('xyz')));
      expect(result, contains('[REDACTED]'));
    });

    test('redacts bearer and basic authorization headers', () {
      final result = SensitiveDataRedactor.redact(
        'Authorization: Bearer eyJhbGciOi.test Authorization: Basic dXNlcjpwYXNz',
      );
      expect(result, isNot(contains('eyJhbGciOi')));
      expect(result, isNot(contains('dXNlcjpwYXNz')));
    });

    test('redacts URL user-info and XML credential elements', () {
      final result = SensitiveDataRedactor.redact(
        'http://camera:secret@192.0.2.1/onvif <wsse:Password>camera-secret</wsse:Password>',
      );
      expect(result, isNot(contains('camera:secret')));
      expect(result, isNot(contains('camera-secret')));
      expect(result, contains('[REDACTED]'));
    });

    test('truncates unusually long messages', () {
      final result = SensitiveDataRedactor.redact('x' * 9000);
      expect(result.length, lessThan(8200));
      expect(result, contains('[TRUNCATED]'));
    });
  });
}