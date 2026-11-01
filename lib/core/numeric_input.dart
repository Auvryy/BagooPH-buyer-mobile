import 'package:flutter/services.dart';

final _unsignedDigits = RegExp(r'^[0-9]*$');

// Preserve the previous edit, including its selection, when pasted text is not
// an unsigned integer. Leading zeros remain meaningful for codes/postal codes.
final unsignedIntegerFormatter = TextInputFormatter.withFunction((old, value) {
  return _unsignedDigits.stringMatch(value.text) == value.text ? value : old;
});
