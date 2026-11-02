import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/profile/inbox_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/order_detail_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:bagoo_buyer_mobile/features/products/chat_page.dart';
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
        'items': [
          {
            'id': 101,
            'quantity': 1,
            'unit_price': '100.00',
            'subtotal': '100.00',
            'sku_snapshot': 'TEST-ITEM',
            'product': null,
          },
        ],
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

class OrderActionSession extends ControlledWebSession {
  int submissions = 0;
  final submissionPaths = <String>[];
  @override
  Future<WebPage> submit(
    String path,
    Map<String, dynamic> values, {
    String method = 'POST',
    String? referer,
    List<UploadPart>? files,
  }) async {
    submissionPaths.add(path);
    submissions++;
    return orderPage(status: 'Completed');
  }
}

class CancelOrderSession extends ControlledWebSession {
  final submissionPaths = <String>[];
  final submissions = <Map<String, dynamic>>[];
  @override
  Future<WebPage> submit(
    String path,
    Map<String, dynamic> values, {
    String method = 'POST',
    String? referer,
    List<UploadPart>? files,
  }) async {
    submissionPaths.add(path);
    submissions.add(Map.of(values));
    return orderPage(status: 'Cancelled');
  }
}

class ReviewOrderSession extends ControlledWebSession {
  final submissionPaths = <String>[];
  @override
  Future<WebPage> submit(
    String path,
    Map<String, dynamic> values, {
    String method = 'POST',
    String? referer,
    List<UploadPart>? files,
  }) async {
    submissionPaths.add(path);
    final page = completedOrderWithReviewableItem();
    (page.props['order'] as Map)['items'][0]['review'] = {
      'rating': 5,
      'comment': 'Synthetic review',
    };
    page.props['flash'] = {'success': 'Review saved.'};
    return page;
  }
}

class RateLimitedReviewSession extends ReviewOrderSession {
  int attempts = 0;

  @override
  Future<WebPage> submit(
    String path,
    Map<String, dynamic> values, {
    String method = 'POST',
    String? referer,
    List<UploadPart>? files,
  }) async {
    attempts++;
    submissionPaths.add(path);
    throw BackendException(
      'Too many attempts. Please wait before trying again.',
      status: 429,
      retryAt: DateTime.now().add(const Duration(seconds: 30)),
    );
  }
}

WebPage completedOrderWithReviewableItem() {
  final page = orderPage(status: 'Completed');
  page.props['canUsePortal'] = true;
  (page.props['order'] as Map)['items'] = [
    {
      'id': 21,
      'quantity': 1,
      'unit_price': '120.00',
      'subtotal': '120.00',
      'sku_snapshot': 'Synthetic review item',
      'product': {'name': 'Synthetic review item', 'slug': 'review-item'},
    },
  ];
  return page;
}

