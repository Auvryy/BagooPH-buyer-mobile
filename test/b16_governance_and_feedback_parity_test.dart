import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/order_result_page.dart';
import 'package:bagoo_buyer_mobile/features/products/product_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/account_status_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/order_detail_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:bagoo_buyer_mobile/features/profile/purchases_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/account_fixtures.dart';
import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart';

class _SubmitSession extends ControlledWebSession {
  Future<WebPage> Function(String path, Map<String, dynamic> body)? onSubmit;

  @override
  Future<WebPage> submit(
    String path,
    Map<String, dynamic> values, {
    String method = 'POST',
    List<UploadPart>? files,
    String? referer,
  }) async {
    if (onSubmit == null) {
      throw StateError('Unexpected submit: $method $path');
    }
    return onSubmit!(path, values);
  }
}

class _SingleProductRepository extends FakeBuyerRepository {
  _SingleProductRepository(this._page);
  final WebPage _page;

  @override
  Future<WebPage> product(String slug) async => _page;
}

void main() {
  testWidgets(
    'ProductPage renders excluded courier issue pill on excluded reviews',
    (tester) async {
      final page = productPage(
        signedIn: true,
        override: {
          'reviews_summary': {
            'average': 5.0,
            'count': 1,
            'breakdown': {'5': 1, '4': 0, '3': 0, '2': 0, '1': 0},
          },
          'reviews': [
            {
              'id': 88,
              'rating': 1,
              'comment': 'Rider arrived late at night',
              'verified_purchase': true,
              'score_excluded': true,
              'moderation_status': 'excluded_courier_issue',
              'created_at': '2026-10-28T00:00:00Z',
              'buyer': {'name': 'Maria'},
            },
          ],
        },
      );
      final repository = _SingleProductRepository(page);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: ProductPage(repository: repository, slug: 'item'),
        ),
      );
      await tester.pumpAndSettle();

      final pill = find.text('Excluded from product score (Delivery issue)');
      await tester.scrollUntilVisible(
        pill,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(pill, findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'AccountStatusPage renders penalties and sanctions and submits settle and appeal',
    (tester) async {
      final session = _SubmitSession();
      addTearDown(session.close);
      session.onPage = (_) async => WebPage('Auth/AccountStatus', {
        'auth': {'user': buyer},
        'status': {
          'title': 'Account status',
          'message': 'Review open items.',
          'account': {
            'id': 7,
            'name': 'Buyer',
            'email': 'buyer@bagoo.ph',
            'role': 'buyer',
            'status': 'active',
            'kyc_status': 'approved',
          },
          'sources': [],
          'requests': [],
          'unpaid_penalties': [
            {
              'id': 9,
              'reference': 'PEN-900',
              'outstanding_cents': 15000,
              'reason': 'Unpaid return adjustment',
              'evidence_summary': 'Return weight variance',
            },
          ],
          'active_sanctions': [
            {
              'id': 4,
              'reference': 'SAN-400',
              'scope': 'cod_restricted',
              'reason': 'Multiple COD refusals',
              'evidence_summary': '3 failed COD deliveries',
              'auto_release_on_debt_clear': true,
              'appeals': [],
            },
          ],
        },
      });
      final submittedPaths = <String>[];
      Map<String, dynamic>? appealBody;
      session.onSubmit = (path, body) async {
        submittedPaths.add(path);
        if (path.endsWith('/appeal')) appealBody = body;
        return WebPage('Auth/AccountStatus', {
          'auth': {'user': buyer},
          'flash': {'success': 'Recorded update.'},
        });
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: AccountStatusPage(repository: BuyerRepository(session)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unpaid Platform Obligations'), findsOneWidget);
      expect(find.text('PEN-900'), findsOneWidget);
      expect(find.text('Cash on Delivery (COD) Restricted'), findsOneWidget);

      await tester.ensureVisible(find.text('Settle via Bagoo Wallet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settle via Bagoo Wallet'));
      await tester.pumpAndSettle();
      expect(submittedPaths, contains('/account/financial-penalties/9/settle'));

      await tester.ensureVisible(find.text('Appeal Decision'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appeal Decision'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Explain why this decision should be reviewed',
        ),
        'Address was corrected with rider confirmation.',
      );
      await tester.ensureVisible(find.text('Submit Appeal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit Appeal'));
      await tester.pumpAndSettle();

      expect(
        submittedPaths,
        contains('/account/enforcement-sanctions/4/appeal'),
      );
      expect(
        appealBody?['reason'],
        'Address was corrected with rider confirmation.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'OrderDetailPage renders ETA, sanctions, safety check-in, courier feedback, and review appeal',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = _SubmitSession();
      addTearDown(session.close);

      WebPage buildOrderPage({Map<String, dynamic>? feedback}) =>
          WebPage('Buyer/OrderDetail', {
            'auth': {'user': buyer},
            'order': {
              'id': 11,
              'order_number': 'ORD-11',
              'status': 'completed',
              'created_at': '2026-10-28T00:00:00Z',
              'subtotal': 100.0,
              'shipping_fee': 50.0,
              'voucher_discount': 0.0,
              'total_amount': 150.0,
              'payment_method': 'wallet',
              'payment_status': 'paid',
              'items': [
                {
                  'id': 101,
                  'quantity': 1,
                  'unit_price': 100.0,
                  'subtotal': 100.0,
                  'sku_snapshot': 'SKU-1',
                  'product': null,
                  'review': {
                    'id': 31,
                    'rating': 2,
                    'comment': 'Box was dented by courier',
                    'moderation_status': 'excluded_courier_issue',
                    'moderation_reason': 'Feedback concerns delivery handling',
                    'appeal_url': '/buyer/reviews/31/appeal',
                  },
                },
              ],
              'tracking': {
                'status_label': 'Delivered',
                'stage_label': 'Delivered to buyer',
                'custodian': 'Buyer',
                'responsible': 'Buyer',
                'next_step': 'Completed.',
                'dispatch_delay_label': 'Dispatch slightly delayed by weather',
                'eta': {
                  'status_label': 'On time',
                  'label': 'Nov 18 - Nov 20',
                  'pause_notice': 'Paused during typhoon warning.',
                  'delay_notice': 'Includes 1 buffer day.',
                },
                'history': [],
              },
            },
            'canConfirmReceipt': false,
            'canUsePortal': true,
            'orderNotices': [],
            'buyerReturns': [],
            'activeSanctions': [
              {
                'id': 5,
                'reference': 'SAN-500',
                'scope': 'warning',
                'reason': 'Late dispute filing notice',
                'appeals': [],
              },
            ],
            'safetyCheckinSignals': [
              {
                'id': 55,
                'reference': 'SIG-55',
                'summary': 'Confirm all payment stayed inside Bagoo.',
                'buyer_checkin_response': null,
              },
            ],
            'deliveryFeedback': feedback,
            'deliveryFeedbackUrl': '/buyer/deliveries/22/feedback',
          });

      session.onPage = (_) async => buildOrderPage();
      final submitted = <String>[];
      session.onSubmit = (path, body) async {
        submitted.add(path);
        return buildOrderPage(
          feedback: path == '/buyer/deliveries/22/feedback'
              ? {
                  'id': 77,
                  'rating': 5,
                  'timeliness_rating': 5,
                  'handling_rating': 5,
                  'communication_rating': 5,
                  'comment': body['comment'],
                  'tags': body['tags'],
                }
              : null,
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

      expect(find.text('Dispatch slightly delayed by weather'), findsOneWidget);
      expect(find.text('Estimated delivery (On time)'), findsOneWidget);
      expect(find.text('Nov 18 - Nov 20'), findsOneWidget);
      expect(
        find.text('Account Restrictions Affecting Checkout or Reviews'),
        findsOneWidget,
      );

      final mainScroll = find.byType(Scrollable).first;
      final checkinBtn = find.text('Everything is normal on Bagoo');
      await tester.scrollUntilVisible(checkinBtn, 300, scrollable: mainScroll);
      await tester.pumpAndSettle();
      await tester.tap(checkinBtn);
      await tester.pumpAndSettle();
      expect(submitted, contains('/buyer/safety-checkins/55'));

      final submitCourier = find.text('Submit Courier Feedback');
      await tester.scrollUntilVisible(
        submitCourier,
        300,
        scrollable: mainScroll,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Fast delivery'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fast delivery'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(submitCourier);
      await tester.pumpAndSettle();
      await tester.tap(submitCourier);
      await tester.pumpAndSettle();
      expect(submitted, contains('/buyer/deliveries/22/feedback'));
      expect(find.text('Edit once'), findsOneWidget);

      final appealBtn = find.text('Appeal moderation decision');
      await tester.scrollUntilVisible(appealBtn, 300, scrollable: mainScroll);
      await tester.pumpAndSettle();
      expect(
        find.text('Excluded from Product Rating (Delivery Issue)'),
        findsOneWidget,
      );
      await tester.tap(appealBtn);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Explain why this review should be restored',
        ),
        'Inner item seal was broken before shipping.',
      );
      await tester.ensureVisible(find.text('Submit appeal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit appeal'));
      await tester.pumpAndSettle();
      expect(submitted, contains('/buyer/reviews/31/appeal'));

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'PurchasesSection renders dispatch_delay_label and ETA, and OrderResultPage renders shipment_finances links',
    (tester) async {
      final session = _SubmitSession();
      addTearDown(session.close);
      final repo = ProfileRepository(BuyerRepository(session));
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: Scaffold(
            body: PurchasesSection(
              repository: repo,
              page: WebPage('Buyer/Profile', {
                ...accountPage().props,
                'currentOrderStatus': 'all',
                'orders': {
                  'data': [
                    {
                      'id': 11,
                      'order_number': 'ORD-202',
                      'status': 'in_transit',
                      'total_amount': 250.0,
                      'created_at': '2026-10-28T00:00:00Z',
                      'tracking': {
                        'status_label': 'In transit',
                        'dispatch_delay_label': 'Delay queued at hub',
                        'eta': {'label': 'Nov 18 - Nov 20'},
                      },
                      'items': [
                        {
                          'id': 1,
                          'quantity': 1,
                          'unit_price': 250.0,
                          'subtotal': 250.0,
                          'sku_snapshot': 'ITEM-1',
                        },
                      ],
                    },
                  ],
                  'current_page': 1,
                  'last_page': 1,
                },
              }),
              onQuery: (_, _) {},
              reload: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delay queued at hub'), findsOneWidget);
      expect(find.text('ETA: Nov 18 - Nov 20'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: OrderResultPage(
            repository: BuyerRepository(session),
            initial: WebPage('Wallet/Payment', {
              'auth': {'user': buyer},
              'payment': {
                'id': 41,
                'order_number': 'ORD-41',
                'reference': 'WLT-41',
                'status': 'paid',
                'can_pay': false,
                'amount_cents': 125000,
                'balance_cents': 500000,
                'expires_at': '2030-01-01T00:00:00Z',
                'shipment_finances': {
                  'records': [
                    {
                      'id': 100,
                      'reference': 'SRC-100',
                      'kind': 'shipping_overcharge',
                      'active': true,
                      'return_reference': null,
                      'href': '/shipment-finances/100',
                    },
                  ],
                  'histories': [],
                },
              },
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shipping review'), findsOneWidget);
      expect(find.text('SRC-100'), findsOneWidget);
      expect(find.text('Review finances'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
