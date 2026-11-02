import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/order_result_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/purchases_section.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_widgets.dart';
import 'package:bagoo_buyer_mobile/features/profile/wallet_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/account_fixtures.dart';
import 'support/fake_buyer_repository.dart' show buyer;
import 'support/return_fixtures.dart';

Map<String, dynamic> _walletTransaction({
  int id = 1,
  Object? reference = 'WLT-SYNTHETIC',
  Object? createdAt = '2026-10-28T00:00:00Z',
  Object? orderId,
}) => {
  'id': id,
  'reference': reference,
  'kind': 'purchase',
  'delta_cents': -100,
  'balance_after_cents': 200,
  'reason': 'Synthetic wallet purchase',
  'created_at': createdAt,
  'order_id': orderId,
};

Map<String, dynamic> _walletCreditRequest({
  int id = 1,
  Object? reference = 'WCR-SYNTHETIC',
  Object? createdAt = '2026-10-28T00:00:00Z',
}) => {
  'id': id,
  'reference': reference,
  'amount_cents': 2500,
  'reason': 'Synthetic credit request',
  'status': 'pending',
  'review_reason': null,
  'created_at': createdAt,
  'reviewed_at': null,
};

void main() {
  Widget walletApp(AccountFixtureRepository repository, WebPage page) =>
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(
          body: WalletSection(
            repository: repository,
            page: page,
            reload: () async {},
            onPage: (_) {},
            onOrder: (_) {},
          ),
        ),
      );

  WebPage walletPage(Map<String, dynamic> overrides) {
    final page = accountPage();
    page.props['wallet'] = {
      ...Map<String, dynamic>.from(page.props['wallet'] as Map),
      ...overrides,
    };
    return page;
  }

  testWidgets('malformed wallet balance is unavailable, not zero', (
    tester,
  ) async {
    final repository = AccountFixtureRepository();
    addTearDown(repository.session.close);
    await tester.pumpWidget(
      walletApp(repository, walletPage({'balance_cents': 'not-money'})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('₱0.00'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('malformed wallet transactions do not display zero amounts', (
    tester,
  ) async {
    final repository = AccountFixtureRepository();
    addTearDown(repository.session.close);
    await tester.pumpWidget(
      walletApp(
        repository,
        walletPage({
          'transactions': {
            'current_page': 1,
            'last_page': 1,
            'data': [
              {
                'id': 1,
                'kind': 'purchase',
                'delta_cents': 'not-money',
                'balance_after_cents': 200,
                'reason': 'Synthetic wallet purchase',
                'created_at': '2026-10-28T00:00:00Z',
                'reference': 'SYNTHETIC',
              },
            ],
          },
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('transaction history could not be confirmed'),
      findsOneWidget,
    );
    expect(find.textContaining('purchase · +₱0.00'), findsNothing);
    expect(find.textContaining('No wallet transactions yet'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('wallet rejects malformed transaction references and dates', (
    tester,
  ) async {
    final repository = AccountFixtureRepository();
    addTearDown(repository.session.close);
    for (final row in [
      _walletTransaction(reference: {'private': 'not a receipt reference'}),
      _walletTransaction(createdAt: '2026-02-30T00:00:00Z'),
    ]) {
      await tester.pumpWidget(
        walletApp(
          repository,
          walletPage({
            'transactions': {
              'current_page': 1,
              'last_page': 1,
              'data': [row],
            },
          }),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('transaction history could not be confirmed'),
        findsOneWidget,
      );
      expect(find.textContaining('not a receipt reference'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('wallet rejects maps with non-text keys without crashing', (
    tester,
  ) async {
    final repository = AccountFixtureRepository();
    addTearDown(repository.session.close);
    final cases = [
      (
        wallet: <String, dynamic>{
          'credit_requests': [
            <Object, Object>{1: 'unexpected key'},
          ],
          'transactions': {
            'current_page': 1,
            'last_page': 1,
            'data': <dynamic>[],
          },
        },
        invalidCredit: true,
        invalidTransactions: false,
      ),
      (
        wallet: <String, dynamic>{
          'credit_requests': <dynamic>[],
          'transactions': {
            'current_page': 1,
            'last_page': 1,
            'data': [
              <Object, Object>{1: 'unexpected key'},
            ],
          },
        },
        invalidCredit: false,
        invalidTransactions: true,
      ),
    ];
    for (final testCase in cases) {
      await tester.pumpWidget(
        walletApp(repository, walletPage(testCase.wallet)),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Credit request history could not be confirmed'),
        testCase.invalidCredit ? findsOneWidget : findsNothing,
      );
      expect(
        find.textContaining('transaction history could not be confirmed'),
        testCase.invalidTransactions ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('wallet disables requests for malformed credit history', (
    tester,
  ) async {
    final repository = AccountFixtureRepository();
    addTearDown(repository.session.close);
    await tester.pumpWidget(
      walletApp(
        repository,
        walletPage({
          'credit_requests': [
            _walletCreditRequest(
              reference: {'private': 'not a request reference'},
            ),
          ],
          'transactions': {'current_page': 1, 'last_page': 1, 'data': []},
        }),
      ),
    );
    await tester.pumpAndSettle();

    final requestButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Request credits'),
    );
    expect(requestButton.onPressed, isNull);
    expect(
      find.textContaining('Credit request history could not be confirmed'),
      findsOneWidget,
    );
    expect(find.textContaining('not a request reference'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('wallet replaces a malformed request token with a UUID', (
    tester,
  ) async {
    final repository = AccountFixtureRepository();
    addTearDown(repository.session.close);
    repository.onJson = (_) async => {
      'reference': 'WCR-SYNTHETIC',
      'status': 'pending',
    };
    await tester.pumpWidget(
      walletApp(
        repository,
        walletPage({
          'request_token': {'invalid': 'token'},
          'credit_requests': [],
          'transactions': {
            'current_page': 1,
            'last_page': 1,
            'data': [_walletTransaction()],
          },
        }),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (PHP)'),
      '25.50',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason'),
      'Synthetic credit request',
    );
    final submit = find.widgetWithText(FilledButton, 'Request credits');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(repository.calls, hasLength(1));
    expect(
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
          .hasMatch(repository.calls.single.values['request_token'] as String),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a complete wallet transaction can open its matching order', (
    tester,
  ) async {
    final repository = AccountFixtureRepository();
    addTearDown(repository.session.close);
    int? openedOrder;
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(
          body: WalletSection(
            repository: repository,
            page: walletPage({
              'credit_requests': [],
              'transactions': {
                'current_page': 1,
                'last_page': 1,
                'data': [_walletTransaction(orderId: 11)],
              },
            }),
            reload: () async {},
            onPage: (_) {},
            onOrder: (id) => openedOrder = id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final orderLink = find.widgetWithText(TextButton, 'View order');
    expect(orderLink, findsOneWidget);
    await tester.ensureVisible(orderLink);
    await tester.pumpAndSettle();
    await tester.tap(orderLink);
    expect(openedOrder, 11);
    expect(find.textContaining('purchase · −₱1.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('malformed credit request amounts are not shown as zero', (
    tester,
  ) async {
    final repository = AccountFixtureRepository();
    addTearDown(repository.session.close);
    await tester.pumpWidget(
      walletApp(
        repository,
        walletPage({
          'credit_requests': [
            {
              'id': 1,
              'amount_cents': 'not-money',
              'status': 'pending',
              'reference': 'REQUEST-1',
              'reason': 'Synthetic credit request',
              'created_at': '2026-10-28T00:00:00Z',
              'reviewed_at': null,
              'review_reason': null,
            },
          ],
          'transactions': {'current_page': 1, 'last_page': 1, 'data': []},
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Credit request history could not be confirmed'),
      findsOneWidget,
    );
    expect(find.textContaining('₱0.00 · pending'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('fractional wallet order ID cannot open another order', (
    tester,
  ) async {
    final repository = AccountFixtureRepository();
    addTearDown(repository.session.close);
    var openedOrder = false;
    final props = Map<String, dynamic>.from(accountPage().props);
    props['wallet'] = {
      ...Map<String, dynamic>.from(props['wallet'] as Map),
      'transactions': {
        'current_page': 1,
        'last_page': 1,
        'data': [
          {
            'id': 1,
            'kind': 'purchase',
            'delta_cents': -100,
            'balance_after_cents': 200,
            'reason': 'Synthetic wallet purchase',
            'created_at': '2026-10-28T00:00:00Z',
            'reference': 'SYNTHETIC',
            'order_id': 11.5,
          },
        ],
      },
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(
          body: WalletSection(
            repository: repository,
            page: WebPage('Buyer/Profile', props),
            reload: () async {},
            onPage: (_) {},
            onOrder: (_) => openedOrder = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('View order'), findsNothing);
    expect(openedOrder, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('fractional order result ID cannot open a different order', (
    tester,
  ) async {
    final repository = AccountFixtureRepository();
    addTearDown(repository.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: OrderResultPage(
          repository: repository.buyer,
          initial: WebPage('Buyer/OrderResult', {
            'auth': {'user': buyer},
            'orders': {
              'current_page': 1,
              'last_page': 1,
              'data': [
                {
                  'id': 11.5,
                  'order_number': 'MALFORMED',
                  'status': 'preparing',
                  'total_amount': 100,
                  'items': [],
                },
              ],
            },
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('View order details'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('fractional purchase IDs cannot open a different order', (
    tester,
  ) async {
    final repository = AccountFixtureRepository();
    addTearDown(repository.session.close);
    final session = repository.session as ReturnSession;
    session.onPage = (_) async => const WebPage('Buyer/OrderDetail', {
      'auth': {'user': buyer},
      'order': {
        'id': 11,
        'order_number': 'TEST-11',
        'status': 'preparing',
        'created_at': '2026-10-28T00:00:00Z',
        'items': [],
        'tracking': {'status_label': 'Preparing', 'history': []},
      },
      'canConfirmReceipt': false,
      'canUsePortal': false,
      'orderNotices': [],
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(
          body: PurchasesSection(
            repository: repository,
            page: WebPage('Buyer/Profile', {
              ...accountPage().props,
              'orders': {
                'data': [
                  {
                    'id': 11.5,
                    'order_number': 'MALFORMED',
                    'items': [],
                    'wallet_payment': {'id': 41.5},
                    'payment_status': 'pending',
                    'can_buy_again': true,
                    'buy_again_token': 'synthetic-token',
                  },
                ],
              },
            }),
            onQuery: (_, _) {},
            reload: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final track = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Track Parcel'),
    );
    final wallet = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Pay with wallet'),
    );
    expect(track.onPressed, isNull);
    expect(wallet.onPressed, isNull);
    expect(find.text('Buy again'), findsNothing);
    expect(session.pageRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial purchase items cannot be shown or confirmed', (
    tester,
  ) async {
    final repository = AccountFixtureRepository();
    addTearDown(repository.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(
          body: PurchasesSection(
            repository: repository,
            page: WebPage('Buyer/Profile', {
              ...accountPage().props,
              'orders': {
                'data': [
                  {
                    'id': 11,
                    'order_number': 'PARTIAL-11',
                    'status': 'delivered',
                    'total_amount': 20,
                    'items': [
                      {
                        'id': 31,
                        'product': {'name': 'Visible partial item'},
                        'quantity': 1,
                        'unit_price': 20,
                        'subtotal': 20,
                      },
                      'malformed item row',
                    ],
                    'can_confirm_receipt': true,
                  },
                ],
              },
            }),
            onQuery: (_, _) {},
            reload: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Visible partial item'), findsNothing);
    expect(find.textContaining('item details are incomplete'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Confirm Received'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('initial and updated selected statuses are visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = AccountFixtureRepository();
    addTearDown(repository.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(
          body: PurchasesSection(
            repository: repository,
            page: WebPage('Buyer/Profile', {
              ...accountPage().props,
              'orders': {'data': []},
              'currentOrderStatus': 'return_refund',
            }),
            onQuery: (_, _) {},
            reload: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Return/Refund (0)').hitTestable(), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Return/Refund (0)')).style?.color,
      BagooTheme.strong,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(
          body: PurchasesSection(
            repository: repository,
            page: WebPage('Buyer/Profile', {
              ...accountPage().props,
              'orders': {'data': []},
              'currentOrderStatus': 'all',
            }),
            onQuery: (_, _) {},
            reload: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('All (0)').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('purchase status tabs scroll and request the selected filter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    final repository = AccountFixtureRepository();
    addTearDown(repository.session.close);
    String? requested;
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(
          body: PurchasesSection(
            repository: repository,
            page: WebPage('Buyer/Profile', {
              ...accountPage().props,
              'orders': {'data': []},
              'currentOrderStatus': 'all',
            }),
            onQuery: (status, _) => requested = status,
            reload: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final selected = tester.widget<Text>(find.text('All (0)'));
    expect(selected.style?.color, BagooTheme.strong);
    expect(
      tester.getSemantics(find.text('All (0)')),
      isSemantics(
        label: 'All (0)',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    final target = find
        .ancestor(of: find.text('All (0)'), matching: find.byType(InkWell))
        .first;
    expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    final strip = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    expect(strip, findsOneWidget);
    await tester.drag(strip, const Offset(-1500, 0));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Return/Refund (0)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Return/Refund (0)'));
    await tester.pump();
    expect(requested, 'return_refund');
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('fractional and negative purchase counts are not displayed', (
    tester,
  ) async {
    final repository = AccountFixtureRepository();
    addTearDown(repository.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(
          body: PurchasesSection(
            repository: repository,
            page: WebPage('Buyer/Profile', {
              ...accountPage().props,
              'orders': {'data': []},
              'orderCounts': {'all': 1.5, 'to_pay': -2},
            }),
            onQuery: (_, _) {},
            reload: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All (—)'), findsOneWidget);
    expect(find.text('To pay (—)'), findsOneWidget);
    expect(find.text('All (1.5)'), findsNothing);
    expect(find.text('To pay (-2)'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final resume in [true, false]) {
    testWidgets(
      resume
          ? 'resuming expired purchases removes private order rows'
          : 'a cached Buy again action cannot start after account expiry',
      (tester) async {
        final repository = AccountFixtureRepository();
        addTearDown(repository.session.close);
        final session = repository.session as ReturnSession;
        session.onPage = (_) async => const WebPage('Cart/Index', {
          'auth': {'user': buyer},
          'items': [],
        });
        repository.onJson = (_) async => {
          'result': {
            'order_id': 11,
            'items': [
              {'cart_item_id': 3},
            ],
          },
        };
        final page = WebPage('Buyer/Profile', {
          ...accountPage().props,
          'orders': {
            'current_page': 1,
            'last_page': 1,
            'data': [
              {
                'id': 11,
                'order_number': 'PRIVATE-11',
                'items': [],
                'can_buy_again': true,
                'buy_again_token': 'synthetic-token',
              },
            ],
          },
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            home: Scaffold(
              body: PurchasesSection(
                repository: repository,
                page: page,
                onQuery: (_, _) {},
                reload: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final action = tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Buy again'))
            .onPressed!;
        session.clear();
        if (resume) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        } else {
          action();
        }
        await tester.pumpAndSettle();
        expect(repository.calls, isEmpty);
        expect(find.text('Order #PRIVATE-11'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
  for (final accept in [true, false]) {
    testWidgets(
      'queued confirmation decision $accept consumes only its dialog',
      (tester) async {
        final errors = <Object>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => confirmAction(
                    context,
                    'Confirm receipt?',
                    'Synthetic decision only.',
                    'Confirm Received',
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final callback = accept
            ? tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Confirm Received'),
                  )
                  .onPressed!
            : tester
                  .widget<TextButton>(
                    find.widgetWithText(TextButton, 'Go back'),
                  )
                  .onPressed!;
        for (var n = 0; n < 3; n++) {
          try {
            callback();
          } catch (e) {
            errors.add(e);
          }
        }
        await tester.pumpAndSettle();
        expect(errors, isEmpty);
        expect(tester.takeException(), isNull);
        expect(find.text('Open'), findsOneWidget);
      },
    );
  }
  testWidgets('queued receipt actions open one confirmation dialog', (
    tester,
  ) async {
    final repository = AccountFixtureRepository();
    addTearDown(repository.session.close);
    final page = WebPage('Buyer/Profile', {
      ...accountPage().props,
      'orders': {
        'data': [
          {
            'id': 11,
            'order_number': 'PRIVATE-11',
            'items': [
              {
                'id': 31,
                'sku_snapshot': 'Synthetic item',
                'quantity': 1,
                'unit_price': 20,
                'subtotal': 20,
              },
            ],
            'can_confirm_receipt': true,
          },
        ],
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PurchasesSection(
            repository: repository,
            page: page,
            onQuery: (_, _) {},
            reload: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final action = tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Confirm Received'),
        )
        .onPressed!;
    action();
    action();
    action();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
    expect(repository.calls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  for (final expire in [false, true]) {
    testWidgets(
      'receipt decision after session expiry $expire respects current ownership',
      (tester) async {
        final repository = AccountFixtureRepository();
        addTearDown(repository.session.close);
        final page = WebPage('Buyer/Profile', {
          ...accountPage().props,
          'orders': {
            'data': [
              {
                'id': 11,
                'order_number': 'PRIVATE-11',
                'items': [
                  {
                    'id': 31,
                    'sku_snapshot': 'Synthetic item',
                    'quantity': 1,
                    'unit_price': 20,
                    'subtotal': 20,
                  },
                ],
                'can_confirm_receipt': true,
              },
            ],
          },
        });
        repository.onMutation = (_) async => page;
        var reloads = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PurchasesSection(
                repository: repository,
                page: page,
                onQuery: (_, _) {},
                reload: () async {
                  reloads++;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Confirm Received'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Confirm Received'));
        await tester.pumpAndSettle();
        if (expire) repository.session.clear();
        final confirm = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        );
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(repository.calls, hasLength(expire ? 0 : 1));
        expect(reloads, expire ? 0 : 1);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
