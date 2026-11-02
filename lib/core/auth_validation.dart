import 'application_text_validation.dart';

String? emailValidator(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return 'Enter your email address.';
  if (email.runes.length > 255 ||
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? registrationNameValidator(String? raw, {required String label}) {
  final value = raw?.trim() ?? '';
  final length = value.runes.length;
  if (length < 2) return 'Enter your $label.';
  if (length > 50) return 'Use at most 50 characters.';
  return buyerNameTextError(value);
}

String? registrationMiddleInitialValidator(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty ||
      RegExp(r'^\p{Script=Latin}{1,2}\.?$', unicode: true).hasMatch(value)) {
    return null;
  }
  return 'Enter one or two letters, such as M. or MD.';
}

String? registrationAddressValidator(String? raw) {
  final value = raw?.trim() ?? '';
  final length = value.runes.length;
  if (length < 5) return 'Enter a complete street address.';
  if (length > 500) return 'Use at most 500 characters.';
  return buyerAddressTextError(value);
}

String? passwordValidator(String? value) {
  final password = value ?? '';
  final length = password.runes.length;
  if (length < 8 ||
      length > 128 ||
      !RegExp(r'\p{Ll}', unicode: true).hasMatch(password) ||
      !RegExp(r'\p{Lu}', unicode: true).hasMatch(password) ||
      !RegExp(r'\p{N}', unicode: true).hasMatch(password) ||
      !RegExp(r'[\p{S}\p{P}]', unicode: true).hasMatch(password) ||
      RegExp(r'\p{C}', unicode: true).hasMatch(password)) {
    return 'Use 8–128 characters with uppercase, lowercase, a number, and a symbol.';
  }
  return null;
}
