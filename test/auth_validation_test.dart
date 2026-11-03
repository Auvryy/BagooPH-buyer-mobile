import 'package:bagoo_buyer_mobile/core/auth_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final value in [
    'Aa1!bcde',
    'Example!123',
    'Éñgel!١٢٣',
    'Aa1!${'x' * 124}',
  ]) {
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
    final maximumEmail = '${'a' * 242}@example.test';
    final overMaximumEmail = '${'a' * 243}@example.test';
    expect(maximumEmail.runes.length, 255);
    expect(overMaximumEmail.runes.length, 256);
    expect(emailValidator(maximumEmail), isNull);
    expect(emailValidator(overMaximumEmail), isNotNull);
    expect(emailValidator('buyer@example.test'), isNull);
  });

  test('registration names enforce exact minimum and maximum lengths', () {
    expect(registrationNameValidator('Al', label: 'first name'), isNull);
    expect(registrationNameValidator('A' * 50, label: 'first name'), isNull);
    expect(registrationNameValidator('A' * 51, label: 'first name'), isNotNull);
  });

  test('registration names follow the backend plain-name contract', () {
    for (final value in ['Ana María', 'Jose\u0301 Dela Cruz', 'Ａｎｎｅ']) {
      expect(
        registrationNameValidator(value, label: 'first name'),
        isNull,
        reason: value,
      );
    }
    for (final value in ['A', 'Ana2', '<script>', 'A' * 51]) {
      expect(
        registrationNameValidator(value, label: 'first name'),
        isNotNull,
        reason: value,
      );
    }
  });

  test('registration middle initials and addresses match server rules', () {
    for (final value in ['', 'M', 'MD', 'MD.']) {
      expect(registrationMiddleInitialValidator(value), isNull, reason: value);
    }
    for (final value in ['12', 'A B', 'ABC', '<x>']) {
      expect(
        registrationMiddleInitialValidator(value),
        isNotNull,
        reason: value,
      );
    }
    expect(registrationAddressValidator('A' * 5), isNull);
    expect(registrationAddressValidator('A' * 4), isNotNull);
    expect(registrationAddressValidator('A' * 500), isNull);
    expect(registrationAddressValidator('A' * 501), isNotNull);
    expect(registrationAddressValidator("Unit #4, St. John's Road"), isNull);
    expect(registrationAddressValidator('123 <script>'), isNotNull);
  });
}
