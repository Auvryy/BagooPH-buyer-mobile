import 'package:bagoo_buyer_mobile/core/strict_datetime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strict date-time rejects overflowing calendar and clock fields', () {
    for (final value in [
      '2026-02-30T10:00:00Z',
      '2026-11-32T23:59:59Z',
      '2026-10-27T24:00:00Z',
      '2026-10-27T10:60:00Z',
      '2026-10-27T10:00:60Z',
      '2026-10-27',
      'not a date',
    ]) {
      expect(strictDateTime(value), isNull, reason: value);
    }
  });

  test('strict date-time accepts valid local, UTC, and offset timestamps', () {
    expect(strictDateTime('2026-10-27T08:30:00'), isNotNull);
    expect(
      strictDateTime('2026-10-27T16:30:00+08:00')?.toUtc(),
      DateTime.utc(2026, 10, 27, 8, 30),
    );
    expect(
      strictDateTime('2026-10-27T08:30:00Z', requireTimezone: true),
      DateTime.utc(2026, 10, 27, 8, 30),
    );
    expect(
      strictDateTime('2026-10-27T08:30:00', requireTimezone: true),
      isNull,
    );
  });

  test('strict date-time rejects offsets beyond the ISO range', () {
    for (final value in [
      '2026-10-27T08:30:00+14:01',
      '2026-10-27T08:30:00+15:00',
      '2026-10-27T08:30:00-15:00',
    ]) {
      expect(strictDateTime(value, requireTimezone: true), isNull);
    }
  });

  test(
    'strict date-only parsing rejects invalid dates and keeps real dates',
    () {
      for (final value in ['2026-02-30', '2026-11-32', '2025-02-29']) {
        expect(strictDateOnly(value), isNull, reason: value);
      }
      expect(strictDateOnly('2024-02-29'), DateTime(2024, 2, 29));
      expect(strictDateOnly('2026-10-27T00:00:00Z'), isNull);
    },
  );
}
