import 'dart:io';
import 'dart:ui' as ui;

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/core/verification_prompt.dart';
import 'package:bagoo_buyer_mobile/features/auth/login_page.dart';
import 'package:bagoo_buyer_mobile/features/checkout/bag_page.dart';
import 'package:bagoo_buyer_mobile/features/checkout/checkout_page.dart';
import 'package:bagoo_buyer_mobile/features/collections/followed_shops_page.dart';
import 'package:bagoo_buyer_mobile/features/collections/saved_products_page.dart';
import 'package:bagoo_buyer_mobile/features/home/home_page.dart';
import 'package:bagoo_buyer_mobile/features/home/product_card.dart';
import 'package:bagoo_buyer_mobile/features/home/search_page.dart';
import 'package:bagoo_buyer_mobile/features/products/chat_page.dart';
import 'package:bagoo_buyer_mobile/features/products/product_page.dart';
import 'package:bagoo_buyer_mobile/features/products/shop_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/inbox_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:bagoo_buyer_mobile/features/promotions/promotion_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';

class ReviewRepository extends FakeBuyerRepository {
  ReviewRepository() {
    productResponse = productPage(
      signedIn: true,
      override: {
        'name': 'Everyday Carry Canvas Tote',
        'rating': 4.8,
        'sales_count': 128,
      },
    );
    homeHandler = (_, _) async {
      final page = homePage(
        products: [
          for (var id = 1; id <= 6; id++)
            {
              ...product(id),
              'name': id.isEven
                  ? 'Wireless Earbuds with Charging Case'
                  : 'Everyday Carry Canvas Tote',
              'price': id.isEven ? '899.00' : '1200.00',
              'rating': 4.8,
              'sales_count': 128,
              'shop': {'name': 'Everyday Goods', 'city': 'San Pablo City'},
            },
        ],
      );
      return WebPage(page.component, {
        ...page.props,
        'feedProducts': {...mapOf(page.props['feedProducts']), 'total': 6},
      });
    };
  }

  @override
  Future<WebPage> document(String path) async {
    if (path.startsWith('/buyer/saved-products')) {
      return WebPage('Buyer/SavedProducts', {
        'auth': {'user': buyer},
        'entries': {
          'data': [
            {
              'product_id': 1,
              'product': {
                ...product(1),
                'name': 'Everyday Carry Canvas Tote',
                'shop': {'name': 'Everyday Goods', 'city': 'San Pablo City'},
              },
            },
          ],
          'current_page': 1,
          'last_page': 2,
          'total': 1,
        },
      });
    }
    if (path.startsWith('/buyer/followed-shops')) {
      return WebPage('Buyer/FollowedShops', {
        'auth': {'user': buyer},
        'entries': {
          'data': [
            {
              'shop_id': 2,
              'shop': {
                'id': 2,
                'slug': 'everyday-goods',
                'name': 'Everyday Goods',
                'description': 'Useful local goods, packed with care.',
                'city': 'San Pablo City',
              },
            },
          ],
          'current_page': 1,
          'last_page': 2,
          'total': 1,
        },
      });
    }
    if (path == '/buyer/messages') {
      return const WebPage('Buyer/Messages', {
        'auth': {'user': buyer},
        'conversations': [
          {
            'user': {'id': 3, 'name': 'Everyday Goods', 'role': 'seller'},
            'last_message': 'Your order is being prepared. Thank you!',
            'last_time': 'Today',
            'unread_count': 2,
            'messages': [],
          },
        ],
      });
    }
    return super.document(path);
  }

  @override
  Future<WebPage> shop(
    String slug, {
    int page = 1,
    String search = '',
    String category = '',
    String storeCategory = 'all',
    String sort = 'relevance',
  }) async => WebPage('Marketplace/ShopDetail', {
    'auth': {'user': buyer},
    'shop': {
      'id': 2,
      'name': 'Everyday Goods',
      'description': 'Useful local goods, packed with care.',
      'city': 'San Pablo City',
      'products_count': 6,
    },
    'products': {
      'data': [
        {
          ...product(1),
          'name': 'Everyday Carry Canvas Tote',
          'shop': {'name': 'Everyday Goods', 'city': 'San Pablo City'},
        },
        for (var id = 2; id <= 6; id++) product(id),
      ],
      'current_page': 1,
      'last_page': 1,
      'per_page': 18,
      'total': 6,
      'from': 1,
      'to': 6,
    },
    'categories': [
      {'slug': 'bags', 'name': 'Bags'},
    ],
    'storeCategories': [
      {'id': 10, 'name': 'Bags', 'parent_id': null},
      {
        'id': 11,
        'name': 'Travel bags, hiking packs, and everyday carry gear',
        'parent_id': 10,
      },
    ],
    'savedProductIds': <int>[],
    'isFollowing': false,
    'followerCount': 86,
    'shopStats': {
      'rating': 4.8,
      'review_count': 32,
      'response_rate': '96%',
      'joined': '2022-05-01T00:00:00Z',
    },
  });

