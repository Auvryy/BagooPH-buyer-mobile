import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/home/search_controller.dart';
import 'package:bagoo_buyer_mobile/features/home/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';
import 'support/widget_helpers.dart';

WebPage results({
  List<Map<String, dynamic>> products = const [],
  int page = 1,
  int last = 1,
}) => WebPage('Buyer/Search', {
  'products': {
    'data': products,
    'current_page': page,
    'last_page': last,
    'total': products.length,
  },
  'categories': [
    {'slug': 'tech', 'name': 'Technology'},
  ],
  'locations': [
    {'value': 'test-area', 'label': 'Test province'},
  ],
  'suggestions': ['sneakers'],
  'relatedProducts': [],
});

class SearchRepository extends FakeBuyerRepository {
  Future<WebPage> Function(Map<String, String>, int)? searchHandler;
  @override
  Future<WebPage> search(Map<String, String> filters, {int page = 1}) =>
      searchHandler?.call(Map.of(filters), page) ?? Future.value(results());
}

void main() {
  test(
    'search keeps all server filters across pages and ignores stale responses',
    () async {
      final repo = SearchRepository();
      final old = Completer<WebPage>();
      final requests = <Map<String, String>>[];
      repo.searchHandler = (filters, page) async {
        requests.add(filters);
        if (filters['search'] == 'old') return old.future;
        return results(
          products: page == 1 ? [product(10)] : [product(10), product(11)],
          page: page,
          last: 2,
        );
      };
      final controller = CatalogueSearchController(repo);
      final pending = controller.apply(const SearchFilters(query: 'old'));
      await controller.apply(
        const SearchFilters(
          query: 'new',
          category: 'tech',
          location: 'test-area',
          minimum: '10.50',
          maximum: '500',
          inStock: true,
          rating: '4.5',
          sort: 'top_rated',
        ),
      );
      old.complete(results(products: [product(1)]));
      await pending;
      expect(controller.products.single['id'], 10);
      await controller.load(more: true);
      expect(controller.products.map((p) => p['id']), [10, 11]);
      expect(requests.last, {
        'search': 'new',
        'category': 'tech',
        'location': 'test-area',
        'min_price': '10.50',
        'max_price': '500',
        'in_stock': '1',
        'rating': '4.5',
        'sort': 'top_rated',
      });
      expect(controller.hasMore, false);
      controller.dispose();
      repo.session.close();
    },
  );
  test('failed later pages retain products for explicit retry', () async {
    final repo = SearchRepository();
    bool fail = true;
    repo.searchHandler = (_, page) async {
      if (page == 2 && fail) throw const BackendException('Offline');
      return results(products: [product(page)], page: page, last: 2);
    };
    final controller = CatalogueSearchController(repo);
    await controller.load();
    await controller.load(more: true);
    expect(controller.products.single['id'], 1);
    expect(controller.moreError, 'Offline');
    fail = false;
    await controller.load(more: true);
    expect(controller.products.length, 2);
    controller.dispose();
    repo.session.close();
  });
  for (final layout in [(375.0, 1.0), (1200.0, 1.0), (375.0, 2.0)]) {
    testWidgets(
      'filters and results fit width ${layout.$1} with text ${layout.$2}',
      (tester) async {
        tester.view.physicalSize = Size(layout.$1, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = SearchRepository();
        addTearDown(repo.session.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  size: Size(layout.$1, 900),
                  textScaler: TextScaler.linear(layout.$2),
                ),
                child: SearchPage(repository: repo),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (layout.$1 < 1050) await press(tester, find.text('Filters'));
        expect(find.text('Filter by'), findsOneWidget);
        final min = find.widgetWithText(TextFormField, 'Minimum price');
        await tester.ensureVisible(min);
        await tester.enterText(min, '500');
        final max = find.widgetWithText(TextFormField, 'Maximum price');
        await tester.ensureVisible(max);
        await tester.enterText(max, '100');
        await press(tester, find.text('Apply filters'));
        expect(find.text('Maximum must be at least minimum.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
