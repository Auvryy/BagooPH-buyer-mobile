import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/purchase_quote.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/checkout_fixtures.dart';

void main() {
  for (final id in [0, -1, 2.5, '2', null]) {
    test('quote rejects malformed shop ID $id', () {
      final quote = Map<String, dynamic>.from(mapOf(confirmedQuote()['quote']));
      final shops = mapsOf(quote['shops']);
      shops.single['shop_id'] = id;
      quote['shops'] = shops;

      expect(
        () => checkedPurchaseQuote(quote, itemIds: [1]),
        throwsA(isA<BackendException>()),
      );
    });
  }

  test('quote rejects duplicate shop IDs before voucher targeting', () {
    final quote = Map<String, dynamic>.from(mapOf(confirmedQuote()['quote']));
    quote['shops'] = [
      ...mapsOf(quote['shops']),
      {...mapsOf(quote['shops']).single},
    ];

    expect(
      () => checkedPurchaseQuote(quote, itemIds: [1]),
      throwsA(isA<BackendException>()),
    );
  });

  test('quote rejects a malformed row hidden among selected item IDs', () {
    final quote = Map<String, dynamic>.from(mapOf(confirmedQuote()['quote']));
    quote['items'] = [...mapsOf(quote['items']), 'malformed quote row'];

    expect(
      () => checkedPurchaseQuote(quote, itemIds: [1]),
      throwsA(isA<BackendException>()),
    );
  });

  test('quote rejects malformed voucher rows hidden by mapsOf', () {
    final quote = Map<String, dynamic>.from(mapOf(confirmedQuote()['quote']));
    quote['vouchers'] = [
      {
        'id': 20,
        'revision_id': 9,
        'code': 'SAVE',
        'name': 'Voucher',
        'issuer': 'platform',
      },
      'malformed voucher row',
    ];

    expect(
      () => checkedPurchaseQuote(quote, itemIds: [1]),
      throwsA(isA<BackendException>()),
    );
  });

  test('shop voucher cannot claim the platform-only free-shipping type', () {
    final quote = Map<String, dynamic>.from(mapOf(confirmedQuote()['quote']));
    final voucher = <String, dynamic>{
      'id': 20,
      'revision_id': 9,
      'code': 'SHIP',
      'name': 'Shipping voucher',
      'issuer': 'shop',
      'discount_type': 'free_shipping',
      'shop_id': 2,
      'shop_name': 'Test store',
      'product_scope': 'all',
    };
    quote
      ..['voucher'] = voucher
      ..['vouchers'] = [voucher];

    expect(
      () => checkedPurchaseQuote(quote, itemIds: [1]),
      throwsA(isA<BackendException>()),
    );
  });

  test('quote rejects redemption rows with an incomplete allocation list', () {
    final quote = Map<String, dynamic>.from(mapOf(confirmedQuote()['quote']));
    quote['redemptions'] = [
      {
        'revision_id': 9,
        'discount_cents': 100,
        'allocations': [
          {
            'shop_id': 2,
            'product_discount_cents': 100,
            'shipping_discount_cents': 0,
            'seller_expense_cents': 0,
            'platform_expense_cents': 100,
          },
          'malformed allocation row',
        ],
      },
    ];

    expect(
      () => checkedPurchaseQuote(quote, itemIds: [1]),
      throwsA(isA<BackendException>()),
    );
  });

  test(
    'quote accepts a complete voucher redemption and its shop allocation',
    () {
      final quote = Map<String, dynamic>.from(mapOf(confirmedQuote()['quote']));
      final voucher = <String, dynamic>{
        'id': 20,
        'revision_id': 9,
        'code': 'SAVE',
        'name': 'Voucher',
        'issuer': 'platform',
        'discount_type': 'fixed',
        'shop_id': null,
        'shop_name': null,
        'product_scope': 'all',
      };
      quote
        ..['discount'] = 1.0
        ..['total'] = 1249.0
        ..['voucher'] = voucher
        ..['vouchers'] = [voucher]
        ..['redemptions'] = [
          {
            'revision_id': 9,
            'discount_cents': 100,
            'allocations': [
              {
                'shop_id': 2,
                'product_discount_cents': 100,
                'shipping_discount_cents': 0,
                'seller_expense_cents': 0,
                'platform_expense_cents': 100,
              },
            ],
          },
        ];
      final shop = Map<String, dynamic>.from(mapsOf(quote['shops']).single)
        ..['discount'] = 1.0
        ..['product_discount'] = 1.0
        ..['total'] = 1249.0;
      quote['shops'] = [shop];

      expect(checkedPurchaseQuote(quote, itemIds: [1])['total'], 1249.0);
    },
  );

  test(
    'quote rejects voucher totals that disagree with redemption allocations',
    () {
      final quote = Map<String, dynamic>.from(mapOf(confirmedQuote()['quote']));
      quote['redemptions'] = [
        {
          'revision_id': 9,
          'discount_cents': 100,
          'allocations': [
            {
              'shop_id': 2,
              'product_discount_cents': 100,
              'shipping_discount_cents': 0,
              'seller_expense_cents': 0,
              'platform_expense_cents': 100,
            },
          ],
        },
      ];
      final voucher = <String, dynamic>{
        'id': 20,
        'revision_id': 9,
        'code': 'SAVE',
        'name': 'Voucher',
        'issuer': 'platform',
        'discount_type': 'fixed',
        'shop_id': null,
        'shop_name': null,
        'product_scope': 'all',
      };
      quote
        ..['voucher'] = voucher
        ..['vouchers'] = [voucher];

      expect(
        () => checkedPurchaseQuote(quote, itemIds: [1]),
        throwsA(isA<BackendException>()),
      );
    },
  );

  for (final entry in [
    ('fractional quantity', 'quantity', 1.5),
    ('invalid unit price', 'unit_price', 'not-money'),
    ('negative subtotal', 'subtotal', -1),
    (
      'partial price segments',
      'price_segments',
      [
        {'quantity': 1, 'unit_price': 1200, 'subtotal': 1200},
        'malformed segment',
      ],
    ),
    (
      'inconsistent segment subtotal',
      'price_segments',
      [
        {'quantity': 1, 'unit_price': 1200, 'subtotal': 1199},
      ],
    ),
  ]) {
    test('quote rejects ${entry.$1}', () {
      final quote = Map<String, dynamic>.from(mapOf(confirmedQuote()['quote']));
      final item = Map<String, dynamic>.from(mapsOf(quote['items']).single);
      item[entry.$2] = entry.$3;
      quote['items'] = [item];

      expect(
        () => checkedPurchaseQuote(quote, itemIds: [1]),
        throwsA(isA<BackendException>()),
      );
    });
  }
}