  @override
  Future<WebPage> bag() async => WebPage('Cart/Index', {
    'auth': {'user': buyer},
    'items': [
      {
        'id': 1,
        'product_id': 1,
        'quantity': 1,
        'unit_price': '1200.00',
        'available_for_purchase': true,
        'product': {
          ...product(1),
          'name': 'Everyday Carry Canvas Tote',
          'shop_id': 2,
          'shop': {'id': 2, 'name': 'Everyday Goods'},
        },
      },
    ],
  });

  @override
  Future<Map<String, dynamic>> bagQuote(List<int> ids) async => {
    'quote': {
      'subtotal': 1200,
      'shipping_fee': 50,
      'discount': 0,
      'shipping_discount': 0,
      'total': 1250,
      'items': [
        for (final id in ids)
          {'id': id, 'quantity': 1, 'unit_price': 1200, 'subtotal': 1200},
      ],
      'shops': [
        {
          'shop_id': 2,
          'shop_name': 'Everyday Goods',
          'shipping': 50,
          'total': 1250,
        },
      ],
    },
    'availableVouchers': [],
  };

  @override
  Future<List<Map<String, dynamic>>> messages(int receiver) async => [
    {
      'id': 1,
      'sender_id': receiver,
      'receiver_id': 7,
      'message': 'Hello! How can we help you with this product?',
      'created_at': '2026-10-28T02:00:00Z',
    },
    {
      'id': 2,
      'sender_id': 7,
      'receiver_id': receiver,
      'message': 'Is the canvas tote available in natural?',
      'created_at': '2026-10-28T02:01:00Z',
    },
  ];
}

Widget verificationReview() => Scaffold(
  body: Center(
    child: Builder(
      builder: (context) => FilledButton(
        onPressed: () => showBuyerVerificationPrompt(context, {
          ...buyer,
          'kyc_status': 'unverified',
        }),
        child: const Text('Show verification'),
      ),
    ),
  ),
);

