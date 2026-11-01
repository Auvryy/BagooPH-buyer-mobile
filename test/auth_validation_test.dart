import 'package:bagoo_buyer_mobile/core/auth_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final value in ['Example!123', 'Éñgel!١٢٣', 'Aa1!${'x' * 124}']) {
    test('allows server-compatible password: $value', () {
      expect(passwordValidator(value), isNull);
    });
  }
  for (final value in [
    '',
    'abcdefgh',
    '12345678',
    'AAAAAAAA',
    'Valid1234',
    'Valid 123',
    'Abc!123\n',
    'Abc!123\u0000',
    'Abc!123\u200b',
    'Aa1!${'x' * 125}',
  ]) {
    test('rejects weak, control or oversized password: $value', () {
      expect(passwordValidator(value), isNotNull);
    });
  }
  test('bounds email before availability checks or authentication', () {
    expect(emailValidator(''), isNotNull);
    expect(emailValidator('bad-email'), isNotNull);
    expect(emailValidator('${'x' * 256}@example.test'), isNotNull);
    expect(emailValidator('buyer@example.test'), isNull);
  });
}