void main() {
  testWidgets(
    'inbox conversation remains usable on a narrow screen with enlarged text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 740);
      addTearDown(tester.view.reset);
      final session = ControlledWebSession();
      addTearDown(session.close);
      final page = inbox(unread: 120);
      final conversation =
          (page.props['conversations'] as List).first as Map<String, dynamic>;
      conversation['user'] = {
        'id': 3,
        'name': 'A very long store name for the buyer conversation',
        'role': 'seller',
      };
      conversation['last_message'] = 'A long message preview that should remain readable within the available space.';
      conversation['last_time'] = 'Yesterday afternoon';
      session.onPage = (_) async => page;
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          builder: (_, child) => MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 740),
              textScaler: TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: InboxPage(
            repository: ProfileRepository(BuyerRepository(session)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('99+'), findsOneWidget);
      expect(
        find.text('A very long store name for the buyer conversation'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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

  testWidgets('rapid conversation taps open only one chat route', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onPage = (_) async => inbox();
    session.onGet = (_) async => {'messages': <dynamic>[]};
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: InboxPage(
          repository: ProfileRepository(BuyerRepository(session)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final conversationTile = find.ancestor(
      of: find.text('Store reply'),
      matching: find.byType(InkWell),
    );
    final openConversation = tester.widget<InkWell>(conversationTile).onTap!;
    openConversation();
    openConversation();
    await tester.pumpAndSettle();

    expect(session.getRequests, ['/chat/messages/3']);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ChatPage), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'inbox does not reuse an older product after a malformed message row',
    (tester) async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      final page = inbox();
      final conversation =
          (page.props['conversations'] as List).single as Map<String, dynamic>;
      conversation['user'] = {
        'id': 3,
        'name': 'Test store',
        'role': 'seller',
        'shop': {'id': 31, 'name': 'Test store'},
      };
      conversation['messages'] = [
        {
          'product': {'id': 41, 'shop_id': 31, 'name': 'Older product'},
        },
        'malformed message row',
      ];
      session.onPage = (_) async => page;
      session.onGet = (_) async => {'messages': <dynamic>[]};
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: InboxPage(
            repository: ProfileRepository(BuyerRepository(session)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Store reply'));
      await tester.pumpAndSettle();

      final chat = tester.widget<ChatPage>(find.byType(ChatPage));
      expect(chat.product, isEmpty);
      expect(session.getRequests, ['/chat/messages/3']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('inbox keeps valid product context for a seller chat', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final page = inbox();
    final conversation =
        (page.props['conversations'] as List).single as Map<String, dynamic>;
    conversation['user'] = {
      'id': 3,
      'name': 'Test store',
      'role': 'seller',
      'shop': {'id': 31, 'name': 'Test store'},
    };
    conversation['messages'] = [
      {
        'product': {'id': 41, 'shop_id': 31, 'name': 'Current product'},
      },
    ];
    session.onPage = (_) async => page;
    session.onGet = (_) async => {'messages': <dynamic>[]};
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: InboxPage(
          repository: ProfileRepository(BuyerRepository(session)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Store reply'));
    await tester.pumpAndSettle();

    final chat = tester.widget<ChatPage>(find.byType(ChatPage));
    expect(chat.product['id'], 41);
    expect(chat.product['shop_id'], 31);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('inbox ignores product context with non-text map keys', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final page = inbox();
    final conversation =
        (page.props['conversations'] as List).single as Map<String, Object>;
    conversation['user'] = {
      'id': 3,
      'name': 'Test store',
      'role': 'seller',
      'shop': {'id': 31, 'name': 'Test store'},
    };
    conversation['messages'] = [
      {
        'product': <Object, Object>{1: 'invalid product metadata'},
      },
    ];
    session.onPage = (_) async => page;
    session.onGet = (_) async => {'messages': <dynamic>[]};
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: InboxPage(
          repository: ProfileRepository(BuyerRepository(session)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Store reply'));
    await tester.pumpAndSettle();

    expect(tester.widget<ChatPage>(find.byType(ChatPage)).product, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('inbox does not truncate malformed recipient IDs', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final page = inbox();
    ((page.props['conversations'] as List).single as Map)['user'] = {
      'id': 3.5,
      'name': 'Malformed recipient',
      'role': 'seller',
    };
    session.onPage = (_) async => page;
    session.onGet = (_) async => {'messages': <dynamic>[]};
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: InboxPage(
          repository: ProfileRepository(BuyerRepository(session)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Malformed recipient'), findsNothing);
    expect(find.textContaining('Inbox could not update'), findsOneWidget);
    expect(session.getRequests, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('inbox rejects fractional unread counts instead of rounding', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final page = inbox();
    ((page.props['conversations'] as List).single as Map)['unread_count'] = 1.5;
    session.onPage = (_) async => page;
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: InboxPage(
          repository: ProfileRepository(BuyerRepository(session)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test store'), findsNothing);
    expect(find.textContaining('Inbox could not update'), findsOneWidget);
    expect(find.byType(Badge), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('inbox rejects duplicate conversation recipients', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final page = inbox();
    final conversations =
        page.props['conversations'] as List<Map<String, Object>>;
    conversations.add(Map<String, Object>.from(conversations.single));
    session.onPage = (_) async => page;
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: InboxPage(
          repository: ProfileRepository(BuyerRepository(session)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Store reply'), findsNothing);
    expect(find.textContaining('Inbox could not update'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('inbox does not stringify a malformed message preview', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final page = inbox();
    ((page.props['conversations'] as List).single as Map)['last_message'] = {
      'private': 'unexpected object',
    };
    session.onPage = (_) async => page;
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: InboxPage(
          repository: ProfileRepository(BuyerRepository(session)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Store reply'), findsNothing);
    expect(find.textContaining('Inbox could not update'), findsOneWidget);
    expect(find.textContaining('unexpected object'), findsNothing);
    expect(tester.takeException(), isNull);
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
    'order detail disables receipt confirmation for malformed item prices',
    (tester) async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      final page = orderPage(status: 'Delivered');
      page.props['canConfirmReceipt'] = true;
      ((page.props['order'] as Map)['items'] as List).single['subtotal'] =
          'not money';
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

      expect(
        find.textContaining('Purchased item details could not be confirmed'),
        findsOneWidget,
      );
      final confirmation = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirm Received'),
      );
      expect(confirmation.onPressed, isNull);
      expect(session.posts, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'order detail disables receipt confirmation for inconsistent line totals',
    (tester) async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      final page = orderPage(status: 'Delivered');
      page.props['canConfirmReceipt'] = true;
      final item = ((page.props['order'] as Map)['items'] as List).single;
      item['quantity'] = 2;
      item['subtotal'] = '100.00';
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

      expect(
        find.textContaining('Purchased item details could not be confirmed'),
        findsOneWidget,
      );
      final confirmation = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirm Received'),
      );
      expect(confirmation.onPressed, isNull);
      expect(session.posts, isEmpty);
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

  testWidgets(
    'an earlier order read cannot undo an explicitly confirmed receipt',
    (tester) async {
      final session = OrderActionSession();
      addTearDown(session.close);
      final delivered = orderPage(status: 'Delivered');
      delivered.props['canConfirmReceipt'] = true;
      session.onPage = (_) async => delivered;
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
      final pending = Completer<WebPage>();
      session.onPage = (_) => pending.future;
      await tester.pump(const Duration(seconds: 15));
      await tester.tap(
        find.widgetWithText(FilledButton, 'Confirm Received').first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Confirm Received').last,
      );
      await tester.pumpAndSettle();
      expect(session.submissions, 1);
      expect(session.submissionPaths, ['/buyer/orders/11/confirm']);
      expect(find.text('Completed'), findsOneWidget);
      session.onPage = (_) async => orderPage(status: 'Completed');
      pending.complete(delivered);
      await tester.pumpAndSettle();
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Delivered'), findsNothing);
      expect(session.submissions, 1);
      expect(session.posts, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('receipt confirmation opens one decision for rapid taps', (
    tester,
  ) async {
    final session = OrderActionSession();
    addTearDown(session.close);
    final delivered = orderPage(status: 'Delivered');
    delivered.props['canConfirmReceipt'] = true;
    session.onPage = (_) async => delivered;
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

    final onPressed = tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Confirm Received'),
        )
        .onPressed!;
    onPressed();
    onPressed();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(session.submissions, 0);
    final dialogConfirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Confirm Received'),
    );
    expect(dialogConfirm, findsOneWidget);
    tester.widget<FilledButton>(dialogConfirm).onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(session.submissions, 1);
    expect(session.submissionPaths, ['/buyer/orders/11/confirm']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('receipt confirmation stops after the buyer session changes', (
    tester,
  ) async {
    final session = OrderActionSession();
    addTearDown(session.close);
    final delivered = orderPage(status: 'Delivered');
    delivered.props['canConfirmReceipt'] = true;
    session.onPage = (_) async => delivered;
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
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm Received'));
    await tester.pumpAndSettle();

    session.clear();
    final dialogConfirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Confirm Received'),
    );
    tester.widget<FilledButton>(dialogConfirm).onPressed!();
    await tester.pumpAndSettle();

    expect(session.submissions, 0);
    expect(find.text('Order #TEST-11'), findsNothing);
    expect(
      find.textContaining('Confirm that you received order #TEST-11'),
      findsNothing,
    );
    expect(
      find.text('Your account changed. Reopen this order after signing in.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancellation form does not submit after buyer session change', (
    tester,
  ) async {
    final session = CancelOrderSession();
    addTearDown(session.close);
    final preparing = orderPage(status: 'Preparing');
    preparing.props['cancelOrderUrl'] = '/buyer/orders/11/cancel';
    preparing.props['cancellationReasons'] = ['Changed my mind'];
    session.onPage = (_) async => preparing;
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
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel order'));
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        )
        .onChanged!('Changed my mind');
    await tester.pump();

    session.clear();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel order'));
    await tester.pumpAndSettle();

    expect(session.submissionPaths, isEmpty);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('Details (optional)'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('malformed cancellation reasons cannot submit an order update', (
    tester,
  ) async {
    final session = CancelOrderSession();
    addTearDown(session.close);
    final preparing = orderPage(status: 'Preparing');
    preparing.props['cancelOrderUrl'] = '/buyer/orders/11/cancel';
    preparing.props['cancellationReasons'] = 'not-a-list';
    session.onPage = (_) async => preparing;
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
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel order'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Cancellation reasons could not be confirmed. Refresh this order before trying again.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel order'));
    await tester.pumpAndSettle();
    expect(session.submissionPaths, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancellation reasons do not show a partial list', (
    tester,
  ) async {
    final session = CancelOrderSession();
    addTearDown(session.close);
    final preparing = orderPage(status: 'Preparing');
    preparing.props['cancelOrderUrl'] = '/buyer/orders/11/cancel';
    preparing.props['cancellationReasons'] = ['Changed my mind', 17];
    session.onPage = (_) async => preparing;
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
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel order'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Cancellation reasons could not be confirmed. Refresh this order before trying again.',
      ),
      findsOneWidget,
    );
    expect(session.submissionPaths, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('duplicate cancellation reasons do not crash on selection', (
    tester,
  ) async {
    final session = CancelOrderSession();
    addTearDown(session.close);
    final preparing = orderPage(status: 'Preparing');
    preparing.props['cancelOrderUrl'] = '/buyer/orders/11/cancel';
    preparing.props['cancellationReasons'] = [
      'Changed my mind',
      'Changed my mind',
    ];
    session.onPage = (_) async => preparing;
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
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel order'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Cancellation reasons could not be confirmed. Refresh this order before trying again.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expect(session.submissionPaths, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('confirmed cancellation returns to the updated order', (
    tester,
  ) async {
    final session = CancelOrderSession();
    addTearDown(session.close);
    final preparing = orderPage(status: 'Preparing');
    preparing.props['cancelOrderUrl'] = '/buyer/orders/11/cancel';
    preparing.props['cancellationReasons'] = ['Changed my mind'];
    session.onPage = (_) async => preparing;
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
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel order'));
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        )
        .onChanged!('Changed my mind');
    await tester.pump();
    session.onPage = (_) async => orderPage(status: 'Cancelled');
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel order'));
    await tester.pumpAndSettle();

    expect(session.submissionPaths, ['/buyer/orders/11/cancel']);
    expect(find.text('Cancelled'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancellation details reject markup before submission', (
    tester,
  ) async {
    final session = CancelOrderSession();
    addTearDown(session.close);
    final preparing = orderPage(status: 'Preparing');
    preparing.props['cancelOrderUrl'] = '/buyer/orders/11/cancel';
    preparing.props['cancellationReasons'] = ['Other reason'];
    session.onPage = (_) async => preparing;
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
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel order'));
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        )
        .onChanged!('Other reason');
    await tester.pump();
    await tester.enterText(
      find.byType(TextFormField).last,
      '<script>alert(1)</script>',
    );
    final submit = find.widgetWithText(FilledButton, 'Cancel order');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(session.submissionPaths, isEmpty);
    expect(
      find.text(
        'Use plain text with letters or numbers, without markup or hidden characters.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('review form does not submit after buyer session change', (
    tester,
  ) async {
    final session = ReviewOrderSession();
    addTearDown(session.close);
    final completed = completedOrderWithReviewableItem();
    session.onPage = (_) async => completed;
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
    final reviewLink = find.text('Rate & review purchased item');
    await tester.ensureVisible(reviewLink);
    await tester.pumpAndSettle();
    await tester.tap(reviewLink);
    await tester.pumpAndSettle();
    final fifthStar = find.byTooltip('Rate 5 out of 5');
    await tester.ensureVisible(fifthStar);
    await tester.pumpAndSettle();
    await tester.tap(fifthStar);
    await tester.pump();

    session.clear();
    final submitReview = find.widgetWithText(FilledButton, 'Submit review');
    await tester.ensureVisible(submitReview);
    await tester.pumpAndSettle();
    await tester.tap(submitReview);
    await tester.pumpAndSettle();

    expect(session.submissionPaths, isEmpty);
    expect(find.text('Synthetic review item'), findsNothing);
    expect(
      find.text(
        'Your buyer account changed or access ended. Reopen this order from your purchases.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('saved review returns to the updated purchase', (tester) async {
    final session = ReviewOrderSession();
    addTearDown(session.close);
    session.onPage = (_) async => completedOrderWithReviewableItem();
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
    final reviewLink = find.text('Rate & review purchased item');
    await tester.ensureVisible(reviewLink);
    await tester.pumpAndSettle();
    await tester.tap(reviewLink);
    await tester.pumpAndSettle();
    final fifthStar = find.byTooltip('Rate 5 out of 5');
    await tester.ensureVisible(fifthStar);
    await tester.pumpAndSettle();
    await tester.tap(fifthStar);
    await tester.pump();
    final reviewed = completedOrderWithReviewableItem();
    (reviewed.props['order'] as Map)['items'][0]['review'] = {
      'rating': 5,
      'comment': 'Synthetic review',
    };
    session.onPage = (_) async => reviewed;
    final submitReview = find.widgetWithText(FilledButton, 'Submit review');
    await tester.ensureVisible(submitReview);
    await tester.pumpAndSettle();
    await tester.tap(submitReview);
    await tester.pumpAndSettle();

    expect(session.submissionPaths, ['/buyer/reviews']);
    expect(find.textContaining('Your rating: 5 / 5'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'rate-limited review keeps its draft and blocks immediate retry',
    (tester) async {
      final session = RateLimitedReviewSession();
      addTearDown(session.close);
      session.onPage = (_) async => completedOrderWithReviewableItem();
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
      final reviewLink = find.text('Rate & review purchased item');
      await tester.ensureVisible(reviewLink);
      await tester.pumpAndSettle();
      await tester.tap(reviewLink);
      await tester.pumpAndSettle();
      final fifthStar = find.byTooltip('Rate 5 out of 5');
      await tester.ensureVisible(fifthStar);
      await tester.pumpAndSettle();
      await tester.tap(fifthStar);
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Your review (optional)'),
        'A verified buyer review.',
      );
      await tester.ensureVisible(find.text('Submit review'));
      await tester.tap(find.text('Submit review'));
      await tester.pumpAndSettle();

      final retryFinder = find.ancestor(
        of: find.textContaining('Retry review in'),
        matching: find.byType(FilledButton),
      );
      expect(retryFinder, findsOneWidget);
      expect(tester.widget<FilledButton>(retryFinder).onPressed, isNull);
      expect(session.attempts, 1);
      expect(session.submissionPaths, ['/buyer/reviews']);
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Your review (optional)'),
            )
            .controller!
            .text,
        'A verified buyer review.',
      );
      expect(find.textContaining('Too many attempts'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final invalidRating in [4.5, '4']) {
    testWidgets(
      'editing a review does not round or cast malformed saved rating: $invalidRating',
      (tester) async {
        final session = ReviewOrderSession();
        addTearDown(session.close);
        final completed = completedOrderWithReviewableItem();
        final item =
            ((completed.props['order'] as Map)['items'] as List).first as Map;
        item['review'] = {
          'id': 31,
          'rating': invalidRating,
          'comment': 'Existing synthetic review',
          'edit_url': '/buyer/reviews/31',
        };
        session.onPage = (_) async => completed;
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
        final editReview = find.text('Edit your review');
        await tester.ensureVisible(editReview);
        await tester.pumpAndSettle();
        await tester.tap(editReview);
        await tester.pumpAndSettle();

        final fourthStar = tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Rate 4 out of 5'),
            matching: find.byType(IconButton),
          ),
        );
        expect((fourthStar.icon as Icon).icon, Icons.star_border_rounded);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('purchase review rejects hidden text before submission', (
    tester,
  ) async {
    final session = ReviewOrderSession();
    addTearDown(session.close);
    session.onPage = (_) async => completedOrderWithReviewableItem();
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
    final reviewLink = find.text('Rate & review purchased item');
    await tester.ensureVisible(reviewLink);
    await tester.pumpAndSettle();
    await tester.tap(reviewLink);
    await tester.pumpAndSettle();
    final fifthStar = find.byTooltip('Rate 5 out of 5');
    await tester.ensureVisible(fifthStar);
    await tester.pumpAndSettle();
    await tester.tap(fifthStar);
    await tester.pump();
    await tester.enterText(
      find.byType(TextFormField).last,
      'Great quality${String.fromCharCode(0x200b)}!',
    );
    final submit = find.widgetWithText(FilledButton, 'Submit review');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(session.submissionPaths, isEmpty);
    expect(
      find.text(
        'Use plain text with letters or numbers, without markup or hidden characters.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
