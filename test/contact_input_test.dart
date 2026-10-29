import 'package:bagoo_buyer_mobile/core/contact_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final value in [
    null,
    '',
    '   ',
    '09171234567',
    '+639171234567',
    '639171234567',
    '+63 (917) 123-4567',
    ' 0917 123 4567 ',
  ]) {
    test('allows optional or Philippine mobile contact: $value', () {
      expect(mobileNumberValidator(value), isNull);
    });
  }
  for (final value in [
    'letters',
    '0917',
    '091712345678',
    '09171234567x',
    '09171234567\n',
    '\t09171234567',
    '０９１７１２３４５６７',
    '٠٩١٧١٢٣٤٥٦٧',
    '0917\u200b1234567',
    '+14155552671',
    '0212345678',
    '9171234567',
    '0917+1234567',
    '++639171234567',
    '+63 917 123 4567 extension',
    '0917${' ' * 25}1234567',
  ]) {
    test('rejects malformed contact: $value', () {
      expect(mobileNumberValidator(value), mobileNumberMessage);
    });
  }
  test('rejects an entire invalid edit without changing text or selection', () {
    const old = TextEditingValue(
      text: '09171234567',
      selection: TextSelection(baseOffset: 4, extentOffset: 7),
    );
    expect(
      mobileNumberFormatter.formatEditUpdate(
        old,
        const TextEditingValue(text: '0917ABC4567'),
      ),
      old,
    );
    expect(
      mobileNumberFormatter.formatEditUpdate(
        old,
        TextEditingValue(text: '1' * 25),
      ),
      old,
    );
  });
}
