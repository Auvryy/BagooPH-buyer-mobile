import 'package:flutter/services.dart';

const mobileNumberMessage =
    'Use a Philippine mobile number, such as 09171234567.';

final _phoneCharacters = RegExp(r'^\+?[0-9 ()-]*$');

// Reject the whole edit rather than turning mixed pasted text into a different
// contact number. Formatting is retained until the server canonicalizes it.
final mobileNumberFormatter = TextInputFormatter.withFunction((
  oldValue,
  value,
) {
  return value.text.length <= 24 &&
          _phoneCharacters.stringMatch(value.text) == value.text
      ? value
      : oldValue;
});

String? mobileNumberValidator(String? input) {
  final value = input?.replaceAll(RegExp(r'^ +| +$'), '') ?? '';
  if (value.isEmpty) return null;
  if (value.length > 24 || _phoneCharacters.stringMatch(value) != value) {
    return mobileNumberMessage;
  }
  var number = value.replaceAll(RegExp(r'[ ()-]'), '');
  if (number.startsWith('0')) {
    number = '+63${number.substring(1)}';
  } else if (number.startsWith('63')) {
    number = '+$number';
  }
  return RegExp(r'^\+639[0-9]{9}$').stringMatch(number) == number
      ? null
      : mobileNumberMessage;
}
