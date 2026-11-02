class TextLengthBounds {
  const TextLengthBounds({required this.minimum, required this.maximum});

  final int minimum;
  final int maximum;
}

int? strictNonNegativeInteger(Object? value) =>
    value is int && value >= 0 ? value : null;

List<String>? uniqueStringOptions(Object? value) {
  if (value is! List) return null;

  final options = <String>[];
  final seen = <String>{};
  for (final option in value) {
    if (option is! String || option.trim().isEmpty) return null;
    if (seen.add(option)) options.add(option);
  }
  return options;
}

TextLengthBounds? parseTextLengthBounds(
  Map<String, dynamic> field, {
  required int defaultMinimum,
  required int defaultMaximum,
}) {
  if (defaultMinimum < 0 || defaultMaximum < defaultMinimum) return null;

  final minimum = field['min_length'] == null
      ? defaultMinimum
      : strictNonNegativeInteger(field['min_length']);
  final maximum = field['max_length'] == null
      ? defaultMaximum
      : strictNonNegativeInteger(field['max_length']);
  if (minimum == null || maximum == null || minimum > maximum) return null;
  return TextLengthBounds(minimum: minimum, maximum: maximum);
}
