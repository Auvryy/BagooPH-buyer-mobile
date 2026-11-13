import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/engagement/buyer_link.dart';
import 'package:bagoo_buyer_mobile/features/home/home_page.dart';
import 'package:bagoo_buyer_mobile/features/home/search_controller.dart';
import 'package:bagoo_buyer_mobile/features/home/top_products_page.dart';
import 'package:bagoo_buyer_mobile/features/home/product_card.dart';
import 'package:bagoo_buyer_mobile/features/home/search_page.dart';
import 'package:bagoo_buyer_mobile/features/products/product_page.dart';
import 'package:bagoo_buyer_mobile/features/products/product_widgets.dart';
import 'package:bagoo_buyer_mobile/features/products/sale_clock.dart';
import 'package:bagoo_buyer_mobile/features/products/shop_page.dart';
import 'package:bagoo_buyer_mobile/features/promotions/campaign_page.dart';
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
    const pageSize = 18;
    const total = 54;
    final products = [
      for (var index = 0; index < pageSize; index++)
        product((page - 1) * pageSize + index + 1),
    ];
    final from = (page - 1) * pageSize + 1;
    requests.add({
      'page': page,
      'search': search,
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
        'data': products,
        'current_page': page,
        'last_page': 3,
        'per_page': pageSize,
        'total': total,
        'from': from,
        'to': from + products.length - 1,
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
      expect(find.text('Filter & sort (1)'), findsOneWidget);
      final filterToggle = find.byKey(const ValueKey('shop-filter-toggle'));
      final scrollable = find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      await tester.dragUntilVisible(
        filterToggle,
        find.byType(CustomScrollView),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      await tester.tap(filterToggle);
      await tester.pumpAndSettle();
      expect(find.text('Department'), findsOneWidget);
      expect(find.text('Store category'), findsOneWidget);
      final sorts = tester
          .widgetList<DropdownButton<String>>(
            find.byType(DropdownButton<String>),
          )
          .last;
      sorts.onChanged!('price_desc');
      await tester.pumpAndSettle();
      expect(find.text('High price'), findsOneWidget);
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

  testWidgets('phone shop shows products before its advanced filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = ShopRepository();
    addTearDown(repo.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ShopPage(repository: repo, slug: 'test'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Department'), findsNothing);
    final toggle = find.byKey(const ValueKey('shop-filter-toggle'));
    expect(tester.getRect(toggle).bottom, lessThan(740));
    expect(tester.getRect(find.byType(ProductCard).first).top, lessThan(740));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Department'), findsOneWidget);
    expect(find.text('Store category'), findsOneWidget);
    expect(find.text('Sort products'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shop search rejects overlong controller input before loading', (
    tester,
  ) async {
    final repo = ShopRepository();
    addTearDown(repo.session.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ShopPage(repository: repo, slug: 'test'),
      ),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.maxLength, 100);
    final before = repo.requests.length;
    field.controller!.text = List.filled(101, 'x').join();
    field.onSubmitted!('ignored');
    await tester.pumpAndSettle();

    expect(repo.requests, hasLength(before));
    expect(
      find.text('Use no more than 100 characters to search this shop.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
                  {
                    'id': 44,
                    'name': 'Eligible bag',
                    'url': '/product/everyday-bag-1',
                  },
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

  testWidgets(
    'home page renders flash deals, top curated collections, and subcategories when provided',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 1200);
      addTearDown(tester.view.reset);
      final repo = FakeBuyerRepository();
      addTearDown(repo.session.close);
      final page = homePage(signedIn: true);
      page.props['subcategories'] = [
        {'id': 21, 'name': 'Smart Audio', 'slug': 'smart-audio'},
      ];
      page.props['flashSaleProducts'] = [
        {...product(1), 'compare_at_price': 1500, 'stock': 5},
      ];
      page.props['topCuratedCollections'] = [
        {
          'name': 'Wireless Audio Picks',
          'slug': 'wireless-audio',
          'ribbon_text': 'TOP 1',
          'sold_display': '2.4k+ Sold',
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: HomePage(
            repository: repo,
            initial: page,
            onLogin: () {},
            onLogout: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Smart Audio'), findsOneWidget);
      expect(find.text('FLASH DEALS'), findsOneWidget);
      expect(find.text('LIMITED TIME'), findsOneWidget);
      expect(find.text('ONLY 5 LEFT'), findsOneWidget);
      expect(find.text('TOP PRODUCTS'), findsOneWidget);
      expect(find.text('Wireless Audio Picks'), findsOneWidget);
      expect(find.text('TOP 1'), findsOneWidget);
      expect(find.text('2.4k+ Sold'), findsOneWidget);
    },
  );

  testWidgets(
    'campaign and top products pages render native storefront experiences and parse links',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 1200);
      addTearDown(tester.view.reset);
      final repo = FakeBuyerRepository();
      addTearDown(repo.session.close);

      final origin = repo.session.origin;
      expect(
        BuyerLink.parse(
          origin.resolve('/campaign/christmas-gala'),
          origin,
        ).kind,
        BuyerLinkKind.destination,
      );
      expect(
        BuyerLink.parse(origin.resolve('/top-products'), origin).kind,
        BuyerLinkKind.destination,
      );

      final campaignWebPage = WebPage('Buyer/Campaign', {
        'auth': {'user': buyer},
        'campaign': {
          'slug': 'christmas-gala',
          'title': 'Christmas Gala Deals',
          'badge': 'HOLIDAY SPECIAL',
          'vouchers': [
            {
              'code': 'XMAS100',
              'title': 'Holiday Voucher',
              'discount': '₱100 OFF',
              'min_spend': 'Min. spend ₱500',
              'badge': 'EVENT VOUCHER',
              'is_saved': false,
            },
          ],
        },
        'products': [
          {
            ...product(1),
            'price': '399.00',
            'discount_pct': 25,
            'event_badge': 'MEGA DEAL',
          },
        ],
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: CampaignPage(repository: repo, initial: campaignWebPage),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Christmas Gala Deals'), findsWidgets);
      expect(find.text('HOLIDAY SPECIAL'), findsOneWidget);
      expect(find.text('XMAS100'), findsOneWidget);
      expect(find.text('MEGA DEAL'), findsOneWidget);

      await tester.tap(find.text('Claim voucher'));
      await tester.pumpAndSettle();
      expect(find.text('Claimed'), findsOneWidget);

      final topProductsWebPage = WebPage('Buyer/TopProducts', {
        'auth': {'user': buyer},
        'activeCollection': {
          'title': 'Best Selling Audio',
          'category_name': 'Electronics',
          'sub_slug': 'best-audio',
        },
        'collections': [
          {
            'id': 1,
            'title': 'Best Selling Audio',
            'sub_slug': 'best-audio',
            'target_url': '/top-products?sub=best-audio',
          },
        ],
        'products': [product(1), product(2)],
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: TopProductsPage(repository: repo, initial: topProductsWebPage),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('TOP PRODUCTS'), findsOneWidget);
      expect(find.text('ALGORITHMIC PICKS'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
    },
  );
}
