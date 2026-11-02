import 'dart:io';
import 'dart:ui' as ui;

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/core/verification_prompt.dart';
import 'package:bagoo_buyer_mobile/features/auth/login_page.dart';
import 'package:bagoo_buyer_mobile/features/checkout/bag_page.dart';
import 'package:bagoo_buyer_mobile/features/checkout/checkout_page.dart';
import 'package:bagoo_buyer_mobile/features/home/home_page.dart';
import 'package:bagoo_buyer_mobile/features/home/product_card.dart';
import 'package:bagoo_buyer_mobile/features/home/search_page.dart';
import 'package:bagoo_buyer_mobile/features/products/chat_page.dart';
import 'package:bagoo_buyer_mobile/features/products/product_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/inbox_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
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
            if (name == 'home' || name == 'login') {
              await tester.runAsync(
                () => precacheImage(
                  const AssetImage('assets/branding/bagoo-mark.png'),
                  tester.element(find.byType(Scaffold).first),
                ),
              );
              await tester.pumpAndSettle();
            }
            await tester.runAsync(() async {
              final render =
                  boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final rendered = await render.toImage();
              final bytes = await rendered.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory('.git/buyer-design/$phase');
              await directory.create(recursive: true);
              await File(
                '${directory.path}/${name}_${scene.$1.width.toInt()}_${scene.$2}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              rendered.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
