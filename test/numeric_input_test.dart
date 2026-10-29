import 'package:bagoo_buyer_mobile/core/numeric_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invalid numeric edits retain the original text and selected range', () {
    const previous = TextEditingValue(
      text: '001234',
      selection: TextSelection(baseOffset: 2, extentOffset: 4),
    );
    for (final value in [
      'ab',
      '2x',
      '-1',
      '1.5',
      '1e2',
      '１２',
      '12\n',
      '12\u200b3',
    ]) {
      expect(
        unsignedIntegerFormatter.formatEditUpdate(
          previous,
          TextEditingValue(text: value),
        ),
        previous,
        reason: value,
      );
    }
  });

  test('numeric edits allow deletion, zeros and caret selection', () {
    for (final value in ['', '0', '001234', '92']) {
      final next = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
      expect(
        unsignedIntegerFormatter.formatEditUpdate(
          const TextEditingValue(text: '1'),
          next,
        ),
        next,
      );
    }
  });
}
