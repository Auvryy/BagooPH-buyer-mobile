import 'package:bagoo_buyer_mobile/core/buyer_actions.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/features/products/product_page.dart';
import 'package:bagoo_buyer_mobile/features/home/product_card.dart';
import 'package:bagoo_buyer_mobile/features/checkout/checkout_page.dart';
import 'package:bagoo_buyer_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';
import 'support/widget_helpers.dart';

void main() {
  late FakeBuyerRepository repo;
  setUp(() => repo = FakeBuyerRepository());
  tearDown(() => repo.session.close());
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
      expect(repo.submittedOrder?['checkout_token'], 'test-checkout-token');
      expect(find.text('Order #TEST-1 successfully placed.'), findsOneWidget);
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
