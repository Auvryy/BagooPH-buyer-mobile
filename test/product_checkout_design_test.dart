import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/core/widgets.dart';
import 'package:bagoo_buyer_mobile/features/checkout/checkout_page.dart';
import 'package:bagoo_buyer_mobile/features/products/product_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Plus Jakarta Sans',
    )..addFont(rootBundle.load('assets/fonts/PlusJakartaSans.ttf'))).load();
  });

  testWidgets(
    'product identity is visible before the gallery and purchase actions',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 812);
      addTearDown(tester.view.reset);
      final repo = FakeBuyerRepository();
      addTearDown(repo.session.close);
      const title = 'Everyday Carry Canvas Tote';
      repo.productResponse = productPage(
        signedIn: true,
        override: {'name': title},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
        ),
      );
      await tester.pumpAndSettle();
      final heading = tester.getRect(find.text(title));
      expect(heading.top, greaterThanOrEqualTo(0));
      expect(
        heading.bottom,
        lessThan(tester.getRect(find.byTooltip('Save product')).top),
      );
      expect(
        heading.bottom,
        lessThan(
          tester.getRect(find.widgetWithText(FilledButton, 'Buy Now')).top,
        ),
      );
      expect(repo.saveCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a long product gallery builds a bounded horizontal strip and keeps arrow navigation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 812);
      addTearDown(tester.view.reset);
      final repo = FakeBuyerRepository();
      addTearDown(repo.session.close);
      repo.productResponse = productPage(
        signedIn: true,
        override: {
          'images': [
            for (var i = 0; i < 30; i++)
              {'image_url': '/public-fixture-$i.png'},
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
      expect(find.byType(RemoteImage).evaluate().length, lessThan(15));
      for (var i = 0; i < 8; i++) {
        await tester.tap(find.byTooltip('Next product photo'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Photo 9 of 30'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(repo.productCalls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'product options and quantity survive a phone-to-tablet layout change',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 812);
      addTearDown(tester.view.reset);
      final repo = FakeBuyerRepository();
      addTearDown(repo.session.close);
      final page = productPage(signedIn: true);
      page.props['variations'] = {
        'colors': [
          {'name': 'Blue', 'in_stock': true},
        ],
        'sizes': [],
      };
      repo.productResponse = page;
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
        ),
      );
      await tester.pumpAndSettle();
      final color = find.widgetWithText(ChoiceChip, 'Blue');
      await tester.ensureVisible(color);
      await tester.pumpAndSettle();
      await tester.tap(color);
      await tester.pumpAndSettle();
      final quantity = find.byWidgetPredicate(
        (w) => w is TextField && w.keyboardType == TextInputType.number,
      );
      await tester.ensureVisible(quantity);
      await tester.enterText(quantity, '2');
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1024, 768);
      await tester.pumpAndSettle();
      // Reflow shortens the product panel; return to it from the old scroll offset.
      await tester.drag(find.byType(RefreshIndicator), const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.ensureVisible(color);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(color).selected, isTrue);
      expect(tester.widget<TextField>(quantity).controller!.text, '2');
      expect(repo.productCalls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final scene in [
    (1.0, 'Test delivery company'),
    (2.0, 'Test delivery company'),
    (2.0, 'Philippine Regional Delivery and Collection Network'),
  ]) {
    testWidgets(
      'selected delivery company text paints within its field at ${scene.$1}: ${scene.$2}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(375, 900);
        addTearDown(tester.view.reset);
        final repo = FakeBuyerRepository();
        addTearDown(repo.session.close);
        final initial = checkoutPage();
        final page = WebPage(initial.component, {
          ...initial.props,
          'logisticsCompanies': [
            {'id': 41, 'name': scene.$2},
          ],
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(375, 900),
                textScaler: TextScaler.linear(scene.$1),
              ),
              child: CheckoutPage(repository: repo, initial: page),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final selected = find.text(scene.$2).first;
        await tester.ensureVisible(selected);
        await tester.pumpAndSettle();
        final paragraph = tester.renderObject<RenderParagraph>(selected);
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: scene.$2.length),
        );
        expect(boxes, isNotEmpty);
        for (final box in boxes) {
          expect(box.top, greaterThanOrEqualTo(-.1));
          expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + .1));
        }
        expect(tester.takeException(), isNull);
        expect(repo.orderCalls, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
