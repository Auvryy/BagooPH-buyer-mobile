import 'dart:io';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/features/checkout/bag_page.dart';
import 'package:bagoo_buyer_mobile/features/products/product_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bag_fixtures.dart';
import 'support/no_network.dart';

void main() {
  final previous = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = NoNetworkHttpOverrides());
  tearDownAll(() => HttpOverrides.global = previous);
  late ReviewBagRepository repository;
  setUp(() => repository = ReviewBagRepository());
  tearDown(() => repository.session.close());

  for (final changeQuantity in [false, true]) {
    testWidgets(
      changeQuantity
          ? 'cached quantity changes wait for the product route to close'
          : 'queued Bag product taps open one product and return to the same Bag',
      (tester) async {
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: BagooTheme.light,
              home: BagPage(repository: repository),
            ),
          );
          await tester.pumpAndSettle();
          final open = tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Private Bag product'),
              )
              .onPressed!;
          final increment = tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) =>
                      w is IconButton && w.tooltip == 'Increase Bag quantity',
                ),
              )
              .onPressed!;
          open();
          if (changeQuantity) {
            increment();
          } else {
            open();
            open();
          }
          await tester.pumpAndSettle();
          expect(repository.productCalls, 1);
          expect(repository.changes, isEmpty);
          expect(find.byType(ProductPage), findsOneWidget);
          Navigator.of(tester.element(find.byType(ProductPage))).pop();
          await tester.pumpAndSettle();
          expect(find.text('Private Bag product'), findsOneWidget);
          expect(repository.reads, 2);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );
  }
}
