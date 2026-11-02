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

  test(
    'decimal formatter rejects malformed edits and keeps the old selection',
    () {
      const previous = TextEditingValue(
        text: '12.50',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
      );
      for (final value in [
        '-1',
        '+1',
        'NaN',
        'Infinity',
        '1e2',
        '1.234',
        '1,000',
        '₱12.50',
        '.5',
        '12..5',
        '12\u200b50',
        '12.50\n',
      ]) {
        expect(
          unsignedDecimalFormatter.formatEditUpdate(
            previous,
            TextEditingValue(text: value),
          ),
          previous,
          reason: value,
        );
      }
    },
  );

  test(
    'decimal formatter allows editing, deletion, and selected replacement',
    () {
      const previous = TextEditingValue(
        text: '12.50',
        selection: TextSelection(baseOffset: 0, extentOffset: 2),
      );
      for (final value in ['', '0', '12', '12.', '12.5', '12.50']) {
        final next = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
        expect(unsignedDecimalFormatter.formatEditUpdate(previous, next), next);
      }

      const replacement = TextEditingValue(
        text: '9.50',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(
        unsignedDecimalFormatter.formatEditUpdate(previous, replacement),
        replacement,
      );
    },
  );
}