Widget reviewScreen(String name, ReviewRepository repo) => switch (name) {
  'home' => HomePage(repository: repo, onLogin: () {}, onLogout: () async {}),
  'signed-home' => HomePage(
    repository: repo,
    initial: homePage(signedIn: true),
    onLogin: () {},
    onLogout: () async {},
  ),
  'signed-search' => HomePage(
    repository: repo,
    initial: homePage(signedIn: true),
    onLogin: () {},
    onLogout: () async {},
  ),
  'shell-search' => HomePage(
    repository: repo,
    onLogin: () {},
    onLogout: () async {},
  ),
  'search' => Scaffold(
    appBar: AppBar(title: const Text('Search Bagoo')),
    body: SearchPage(repository: repo),
  ),
  'product' => ProductPage(repository: repo, slug: 'everyday-bag-1'),
  'shop' => ShopPage(repository: repo, slug: 'everyday-goods'),
  'promotion' => PromotionPage(
    repository: repo,
    initial: WebPage('Buyer/Promotion', {
      'auth': {'user': buyer},
      'promotion': {
        'available': true,
        'title': 'Weekend Local Finds',
        'starts_at': '2026-10-28T00:00:00Z',
        'ends_at': '2026-11-02T15:59:00Z',
        'summary': 'Discover practical picks from neighborhood shops.',
        'offer': {
          'name': 'Local Finds voucher',
          'shop_name': 'Everyday Goods',
          'discount_type': 'percent',
          'percentage_bps': 1500,
          'code': 'LOCAL15',
          'description': 'Valid on selected products while supplies last.',
          'starts_at': '2026-10-28T00:00:00Z',
          'ends_at': '2026-11-02T15:59:00Z',
          'minimum_cents': 100000,
          'maximum_cents': 20000,
          'per_buyer_limit': 1,
        },
        'target': {'url': '/buyer/search', 'label': 'featured items'},
      },
      'products': [
        {
          ...product(1),
          'name': 'Everyday Carry Canvas Tote',
          'shop': {'name': 'Everyday Goods', 'city': 'San Pablo City'},
        },
      ],
    }),
    onOpenDestination: (_) async {},
    onProfileSection: (_) {},
  ),
  'saved-products' => SavedProductsPage(
    repository: repo,
    ownerId: 7,
    onSearch: (_) {},
  ),
  'followed-shops' => FollowedShopsPage(
    repository: repo,
    ownerId: 7,
    onSearch: (_) {},
  ),
  'verification' => verificationReview(),
  'bag' => BagPage(repository: repo),
  'checkout' => CheckoutPage(repository: repo, initial: checkoutPage()),
  'profile' => Scaffold(
    appBar: AppBar(title: const Text('Your account')),
    body: ProfilePage(
      repository: repo,
      user: buyer,
      onLogin: () {},
      onLogout: () async {},
      onUserChanged: (_) {},
    ),
  ),
  'purchases' => Scaffold(
    appBar: AppBar(title: const Text('Your account')),
    body: ProfilePage(
      repository: repo,
      user: buyer,
      initialSection: 'orders',
      onLogin: () {},
      onLogout: () async {},
      onUserChanged: (_) {},
    ),
  ),
  'inbox' => InboxPage(repository: ProfileRepository(repo)),
  'chat' => ChatPage(
    repository: repo,
    userId: 7,
    receiverId: 3,
    conversationTitle: 'Everyday Goods',
  ),
  _ => LoginPage(
    repository: repo,
    onAuthenticated: (_) {},
    onRegister: () {},
    onForgot: () {},
    onBrowse: () {},
  ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Plus Jakarta Sans')
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  const export = bool.fromEnvironment('BAGOO_RENDER_REVIEW');
  const phase = String.fromEnvironment(
    'BAGOO_REVIEW_PHASE',
    defaultValue: 'current',
  );
  testWidgets('shared toggles use Bagoo colors and accessible targets', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              Checkbox(value: false, onChanged: (_) {}),
              Checkbox(value: true, onChanged: (_) {}),
              Switch(value: false, onChanged: (_) {}),
              Switch(value: true, onChanged: (_) {}),
              const Switch(value: true, onChanged: null),
            ],
          ),
        ),
      ),
    );
    final theme = Theme.of(tester.element(find.byType(Checkbox).first))
        .checkboxTheme;
    expect(theme.fillColor?.resolve({}), Colors.white);
    expect(
      theme.fillColor?.resolve({WidgetState.selected}),
      BagooTheme.crimson,
    );
    expect(theme.fillColor?.resolve({WidgetState.disabled}), BagooTheme.canvas);
    expect(theme.checkColor?.resolve({}), Colors.white);
    expect(theme.shape, isA<RoundedRectangleBorder>());
    expect(
      tester.getSize(find.byType(Checkbox).first).width,
      greaterThanOrEqualTo(48),
    );
    final switchTheme = Theme.of(tester.element(find.byType(Switch).first))
        .switchTheme;
    expect(switchTheme.thumbColor?.resolve({}), BagooTheme.muted);
    expect(
      switchTheme.thumbColor?.resolve({WidgetState.selected}),
      Colors.white,
    );
    expect(
      switchTheme.thumbColor?.resolve({WidgetState.disabled}),
      BagooTheme.muted,
    );
    expect(switchTheme.trackColor?.resolve({}), Colors.white);
    expect(
      switchTheme.trackColor?.resolve({WidgetState.selected}),
      BagooTheme.crimson,
    );
    expect(
      switchTheme.trackColor?.resolve({WidgetState.disabled}),
      BagooTheme.canvas,
    );
    expect(switchTheme.trackOutlineColor?.resolve({}), BagooTheme.muted);
    expect(
      switchTheme.trackOutlineColor?.resolve({WidgetState.selected}),
      BagooTheme.crimson,
    );
    expect(
      switchTheme.trackOutlineColor?.resolve({WidgetState.disabled}),
      BagooTheme.border,
    );
    expect(switchTheme.materialTapTargetSize, MaterialTapTargetSize.padded);
    expect(tester.takeException(), isNull);
  });
  testWidgets('search filter switch is branded in its phone layout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 740);
    addTearDown(tester.view.reset);
    final repo = ReviewRepository();
    addTearDown(repo.session.close);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: BagooTheme.light.copyWith(platform: TargetPlatform.android),
          builder: (_, child) => MediaQuery(
            data: const MediaQueryData(size: Size(320, 740)),
            child: child!,
          ),
          home: Scaffold(body: SearchPage(repository: repo)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    final toggle = find.text('In stock only');
    await tester.scrollUntilVisible(
      toggle,
      160,
      scrollable: find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (export) {
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final rendered = await render.toImage();
        final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('.git/buyer-design/$phase');
        await directory.create(recursive: true);
        await File('${directory.path}/search-filter-switch_320_1.0.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        rendered.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final name in [
    'home',
    'signed-home',
    'signed-search',
    'shell-search',
    'search',
    'product',
    'shop',
    'promotion',
    'saved-products',
    'followed-shops',
    'verification',
    'bag',
    'checkout',
    'profile',
    'purchases',
    'chat',
    'inbox',
    'login',
  ]) {
    for (final scene in [
      (const Size(320, 740), 1.0, 0.0),
      if (name == 'search') (const Size(320, 740), 2.0, 0.0),
      if ([
        'shop',
        'promotion',
        'saved-products',
        'followed-shops',
      ].contains(name))
        (const Size(320, 740), 2.0, 0.0),
      (const Size(375, 812), 1.0, 0.0),
      (const Size(700, 375), 2.0, 0.0),
      (const Size(1024, 768), 1.0, 0.0),
    ]) {
      testWidgets(
        '$name is usable at ${scene.$1} text ${scene.$2} keyboard ${scene.$3}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = scene.$1;
          addTearDown(tester.view.reset);
          final repo = ReviewRepository();
          addTearDown(repo.session.close);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                theme: BagooTheme.light,
                debugShowCheckedModeBanner: false,
                builder: (_, child) => MediaQuery(
                  data: MediaQueryData(
                    size: scene.$1,
                    textScaler: TextScaler.linear(scene.$2),
                    viewInsets: EdgeInsets.only(bottom: scene.$3),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: reviewScreen(name, repo),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (name == 'saved-products') {
            expect(
              tester
                  .widget<TextButton>(
                    find.widgetWithText(TextButton, 'Continue shopping'),
                  )
                  .onPressed,
              isNotNull,
            );
          }
          if (name == 'followed-shops') {
            expect(
              tester
                  .widget<TextButton>(
                    find.widgetWithText(TextButton, 'Browse shops'),
                  )
                  .onPressed,
              isNotNull,
            );
          }
          if (name == 'shell-search' || name == 'signed-search') {
            final search = find.byKey(const ValueKey('buyer-header-search'));
            await tester.tap(search);
            await tester.pumpAndSettle();
            if (name == 'signed-search') {
              await tester.enterText(search, 'wireless headphones');
              await tester.pumpAndSettle();
            }
          }
          if (name == 'verification') {
            await tester.tap(
              find.widgetWithText(FilledButton, 'Show verification'),
            );
            await tester.pumpAndSettle();
            expect(find.text('Verification needed'), findsOneWidget);
          }
          if (name == 'login' && scene.$1.width == 320 && scene.$2 == 1) {
            final label = find.text('Remember this device');
            expect(label, findsOneWidget);
            expect(tester.getSize(label).height, lessThan(30));
            expect(
              tester.getSize(find.byType(CheckboxListTile)).height,
              greaterThanOrEqualTo(48),
            );
          }
          if (name == 'search' && scene.$1.width == 320) {
            final field = tester.getRect(find.byType(TextField).first);
            final filters = tester.getRect(find.byTooltip('Filters'));
            if (scene.$2 == 1) {
              expect((field.center.dy - filters.center.dy).abs(), lessThan(1));
              expect(filters.left, greaterThan(field.right));
            } else {
              expect(filters.top, greaterThanOrEqualTo(field.bottom + 7));
            }
          }
          if (name == 'shop' && scene.$1.width == 320 && scene.$2 == 1.0) {
            expect(find.text('Department'), findsNothing);
            final toggle = find.byKey(const ValueKey('shop-filter-toggle'));
            expect(tester.getRect(toggle).bottom, lessThan(scene.$1.height));
            expect(
              tester.getRect(find.byType(ProductCard).first).top,
              lessThan(scene.$1.height),
            );
            expect(
              tester.getRect(find.text('Everyday Carry Canvas Tote')).bottom,
              lessThan(scene.$1.height),
            );
            expect(
              tester.getRect(find.text('₱1,200.00').first).bottom,
              lessThan(scene.$1.height),
            );
          }
          expect(tester.takeException(), isNull);
          expect(find.byType(Scaffold), findsWidgets);
          if (name == 'home' &&
              [375.0, 1024.0].contains(scene.$1.width) &&
              scene.$2 == 1) {
            final card = find.byType(ProductCard).first;
            expect(card, findsOneWidget);
            final price = find
                .descendant(of: card, matching: find.text('₱1,200.00'))
                .first;
            expect(
              tester.getRect(price).bottom,
              lessThan(
                tester
                    .getRect(
                      find.byKey(const ValueKey('buyer-bottom-navigation')),
                    )
                    .top,
              ),
            );
          }
          if (name == 'home' && scene.$1.width == 1024 && scene.$2 == 1) {
            final card = find.byType(ProductCard).at(1);
            expect(tester.getSize(card).width, greaterThan(200));
            final title = find.descendant(
              of: card,
              matching: find.text('Wireless Earbuds with Charging Case'),
            );
            expect(
              tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
              isFalse,
            );
          }
          if (export) {
            Future<void> saveRender(String filename) =>
                tester.runAsync(() async {
                  final render =
                      boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary;
                  final rendered = await render.toImage();
                  final bytes = await rendered.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  final directory = Directory('.git/buyer-design/$phase');
                  await directory.create(recursive: true);
                  await File('${directory.path}/$filename.png')
                      .writeAsBytes(bytes!.buffer.asUint8List());
                  rendered.dispose();
                });
            if (name == 'home' || name == 'login') {
              await tester.runAsync(
                () => precacheImage(
                  const AssetImage('assets/branding/bagoo-mark.png'),
                  tester.element(find.byType(Scaffold).first),
                ),
              );
              await tester.pumpAndSettle();
            }
            await saveRender('${name}_${scene.$1.width.toInt()}_${scene.$2}');
            if (name == 'shop' && scene.$1.width == 320) {
              final toggle = find.byKey(const ValueKey('shop-filter-toggle'));
              if (scene.$2 > 1.0) {
                await tester.dragUntilVisible(
                  toggle,
                  find.byType(CustomScrollView),
                  const Offset(0, -250),
                );
                await tester.pumpAndSettle();
              }
              await tester.tap(toggle);
              await tester.pumpAndSettle();
              expect(find.text('Department'), findsOneWidget);
              expect(find.text('Store category'), findsOneWidget);
              final dropdowns = find.byType(DropdownButtonFormField<String>);
              expect(dropdowns, findsNWidgets(3));
              final displayedValues = scene.$2 >= 1.5
                  ? ['All', 'All', 'Suggested']
                  : ['All departments', 'All products', 'Recommended'];
              final semanticsValues = [
                'All departments',
                'All products',
                'Recommended',
              ];
              for (final index in [0, 1, 2]) {
                final field = tester.getRect(dropdowns.at(index));
                final selectedText = find.descendant(
                  of: dropdowns.at(index),
                  matching: find.text(displayedValues[index]),
                );
                final selected = tester.getRect(selectedText);
                expect(selected.top, greaterThanOrEqualTo(field.top));
                expect(selected.bottom, lessThanOrEqualTo(field.bottom));
                expect(
                  tester
                      .renderObject<RenderParagraph>(selectedText)
                      .didExceedMaxLines,
                  isFalse,
                );
                expect(
                  find.descendant(
                    of: dropdowns.at(index),
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is Semantics &&
                          widget.properties.label == semanticsValues[index],
                    ),
                  ),
                  findsOneWidget,
                );
              }
              await saveRender('shop-filters_320_${scene.$2}');

              final storeFilter = tester.widget<DropdownButton<String>>(
                find.descendant(
                  of: dropdowns.at(1),
                  matching: find.byType(DropdownButton<String>),
                ),
              );
              storeFilter.onChanged!('11');
              await tester.pumpAndSettle();
              final selectedStoreFilter = find
                  .byType(DropdownButtonFormField<String>)
                  .at(1);
              final selectedSummary = find.descendant(
                of: selectedStoreFilter,
                matching: find.text('Selected'),
              );
              final fullSelection =
                  'Selected: Travel bags, hiking packs, and everyday carry gear';
              final selectionDetail = find.text(fullSelection);
              expect(selectedSummary, findsOneWidget);
              expect(selectionDetail, findsOneWidget);
              expect(
                tester
                    .renderObject<RenderParagraph>(selectionDetail)
                    .didExceedMaxLines,
                isFalse,
              );
              expect(
                find.descendant(
                  of: selectedStoreFilter,
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is Semantics && widget.properties.label == 'Travel bags, hiking packs, and everyday carry gear',
                  ),
                ),
                findsOneWidget,
              );
              await Scrollable.ensureVisible(
                tester.element(selectedStoreFilter),
                alignment: .2,
              );
              await tester.pumpAndSettle();
              final selectionRect = tester.getRect(selectionDetail);
              final filterViewport = tester.getRect(
                find.byType(CustomScrollView),
              );
              expect(
                selectionRect.top,
                greaterThanOrEqualTo(filterViewport.top),
              );
              expect(
                selectionRect.bottom,
                lessThanOrEqualTo(filterViewport.bottom),
              );
              await saveRender('shop-category-selected_320_${scene.$2}');
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
