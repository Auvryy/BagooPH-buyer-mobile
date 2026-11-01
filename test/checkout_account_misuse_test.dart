import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/device_actions.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/checkout_page.dart';
import 'package:bagoo_buyer_mobile/features/checkout/order_result_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/checkout_fixtures.dart';
import 'support/fake_buyer_repository.dart';
import 'support/widget_helpers.dart';

void main() {
  late FakeBuyerRepository repository;
  late WebPage initial;
  late List<Map<String, dynamic>> quotes;
  setUp(() {
    repository = FakeBuyerRepository();
    initial = ownedCheckout();
    quotes = [];
    repository.quoteHandler = (values) async {
      quotes.add(Map.of(values));
      return confirmedQuote();
    };
    repository.orderHandler = (_) async => ownedOrderResult();
  });
  tearDown(() => repository.session.close());

  void check(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }

  Widget app({Future<BuyerLocation> Function()? location}) => MaterialApp(
    theme: BagooTheme.light,
    home: CheckoutPage(
      repository: repository,
      initial: initial,
      captureLocation:
          location ??
          () async => (latitude: 14.0, longitude: 121.0, accuracy: 10.0),
    ),
  );
  Future<void> open(
    WidgetTester tester, {
    Future<BuyerLocation> Function()? location,
  }) async {
    await tester.pumpWidget(app(location: location));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextFormField, 'Recipient name'),
      findsOneWidget,
    );
    expect(quotes, isNotEmpty);
  }

  Future<void> review(WidgetTester tester) async {
    await press(tester, find.widgetWithText(FilledButton, 'Review order'));
    expect(find.text('Confirm your order'), findsOneWidget);
  }

  Future<void> startTap(WidgetTester tester, Finder target) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    if (target.hitTestable().evaluate().isEmpty) {
      await Scrollable.ensureVisible(
        tester.element(target.first),
        alignment: .5,
      );
      await tester.pumpAndSettle();
    }
    expect(target.hitTestable(), findsWidgets);
    await tester.tap(target.hitTestable().first);
    await tester.pump();
  }

  check('valid checkout requires explicit review and places one owned order', (
    tester,
  ) async {
    await open(tester);
    await review(tester);
    expect(repository.orderCalls, 0);
    await press(tester, find.byType(CheckboxListTile).last);
    await press(tester, find.widgetWithText(FilledButton, 'Place order'));
    expect(repository.orderCalls, 1);
    expect(repository.submittedOrder?['checkout_token'], checkoutToken());
    expect(find.text('Order PRIVATE-41 recorded.'), findsOneWidget);
  });

  check('checkout clears private form fields on resume after account expiry', (
    tester,
  ) async {
    await open(tester);
    repository.session.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Recipient name'), findsNothing);
    expect(repository.orderCalls, 0);
  });

  check('expired checkout cannot request another quote or open a review', (
    tester,
  ) async {
    await open(tester);
    final count = quotes.length;
    repository.session.clear();
    await press(tester, find.widgetWithText(FilledButton, 'Review order'));
    expect(quotes, hasLength(count));
    expect(find.text('Confirm your order'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Recipient name'), findsNothing);
  });

  check(
    'a quote completing after account expiry cannot retain private checkout',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      repository.quoteHandler = (_) => pending.future;
      await tester.pumpWidget(app());
      await tester.pump();
      repository.session.clear();
      pending.complete(confirmedQuote());
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextFormField, 'Recipient name'),
        findsNothing,
      );
      expect(repository.orderCalls, 0);
    },
  );

  check('denied quote access clears the previous checkout draft', (
    tester,
  ) async {
    await open(tester);
    repository.quoteHandler = (_) async =>
        throw const BackendException('Buyer access ended.', status: 403);
    await press(tester, find.widgetWithText(FilledButton, 'Review order'));
    expect(find.widgetWithText(TextFormField, 'Recipient name'), findsNothing);
    expect(find.text('Confirm your order'), findsNothing);
  });

  check('late GPS cannot restore a checkout after the buyer changes', (
    tester,
  ) async {
    final pending = Completer<BuyerLocation>();
    await open(tester, location: () => pending.future);
    await startTap(
      tester,
      find.widgetWithText(OutlinedButton, 'Use current location'),
    );
    repository.session.clear();
    pending.complete((latitude: 14.1, longitude: 121.1, accuracy: 10.0));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Recipient name'), findsNothing);
    expect(find.textContaining('Location pinned.'), findsNothing);
  });

  check('expired account confirmation cannot place the old checkout', (
    tester,
  ) async {
    await open(tester);
    await review(tester);
    await press(tester, find.byType(CheckboxListTile).last);
    repository.session.clear();
    await press(tester, find.widgetWithText(FilledButton, 'Place order'));
    expect(repository.orderCalls, 0);
    expect(find.text('Order PRIVATE-41 recorded.'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Recipient name'), findsNothing);
  });

  check(
    'cancelling an expired checkout review removes its underlying private draft',
    (tester) async {
      await open(tester);
      await review(tester);
      repository.session.clear();
      await press(tester, find.widgetWithText(TextButton, 'Back'));
      expect(
        find.widgetWithText(TextFormField, 'Recipient name'),
        findsNothing,
      );
      expect(repository.orderCalls, 0);
    },
  );

  check(
    'cancelling an expired wallet confirmation clears recorded payment details',
    (tester) async {
      final result = ownedOrderResult();
      result.props['payment'] = {
        'id': 41,
        'order_number': 'PRIVATE-PAYMENT-41',
        'status': 'pending',
        'can_pay': true,
        'amount_cents': 125000,
        'expires_at': DateTime.now()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: OrderResultPage(repository: repository, initial: result),
        ),
      );
      await tester.pumpAndSettle();
      await press(tester, find.text('Cancel payment'));
      repository.session.clear();
      await press(tester, find.text('Keep payment'));
      expect(find.textContaining('PRIVATE-PAYMENT-41'), findsNothing);
      expect(find.text('Confirm payment'), findsNothing);
      expect(repository.orderCalls, 0);
    },
  );

  check('account expiry hides recipient details inside an open review', (
    tester,
  ) async {
    await open(tester);
    await review(tester);
    repository.session.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('Test Buyer · 09171234567'), findsNothing);
    expect(find.text('Place order'), findsNothing);
    expect(repository.orderCalls, 0);
  });

  for (final changedAccount in [true, false]) {
    check(
      'late order acknowledgement is bound to the opening buyer: $changedAccount',
      (tester) async {
        final pending = Completer<WebPage>();
        repository.orderHandler = (_) => pending.future;
        await open(tester);
        await review(tester);
        await press(tester, find.byType(CheckboxListTile).last);
        await startTap(
          tester,
          find.widgetWithText(FilledButton, 'Place order'),
        );
        expect(repository.orderCalls, 1);
        if (changedAccount) repository.session.clear();
        pending.complete(ownedOrderResult(owner: changedAccount ? 7 : 8));
        await tester.pumpAndSettle();
        expect(find.byType(OrderResultPage), findsNothing);
        expect(find.text('Order PRIVATE-41 recorded.'), findsNothing);
      },
    );
  }

  for (final invalid in ['missing-buyer', 'foreign-user', 'seller']) {
    check('checkout rejects invalid opening identity: $invalid', (
      tester,
    ) async {
      if (invalid == 'missing-buyer') {
        (initial.props['auth'] as Map)['user'] = {'role': 'buyer'};
      } else if (invalid == 'foreign-user') {
        (initial.props['user'] as Map)['id'] = 8;
      } else {
        ((initial.props['auth'] as Map)['user'] as Map)['role'] = 'seller';
      }
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(quotes, isEmpty);
      expect(
        find.widgetWithText(TextFormField, 'Recipient name'),
        findsNothing,
      );
      expect(repository.orderCalls, 0);
    });
  }

  for (final token in [
    null,
    '',
    'tampered',
    3,
    'v2.${'a' * 64}.${'g' * 64}',
    '${checkoutToken()}\n',
  ]) {
    check('checkout cannot start from a malformed signed form token: $token', (
      tester,
    ) async {
      initial.props['checkoutToken'] = token;
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(quotes, isEmpty);
      expect(
        find.widgetWithText(TextFormField, 'Recipient name'),
        findsNothing,
      );
      expect(repository.orderCalls, 0);
    });
  }
}
