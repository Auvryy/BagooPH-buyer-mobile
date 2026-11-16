import 'package:bagoo_buyer_mobile/features/home/bag_heart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the heart picks the first in-stock colour and size, like the website',
    () {
      final choice = bagHeartChoice({
        'stock': 5,
        'variants': {
          'combinations': [
            {'color': 'Red', 'size': 'S', 'stock': 0},
            {'color': 'Blue', 'size': 'M', 'stock': 2},
          ],
        },
      });
      expect(choice.available, isTrue);
      expect(choice.color, 'Blue');
      expect(choice.size, 'M');
    },
  );

  test('a product without variants can be added as it is', () {
    final choice = bagHeartChoice({'stock': 3});
    expect(choice.available, isTrue);
    expect(choice.color, isNull);
    expect(choice.size, isNull);
  });

  test('sold out, variant sold out or a shop on vacation cannot be added', () {
    expect(bagHeartChoice({'stock': 0}).available, isFalse);
    expect(
      bagHeartChoice({
        'stock': 4,
        'variants': {
          'combinations': [
            {'color': 'Red', 'size': 'S', 'stock': 0},
          ],
        },
      }).available,
      isFalse,
    );
    expect(
      bagHeartChoice({
        'stock': 4,
        'shop': {'vacation_mode': true},
      }).available,
      isFalse,
    );
  });

  test('a product already in the Bag is read from the shared page data', () {
    final props = {
      'cartItemIdsByProduct': {'12': 99},
    };
    expect(bagLineFor(props, 12), 99);
    expect(bagLineFor(props, 13), isNull);
    expect(bagLineFor(null, 12), isNull);
  });
}
