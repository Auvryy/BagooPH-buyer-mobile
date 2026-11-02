import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/profile/order_detail_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart' show buyer;

WebPage _pickupOrder({String status = 'ready'}) =>
    WebPage('Buyer/OrderDetail', {
      'auth': {'user': buyer},
      'order': {
        'id': 11,
        'order_number': 'PICKUP-11',
        'status': 'sorted',
        'created_at': '2026-11-02T00:00:00Z',
        'items': <dynamic>[],
        'tracking': {'status_label': 'Ready for hub pickup'},
      },
      'canUsePortal': false,
      'canConfirmReceipt': false,
      'pickupClaim': {
        'reference': 'CLAIM-11',
        'status': status,
        'expires_at': DateTime.now()
            .add(const Duration(hours: 1))
            .toUtc()
            .toIso8601String(),
        'locked_until': null,
        'code_issued_at': null,
      },
      'pickupHub': {
        'name': 'Test hub',
        'address': 'Synthetic address',
        'operating_hours': 'Synthetic hours',
      },
      'pickupCodeAvailable': true,
    });

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  for (final entry in <({String label, dynamic items})>[
    (label: 'missing item list', items: 'missing'),
    (
      label: 'malformed row',
      items: [
        {'id': 21},
        'not an item row',
      ],
    ),
    (
      label: 'duplicate item IDs',
      items: [
        {'id': 21},
        {'id': 21},
      ],
    ),
  ]) {
    testWidgets('unconfirmed order items are not shown: ${entry.label}', (
      tester,
    ) async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      final page = _pickupOrder();
      final order = page.props['order'] as Map;
      if (entry.items == 'missing') {
        order.remove('items');
      } else {
        order['items'] = entry.items;
      }
      session.onPage = (_) async => page;
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: OrderDetailPage(
            repository: ProfileRepository(BuyerRepository(session)),
            orderId: 11,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Order progress'), findsNothing);
      expect(find.textContaining('could not be confirmed'), findsOneWidget);
      expect(session.pageRequests, ['/buyer/orders/11']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('fractional order relation IDs cannot open other resources', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final page = _pickupOrder();
    (page.props['order'] as Map)['wallet_payment'] = {'id': 41.5};
    page.props['buyerReturns'] = [
      {'id': 4.5, 'reference': 'RETURN-4', 'status': 'approved'},
    ];
    session.onPage = (_) async => page;
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: OrderDetailPage(
          repository: ProfileRepository(BuyerRepository(session)),
          orderId: 11,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('could not be confirmed'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Review wallet payment'), findsNothing);
    expect(find.text('RETURN-4'), findsNothing);
    expect(
      find.text(
        'Return details could not be confirmed. Refresh this order to check again.',
      ),
      findsOneWidget,
    );
    expect(session.pageRequests, ['/buyer/orders/11']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a malformed return row suppresses the incomplete return list', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final page = _pickupOrder();
    page.props['buyerReturns'] = [
      {'id': 4, 'reference': 'RETURN-4', 'status': 'approved'},
      'not a return row',
    ];
    session.onPage = (_) async => page;
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: OrderDetailPage(
          repository: ProfileRepository(BuyerRepository(session)),
          orderId: 11,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(
        'Return details could not be confirmed. Refresh this order to check again.',
      ),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('RETURN-4'), findsNothing);
    expect(
      find.textContaining('Return details could not be confirmed'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a malformed order notice suppresses the incomplete notice list',
    (tester) async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      final page = _pickupOrder();
      page.props['orderNotices'] = [
        {
          'id': '10000000-0000-4000-8000-000000000001',
          'type': 'parcel-event',
          'data': {'title': 'Valid but incomplete update'},
          'read_at': null,
          'created_at': '2026-11-02T00:00:00Z',
          'checkpoint_id': null,
          'milestone': null,
        },
        'not a notice row',
      ];
      session.onPage = (_) async => page;
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: OrderDetailPage(
            repository: ProfileRepository(BuyerRepository(session)),
            orderId: 11,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(
          'Order updates could not be confirmed. Refresh this order to check again.',
        ),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Valid but incomplete update'), findsNothing);
      expect(
        find.textContaining('Order updates could not be confirmed'),
        findsOneWidget,
      );
      expect(find.text('Mark update read'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('repeated pickup-code taps open only one confirmation', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onPage = (_) async => _pickupOrder();
    session.onPost = (_) async => {'code': 'ABCDEF123456'};
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: OrderDetailPage(
          repository: ProfileRepository(BuyerRepository(session)),
          orderId: 11,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final showCode = tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Show my code once'),
        )
        .onPressed!;
    showCode();
    showCode();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(session.posts, isEmpty);
    final confirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Show my code once'),
    );
    expect(confirm, findsOneWidget);
    await _tap(tester, confirm);

    expect(session.posts, hasLength(1));
    expect(session.posts.single.path, '/buyer/orders/11/pickup-code');
    expect(find.text('ABCDEF123456'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a pickup claim that expires in the decision is not requested', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final page = _pickupOrder();
    session.onPage = (_) async => page;
    session.onPost = (_) async => {'code': 'ABCDEF123456'};
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: OrderDetailPage(
          repository: ProfileRepository(BuyerRepository(session)),
          orderId: 11,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.widgetWithText(FilledButton, 'Show my code once'));

    (page.props['pickupClaim'] as Map)['status'] = 'expired';
    final confirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Show my code once'),
    );
    await _tap(tester, confirm);

    expect(session.posts, isEmpty);
    expect(find.text('ABCDEF123456'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an impossible pickup expiry cannot unlock code issuance', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final page = _pickupOrder();
    final now = DateTime.now().toUtc();
    final lastDay = DateTime.utc(now.year, now.month + 1, 0).day;
    final impossibleExpiry =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${(lastDay + 1).toString().padLeft(2, '0')}T23:59:59Z';
    (page.props['pickupClaim'] as Map)['expires_at'] = impossibleExpiry;
    session.onPage = (_) async => page;
    session.onPost = (_) async => {'code': 'ABCDEF123456'};

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: OrderDetailPage(
          repository: ProfileRepository(BuyerRepository(session)),
          orderId: 11,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Show my code once'), findsNothing);
    expect(session.posts, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final until in <Object?>[
    null,
    '2026-02-30T10:00:00Z',
    DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String(),
  ]) {
    testWidgets('unconfirmed return deadline does not show request action', (
      tester,
    ) async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      final page = _pickupOrder();
      page.props['returnAvailability'] = {
        'can_request': true,
        'until': until,
        'reason': null,
      };
      session.onPage = (_) async => page;
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: OrderDetailPage(
            repository: ProfileRepository(BuyerRepository(session)),
            orderId: 11,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Request return/refund'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('a confirmed future return deadline keeps request action', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final page = _pickupOrder();
    page.props['returnAvailability'] = {
      'can_request': true,
      'until': DateTime.now()
          .add(const Duration(days: 1))
          .toUtc()
          .toIso8601String(),
      'reason': null,
    };
    session.onPage = (_) async => page;
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: OrderDetailPage(
          repository: ProfileRepository(BuyerRepository(session)),
          orderId: 11,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Request return/refund'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('malformed one-time code responses are never displayed', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onPage = (_) async => _pickupOrder();
    session.onPost = (_) async => {'code': 'NOT-A-VALID-CODE'};
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: OrderDetailPage(
          repository: ProfileRepository(BuyerRepository(session)),
          orderId: 11,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.widgetWithText(FilledButton, 'Show my code once'));
    await _tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Show my code once'),
      ),
    );

    expect(session.posts, hasLength(1));
    expect(find.text('NOT-A-VALID-CODE'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a rate-limited pickup-code request honors Retry-After', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onPage = (_) async => _pickupOrder();
    var attempts = 0;
    session.onPost = (_) async {
      attempts++;
      throw BackendException(
        'Too many attempts. Please wait before trying again.',
        status: 429,
        retryAt: DateTime.now().add(const Duration(seconds: 5)),
      );
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: OrderDetailPage(
          repository: ProfileRepository(BuyerRepository(session)),
          orderId: 11,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.widgetWithText(FilledButton, 'Show my code once'));
    await _tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Show my code once'),
      ),
    );

    final retryButtonFinder = find.ancestor(
      of: find.textContaining('Try again in'),
      matching: find.byType(FilledButton),
    );
    expect(retryButtonFinder, findsOneWidget);
    final retryButton = tester.widget<FilledButton>(retryButtonFinder);
    expect(retryButton.onPressed, isNull);
    expect(find.textContaining('Try again in'), findsOneWidget);
    expect(attempts, 1);
    expect(session.posts.single.path, '/buyer/orders/11/pickup-code');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('account change in the pickup decision sends no request', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onPage = (_) async => _pickupOrder();
    session.onPost = (_) async => {'code': 'ABCDEF123456'};
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: OrderDetailPage(
          repository: ProfileRepository(BuyerRepository(session)),
          orderId: 11,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.widgetWithText(FilledButton, 'Show my code once'));

    session.clear();
    await _tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Show my code once'),
      ),
    );

    expect(session.posts, isEmpty);
    expect(find.text('Order #PICKUP-11'), findsNothing);
    expect(find.text('ABCDEF123456'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
