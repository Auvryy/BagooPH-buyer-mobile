import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/checkout_page.dart';

import 'support/fake_buyer_repository.dart';
import 'support/widget_helpers.dart';

class VoucherRepository extends FakeBuyerRepository {
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? bestHandler;
  @override
  Future<Map<String, dynamic>> bestVouchers(Map<String, dynamic> values) =>
      bestHandler!(values);
}

void main() {
  late FakeBuyerRepository repo;
  setUp(() => repo = FakeBuyerRepository());
  tearDown(() => repo.session.close());
  testWidgets(
    'expired voucher repairs retain other slots and recheck the quote',
    (tester) async {
      final vouchers = VoucherRepository();
      repo.session.close();
      repo = vouchers;
      final requests = <Map<String, dynamic>>[];
      vouchers.bestHandler = (_) async => {
        'selection': {
          'voucher_code': null,
          'platform_voucher_revision_id': null,
          'shop_voucher_revision_ids': {'2': 22},
        },
        'quote': checkoutPage().props['quote'],
      };
      vouchers.quoteHandler = (values) async {
        requests.add(jsonDecode(jsonEncode(values)) as Map<String, dynamic>);
        if (values['code'] == 'EXPIRED') {
          throw BackendException(
            'Voucher expired',
            status: 422,
            data: {
              'quote': checkoutPage().props['quote'],
              'availableVouchers': [],
              'validSelection': {
                'voucher_code': null,
                'platform_voucher_revision_id': null,
                'shop_voucher_revision_ids': {'2': 22},
              },
              'selectionErrors': {'code': 'Voucher expired'},
            },
          );
        }
        return {
          'success': true,
          'quote': checkoutPage().props['quote'],
          'availableVouchers': [],
          'validSelection': {
            'voucher_code': null,
            'platform_voucher_revision_id':
                values['platform_voucher_revision_id'],
            'shop_voucher_revision_ids': values['shop_voucher_revision_ids'],
          },
        };
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: CheckoutPage(repository: repo, initial: checkoutPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Use best vouchers'));
      await tester.pumpAndSettle();
      expect(find.text('Use best vouchers').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Use best vouchers'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(requests.last['shop_voucher_revision_ids'], {'2': 22});
      final code = find.widgetWithText(
        TextFormField,
        'Voucher code (optional)',
      );
      await tester.enterText(code, 'EXPIRED');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(requests.last['code'], '');
      expect(requests.last['shop_voucher_revision_ids'], {'2': 22});
      expect(
        find.textContaining('Your other voucher choices are retained.'),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<FilledButton>(
              find.widgetWithText(FilledButton, 'Review order'),
            )
            .any((button) => button.onPressed != null),
        true,
      );
      expect(repo.orderCalls, 0);
    },
  );
  testWidgets('voucher comparison cannot replace a newer delivery selection', (
    tester,
  ) async {
    final vouchers = VoucherRepository();
    repo.session.close();
    repo = vouchers;
    final pending = Completer<Map<String, dynamic>>();
    vouchers.bestHandler = (_) => pending.future;
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: CheckoutPage(repository: repo, initial: checkoutPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Use best vouchers'));
    await tester.pumpAndSettle();
    expect(find.text('Use best vouchers').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Use best vouchers'));
    await tester.pump();
    final pickup = find.text('Bayan Hub self-pickup');
    await tester.ensureVisible(pickup);
    await tester.pump();
    expect(pickup.hitTestable(), findsOneWidget);
    await tester.tap(pickup);
    await tester.pump(const Duration(milliseconds: 400));
    pending.complete({
      'selection': {
        'voucher_code': null,
        'platform_voucher_revision_id': 55,
        'shop_voucher_revision_ids': {},
      },
      'quote': checkoutPage().props['quote'],
    });
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Compare vouchers again for the updated items'),
      findsOneWidget,
    );
    expect(find.text('Platform voucher selected'), findsNothing);
    expect(repo.orderCalls, 0);
  });
  testWidgets('summary separates product savings from shipping savings', (
    tester,
  ) async {
    repo.quoteHandler = (_) async => {
      'success': true,
      'availableVouchers': [],
      'quote': {
        ...mapOf(checkoutPage().props['quote']),
        'discount': 30,
        'shipping_discount': 10,
        'total': 1220,
      },
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: CheckoutPage(repository: repo, initial: checkoutPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('-₱20.00'), findsOneWidget);
    expect(find.text('-₱10.00'), findsOneWidget);
    expect(find.text('-₱30.00'), findsNothing);
    expect(find.text('₱1,220.00'), findsWidgets);
  });
  testWidgets(
    'recipient validation survives long scrolling and width changes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 820);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: CheckoutPage(repository: repo, initial: checkoutPage()),
        ),
      );
      await tester.pumpAndSettle();
      final phone = find.widgetWithText(
        TextFormField,
        'Philippine mobile number',
      );
      // Bypass keyboard filtering to check the submission guard as well.
      tester.widget<TextFormField>(phone).controller!.text = 'bad';
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(375, 820);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Payment summary'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Review order').hitTestable().first,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Use a Philippine mobile number, such as 09171234567.'),
        findsOneWidget,
      );
      expect(find.text('Confirm your order'), findsNothing);
      expect(repo.orderCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('late quotes cannot replace the latest checkout total', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: CheckoutPage(repository: repo, initial: checkoutPage()),
      ),
    );
    await tester.pumpAndSettle();
    final pending = <Completer<Map<String, dynamic>>>[];
    repo.quoteHandler = (_) {
      final next = Completer<Map<String, dynamic>>();
      pending.add(next);
      return next.future;
    };
    final voucher = find.widgetWithText(
      TextFormField,
      'Voucher code (optional)',
    );
    await tester.enterText(voucher, 'OLD');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(voucher, 'LATEST');
    await tester.pump(const Duration(milliseconds: 400));
    expect(pending, hasLength(2));
    Map<String, dynamic> response(double total) => {
      'success': true,
      'quote': {...mapOf(checkoutPage().props['quote']), 'total': total},
      'availableVouchers': [],
    };
    pending[1].complete(response(1100));
    await tester.pump();
    pending[0].complete(response(900));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Total'),
      400,
      scrollable: verticalScroll(),
    );
    await tester.pumpAndSettle();
    expect(find.text('₱1,100.00'), findsWidgets);
    expect(find.text('₱900.00'), findsNothing);
    expect(repo.orderCalls, 0);
  });
  testWidgets('uncertain order retries retain the exact payload and token', (
    tester,
  ) async {
    final requests = <String>[];
    repo.orderHandler = (values) async {
      requests.add(jsonEncode(values));
      if (requests.length == 1) {
        throw const BackendException(
          'The connection timed out. Please try again.',
        );
      }
      return const WebPage('Buyer/Profile', {
        'flash': {'success': 'Order recorded.'},
        'orders': {'data': []},
      });
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: CheckoutPage(repository: repo, initial: checkoutPage()),
      ),
    );
    await tester.pumpAndSettle();
    await press(tester, find.widgetWithText(FilledButton, 'Review order'));
    await press(tester, find.byType(CheckboxListTile).last);
    await press(tester, find.widgetWithText(FilledButton, 'Place order'));
    expect(repo.orderCalls, 1);
    expect(
      find.textContaining('Your exact checkout details are retained'),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .every((w) => w.enabled == false),
      isTrue,
    );
    await press(tester, find.widgetWithText(FilledButton, 'Review safe retry'));
    await press(tester, find.byType(CheckboxListTile).last);
    await press(tester, find.widgetWithText(FilledButton, 'Retry same order'));
    expect(repo.orderCalls, 2);
    expect(requests[0], requests[1]);
    expect(find.text('Order recorded.'), findsOneWidget);
  });
}
