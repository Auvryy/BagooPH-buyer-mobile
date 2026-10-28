import 'dart:io';
import 'dart:ui' as ui;

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/auth/recovery_page.dart';
import 'package:bagoo_buyer_mobile/features/auth/register_page.dart';
import 'package:bagoo_buyer_mobile/features/notifications/notifications_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/order_detail_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:bagoo_buyer_mobile/features/profile/returns_page.dart';
import 'package:bagoo_buyer_mobile/features/support/support_assistant_page.dart';
import 'package:bagoo_buyer_mobile/features/tracking/parcel_tracking_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart';
import 'support/tracking_fixtures.dart';

WebPage _reviewPage(String path) => switch (Uri.parse(path).path) {
  '/notifications' => WebPage('Notifications/Index', {
    'auth': {'user': buyer},
    'errors': {},
    'portal': 'buyer',
    'available': true,
    'filter': 'all',
    'notices': {
      'data': [
        {
          'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'type': 'order-event',
          'created_at': '2026-10-28T08:00:00Z',
          'read_at': null,
          'href': null,
          'data': {
            'title': 'Order update',
            'body': 'Your order is being prepared. Check its recorded details for the next delivery step.',
          },
        },
      ],
      'current_page': 1,
      'last_page': 2,
    },
    'readSnapshot': {'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'count': 1},
    'notificationSummary': {'available': true, 'unread': 1},
  }),
  '/track' => publicTrackingPage(),
  '/buyer/orders/11' => WebPage('Buyer/OrderDetail', {
    'auth': {'user': buyer},
    'order': {
      'id': 11,
      'order_number': 'TEST-11',
      'status': 'preparing',
      'created_at': '2026-10-28T00:00:00Z',
      'items': [
        {
          'id': 101,
          'product': product(1),
          'quantity': 1,
          'unit_price': 1200,
          'subtotal': 1200,
        },
      ],
      'subtotal': 1200,
      'shipping_fee': 50,
      'voucher_discount': 0,
      'total_amount': 1250,
      'payment_method': 'cod',
      'payment_status': 'unpaid',
      'tracking': {
        'status_label': 'Preparing',
        'stage_label': 'The seller is preparing your parcel',
        'custodian': 'Seller',
        'next_step': 'Wait for the recorded pickup handover.',
        'history': [],
      },
    },
    'canConfirmReceipt': false,
    'canUsePortal': false,
    'orderNotices': [],
  }),
  '/buyer-returns/4' => WebPage('Returns/Show', {
    'auth': {'user': buyer},
    'returnCase': {
      'id': 4,
      'reference': 'RETURN-TEST-4',
      'order': {'order_number': 'TEST-11'},
      'status': 'requested',
      'reason': 'Item damaged on arrival',
      'description': 'The strap stitching is damaged. Photos have been provided for review.',
      'items': [
        {
          'purchase': {
            'name': 'Everyday Carry Canvas Tote',
            'color': 'Natural',
          },
          'quantity': 1,
        },
      ],
      'actions': [],
      'evidence': [],
    },
  }),
  '/register' => const WebPage('Auth/Register', {
    'birthDateLimits': {'adult_maximum': '2008-10-28', 'today': '2026-10-28'},
    'policies': {
      'terms_version': '2026-10-12',
      'privacy_version': '2026-10-12',
      'terms_url': '/terms/2026-10-12',
      'privacy_url': '/privacy/2026-10-12',
    },
  }),
  _ => throw StateError('Unexpected review read: $path'),
};

Widget _screen(String name, BuyerRepository repo) => switch (name) {
  'notifications' => NotificationsPage(repository: repo, ownerId: 7),
  'tracking' => ParcelTrackingPage(repository: repo, initialNumber: 'BAGOO-1'),
  'support' => SupportAssistantPage(
    repository: repo,
    user: buyer,
    available: true,
  ),
  'order' => OrderDetailPage(repository: ProfileRepository(repo), orderId: 11),
  'return' => ReturnsPage(repository: ProfileRepository(repo), caseId: 4),
  'register' => RegisterPage(
    repository: repo,
    onBack: () {},
    onBrowse: () {},
    onComplete: (_) {},
  ),
  _ => RecoveryPage(
    repository: repo,
    onBack: () {},
    onBrowse: () {},
    onComplete: () {},
  ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Plus Jakarta Sans',
    )..addFont(rootBundle.load('assets/fonts/PlusJakartaSans.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  const export = bool.fromEnvironment('BAGOO_RENDER_REVIEW');
  const phase = String.fromEnvironment(
    'BAGOO_REVIEW_PHASE',
    defaultValue: 'journeys',
  );
  for (final entry in const {
    'notifications': 'Order update',
    'tracking': 'Delivered · awaiting buyer confirmation',
    'support': 'Hi! Ask me about Bagoo shopping, checkout, orders, payments, delivery, or returns.',
    'order': 'Preparing',
    'return': 'RETURN-TEST-4',
    'register': 'Account details',
    'recovery': 'Reset Password',
  }.entries) {
    for (final scene in [
      (const Size(320, 740), 1.0, 0.0),
      (const Size(375, 812), 1.0, 0.0),
      (const Size(700, 375), 2.0, 120.0),
      (const Size(1024, 768), 1.0, 0.0),
    ]) {
      testWidgets(
        '${entry.key} renders its recorded state at ${scene.$1}, text ${scene.$2}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = scene.$1;
          addTearDown(tester.view.reset);
          final session = ControlledWebSession()
            ..onPage = (path) async => _reviewPage(path);
          addTearDown(session.close);
          final repo = BuyerRepository(session);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                theme: BagooTheme.light,
                debugShowCheckedModeBanner: false,
                home: MediaQuery(
                  data: MediaQueryData(
                    size: scene.$1,
                    textScaler: TextScaler.linear(scene.$2),
                    viewInsets: EdgeInsets.only(bottom: scene.$3),
                    disableAnimations: true,
                  ),
                  child: _screen(entry.key, repo),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final intended = find.text(entry.value);
          if (intended.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              intended,
              160,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
          }
          expect(intended, findsOneWidget);
          if (entry.key == 'tracking' && scene.$1.width == 375) {
            expect(tester.getRect(intended).bottom, lessThan(500));
          }
          expect(find.textContaining('HIDDEN'), findsNothing);
          expect(session.posts, isEmpty);
          if (export) {
            if (entry.key == 'register' || entry.key == 'recovery') {
              await tester.runAsync(
                () => precacheImage(
                  const AssetImage('assets/branding/bagoo-mark.png'),
                  tester.element(find.byType(Scaffold).first),
                ),
              );
              await tester.pumpAndSettle();
            }
            await tester.runAsync(() async {
              final render =
                  boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final rendered = await render.toImage();
              final bytes = await rendered.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory('.git/buyer-design/$phase');
              await directory.create(recursive: true);
              await File(
                '${directory.path}/${entry.key}_${scene.$1.width.toInt()}_${scene.$2}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              rendered.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox.shrink());
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
