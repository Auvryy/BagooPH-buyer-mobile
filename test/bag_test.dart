import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/bag_controller.dart';
import 'package:bagoo_buyer_mobile/features/checkout/bag_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';

Map<String, dynamic> line(int id, {String color = 'Red', int quantity = 1}) => {
  'id': id,
  'product_id': 10,
  'color': color,
  'size': 'M',
  'quantity': quantity,
  'unit_price': 100,
  'available_for_purchase': true,
  'product': {
    'id': 10,
    'name': 'Test product',
    'slug': 'test-product',
    'price': 100,
    'stock': 20,
    'shop_id': 1,
    'shop': {'id': 1, 'name': 'Test shop'},
    'variants': {
      'colors': [
        {'name': 'Red'},
        {'name': 'Blue'},
      ],
      'sizes': [
        {'name': 'M', 'stock': 4},
      ],
      'combinations': [
        {'color': 'Red', 'size': 'M', 'stock': 3},
        {'color': 'Blue', 'size': 'M', 'stock': 8},
      ],
    },
  },
};
Map<String, dynamic> priced(List<int> ids) => {
  'quote': {
    'subtotal': ids.length * 100,
    'shipping_fee': 50,
    'discount': 0,
    'shipping_discount': 0,
    'total': ids.length * 100 + 50,
    'items': [
      for (final id in ids)
        {'id': id, 'quantity': 1, 'unit_price': 100, 'subtotal': 100},
    ],
    'shops': [
      {
        'shop_id': 1,
        'shop_name': 'Test shop',
        'shipping': 50,
        'total': ids.length * 100 + 50,
      },
    ],
  },
  'availableVouchers': [],
};

class BagRepository extends FakeBuyerRepository {
  List<Map<String, dynamic>> rows = [line(1), line(2, color: 'Blue')];
  Future<Map<String, dynamic>> Function(List<int>)? bagQuoteHandler;
  bool failRemoval = false;
  @override
  Future<WebPage> bag() async => WebPage('Cart/Index', {
    'auth': {'user': buyer},
    'items': rows,
  });
  @override
  Future<Map<String, dynamic>> bagQuote(List<int> ids) =>
      bagQuoteHandler?.call(ids) ?? Future.value(priced(ids));
  @override
  Future<WebPage> changeBagItem(int id, int? quantity) async {
    if (quantity == null && failRemoval) {
      throw const BackendException('Removal not confirmed');
    }
    if (quantity == null) {
      rows = rows.where((row) => row['id'] != id).toList();
    } else {
      rows = [
        for (final row in rows)
          if (row['id'] == id) {...row, 'quantity': quantity} else row,
      ];
    }
    return bag();
  }
}

void main() {
  test('Bag quantity bounds honor total stock and exact matrix selection', () {
    final red = line(1), blue = line(2, color: 'Blue', quantity: 4);
    expect(bagMaximumQuantity(red, [red, blue]), 3);
    final anotherRed = line(3);
    expect(bagMaximumQuantity(red, [red, blue, anotherRed]), 2);
    final stockLimited = {
      ...red,
      'product': {...mapOf(red['product']), 'stock': 5},
    };
    expect(bagMaximumQuantity(stockLimited, [stockLimited, blue]), 1);
    expect(
      bagMaximumQuantity({...red, 'available_for_purchase': false}, [red]),
      0,
    );
    final legacy = {
      ...red,
      'product': {
        ...mapOf(red['product']),
        'variants': {
          'sizes': [
            {'name': 'M', 'stock': 4},
          ],
        },
      },
    };
    expect(
      bagMaximumQuantity(legacy, [legacy, line(2, color: 'Blue', quantity: 2)]),
      2,
    );
  });
  test(
    'selection quotes discard stale results and require matching item IDs',
    () async {
      final repo = BagRepository();
      final controller = BagController(repo);
      await controller.load();
      expect(controller.selected, {1});
      expect(controller.ready, true);
      final old = Completer<Map<String, dynamic>>();
      repo.bagQuoteHandler = (_) => old.future;
      final first = controller.refreshQuote();
      controller.select([1], false);
      repo.bagQuoteHandler = (ids) async => priced(ids);
      controller.select([2], true);
      await Future<void>.delayed(Duration.zero);
      old.complete(priced([1]));
      await first;
      expect(controller.selected, {2});
      expect(mapsOf(controller.quote?['items']).single['id'], 2);
      repo.bagQuoteHandler = (_) async => priced([99]);
      await controller.refreshQuote();
      expect(controller.ready, false);
      expect(controller.quoteError, contains('does not match'));
      controller.dispose();
      repo.session.close();
    },
  );
  test(
    'failed removals preserve rows and selection until server confirmation',
    () async {
      final repo = BagRepository()..failRemoval = true;
      final controller = BagController(repo);
      await controller.load();
      expect(await controller.change(1, null), false);
      expect(controller.items, hasLength(2));
      expect(controller.selected, {1});
      expect(controller.itemErrors[1], 'Removal not confirmed');
      expect(controller.ready, false);
      repo.failRemoval = false;
      expect(await controller.change(1, null), true);
      expect(controller.items.single['id'], 2);
      expect(controller.selected, isEmpty);
      await controller.load();
      expect(controller.selected, isEmpty);
      controller.dispose();
      repo.session.close();
    },
  );
  for (final layout in [
    (375.0, 820.0, 1.0),
    (1200.0, 820.0, 1.0),
    (375.0, 820.0, 2.0),
    (820.0, 375.0, 1.0),
  ]) {
    testWidgets('Bag layout ${layout.$1} x ${layout.$2} text ${layout.$3}', (
      tester,
    ) async {
      tester.view.physicalSize = Size(layout.$1, layout.$2);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = BagRepository();
      addTearDown(repo.session.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(layout.$1, layout.$2),
              textScaler: TextScaler.linear(layout.$3),
            ),
            child: BagPage(repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Checkout (1)'), findsWidgets);
      final scrolls = find.byType(Scrollable);
      for (var i = 0; i < 5; i++) {
        await tester.drag(scrolls.first, const Offset(0, -700));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
