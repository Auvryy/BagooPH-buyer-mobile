import 'package:bagoo_buyer_mobile/core/application_text_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buyer names allow Latin scripts and backend compatibility forms', () {
    for (final value in [
      'Ana María O’Connor-Smith',
      'Jose\u0301 Dela Cruz',
      'Ａｎｎｅ Ｍａｒｉｅ',
    ]) {
      expect(buyerNameTextError(value), isNull, reason: value);
    }
  });

  test('buyer names reject numbers, non-Latin scripts and hidden text', () {
    for (final value in [
      'Revised2',
      'Жанна',
      '<script>',
      'Anne\u200bMarie',
      'Ana\u034fMaria',
    ]) {
      expect(buyerNameTextError(value), isNotNull, reason: value);
    }
  });

  test(
    'addresses allow the server punctuation and require meaningful text',
    () {
      expect(
        buyerAddressTextError(
          "Unit #4, 12-D St. John's Road / Annex (East) & 2",
        ),
        isNull,
      );
      expect(buyerAddressTextError('１２３ New Street'), isNull);
      expect(buyerAddressTextError('--- # / :'), isNotNull);
      expect(buyerAddressTextError('123 <b>Street</b>'), isNotNull);
      expect(buyerAddressTextError('123 Street\u200b'), isNotNull);
    },
  );

  test('notes permit ordinary newlines and reject markup and unsafe text', () {
    expect(buyerNotesTextError('Leave at the gate\nCall on arrival.'), isNull);
    expect(
      buyerNotesTextError('Leave at the gate\r\nCall on arrival.'),
      isNull,
    );
    expect(buyerNotesTextError('Please call at 3pm.'), isNull);
    expect(buyerNotesTextError('   '), isNotNull);
    expect(
      buyerNotesTextError('Leave at the gate\rCall on arrival.'),
      isNotNull,
    );
    expect(buyerNotesTextError('<script>alert(1)</script>'), isNotNull);
    expect(buyerNotesTextError('javascript:alert(1)'), isNotNull);
    expect(buyerNotesTextError('onerror = run()'), isNotNull);
    expect(buyerNotesTextError('Call\tme'), isNotNull);
  });

  test('application field checks use the matching buyer server rule', () {
    expect(buyerApplicationFieldError('first_name', 'Maria'), isNull);
    expect(buyerApplicationFieldError('first_name', 'Maria2'), isNotNull);
    expect(buyerApplicationFieldError('address', '12 New Street'), isNull);
    expect(buyerApplicationFieldError('city', '<Laguna>'), isNotNull);
    expect(buyerApplicationFieldError('postal_code', '4000'), isNull);
    expect(buyerApplicationFieldError('postal_code', '４０００'), isNotNull);
  });
}
