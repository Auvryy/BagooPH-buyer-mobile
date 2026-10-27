import 'package:flutter_test/flutter_test.dart';
import 'package:bagoo_buyer_mobile/features/products/product_model.dart';

import 'support/fake_buyer_repository.dart';

void main() {
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
