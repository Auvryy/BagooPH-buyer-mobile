import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/checkout_page.dart';

import 'support/fake_buyer_repository.dart';
import 'support/widget_helpers.dart';

void main() {
  late FakeBuyerRepository repo;
  setUp(() => repo = FakeBuyerRepository());
  tearDown(() => repo.session.close());
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
    expect(find.text('₱1,100.00'), findsOneWidget);
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
