import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/home/search_controller.dart';
import 'package:bagoo_buyer_mobile/features/home/search_page.dart';
import 'package:bagoo_buyer_mobile/features/products/product_page.dart';
import 'package:bagoo_buyer_mobile/features/products/product_widgets.dart';
import 'package:bagoo_buyer_mobile/features/products/sale_clock.dart';
import 'package:bagoo_buyer_mobile/features/products/shop_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'search_test.dart' show SearchRepository, results;
import 'support/fake_buyer_repository.dart';

class ShopRepository extends FakeBuyerRepository {
  final requests = <Map<String, dynamic>>[];
  @override
  Future<WebPage> shop(
    String slug, {
    int page = 1,
    String search = '',
    String category = '',
    String storeCategory = 'all',
    String sort = 'relevance',
  }) async {
    requests.add({
      'page': page,
      'category': category,
      'store_category': storeCategory,
      'sort': sort,
    });
    return WebPage('Marketplace/ShopDetail', {
      'shop': {
        'id': 2,
        'name': 'Test shop',
        'city': 'Test city',
        'address': '123 Test Street',
      },
      'products': {
        'data': [product(1)],
        'current_page': page,
        'last_page': 3,
        'total': 3,
        'from': page,
        'to': page,
      },
      'categories': [
        {'slug': 'tech', 'name': 'Technology'},
      ],
      'storeCategories': [
        {'id': 10, 'name': 'Bags', 'parent_id': null},
        {'id': 11, 'name': 'Travel', 'parent_id': 10},
      ],
      'followerCount': 8,
      'shopStats': {'response_rate': '80%', 'joined': '2026-01-01T00:00:00Z'},
    });
  }
}

void main() {
  test(
    'direct page selection retains filters and rejects older page replies',
    () async {
      final repo = SearchRepository();
      addTearDown(repo.session.close);
      final pending = Completer<WebPage>();
      final requested = <int>[];
      repo.searchHandler = (filters, page) async {
        requested.add(page);
        expect(filters['category'], 'tech');
        return page == 2
            ? pending.future
            : results(products: [product(page)], page: page, last: 4);
      };
      final controller = CatalogueSearchController(repo);
      addTearDown(controller.dispose);
      await controller.apply(const SearchFilters(category: 'tech'));
      final old = controller.load(pageNumber: 2);
      await controller.load(pageNumber: 4);
      pending.complete(results(products: [product(2)], page: 2, last: 4));
      await old;
      expect(requested, [1, 2, 4]);
      expect(controller.currentPage, 4);
      expect(controller.products.single['id'], 4);
    },
  );

  testWidgets('matching and related products remain separate native grids', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = SearchRepository();
    addTearDown(repo.session.close);
    repo.searchHandler = (_, _) async => WebPage('Buyer/Search', {
      ...results(products: [product(1)]).props,
      'relatedProducts': [product(2)],
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(body: SearchPage(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Everyday bag 1'), findsOneWidget);
    expect(find.text('Everyday bag 2'), findsOneWidget);
    expect(find.text('You may also like'), findsOneWidget);
  });

  testWidgets(
    'shop category and sort context survives page navigation at large text',
    (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = ShopRepository();
      addTearDown(repo.session.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(375, 900),
              textScaler: TextScaler.linear(2),
            ),
            child: ShopPage(
              repository: repo,
              slug: 'test',
              storeCategory: '11',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final sorts = tester
          .widgetList<DropdownButton<String>>(
            find.byType(DropdownButton<String>),
          )
          .last;
      sorts.onChanged!('price_desc');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('Next page'),
        400,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      next.onPressed!();
      await tester.pumpAndSettle();
      expect(repo.requests.last, containsPair('page', 2));
      expect(repo.requests.last, containsPair('store_category', '11'));
      expect(repo.requests.last, containsPair('sort', 'price_desc'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'voucher product URLs open native product detail with the capped benefit',
    (tester) async {
      final repo = FakeBuyerRepository();
      addTearDown(repo.session.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: Scaffold(
            body: OfferTile(
              repository: repo,
              offer: const {
                'issuer': 'shop',
                'shop_name': 'Test store',
                'discount_type': 'fixed',
                'discount_value': 100,
                'max_discount': 50,
                'product_scope': 'selected',
                'eligible_products': [
                  {'name': 'Eligible bag', 'url': '/product/everyday-bag-1'},
                ],
              },
            ),
          ),
        ),
      );
      expect(find.text('₱50.00 off'), findsWidgets);
      expect(find.text('₱100.00 off'), findsNothing);
      await tester.tap(find.text('Eligible bag'));
      await tester.pumpAndSettle();
      expect(find.byType(ProductPage), findsOneWidget);
      expect(repo.productCalls, 1);
    },
  );

  testWidgets(
    'sale boundary refreshes once while the same expired offer remains',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SaleClock(
            offer: const {
              'server_now': '2026-10-28T10:00:00Z',
              'active': {'ends_at': '2026-10-28T09:59:59Z'},
            },
            onBoundary: () => calls++,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 3));
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
