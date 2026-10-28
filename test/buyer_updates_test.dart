import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/profile/inbox_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/order_detail_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart';

WebPage inbox({int unread = 1, int owner = 7}) => WebPage('Buyer/Messages', {
  'auth': {
    'user': {...buyer, 'id': owner},
  },
  'conversations': [
    {
      'user': {'id': 3, 'name': 'Test store', 'role': 'seller'},
      'last_message': 'Store reply',
      'last_time': 'Now',
      'unread_count': unread,
      'messages': [],
    },
  ],
});

WebPage orderPage({String status = 'Preparing', int owner = 7}) =>
    WebPage('Buyer/OrderDetail', {
      'auth': {
        'user': {...buyer, 'id': owner},
      },
      'order': {
        'id': 11,
        'order_number': 'TEST-11',
        'status': status.toLowerCase(),
        'created_at': '2026-10-28T00:00:00Z',
        'items': [],
        'tracking': {
          'status_label': status,
          'stage_label': 'Recorded stage',
          'history': [],
        },
      },
      'canConfirmReceipt': false,
      'canUsePortal': false,
      'orderNotices': [],
    });

void main() {
  testWidgets('inbox updates unread badges while preserving search', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    var unread = 1;
    session.onPage = (_) async => inbox(unread: unread);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: InboxPage(
          repository: ProfileRepository(BuyerRepository(session)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'store');
    unread = 4;
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Badge, '4'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'store',
    );
    expect(session.pageRequests, ['/buyer/messages', '/buyer/messages']);
    expect(session.posts, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('inbox never retains conversations from a switched owner', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    var owner = 7;
    session.onPage = (_) async => inbox(owner: owner);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: InboxPage(
          repository: ProfileRepository(BuyerRepository(session)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test store'), findsOneWidget);
    owner = 8;
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(find.text('Test store'), findsNothing);
    expect(find.textContaining('unavailable for this account'), findsOneWidget);
    await tester.pump(const Duration(minutes: 5));
    expect(session.pageRequests, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'order status refreshes from the server without taking any action',
    (tester) async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      var status = 'Preparing';
      session.onPage = (_) async => orderPage(status: status);
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
      expect(find.text('Preparing'), findsOneWidget);
      status = 'Out for delivery';
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.text('Out for delivery'), findsOneWidget);
      expect(find.text('Preparing'), findsNothing);
      expect(session.posts, isEmpty);
      expect(session.pageRequests, ['/buyer/orders/11', '/buyer/orders/11']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'order network failures retain confirmed state; revoked access clears it',
    (tester) async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      session.onPage = (_) async => orderPage();
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
      session.onPage = (_) async =>
          throw const BackendException('Connection unavailable.');
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.text('Preparing'), findsOneWidget);
      expect(find.textContaining('updates are delayed'), findsOneWidget);
      session.onPage = (_) async =>
          throw const BackendException('Order access revoked.', status: 403);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('Preparing'), findsNothing);
      expect(find.text('Order access revoked.'), findsOneWidget);
      await tester.pump(const Duration(minutes: 5));
      expect(session.pageRequests, hasLength(3));
      expect(session.posts, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'late order responses after identity clearing reveal no private state',
    (tester) async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      final pending = Completer<WebPage>();
      session.onPage = (_) => pending.future;
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: OrderDetailPage(
            repository: ProfileRepository(BuyerRepository(session)),
            orderId: 11,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1));
      session.clear();
      pending.complete(orderPage());
      await tester.pumpAndSettle();
      expect(find.text('Preparing'), findsNothing);
      expect(find.textContaining('could not be confirmed'), findsOneWidget);
      await tester.pump(const Duration(minutes: 5));
      expect(session.pageRequests, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
