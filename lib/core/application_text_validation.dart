final _latinName = RegExp(r"[\p{Script=Latin}\p{M} .’'\-]+", unicode: true);
final _latinLetter = RegExp(r'\p{Script=Latin}', unicode: true);
final _plainAddress = RegExp(
  r"[\p{Script=Latin}\p{M}\p{N} #.,’'\-/()&:]+",
  unicode: true,
);
final _letterOrNumber = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _plainNotes = RegExp(r'''(?:[^\p{C}<>`{}]|\r?\n)*''', unicode: true);
final _unsafeText = RegExp(
  r'[\u034f\uFE00-\uFE0F]|(?:javascript|vbscript|data)\s*:|\bon[a-z]+\s*=',
  caseSensitive: false,
  unicode: true,
);

String? buyerNameTextError(String? raw) {
  final value = _compatibilityText(raw ?? '');
  if (value.isEmpty) return null;
  if (_unsafeText.hasMatch(value) ||
      !_matchesWhole(_latinName, value) ||
      !_latinLetter.hasMatch(value)) {
    return 'Use Latin letters, spaces, apostrophes, hyphens or periods. Numbers and other symbols are not allowed.';
  }
  return null;
}

String? buyerAddressTextError(String? raw) {
  final value = _compatibilityText(raw ?? '');
  if (value.isEmpty) return null;
  if (_unsafeText.hasMatch(value) ||
      !_matchesWhole(_plainAddress, value) ||
      !_letterOrNumber.hasMatch(value)) {
    return 'Use plain text with letters or numbers. Markup and hidden characters are not allowed.';
  }
  return null;
}

String? buyerNotesTextError(String? raw) {
  final value = _compatibilityText(raw ?? '');
  if (value.isEmpty) return null;
  if (_unsafeText.hasMatch(value) ||
      !_matchesWhole(_plainNotes, value) ||
      !_letterOrNumber.hasMatch(value)) {
    return 'Use plain text with letters or numbers, without markup or hidden characters.';
  }
  return null;
}

String? buyerApplicationFieldError(String key, String? value) => switch (key) {
  'name' ||
  'first_name' ||
  'middle_name' ||
  'last_name' => buyerNameTextError(value),
  'address' ||
  'city' ||
  'province' ||
  'municipality' ||
  'barangay' => buyerAddressTextError(value),
  'postal_code' =>
    value == null || value.isEmpty || RegExp(r'^[0-9]{4}$').hasMatch(value)
        ? null
        : 'Enter a four-digit postal code.',
  _ => null,
};

bool _matchesWhole(RegExp pattern, String value) =>
    pattern.matchAsPrefix(value)?.end == value.length;

// The backend normalizes compatibility-width ASCII before validation. Mirror
// that common keyboard/paste case without adding a normalization dependency.
String _compatibilityText(String value) => String.fromCharCodes(
  value.runes.map((rune) {
    if (rune == 0x3000) return 0x20;
    if (rune >= 0xff01 && rune <= 0xff5e) return rune - 0xfee0;
    return rune;
  }),
);
