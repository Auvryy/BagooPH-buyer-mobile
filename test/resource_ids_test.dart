import 'package:flutter_test/flutter_test.dart';

import 'package:bagoo_buyer_mobile/core/resource_ids.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';

void main() {
  test('positiveInt32ResourceId enforces the supported identifier range', () {
    expect(positiveInt32ResourceId(1), 1);
    expect(positiveInt32ResourceId(2147483647), 2147483647);
    for (final value in [0, -1, 2147483648, 1.0, '1', null]) {
      expect(positiveInt32ResourceId(value), isNull, reason: '$value');
    }
  });

  test('positiveResourceIds filters malformed and non-positive IDs', () {
    expect(positiveResourceIds([1, 0, -2, 2.5, '3', null, 4]), {1, 4});
  });

  test('positiveResourceIds treats a non-list response as empty', () {
    expect(positiveResourceIds('not-a-list'), isEmpty);
    expect(positiveResourceIds(null), isEmpty);
  });

  test('requireRowsWithIds rejects non-text map keys with a typed error', () {
    expect(
      () => requireRowsWithIds(
        [
          {'id': 1, 7: 'unexpected'},
        ],
        idKey: 'id',
        error: 'Malformed rows.',
      ),
      throwsA(
        isA<BackendException>().having(
          (error) => error.message,
          'message',
          'Malformed rows.',
        ),
      ),
    );
  });

  test('stringsOf keeps only strings from an actual list', () {
    expect(stringsOf(['valid', 7, null, 'also valid']), [
      'valid',
      'also valid',
    ]);
    expect(stringsOf('not-a-list'), isEmpty);
  });
}
