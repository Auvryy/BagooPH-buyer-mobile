import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/features/checkout/order_result_page.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/checkout_fixtures.dart';
import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart' show buyer;

void main() {
  testWidgets('malformed wallet balance is shown as unavailable', (
    tester,
  ) async {
    final initial = ownedOrderResult();
    initial.props['payment'] = {
      'id': 41,
      'order_number': 'TEST-PAYMENT-41',
      'status': 'paid',
      'amount_cents': 125000,
      'balance_cents': 'not-money',
    };
    final session = ControlledWebSession();
    addTearDown(session.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: OrderResultPage(
          repository: BuyerRepository(session),
          initial: initial,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Available virtual credits: Unavailable'), findsOneWidget);
    expect(find.text('Available virtual credits: ₱0.00'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('malformed payment item rows do not produce a partial receipt', (
    tester,
  ) async {
    final initial = ownedOrderResult();
    initial.props['payment'] = {
      'id': 41,
      'order_number': 'TEST-PAYMENT-41',
      'status': 'pending',
      'can_pay': true,
      'amount_cents': 125000,
      'expires_at': DateTime.now()
          .add(const Duration(days: 1))
          .toUtc()
          .toIso8601String(),
      'items': [
        {'name': 'Visible partial item', 'quantity': 1, 'unit_price': 1250},
        'malformed item row',
      ],
    };
    final session = ControlledWebSession();
    addTearDown(session.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: OrderResultPage(
          repository: BuyerRepository(session),
          initial: initial,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Visible partial item'), findsNothing);
    expect(find.text('Confirm payment'), findsNothing);
    expect(
      find.textContaining('Order item details could not be confirmed'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final amountCents in ['not-money', -1, 1000.5, '1000']) {
    testWidgets(
      'malformed wallet payment amount cannot enable confirmation: $amountCents',
      (tester) async {
        final initial = ownedOrderResult();
        initial.props['payment'] = {
          'id': 41,
          'order_number': 'TEST-PAYMENT-41',
          'status': 'pending',
          'can_pay': true,
          'amount_cents': amountCents,
          'expires_at': DateTime.now()
              .add(const Duration(days: 1))
              .toUtc()
              .toIso8601String(),
        };
        final session = ControlledWebSession();
        addTearDown(session.close);

        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            home: OrderResultPage(
              repository: BuyerRepository(session),
              initial: initial,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Confirm payment'), findsNothing);
        expect(find.text('Cancel payment'), findsOneWidget);
        expect(
          find.textContaining('Payment amount could not be confirmed'),
          findsOneWidget,
        );
        expect(find.text('₱0.00'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('wallet refresh cannot replace a different payment record', (
    tester,
  ) async {
    final initial = ownedOrderResult();
    initial.props['payment'] = {
      'id': 41,
      'order_number': 'INITIAL-PAYMENT-41',
      'status': 'pending',
      'can_pay': false,
      'amount_cents': 125000,
    };
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onPage = (_) async => WebPage('Wallet/Payment', {
      'auth': {'user': buyer},
      'payment': {
        'id': 42,
        'order_number': 'OTHER-PAYMENT-42',
        'status': 'paid',
        'amount_cents': 250000,
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: OrderResultPage(
          repository: BuyerRepository(session),
          initial: initial,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh recorded status'));
    await tester.pumpAndSettle();

    expect(session.pageRequests, ['/wallet/payments/41']);
    expect(find.text('Order OTHER-PAYMENT-42'), findsNothing);
    expect(find.text('Order INITIAL-PAYMENT-41'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('wallet payment link rejects a different payment record', (
    tester,
  ) async {
    final initial = ownedOrderResult();
    initial.props['orders'] = {
      'current_page': 1,
      'last_page': 1,
      'total': 1,
      'data': [
        {
          'id': 11,
          'order_number': 'TEST-ORDER-11',
          'status': 'pending',
          'total_amount': '1250.00',
          'wallet_payment': {'id': 41},
        },
      ],
    };
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onPage = (_) async => WebPage('Wallet/Payment', {
      'auth': {'user': buyer},
      'payment': {
        'id': 42,
        'order_number': 'OTHER-PAYMENT-42',
        'status': 'paid',
        'amount_cents': 250000,
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: OrderResultPage(
          repository: BuyerRepository(session),
          initial: initial,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review wallet payment'));
    await tester.tap(find.text('Review wallet payment'));
    await tester.pumpAndSettle();

    expect(session.pageRequests, ['/wallet/payments/41']);
    expect(find.text('Order OTHER-PAYMENT-42'), findsNothing);
    expect(find.text('Order TEST-ORDER-11'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('initial order history rejects fractional pagination controls', (
    tester,
  ) async {
    final initial = ownedOrderResult();
    final orders = Map<String, dynamic>.from(initial.props['orders'] as Map);
    initial.props['orders'] = orders;
    orders['current_page'] = 1.5;
    orders['last_page'] = 3;
    orders['total'] = 3;
    orders['data'] = [
      {
        'id': 11,
        'order_number': 'PRIVATE-ORDER-11',
        'status': 'pending',
        'total_amount': '100.00',
      },
    ];
    final session = ControlledWebSession();
    addTearDown(session.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: OrderResultPage(
          repository: BuyerRepository(session),
          initial: initial,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Recorded order pagination could not be confirmed. Refresh and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Order PRIVATE-ORDER-11'), findsNothing);
    expect(find.text('Previous orders'), findsNothing);
    expect(find.text('Next orders'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('refreshed order history rejects a string page number', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onPage = (_) async => WebPage('Buyer/Profile', {
      'auth': {'user': buyer},
      'orders': {
        'current_page': '1',
        'last_page': 2,
        'total': 2,
        'data': <dynamic>[],
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: OrderResultPage(
          repository: BuyerRepository(session),
          initial: ownedOrderResult(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh recorded status'));
    await tester.pumpAndSettle();

    expect(session.pageRequests, ['/buyer/orders?page=1']);
    expect(
      find.text(
        'Recorded order pagination could not be confirmed. Refresh and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Next orders'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
