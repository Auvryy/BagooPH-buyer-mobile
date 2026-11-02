/// Parses an ISO date-time without accepting overflowing calendar fields.
///
/// `DateTime.parse` normalizes inputs such as February 30 into another date.
/// Server timestamps should not be allowed to move a deadline or milestone.
DateTime? strictDateTime(Object? value, {bool requireTimezone = false}) {
  if (value is! String) return null;
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:([Zz])|([+-])(\d{2}):(\d{2}))?$',
  ).firstMatch(value);
  if (match == null ||
      requireTimezone && match.group(7) == null && match.group(8) == null) {
    return null;
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final writtenCalendar = DateTime.utc(year, month, day, hour, minute, second);
  if (writtenCalendar.year != year ||
      writtenCalendar.month != month ||
      writtenCalendar.day != day ||
      writtenCalendar.hour != hour ||
      writtenCalendar.minute != minute ||
      writtenCalendar.second != second) {
    return null;
  }
  if (match.group(8) != null) {
    final offsetHour = int.parse(match.group(9)!);
    final offsetMinute = int.parse(match.group(10)!);
    if (offsetHour > 14 ||
        offsetMinute > 59 ||
        offsetHour == 14 && offsetMinute != 0) {
      return null;
    }
  }
  return DateTime.tryParse(value);
}

/// Parses an ISO calendar date without accepting day or month overflow.
DateTime? strictDateOnly(Object? value) {
  if (value is! String) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final calendar = DateTime.utc(year, month, day);
  if (calendar.year != year || calendar.month != month || calendar.day != day) {
    return null;
  }
  return DateTime(year, month, day);
}
