import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/core/catalogue_pages.dart';
import 'package:bagoo_buyer_mobile/features/home/search_controller.dart';
import 'package:bagoo_buyer_mobile/features/home/search_page.dart';
import 'package:bagoo_buyer_mobile/features/home/product_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';
import 'support/widget_helpers.dart';

WebPage results({
  List<Map<String, dynamic>> products = const [],
  int page = 1,
  int? last,
  int? total,
}) {
  const pageSize = 24;
  final rows = List<Map<String, dynamic>>.of(products);
  final totalCount =
      total ?? (last == null ? rows.length : (last - 1) * pageSize + 1);
  final lastCount =
      last ?? (totalCount == 0 ? 1 : (totalCount + pageSize - 1) ~/ pageSize);
  final current = page < 1
      ? 1
      : page > lastCount
      ? lastCount
      : page;
  final remaining = totalCount - (current - 1) * pageSize;
  final expectedRows = remaining <= 0
      ? 0
      : remaining < pageSize
      ? remaining
      : pageSize;
  while (rows.length < expectedRows) {
    rows.add(product(200000 + current * pageSize + rows.length));
  }
  final from = rows.isEmpty ? null : (current - 1) * pageSize + 1;
  final to = rows.isEmpty ? null : from! + rows.length - 1;
  return WebPage('Buyer/Search', {
    'products': {
      'data': rows,
      'current_page': current,
      'last_page': lastCount,
      'per_page': pageSize,
      'total': totalCount,
      'from': from,
      'to': to,
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
}

class SearchRepository extends FakeBuyerRepository {
  Future<WebPage> Function(Map<String, String>, int)? searchHandler;
  @override
  Future<WebPage> search(Map<String, String> filters, {int page = 1}) =>
      searchHandler?.call(Map.of(filters), page) ?? Future.value(results());
}

void main() {
  test(
    'linked search rejects an overlong query before requesting the server',
    () async {
      final repository = SearchRepository();
      final controller = CatalogueSearchController(repository);

      await controller.apply(
        SearchFilters(query: List.filled(101, 'x').join()),
      );

      expect(repository.searchRequests, isEmpty);
      expect(
        controller.error,
        'Use no more than 100 characters for your search.',
      );
      controller.dispose();
      repository.session.close();
    },
  );

  test(
    'search rejects fractional product IDs before exposing save targets',
    () async {
      final repository = SearchRepository();
      repository.searchHandler = (_, _) async => results(
        products: [
          {...product(1), 'id': 1.5},
        ],
      );
      final controller = CatalogueSearchController(repository);
      await controller.apply(const SearchFilters());
      expect(controller.products, isEmpty);
      expect(
        controller.error,
        contains('Search results could not be confirmed'),
      );
      controller.dispose();
      repository.session.close();
    },
  );

  test(
    'search rejects product rows without a confirmed detail route',
    () async {
      final repository = SearchRepository();
      final malformedProduct = product(1)..remove('slug');
      repository.searchHandler = (_, _) async =>
          results(products: [malformedProduct]);
      final controller = CatalogueSearchController(repository);

      await controller.load();

      expect(controller.products, isEmpty);
      expect(
        controller.error,
        contains('Search results could not be confirmed'),
      );
      controller.dispose();
      repository.session.close();
    },
  );

  test('search ignores malformed suggestion metadata', () async {
    final repository = SearchRepository();
    addTearDown(repository.session.close);
    final page = results();
    page.props['suggestions'] = 'not-a-list';
    repository.searchHandler = (_, _) async => page;
    final controller = CatalogueSearchController(repository);

    await controller.load();

    expect(controller.suggestions, isEmpty);
    controller.dispose();
  });

  test('search hides partial suggestion metadata', () async {
    final repository = SearchRepository();
    addTearDown(repository.session.close);
    final page = results();
    page.props['suggestions'] = ['sneakers', 17];
    repository.searchHandler = (_, _) async => page;
    final controller = CatalogueSearchController(repository);

    await controller.load();

    expect(controller.suggestions, isEmpty);
    controller.dispose();
  });

  test('search hides incomplete category and location filter lists', () async {
    final repository = SearchRepository();
    addTearDown(repository.session.close);
    final page = results();
    page.props['categories'] = [
      {'slug': 'tech', 'name': 'Technology'},
      'malformed category',
    ];
    page.props['locations'] = [
      {'value': 'test-area', 'label': 'Test province'},
      {'value': 'other-area'},
    ];
    repository.searchHandler = (_, _) async => page;
    final controller = CatalogueSearchController(repository);

    await controller.load();

    expect(controller.categories, isEmpty);
    expect(controller.locations, isEmpty);
    expect(controller.products, isEmpty);
    expect(controller.error, isNull);
    controller.dispose();
  });

  test('search hides a partial related-product list', () async {
    final repository = SearchRepository();
    addTearDown(repository.session.close);
    final page = results();
    page.props['relatedProducts'] = [product(3), 'malformed related row'];
    repository.searchHandler = (_, _) async => page;
    final controller = CatalogueSearchController(repository);

    await controller.load();

    expect(controller.related, isEmpty);
    controller.dispose();
  });

  test('standalone filters reject partial choice metadata', () {
    expect(
      completeSearchFilterChoices(
        [
          {'slug': 'tech', 'name': 'Technology'},
          'broken row',
        ],
        valueKey: 'slug',
        labelKey: 'name',
      ),
      isEmpty,
    );
    expect(
      completeSearchFilterChoices(
        [
          {'value': 'one', 'label': 'One'},
          {'value': 'one', 'label': 'Duplicate'},
        ],
        valueKey: 'value',
        labelKey: 'label',
      ),
      isEmpty,
    );
  });

  testWidgets('malformed saved-product IDs do not crash Search results', (
    tester,
  ) async {
    final repository = SearchRepository();
    addTearDown(repository.session.close);
    final page = results(products: [product(1)]);
    page.props['savedProductIds'] = 'not-a-list';
    repository.searchHandler = (_, _) async => page;

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(body: SearchPage(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ProductCard), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final (field, value) in [
    ('current_page', 1.5),
    ('current_page', 2),
    ('last_page', -1),
    ('last_page', 99),
    ('total', '1'),
    ('total', 9223372036854775807),
    ('per_page', 18),
    ('from', 2),
    ('to', 0),
  ]) {
    test('search rejects malformed paginator $field=$value', () async {
      final repository = SearchRepository();
      repository.searchHandler = (_, _) async {
        final page = results(products: [product(1)]);
        final props = Map<String, dynamic>.from(page.props);
        final feed = Map<String, dynamic>.from(props['products'] as Map)
          ..[field] = value;
        props['products'] = feed;
        return WebPage('Buyer/Search', props);
      };
      final controller = CatalogueSearchController(repository);

      await controller.apply(const SearchFilters());

      expect(controller.products, isEmpty);
      expect(controller.data, isNull);
      expect(controller.error, contains('pagination'));
      controller.dispose();
      repository.session.close();
    });
  }

  test('search rejects invalid page requests before networking', () async {
    final repository = SearchRepository();
    var calls = 0;
    repository.searchHandler = (_, _) async {
      calls++;
      return results();
    };
    final controller = CatalogueSearchController(repository);

    await controller.load(pageNumber: 0);
    expect(calls, 0);
    expect(controller.error, 'Choose a valid product page.');
    await controller.load(pageNumber: 1000001);
    expect(calls, 0);

    controller.dispose();
    repository.session.close();
  });

  test(
    'search accepts the backend correction to a reduced last page',
    () async {
      final repository = SearchRepository();
      repository.searchHandler = (_, page) async =>
          results(products: [product(25)], page: page, last: 2, total: 25);
      final controller = CatalogueSearchController(repository);

      await controller.load(pageNumber: 100);

      expect(controller.currentPage, 2);
      expect(controller.lastPage, 2);
      expect(controller.products.single['id'], 25);
      controller.dispose();
      repository.session.close();
    },
  );

  test('search rejects more rows than the backend page size', () async {
    final repository = SearchRepository();
    repository.searchHandler = (_, _) async => results(
      products: [for (var id = 1; id <= 25; id++) product(id)],
      total: 25,
    );
    final controller = CatalogueSearchController(repository);

    await controller.load();

    expect(controller.products, isEmpty);
    expect(controller.error, contains('results'));
    controller.dispose();
    repository.session.close();
  });

  testWidgets(
    'pagination hides inactive controls for one page and accepts a valid page on longer lists',
    (tester) async {
      int? selected;
      Widget screen(int last) => MaterialApp(
        home: Scaffold(
          body: CataloguePages(
            current: 1,
            last: last,
            total: 4,
            onPage: (page) => selected = page,
          ),
        ),
      );
      await tester.pumpWidget(screen(1));
      expect(find.byTooltip('Next page'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      await tester.pumpWidget(screen(3));
      expect(find.byTooltip('Next page'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '3');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      expect(selected, 3);
    },
  );
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
          total: 26,
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
      expect(controller.products, hasLength(24));
      expect(controller.products.first['id'], 10);
      await controller.load(more: true);
      expect(controller.products, hasLength(25));
      expect(controller.products.map((p) => p['id']), containsAll([10, 11]));
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
    expect(controller.products, hasLength(24));
    expect(controller.products.first['id'], 1);
    expect(controller.moreError, 'Offline');
    fail = false;
    await controller.load(more: true);
    expect(controller.products.length, 25);
    controller.dispose();
    repo.session.close();
  });
  testWidgets(
    'phone search keeps filters beside the field unless text is enlarged',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = SearchRepository();
      addTearDown(repo.session.close);

      Widget screen(double scale) => MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 900),
              textScaler: TextScaler.linear(scale),
            ),
            child: SearchPage(repository: repo),
          ),
        ),
      );

      await tester.pumpWidget(screen(1));
      await tester.pumpAndSettle();
      final field = find.byType(TextField).first;
      final filters = find.byTooltip('Filters');
      final fieldBounds = tester.getRect(field);
      final filterBounds = tester.getRect(filters);
      expect(
        (fieldBounds.center.dy - filterBounds.center.dy).abs(),
        lessThan(1),
      );
      expect(filterBounds.left, greaterThan(fieldBounds.right));

      await tester.pumpWidget(screen(2));
      await tester.pumpAndSettle();
      expect(find.text('Search'), findsOneWidget);
      final enlargedFieldBounds = tester.getRect(field);
      final enlargedFilterBounds = tester.getRect(filters);
      expect(
        enlargedFilterBounds.top,
        greaterThanOrEqualTo(enlargedFieldBounds.bottom + 7),
      );
      expect(tester.takeException(), isNull);
    },
  );
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
        if (layout.$1 < 1050) await press(tester, find.byTooltip('Filters'));
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
