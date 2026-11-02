import 'package:flutter/services.dart';

final _unsignedDigits = RegExp(r'^[0-9]*$');
final _unsignedDecimal = RegExp(r'^[0-9]+(?:\.[0-9]{0,2})?$');
final _signedCoordinate = RegExp(r'^-?[0-9]+(?:\.[0-9]{0,7})?$');

// Preserve the previous edit, including its selection, when pasted text is not
// an unsigned integer. Leading zeros remain meaningful for codes/postal codes.
final unsignedIntegerFormatter = TextInputFormatter.withFunction((old, value) {
  return _unsignedDigits.stringMatch(value.text) == value.text ? value : old;
});

// Allow a trailing decimal separator while editing (for example "12.") but
// reject signs, grouping symbols, exponents, and more than two decimal digits.
// The form validator still owns the complete amount range and submit rules.
final unsignedDecimalFormatter = TextInputFormatter.withFunction((old, value) {
  final text = value.text;
  return text.isEmpty || _unsignedDecimal.stringMatch(text) == text
      ? value
      : old;
});

// Coordinates allow a minus sign and up to seven fractional digits. Keep a
// lone minus and a trailing decimal point editable; the form validator checks
// completeness and geographic range before checkout can be reviewed.
final signedCoordinateFormatter = TextInputFormatter.withFunction((old, value) {
  final text = value.text;
  return text.isEmpty ||
          text == '-' ||
          _signedCoordinate.stringMatch(text) == text
      ? value
      : old;
});
