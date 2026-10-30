import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/bag_page.dart';
import 'package:bagoo_buyer_mobile/features/checkout/checkout_page.dart';
import 'package:bagoo_buyer_mobile/features/engagement/buyer_destination_router.dart';
import 'package:bagoo_buyer_mobile/features/products/product_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bag_test.dart' show BagRepository;
import 'support/checkout_fixtures.dart';
import 'support/widget_helpers.dart';

class _CheckoutRepository extends BagRepository {
  _CheckoutRepository() {
    signedIn = true;
  }
  final pending = Completer<WebPage>();
  bool defer = false;
  int opens = 0, quotes = 0;
  Future<WebPage> _checkout() {
    opens++;
    return defer ? pending.future : Future.value(ownedCheckout());
  }

  @override
  Future<WebPage> checkout(List<int> ids) => _checkout();
  @override
  Future<WebPage> document(String path) =>
      Uri.parse(path).path == '/checkout' ? _checkout() : super.document(path);
  @override
  Future<WebPage> addToBag(
    Map<String, dynamic> product,
    int quantity, {
    String? color,
    String? size,
    bool buyNow = false,
    int previousQuantity = 0,
  }) => buyNow
      ? _checkout()
      : super.addToBag(
          product,
          quantity,
          color: color,
          size: size,
          previousQuantity: previousQuantity,
        );
  @override
  Future<Map<String, dynamic>> quote(Map<String, dynamic> values) async {
    quotes++;
    return confirmedQuote();
  }
}

class _ExpireOnPush extends NavigatorObserver {
  _ExpireOnPush(this.expire, {this.replace = false});
  final VoidCallback expire;
  final bool replace;
  bool armed = false;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!replace &&
        armed &&
        previousRoute != null &&
        route is MaterialPageRoute) {
      armed = false;
      expire();
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (replace && armed && newRoute is MaterialPageRoute) {
      armed = false;
      expire();
    }
  }
}

void main() {
  for (final source in ['product', 'bag', 'link']) {
    for (final stage in ['pending reply', 'route creation', 'before-tap']) {
      if (source == 'link' && stage == 'before-tap') continue;
      final inFlight = stage == 'pending reply';
      testWidgets(
        'checkout from $source keeps the opening account across $stage',
        (tester) async {
          final repository = _CheckoutRepository()..defer = inFlight;
          addTearDown(repository.session.close);
          final observer = _ExpireOnPush(repository.session.clear);
          final failures = <Object>[];
          await tester.pumpWidget(
            MaterialApp(
              theme: BagooTheme.light,
              navigatorObservers: [observer],
              home: switch (source) {
                'product' => ProductPage(
                  repository: repository,
                  slug: 'everyday-bag-1',
                ),
                'bag' => BagPage(repository: repository),
                _ => Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () async {
                        try {
                          await BuyerDestinationRouter.openHref(
                            context,
                            repository,
                            '/checkout?items=1',
                            onSearch: null,
                            onProfileSection: null,
                          );
                        } on BackendException catch (error) {
                          failures.add(error);
                        }
                      },
                      child: const Text('Open checkout'),
                    ),
                  ),
                ),
              },
            ),
          );
          await tester.pumpAndSettle();
          final target = switch (source) {
            'product' => find.widgetWithText(FilledButton, 'Buy Now'),
            'bag' => find.text('Checkout (1)'),
            _ => find.text('Open checkout'),
          };
          if (target.hitTestable().evaluate().isEmpty) {
            await Scrollable.ensureVisible(
              tester.element(target.first),
              alignment: .5,
            );
            await tester.pumpAndSettle();
          }
          expect(target.hitTestable(), findsWidgets);
          observer.armed = stage == 'route creation';
          if (stage == 'before-tap') repository.session.clear();
          await tester.tap(target.hitTestable().first);
          await tester.pump();
          expect(repository.opens, stage == 'before-tap' ? 0 : 1);
          if (inFlight) {
            repository.session.clear();
            repository.pending.complete(ownedCheckout());
          }
          await tester.pumpAndSettle();
          expect(repository.quotes, 0);
          expect(
            find.widgetWithText(TextFormField, 'Recipient name'),
            findsNothing,
          );
          if (source == 'link' && inFlight) expect(failures, hasLength(1));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );
    }
  }
  testWidgets(
    'order-result replacement retains the acknowledged buyer before its route builds',
    (tester) async {
      final repository = _CheckoutRepository();
      addTearDown(repository.session.close);
      repository.orderHandler = (_) async => ownedOrderResult();
      final observer = _ExpireOnPush(repository.session.clear, replace: true);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          navigatorObservers: [observer],
          home: CheckoutPage(repository: repository, initial: ownedCheckout()),
        ),
      );
      await tester.pumpAndSettle();
      await press(tester, find.widgetWithText(FilledButton, 'Review order'));
      await press(tester, find.byType(CheckboxListTile).last);
      observer.armed = true;
      await press(tester, find.widgetWithText(FilledButton, 'Place order'));
      expect(repository.orderCalls, 1);
      expect(find.text('Order PRIVATE-41 recorded.'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
