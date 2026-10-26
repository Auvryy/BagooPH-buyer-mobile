import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/features/home/product_card.dart';

import 'support/fake_buyer_repository.dart';

void main() {
  for (final scale in [1.0, 1.4, 2.0]) {
    testWidgets(
      'cards retain equal dimensions and fit saved errors at text $scale',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1000);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.reset();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final session = FakeSession();
        addTearDown(session.close);
        var opened = 0;
        var saved = 0;
        Widget card(bool ranged) => ProductCard(
          product: {
            ...product(ranged ? 2 : 1),
            'compare_at_price': 1500,
            if (ranged) 'price_range': {'min': 1200, 'max': 999999.99},
          },
          session: session,
          onTap: () => opened++,
          onSave: () => saved++,
          saveLabel: 'Remove from saved',
          error: 'The change could not be confirmed. Try again.',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: scale > 1.4 ? 400 : 320,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: card(false)),
                      const SizedBox(width: 14),
                      Expanded(child: card(true)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final cards = find.byType(ProductCard);
        expect(tester.getSize(cards.at(0)), tester.getSize(cards.at(1)));
        expect(find.text('-20%'), findsOneWidget);
        await tester.tap(find.text('₱1,200.00'));
        expect(opened, 1);
        await tester.ensureVisible(find.text('Remove from saved').first);
        await tester.tap(find.text('Remove from saved').first);
        expect(saved, 1);
        expect(opened, 1);
      },
    );
  }
}
