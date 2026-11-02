import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/order_result_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/checkout_fixtures.dart';
import 'support/controlled_web_session.dart';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wallet payment rate limits pause both payment actions', (
    tester,
  ) async {
    var now = DateTime.now();
    final initial = ownedOrderResult();
    initial.props['payment'] = {
      'id': 41,
      'order_id': 11,
      'order_number': 'TEST-PAYMENT-41',
      'reference': 'WALLET-41',
      'request_token': 'request-token-41',
      'status': 'pending',
      'can_pay': true,
      'amount_cents': 125000,
      'balance_cents': 250000,
      'expires_at': now.add(const Duration(days: 1)).toUtc().toIso8601String(),
      'items': <Map<String, dynamic>>[],
    };
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onPost = (_) async => throw BackendException(
      'Too many attempts. Please wait before trying again.',
      status: 429,
      retryAt: now.add(const Duration(seconds: 45)),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: OrderResultPage(
          repository: BuyerRepository(session),
          initial: initial,
          now: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byType(CheckboxListTile));
    await _tap(tester, find.widgetWithText(FilledButton, 'Confirm payment'));

    final retryPayFinder = find.ancestor(
      of: find.textContaining('Try again in'),
      matching: find.byType(FilledButton),
    );
    final retryCancelFinder = find.ancestor(
      of: find.textContaining('Cancel payment in'),
      matching: find.byType(TextButton),
    );
    expect(retryPayFinder, findsOneWidget);
    expect(retryCancelFinder, findsOneWidget);
    final payButton = tester.widget<FilledButton>(retryPayFinder);
    final cancelButton = tester.widget<TextButton>(retryCancelFinder);
    expect(payButton.onPressed, isNull);
    expect(cancelButton.onPressed, isNull);
    expect(find.textContaining('Try again in'), findsOneWidget);
    expect(find.textContaining('Cancel payment in'), findsOneWidget);
    expect(session.posts, hasLength(1));
    expect(session.posts.single.path, '/wallet/payments/41/pay');

    now = now.add(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();

    final readyPayButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm payment'),
    );
    final readyCancelButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Cancel payment'),
    );
    expect(readyPayButton.onPressed, isNotNull);
    expect(readyCancelButton.onPressed, isNotNull);
    expect(session.posts, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
