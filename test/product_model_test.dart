import 'package:flutter_test/flutter_test.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/core/count_metadata.dart';
import 'package:bagoo_buyer_mobile/features/products/product_model.dart';

import 'support/fake_buyer_repository.dart';

void main() {
  test('display counts require exact nonnegative integers', () {
    for (final value in [0, 1, 99999]) {
      expect(nonNegativeCount(value), value);
    }
    for (final value in [
      -1,
      1.0,
      1.5,
      '2',
      double.nan,
      double.infinity,
      null,
    ]) {
      expect(nonNegativeCount(value), isNull);
    }
  });

  for (final id in [0, -1, 1.5, '1', null]) {
    test('product selection rejects malformed resource ID $id', () {
      expect(
        () => ProductSelection(productPage(override: {'id': id})),
        throwsA(isA<BackendException>()),
      );
    });
  }

  test(
    'card uses web comparison and discount rules without discounting ranges',
    () {
      final card = ProductPrice({
        'price': '100.00',
        'compare_at_price': '150.00',
        'price_range': {'min': 120, 'max': 120, 'regular_min': 120},
      });
      expect(card.comparison, 170);
      expect(card.discount, 29);
      final ranged = ProductPrice({
        'price': 100,
        'compare_at_price': 150,
        'price_range': {'min': 100, 'max': 120},
      });
      expect(ranged.discount, isNull);
      expect(ranged.label, '₱100.00 – ₱120.00');
      expect(recordedRating(0), isNull);
      expect(recordedRating('4.5'), 4.5);
    },
  );

  test('invalid product prices never appear as free or negative prices', () {
    for (final price in [
      null,
      'not a price',
      -1,
      double.nan,
      double.infinity,
    ]) {
      final productPricing = ProductPrice({'price': price});
      expect(productPricing.label, 'Price unavailable');

      final selection = ProductSelection(
        productPage(override: {'price': price}),
      );
      expect(selection.priceLabel, 'Price unavailable');
      expect(selection.maxQuantity, 0);
      expect(selection.quantityError, contains('Price could not be confirmed'));
    }
  });

  test('invalid independent option prices are unavailable and not buyable', () {
    for (final malformedPrice in [null, 'not a price', 0, -1, 1000000.01]) {
      final page = productPage(override: {'price': 100, 'stock': 10});
      page.props['variations'] = {
        'pricing_mode': 'independent',
        'colors': [
          {'name': 'Red'},
        ],
        'sizes': [
          {'name': 'Large'},
        ],
        'combinations': [
          {
            'color': 'Red',
            'size': 'Large',
            'stock': 5,
            'price': malformedPrice,
          },
        ],
      };
      final selection = ProductSelection(page)
        ..color = 'Red'
        ..size = 'Large';

      expect(selection.priceLabel, 'Price unavailable');
      expect(selection.maxQuantity, 0);
      expect(selection.quantityError, contains('Price could not be confirmed'));
      expect(selection.comparison, isNull);
    }
  });

  test('invalid surcharge option prices are unavailable and not buyable', () {
    for (final malformedSurcharge in [-1, 'not a price', double.infinity]) {
      final page = productPage(override: {'price': 100, 'stock': 10});
      page.props['variations'] = {
        'colors': [],
        'sizes': [
          {'name': 'Large'},
        ],
        'combinations': [
          {
            'color': null,
            'size': 'Large',
            'stock': 5,
            'extra_price': malformedSurcharge,
          },
        ],
      };
      final selection = ProductSelection(page)..size = 'Large';

      expect(selection.priceLabel, 'Price unavailable');
      expect(selection.maxQuantity, 0);
      expect(selection.quantityError, contains('Price could not be confirmed'));
    }
  });

  test('invalid legacy size surcharges are unavailable and not buyable', () {
    final page = productPage(override: {'price': 100, 'stock': 10});
    page.props['variations'] = {
      'colors': [],
      'sizes': [
        {'name': 'Large', 'extra_price': -20},
      ],
    };
    final selection = ProductSelection(page)..size = 'Large';

    expect(selection.priceLabel, 'Price unavailable');
    expect(selection.maxQuantity, 0);
    expect(selection.quantityError, contains('Price could not be confirmed'));
  });

  test('malformed sale terms do not turn into a one-cent price', () {
    for (final malformedSale in [
      {'discount_type': 'percentage', 'percentage': 'not a percentage'},
      {'discount_type': 'percentage', 'percentage': 100},
      {'discount_type': 'fixed', 'price': 'not a price'},
    ]) {
      final page = productPage(
        override: {
          'price': 100,
          'stock': 10,
          'sale_offer': {'effective_price': 0.01, 'active': malformedSale},
        },
      );
      final selection = ProductSelection(page);

      expect(selection.priceLabel, 'Price unavailable');
      expect(selection.maxQuantity, 0);
      expect(selection.quantityError, contains('Price could not be confirmed'));
    }
  });

  test('malformed option metadata is not treated as a no-option product', () {
    for (final variations in [
      null,
      'not an object',
      {'colors': 'Red', 'sizes': <Object?>[]},
      {'colors': <Object?>[], 'sizes': null},
    ]) {
      final page = productPage(override: {'price': 100, 'stock': 10})
        ..props['variations'] = variations;
      final selection = ProductSelection(page);

      expect(selection.inventoryCountsValid, isFalse);
      expect(selection.maxQuantity, 0);
      expect(selection.quantityError, contains('could not be confirmed'));
    }
  });

  test('related-product cards require a complete unique feed', () {
    expect(completeRelatedProducts([product(2), 'malformed row']), isNull);
    expect(completeRelatedProducts([product(2), product(2)]), isNull);
    expect(
      completeRelatedProducts([
        {...product(2), 'slug': '   '},
      ]),
      isNull,
    );
    expect(completeRelatedProducts([product(2)]), [product(2)]);
  });

  test('product card pages reject rows beyond the backend page bound', () {
    final rows = [for (var id = 1; id <= 25; id++) product(id)];
    expect(completeProductCards(rows), isNull);
  });

  test('independent options apply percentage sale in cents and retain real comparison', () {
    final page = productPage(
      override: {
        'price': '100.00',
        'stock': 10,
        'price_range': {'min': 90, 'max': 180, 'regular_min': 100},
        'sale_offer': {
          'active': {'discount_type': 'percentage', 'percentage': 10},
        },
      },
    );
    page.props['variations'] = {
      'pricing_mode': 'independent',
      'colors': [
        {'name': 'Red', 'in_stock': true},
      ],
      'sizes': [
        {'name': 'Large'},
      ],
      'combinations': [
        {'color': 'Red', 'size': 'Large', 'price': '199.99', 'stock': 6},
      ],
    };
    final selection = ProductSelection(page);
    expect(selection.complete, isFalse);
    expect(selection.quantityError, contains('Choose'));
    selection.color = 'Red';
    selection.size = 'Large';
    expect(selection.regular, 199.99);
    expect(selection.price, 179.99);
    expect(selection.comparison, 199.99);
  });
  test('quantity respects global stock, selected stock, limits and existing Bag rows', () {
    final page = productPage(override: {'price': 100, 'stock': 10});
    page.props['purchaseAllowance'] = 8;
    page.props['cartQuantities'] = [
      {'color': 'Red', 'size': 'Small', 'quantity': 2},
      {'color': 'Blue', 'size': 'Small', 'quantity': 1},
    ];
    page.props['variations'] = {
      'colors': [
        {'name': 'Red', 'in_stock': true},
        {'name': 'Blue', 'in_stock': true},
      ],
      'sizes': [
        {'name': 'Small'},
      ],
      'combinations': [
        {'color': 'Red', 'size': 'Small', 'stock': 4},
        {'color': 'Blue', 'size': 'Small', 'stock': 8},
      ],
    };
    final selection = ProductSelection(page)
      ..color = 'Red'
      ..size = 'Small';
    expect(selection.maxQuantity, 2);
    selection.quantityText = '3';
    expect(selection.quantityError, contains('Only 2'));
    selection.quantityText = '2.5';
    expect(selection.quantityError, contains('whole quantity'));
    selection.color = 'Missing';
    expect(selection.stock, 0);
    expect(selection.maxQuantity, 0);
  });
  for (final field in [
    'product stock',
    'Bag quantity',
    'purchase allowance',
    'variant stock',
  ]) {
    test('fractional $field fails closed before quantity is offered', () {
      final page = productPage();
      late ProductSelection selection;
      switch (field) {
        case 'product stock':
          (page.props['product'] as Map)['stock'] = 1.5;
          selection = ProductSelection(page);
        case 'Bag quantity':
          page.props['cartQuantities'] = [
            {'color': null, 'size': null, 'quantity': 1.5},
          ];
          selection = ProductSelection(page);
        case 'purchase allowance':
          page.props['purchaseAllowance'] = 1.5;
          selection = ProductSelection(page);
        case 'variant stock':
          page.props['variations'] = {
            'colors': [
              {'name': 'Red'},
            ],
            'sizes': [],
            'combinations': [
              {'color': 'Red', 'size': null, 'stock': 1.5},
            ],
          };
          selection = ProductSelection(page)..color = 'Red';
        default:
          throw StateError('Unexpected quantity field: $field');
      }

      expect(selection.maxQuantity, 0);
      expect(selection.quantityError, contains('could not be confirmed'));
    });
  }
  test('string Bag quantities are not parsed as inventory counts', () {
    final page = productPage()
      ..props['cartQuantities'] = [
        {'color': null, 'size': null, 'quantity': '1'},
      ];
    final selection = ProductSelection(page);

    expect(selection.maxQuantity, 0);
    expect(selection.quantityError, contains('could not be confirmed'));
  });
  test('surcharges and fixed sale preserve the selected option adjustment', () {
    final page = productPage(
      override: {
        'price': '100.00',
        'price_range': {'regular_min': 100, 'min': 80, 'max': 100},
        'sale_offer': {
          'active': {'discount_type': 'fixed', 'price': 80},
        },
      },
    );
    page.props['variations'] = {
      'colors': [],
      'sizes': [
        {'name': 'XL', 'extra_price': 20, 'stock': 8},
      ],
    };
    final selection = ProductSelection(page)..size = 'XL';
    expect(selection.regular, 120);
    expect(selection.price, 100);
  });

  test('disabled colors and legacy size stock cannot be selected', () {
    final page = productPage();
    page.props['variations'] = {
      'colors': [
        {'name': 'Paused', 'in_stock': false},
        {'name': 'Available'},
      ],
      'sizes': [
        {'name': 'Sold out', 'stock': 0},
        {'name': 'Small', 'stock': 4},
      ],
    };
    final selection = ProductSelection(page);
    expect(selection.colorAvailable('Paused'), false);
    expect(selection.colorAvailable('Available'), true);
    expect(selection.sizeAvailable('Sold out'), false);
    expect(selection.sizeAvailable('Small'), true);
    page.props['variations'] = {
      'colors': [
        {'name': 'Red'},
        {'name': 'Blue'},
      ],
      'combinations': [
        {'color': 'Red', 'size': 'S', 'stock': 0},
        {'color': 'Blue', 'size': 'S', 'stock': 2},
      ],
    };
    expect(selection.colorAvailable('Red'), false);
    expect(selection.colorAvailable('Blue'), true);
  });
  test('duplicate product option names fail closed before purchase', () {
    final page = productPage();
    page.props['variations'] = {
      'colors': [
        {'name': 'Red', 'in_stock': true},
        {'name': 'Red', 'in_stock': false},
      ],
      'sizes': <Map<String, dynamic>>[],
    };
    final selection = ProductSelection(page)..color = 'Red';

    expect(selection.inventoryCountsValid, isFalse);
    expect(selection.maxQuantity, 0);
    expect(selection.quantityError, contains('could not be confirmed'));
  });

  test('duplicate product option combinations fail closed before purchase', () {
    final page = productPage();
    page.props['variations'] = {
      'colors': [
        {'name': 'Red'},
      ],
      'sizes': [
        {'name': 'Large'},
      ],
      'combinations': [
        {'color': 'Red', 'size': 'Large', 'price': 100, 'stock': 1},
        {'color': 'Red', 'size': 'Large', 'price': 150, 'stock': 5},
      ],
    };
    final selection = ProductSelection(page)
      ..color = 'Red'
      ..size = 'Large';

    expect(selection.inventoryCountsValid, isFalse);
    expect(selection.maxQuantity, 0);
    expect(selection.quantityError, contains('could not be confirmed'));
  });
  test(
    'gallery contains only real unique images and vacation blocks additions',
    () {
      final page = productPage(
        override: {
          'featured_image': '/front.jpg',
          'images': [
            {'image_url': '/front.jpg'},
            {'image_url': '/side.jpg'},
          ],
          'shop': {'vacation_mode': true},
        },
      );
      final selection = ProductSelection(page);
      expect(selection.gallery, ['/front.jpg', '/side.jpg']);
      expect(selection.maxQuantity, 0);
    },
  );
}
