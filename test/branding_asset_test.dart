import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('official Oxita logo is bundled for offline mobile branding', () async {
    final data = await rootBundle.load('assets/oxita-logo.png');
    expect(data.lengthInBytes, greaterThan(1000));
  });
}
