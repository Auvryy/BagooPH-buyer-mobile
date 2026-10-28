import 'dart:async';
import 'dart:convert';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/order_result_page.dart';
import 'package:bagoo_buyer_mobile/features/products/chat_page.dart';
import 'package:bagoo_buyer_mobile/features/products/product_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/order_journey.dart';
import 'package:bagoo_buyer_mobile/features/profile/return_codes.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart';

class ChatRepository extends FakeBuyerRepository {
  final sent = <Map<String, dynamic>>[];
  bool fail = true;
  @override
  Future<List<Map<String, dynamic>>> messages(int receiver) async => [
    {
      'id': 1,
      'sender_id': 3,
      'message': 'Hello',
      'product': product(1),
      'created_at': '2026-10-28T00:00:00Z',
    },
  ];
  @override
  Future<Map<String, dynamic>> sendMessage(
    Map<String, dynamic> values, {
    List<UploadPart>? files,
  }) async {
    sent.add(Map.of(values));
    if (fail) throw const BackendException('Message result uncertain.');
    return {
      'id': 2,
      'sender_id': 7,
      'message': values['message'],
      'created_at': '2026-10-28T00:01:00Z',
    };
  }
}

void main() {
  test(
    'repeated scans keep separate notices unless their checkpoint matches',
    () {
      final entries = buyerJourneyEntries(
        {
          'history': [
            {
              'id': 1,
              'type': 'out_for_delivery',
              'created_at': '2026-10-27T00:00:00Z',
            },
            {
              'id': 2,
              'type': 'out_for_delivery',
              'created_at': '2026-10-28T00:00:00Z',
            },
          ],
        },
        [
          {
            'id': 'first',
            'type': 'order-event',
            'milestone': 'out_for_delivery',
            'checkpoint_id': 2,
          },
          {
            'id': 'ambiguous',
            'type': 'order-event',
            'milestone': 'out_for_delivery',
          },
          {
            'id': 'first',
            'type': 'order-event',
            'milestone': 'out_for_delivery',
            'checkpoint_id': 2,
          },
        ],
      );
      expect(entries, hasLength(3));
      expect(mapsOf(entries[1]['notices']).single['id'], 'first');
      expect(entries.last['checkpoint'], isNull);
      expect(mapsOf(entries.last['notices']).single['id'], 'ambiguous');
    },
  );

  test('completed server state does not fabricate missing packing or shipping scans', () {
    final milestones = buyerMilestones(
      {
        'commercial_status': 'completed',
        'placed_at': '2026-10-27T00:00:00Z',
        'history': [
          {'id': 5, 'type': 'completed'},
        ],
      },
      {
        'items': [
          {'id': 1},
        ],
      },
    );
    expect(milestones[1].recorded, isFalse);
    expect(milestones[1].missing, isTrue);
    expect(milestones[2].complete, isFalse);
    expect(milestones.last.current, isTrue);
    expect(milestones[3].recorded, isFalse);
  });

  testWidgets('both return symbols encode only the separate return barcode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReturnCodes(code: 'BRT-TEST1234567890')),
      ),
    );
    final symbols = tester.widgetList<BarcodeWidget>(
      find.byType(BarcodeWidget),
    );
    expect(symbols, hasLength(2));
    expect(
      symbols.every(
        (symbol) => utf8.decode(symbol.data) == 'BRT-TEST1234567890',
      ),
      isTrue,
    );
  });

  testWidgets(
    'payment deadline disables confirmation while a status refresh is pending',
    (tester) async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      var now = DateTime.utc(2026, 10, 28, 8);
      final payment = {
        'id': 41,
        'status': 'pending',
        'can_pay': true,
        'amount_cents': 125000,
        'expires_at': now.add(const Duration(minutes: 1)).toIso8601String(),
      };
      final page = WebPage('Wallet/Payment', {
        'auth': {'user': buyer},
        'payment': payment,
      });
      final refresh = Completer<WebPage>();
      session.onPage = (_) => refresh.future;
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: OrderResultPage(
            repository: BuyerRepository(session),
            initial: page,
            now: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Confirm payment'), findsOneWidget);
      now = now.add(const Duration(minutes: 2));
      await tester.pump(const Duration(minutes: 2));
      expect(find.text('Confirm payment'), findsNothing);
      expect(session.pageRequests, ['/wallet/payments/41']);
      expect(session.posts, isEmpty);
      refresh.complete(page);
      await tester.pumpAndSettle();
      expect(find.text('Status: pending'), findsOneWidget);
      expect(find.text('Confirm payment'), findsNothing);
      expect(session.posts, isEmpty);
    },
  );

  testWidgets(
    'chat questions remain editable and retries keep their original request key',
    (tester) async {
      final repo = ChatRepository();
      addTearDown(repo.session.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: ChatPage(
            repository: repo,
            userId: 7,
            receiverId: 3,
            product: {...product(1), 'shop_id': 2},
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<ActionChip>(
            find.widgetWithText(ActionChip, 'Is this available?'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      final draft = find.widgetWithText(TextField, 'Message');
      expect(
        tester.widget<TextField>(draft).controller!.text,
        'Is this available?',
      );
      expect(repo.sent, isEmpty);
      await tester.enterText(draft, 'Is this available in blue?');
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Send message',
            ),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(draft).controller!.text,
        'Is this available in blue?',
      );
      repo.fail = false;
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Send message',
            ),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(repo.sent, hasLength(2));
      expect(repo.sent.first['request_key'], repo.sent.last['request_key']);
      expect(repo.sent.last['product_id'], 1);
      expect(tester.widget<TextField>(draft).controller!.text, isEmpty);
      await tester.tap(find.text('Everyday bag 1').first);
      await tester.pumpAndSettle();
      expect(find.byType(ProductPage), findsOneWidget);
    },
  );

  testWidgets(
    'chat composer remains scrollable with keyboard and 200 percent text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 375);
      addTearDown(tester.view.reset);
      final repo = ChatRepository();
      addTearDown(repo.session.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(600, 375),
              viewInsets: EdgeInsets.only(bottom: 150),
              textScaler: TextScaler.linear(2),
            ),
            child: ChatPage(
              repository: repo,
              userId: 7,
              receiverId: 3,
              product: product(1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Send message',
        ),
        findsOneWidget,
      );
    },
  );
}
