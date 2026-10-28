import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/cached_catalogue_notice.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/products/product_model.dart';
import 'package:bagoo_buyer_mobile/features/products/product_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';

void main() {
  testWidgets(
    'cached products stay read-only until a fresh response is loaded',
    (tester) async {
      final repo = FakeBuyerRepository();
      addTearDown(repo.session.close);
      final cached = productPage(signedIn: true);
      repo.productResponse = WebPage(
        cached.component,
        cached.props,
        cachedAt: DateTime.utc(2026, 10, 28),
      );
      final selection = ProductSelection(repo.productResponse!);
      expect(selection.canChangeBag, isFalse);
      expect(selection.approved, isFalse);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CachedCatalogueNotice), findsOneWidget);
      final buy = find.widgetWithText(FilledButton, 'Buy Now');
      expect(tester.widget<FilledButton>(buy).onPressed, isNull);
      expect(repo.saveCalls, 0);
      expect(repo.orderCalls, 0);
      repo.productResponse = productPage(signedIn: true);
      await tester.tap(find.text('Refresh from Bagoo'));
      await tester.pumpAndSettle();
      expect(find.byType(CachedCatalogueNotice), findsNothing);
      expect(tester.widget<FilledButton>(buy).onPressed, isNotNull);
      expect(repo.productCalls, 2);
      expect(repo.saveCalls, 0);
      expect(repo.orderCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final size in [
    const Size(375, 800),
    const Size(700, 375),
    const Size(1024, 768),
  ]) {
    testWidgets(
      'saved-data feedback fits $size with large text and reduced motion',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: SafeArea(
                  child: SingleChildScrollView(
                    child: CachedCatalogueNotice(
                      savedAt: DateTime.utc(2026, 10, 28),
                      onRefresh: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('Prices and availability may have changed'),
          findsOneWidget,
        );
      },
    );
  }
}
