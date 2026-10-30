import 'dart:async';
import 'dart:io';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/checkout_page.dart';
import 'package:bagoo_buyer_mobile/features/checkout/order_result_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/checkout_fixtures.dart';
import 'support/fake_buyer_repository.dart';
import 'support/no_network.dart';
import 'support/widget_helpers.dart';

class _PopObserver extends NavigatorObserver {
  int pops = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

void main() {
  final originalOverrides = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = NoNetworkHttpOverrides());
  tearDownAll(() => HttpOverrides.global = originalOverrides);

  for (final action in ['Place order', 'Back', 'Keep payment']) {
    testWidgets(
      'repeated $action activations decide only the current confirmation',
      (tester) async {
        final repository = FakeBuyerRepository();
        addTearDown(repository.session.close);
        final pending = Completer<WebPage>();
        repository.quoteHandler = (_) async => confirmedQuote();
        repository.orderHandler = (_) => pending.future;
        final observer = _PopObserver();
        final payment = ownedOrderResult();
        payment.props['payment'] = {
          'id': 41,
          'order_number': 'TEST-PAYMENT-41',
          'status': 'pending',
          'can_pay': true,
          'amount_cents': 125000,
          'expires_at': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        };
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: BagooTheme.light,
              navigatorObservers: [observer],
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => action == 'Keep payment'
                            ? OrderResultPage(
                                repository: repository,
                                initial: payment,
                              )
                            : CheckoutPage(
                                repository: repository,
                                initial: ownedCheckout(),
                              ),
                      ),
                    ),
                    child: const Text('Open owned checkout'),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await press(tester, find.text('Open owned checkout'));
          if (action == 'Keep payment') {
            await press(tester, find.text('Cancel payment'));
          } else {
            await press(
              tester,
              find.widgetWithText(FilledButton, 'Review order'),
            );
            if (action == 'Place order') {
              await press(tester, find.byType(CheckboxListTile).last);
            }
          }
          final button = action == 'Place order'
              ? tester
                    .widget<FilledButton>(
                      find.widgetWithText(FilledButton, action),
                    )
                    .onPressed!
              : tester
                    .widget<TextButton>(find.widgetWithText(TextButton, action))
                    .onPressed!;
          final errors = <Object>[];
          // A retained callback also models queued accessibility/keyboard events
          // before the exiting dialog has left the widget tree.
          for (var index = 0; index < 8; index++) {
            try {
              button();
            } catch (error) {
              errors.add(error);
            }
          }
          await tester.pump(const Duration(milliseconds: 400));
          final frameworkError = tester.takeException();
          expect(errors, isEmpty);
          expect(frameworkError, isNull);
          expect(observer.pops, 1);
          expect(repository.orderCalls, action == 'Place order' ? 1 : 0);
          expect(
            find.byType(
              action == 'Keep payment' ? OrderResultPage : CheckoutPage,
            ),
            findsOneWidget,
          );
        } finally {
          if (!pending.isCompleted) pending.complete(ownedOrderResult());
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );
  }
}
