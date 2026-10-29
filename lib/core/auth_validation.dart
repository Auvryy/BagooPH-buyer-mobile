String? emailValidator(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return 'Enter your email address.';
  if (email.runes.length > 255 ||
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    return 'Enter a valid email address.';
  }
  return null;
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
