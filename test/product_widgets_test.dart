import 'dart:io';

import 'package:bagoo_buyer_mobile/core/buyer_actions.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/features/products/product_page.dart';
import 'package:bagoo_buyer_mobile/features/products/product_widgets.dart'
    show ImageViewer, readableDate, readableDateTime;
import 'package:bagoo_buyer_mobile/features/home/product_card.dart';
import 'package:bagoo_buyer_mobile/features/home/home_page.dart';
import 'package:bagoo_buyer_mobile/features/checkout/checkout_page.dart';
import 'package:bagoo_buyer_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';
import 'support/widget_helpers.dart';

Future<void> openReviewsSection(WidgetTester tester) async {
  final reviewsTab = find.widgetWithText(ActionChip, 'Reviews & photos');
  await tester.scrollUntilVisible(
    reviewsTab,
    300,
    scrollable: find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(reviewsTab);
  await tester.pumpAndSettle();
}

void main() {
  late FakeBuyerRepository repo;
  setUp(() => repo = FakeBuyerRepository());
  tearDown(() => repo.session.close());
  testWidgets('malformed review and sales counts are not shown as facts', (
    tester,
  ) async {
    repo.productResponse = productPage(
      override: {'verified_review_count': 1.5, 'sales_count': -2},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1.5 verified ratings'), findsNothing);
    expect(find.text('(1.5 verified reviews)'), findsNothing);
    expect(find.text('-2 sold'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Linux sharing offers a working copy-link fallback', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    repo.productResponse = productPage();

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ProductPage(repository: repo, slug: 'everyday-bag/blue'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Share product'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'System sharing is unavailable in this preview. Use Copy link.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Copy product link'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(copied, 'http://backend.test/product/everyday-bag%2Fblue');
    expect(find.text('Product link copied.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isLinux);

  for (final malformedSlug in ['', '   ', 12]) {
    testWidgets(
      'product detail disables the shop route for malformed slug $malformedSlug',
      (tester) async {
        final page = productPage();
        final productData = page.props['product'] as Map;
        final shop = productData['shop'] as Map;
        shop['slug'] = malformedSlug;
        repo.productResponse = page;

        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
          ),
        );
        await tester.pumpAndSettle();
        final route = find.widgetWithText(OutlinedButton, 'View Shop');
        await tester.scrollUntilVisible(
          find.text('View Shop'),
          300,
          scrollable: find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();

        expect(tester.widget<OutlinedButton>(route).onPressed, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('a partial related-product feed does not show a complete strip', (
    tester,
  ) async {
    final page = productPage();
    page.props['relatedProducts'] = [product(2), 'malformed related product'];
    repo.productResponse = page;
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -5000));
    await tester.pumpAndSettle();

    expect(find.text('You may also like'), findsNothing);
    expect(find.text('Everyday bag 2'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('date labels do not normalize impossible calendar values', () {
    expect(readableDate('2026-02-30'), 'Date unavailable');
    expect(readableDateTime('2026-02-30T10:00:00Z'), 'Not provided');
    expect(readableDate('2024-02-29'), '29/2/2024');
  });

  testWidgets('named product photo control opens the native image viewer', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 820);
    addTearDown(tester.view.reset);
    repo.productResponse = productPage(
      override: {'featured_image': '/product-photo.jpg'},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
      ),
    );
    await tester.pumpAndSettle();
    final photo = find.bySemanticsLabel('Open product photo 1 of 1');
    expect(photo, findsOneWidget);
    await tester.tap(photo);
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewer), findsOneWidget);
  });
  testWidgets('malformed review photo data does not crash the product page', (
    tester,
  ) async {
    repo.productResponse = productPage(
      override: {
        'reviews': [
          {
            'id': 31,
            'rating': 5,
            'images': 'not-a-list',
            'comment': 'Useful product.',
            'created_at': '2026-11-02T00:00:00Z',
            'verified_purchase': true,
            'buyer': {'name': 'A***'},
          },
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Useful product.'),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Useful product.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('malformed review rows are not shown as a complete list', (
    tester,
  ) async {
    repo.productResponse = productPage(
      override: {
        'verified_review_count': 2,
        'reviews': <Object?>[
          {
            'id': 31,
            'rating': 5,
            'images': [],
            'comment': 'Partial review list entry.',
            'created_at': '2026-11-02T00:00:00Z',
            'verified_purchase': true,
          },
          'not-a-review',
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
      ),
    );
    await tester.pumpAndSettle();
    final reviewsTab = find.widgetWithText(ActionChip, 'Reviews & photos');
    await tester.scrollUntilVisible(
      reviewsTab,
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(reviewsTab);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Customer reviews could not be confirmed. Refresh this product.',
      ),
      findsOneWidget,
    );
    expect(find.text('Partial review list entry.'), findsNothing);
    expect(find.text('No customer reviews yet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (label, invalidField, invalidValue) in [
    ('string rating', 'rating', '5'),
    ('out-of-range rating', 'rating', 6),
    ('impossible review date', 'created_at', '2026-02-30T12:00:00Z'),
    ('unconfirmed purchase status', 'verified_purchase', 'true'),
  ]) {
    testWidgets('product review list rejects $label', (tester) async {
      repo.productResponse = productPage(
        override: {
          'reviews': [
            {
              'id': 31,
              'rating': 5,
              'images': [],
              'comment': 'Review with malformed $label.',
              'created_at': '2026-11-02T00:00:00Z',
              'verified_purchase': true,
              'buyer': {'name': 'A***'},
              invalidField: invalidValue,
            },
          ],
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
        ),
      );
      await tester.pumpAndSettle();
      final reviewsTab = find.widgetWithText(ActionChip, 'Reviews & photos');
      await tester.scrollUntilVisible(
        reviewsTab,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(reviewsTab);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Customer reviews could not be confirmed. Refresh this product.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Review with malformed'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('complete verified reviews render nested details and photos', (
    tester,
  ) async {
    repo.productResponse = productPage(
      override: {
        'verified_review_count': 1,
        'reviews': [
          {
            'id': 31,
            'rating': 5,
            'images': ['/review-photo.jpg', '', 42, '   '],
            'comment': 'Useful product.',
            'created_at': '2026-11-02T00:00:00Z',
            'verified_purchase': true,
            'buyer': {'name': 'A***'},
            'purchased_options': {'Color': 'Blue'},
            'reply': {
              'text': 'Thank you for sharing your feedback.',
              'created_at': '2026-11-02T01:00:00Z',
              'updated_at': '2026-11-02T02:00:00Z',
              'shop_name': 'Everyday Goods',
            },
          },
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
      ),
    );
    await tester.pumpAndSettle();
    await openReviewsSection(tester);

    expect(find.text('Customer photo gallery'), findsOneWidget);
    expect(find.text('A***'), findsOneWidget);
    expect(find.text('Verified Purchase'), findsOneWidget);
    expect(find.text('Purchased option: Blue'), findsOneWidget);
    expect(find.text('Useful product.'), findsOneWidget);
    expect(find.text('Seller reply · Everyday Goods'), findsOneWidget);
    expect(find.text('Thank you for sharing your feedback.'), findsOneWidget);
    final photo = find.bySemanticsLabel('Open customer photo 1');
    await tester.ensureVisible(photo);
    await tester.tap(photo);
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'legacy reviews use safe labels when optional fields are absent',
    (tester) async {
      repo.productResponse = productPage(
        override: {
          'reviews': [
            {
              'id': 32,
              'rating': 4,
              'created_at': '2026-11-02T00:00:00Z',
              'verified_purchase': false,
            },
          ],
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
        ),
      );
      await tester.pumpAndSettle();
      await openReviewsSection(tester);

      expect(find.text('Shopper'), findsOneWidget);
      expect(find.text('Unverified legacy review'), findsOneWidget);
      expect(find.text('Customer photo gallery'), findsNothing);
      expect(find.text('No customer reviews yet'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('duplicate review IDs do not render a partial review list', (
    tester,
  ) async {
    final review = {
      'id': 31,
      'rating': 5,
      'images': [],
      'created_at': '2026-11-02T00:00:00Z',
      'verified_purchase': true,
    };
    repo.productResponse = productPage(
      override: {
        'reviews': [
          {...review, 'comment': 'First review.'},
          {...review, 'comment': 'Duplicate review.'},
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
      ),
    );
    await tester.pumpAndSettle();
    await openReviewsSection(tester);

    expect(
      find.text(
        'Customer reviews could not be confirmed. Refresh this product.',
      ),
      findsOneWidget,
    );
    expect(find.text('First review.'), findsNothing);
    expect(find.text('Duplicate review.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (label, field, value) in [
    ('zero ID', 'id', 0),
    ('fractional ID', 'id', 31.5),
    ('string ID', 'id', '31'),
    ('non-text comment', 'comment', 9),
    ('non-text review date', 'created_at', 20261102),
    ('buyer row type', 'buyer', 'malformed buyer'),
    ('buyer key type', 'buyer', {1: 'malformed key'}),
    ('buyer name type', 'buyer', {'name': 7}),
    ('option row type', 'purchased_options', 'Blue'),
    ('option key type', 'purchased_options', {1: 'Blue'}),
    ('option value type', 'purchased_options', {'Color': 7}),
    ('reply row type', 'reply', 'malformed reply'),
    ('reply key type', 'reply', {1: 'malformed key'}),
    ('reply text type', 'reply', {'text': 7}),
    ('blank reply text', 'reply', {'text': '   '}),
    (
      'impossible reply date',
      'reply',
      {'text': 'Thanks', 'created_at': '2026-02-30T12:00:00Z'},
    ),
    (
      'impossible reply update date',
      'reply',
      {
        'text': 'Thanks',
        'created_at': '2026-11-02T00:00:00Z',
        'updated_at': '2026-02-30T12:00:00Z',
      },
    ),
    (
      'non-text reply update date',
      'reply',
      {
        'text': 'Thanks',
        'created_at': '2026-11-02T00:00:00Z',
        'updated_at': 20261102,
      },
    ),
    (
      'shop name type',
      'reply',
      {'text': 'Thanks', 'created_at': '2026-11-02T00:00:00Z', 'shop_name': 9},
    ),
  ]) {
    testWidgets('product reviews reject malformed $label data', (tester) async {
      repo.productResponse = productPage(
        override: {
          'reviews': [
            {
              'id': 31,
              'rating': 5,
              'images': [],
              'comment': 'Do not show a partial review.',
              'created_at': '2026-11-02T00:00:00Z',
              'verified_purchase': true,
              'buyer': {'name': 'A***'},
              field: value,
            },
          ],
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
        ),
      );
      await tester.pumpAndSettle();
      await openReviewsSection(tester);

      expect(
        find.text(
          'Customer reviews could not be confirmed. Refresh this product.',
        ),
        findsOneWidget,
      );
      expect(find.text('Do not show a partial review.'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('malformed saved-product IDs do not crash the product page', (
    tester,
  ) async {
    final page = productPage();
    page.props['savedProductIds'] = 'not-a-list';
    repo.productResponse = page;

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Everyday bag 1'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('malformed saved-product IDs do not crash Home cards', (
    tester,
  ) async {
    final page = homePage();
    page.props['savedProductIds'] = 'not-a-list';
    repo.homeHandler = (_, _) async => page;

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: HomePage(repository: repo, onLogin: () {}, onLogout: () async {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Everyday bag 1'),
      400,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );

    expect(find.text('Everyday bag 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'home cards use equal sizes and open a fetched full product page',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 860);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MainApp(repository: repo));
      await press(tester, find.text('Browse the marketplace'));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      final cards = find.byType(ProductCard);
      expect(cards, findsNWidgets(2));
      expect(tester.getSize(cards.at(0)), tester.getSize(cards.at(1)));
      await press(tester, find.text('Everyday bag 1'));
      expect(repo.productCalls, 1);
      expect(find.byType(BottomSheet), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Product specifications'),
        400,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Declared weight'), findsOneWidget);
      expect(find.text('Product Description'), findsOneWidget);
    },
  );
  testWidgets(
    'product includes web comparison, discount, metadata and real add confirmation',
    (tester) async {
      repo.signedIn = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('-20% OFF'), findsOneWidget);
      expect(find.text('SKU: BAG-001'), findsOneWidget);
      await press(tester, find.widgetWithText(OutlinedButton, 'Add to Bag'));
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('1 added to your Shopping Bag.'),
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets('fractional Bag counts disable product purchase controls', (
    tester,
  ) async {
    repo.signedIn = true;
    final page = productPage(signedIn: true);
    page.props['cartQuantities'] = [
      {'color': null, 'size': null, 'quantity': 1.5},
    ];
    repo.productResponse = page;

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Available stock and Bag quantities could not be confirmed. Refresh this product.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Unavailable'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Buy Now'))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'guest Buy Now requests native login and never creates checkout',
    (tester) async {
      String? requested;
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: BuyerActions(
            signIn: (slug) => requested = slug,
            child: ProductPage(repository: repo, slug: 'everyday-bag-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await press(tester, find.widgetWithText(FilledButton, 'Buy Now'));
      expect(requested, 'everyday-bag-1');
      expect(repo.orderCalls, 0);
      expect(find.byType(CheckoutPage), findsNothing);
    },
  );
  testWidgets(
    'Buy Now opens native checkout and places only after explicit review',
    (tester) async {
      repo.signedIn = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
        ),
      );
      await tester.pumpAndSettle();
      await press(tester, find.widgetWithText(FilledButton, 'Buy Now'));
      expect(find.byType(CheckoutPage), findsOneWidget);
      expect(repo.orderCalls, 0);
      await press(tester, find.widgetWithText(FilledButton, 'Review order'));
      expect(find.text('Confirm your order'), findsOneWidget);
      expect(repo.orderCalls, 0);
      await press(tester, find.byType(CheckboxListTile).last);
      await press(tester, find.widgetWithText(FilledButton, 'Place order'));
      expect(repo.orderCalls, 1);
      expect(repo.submittedOrder?['checkout_token'], checkoutFixtureToken());
      expect(find.text('Order #TEST-1 successfully placed.'), findsOneWidget);
    },
  );
  testWidgets(
    'malformed option prices leave Product Detail purchase actions disabled',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 820);
      addTearDown(tester.view.reset);
      repo.signedIn = true;
      final page = productPage(signedIn: true, override: {'price': 100});
      page.props['variations'] = {
        'pricing_mode': 'independent',
        'colors': [
          {'name': 'Red'},
        ],
        'sizes': [
          {'name': 'Large'},
        ],
        'combinations': [
          {'color': 'Red', 'size': 'Large', 'stock': 5, 'price': 'not a price'},
        ],
      };
      repo.productResponse = page;

      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
        ),
      );
      await tester.pumpAndSettle();
      final red = find.widgetWithText(ChoiceChip, 'Red');
      await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.tap(red);
      await tester.pumpAndSettle();
      final large = find.widgetWithText(ChoiceChip, 'Large');
      await tester.ensureVisible(large);
      await tester.tap(large);
      await tester.pumpAndSettle();

      expect(find.text('Price unavailable'), findsWidgets);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Unavailable'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Buy Now'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'mobile purchase controls guide option selection before checkout',
    (tester) async {
      repo.signedIn = true;
      final page = productPage(signedIn: true);
      page.props['variations'] = {
        'colors': [
          {'name': 'Red'},
          {'name': 'Blue'},
        ],
        'sizes': [
          {'name': 'Small'},
        ],
        'combinations': [
          {'color': 'Red', 'size': 'Small', 'stock': 0},
          {'color': 'Blue', 'size': 'Small', 'stock': 3},
        ],
      };
      repo.productResponse = page;
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Buy Now'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutPage), findsNothing);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Red'))
            .onSelected,
        isNull,
      );
      final blue = find.widgetWithText(ChoiceChip, 'Blue');
      await tester.ensureVisible(blue);
      await tester.tap(blue);
      await tester.pumpAndSettle();
      final size = find.widgetWithText(ChoiceChip, 'Small');
      await tester.ensureVisible(size);
      await tester.tap(size);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Buy Now'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutPage), findsOneWidget);
      expect(repo.orderCalls, 0);
    },
  );
  for (final scenario in [
    (size: const Size(320, 640), scale: 1.0),
    (size: const Size(430, 860), scale: 1.0),
    (size: const Size(1024, 768), scale: 1.0),
    (size: const Size(1200, 900), scale: 1.0),
    (size: const Size(820, 375), scale: 1.0),
    (size: const Size(375, 812), scale: 2.0),
  ]) {
    testWidgets(
      'product, cards and checkout reflow at ${scenario.size} text ${scenario.scale}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = scenario.size;
        tester.platformDispatcher.textScaleFactorTestValue = scenario.scale;
        addTearDown(() {
          tester.view.reset();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                child: Center(
                  child: SizedBox(
                    width: scenario.scale > 1 ? 343 : 140,
                    child: ProductCard(
                      product: {...product(1), 'compare_at_price': 1500},
                      session: repo.session,
                      onTap: () {},
                      onSave: () {},
                      saveLabel: 'Save product',
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).first, const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            home: CheckoutPage(repository: repo, initial: checkoutPage()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).first, const Offset(0, -900));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('product failure provides retry without stale preview data', (
    tester,
  ) async {
    repo.productError = const BackendException(
      'Product not found.',
      status: 404,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ProductPage(repository: repo, slug: 'missing'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Product not found.'), findsOneWidget);
    repo.productError = null;
    await press(tester, find.text('Try again'));
    expect(find.text('Everyday bag 1'), findsOneWidget);
  });
}
