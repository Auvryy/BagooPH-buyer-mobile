import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/bag_controller.dart';
import 'package:bagoo_buyer_mobile/features/checkout/bag_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bag_fixtures.dart' show line, priced;
import 'support/fake_buyer_repository.dart';

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
  for (final field in [
    'product stock',
    'variant stock',
    'other Bag quantity',
  ]) {
    test('Bag quantity calculation rejects fractional $field', () {
      final current = line(1);
      final another = line(2, color: 'Blue');
      if (field == 'product stock') {
        current['product'] = {...mapOf(current['product']), 'stock': 5.5};
      } else if (field == 'variant stock') {
        final product = Map<String, dynamic>.from(current['product'] as Map);
        final variants = Map<String, dynamic>.from(product['variants'] as Map);
        final combinations = List<Map<String, dynamic>>.from(
          variants['combinations'] as List,
        );
        combinations[0] = {...combinations[0], 'stock': 1.5};
        variants['combinations'] = combinations;
        current['product'] = {...product, 'variants': variants};
      } else {
        another['quantity'] = 1.5;
      }

      expect(bagMaximumQuantity(current, [current, another]), 0);
    });
  }
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
  test('a partial quote never leaves the Bag ready for checkout', () async {
    final repo = BagRepository();
    repo.bagQuoteHandler = (ids) async {
      final response = priced(ids);
      final quote = mapOf(response['quote']);
      response['quote'] = {
        ...quote,
        'items': [...mapsOf(quote['items']), 'malformed quote row'],
      };
      return response;
    };
    final controller = BagController(repo);
    addTearDown(() {
      controller.dispose();
      repo.session.close();
    });

    await controller.load();

    expect(controller.quote, isNull);
    expect(
      controller.quoteError,
      contains('item prices could not be confirmed'),
    );
    expect(controller.ready, isFalse);
  });
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
