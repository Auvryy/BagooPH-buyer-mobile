import 'dart:async';
import 'dart:convert';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/device_actions.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/checkout_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';
import 'support/widget_helpers.dart';

void main() {
  late FakeBuyerRepository repo;
  setUp(() => repo = FakeBuyerRepository());
  tearDown(() => repo.session.close());

  Future<void> open(
    WidgetTester tester,
    WebPage page, {
    Future<BuyerLocation> Function()? location,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: CheckoutPage(
          repository: repo,
          initial: page,
          captureLocation: location ?? captureBuyerLocation,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'older checkout contracts retain their existing server-quoted flow',
    (tester) async {
      final props = Map<String, dynamic>.from(checkoutPage().props)
        ..remove('logisticsCompanies');
      final requests = <Map<String, dynamic>>[];
      repo.quoteHandler = (values) async {
        requests.add(values);
        return {'success': true, 'quote': props['quote']};
      };
      await open(tester, WebPage('Checkout/Index', props));
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(requests.last.containsKey('logistics_company_id'), isFalse);
      await press(tester, find.widgetWithText(FilledButton, 'Review order'));
      expect(find.text('Confirm your order'), findsOneWidget);
      expect(repo.orderCalls, 0);
    },
  );

  testWidgets(
    'an explicit empty serving-company list cannot use the older checkout flow',
    (tester) async {
      final props = {
        ...checkoutPage().props,
        'logisticsCompanies': <Map<String, dynamic>>[],
      };
      await open(tester, WebPage('Checkout/Index', props));
      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
      expect(
        tester
            .widgetList<FilledButton>(
              find.widgetWithText(FilledButton, 'Review order'),
            )
            .every((button) => button.onPressed == null),
        isTrue,
      );
      expect(repo.orderCalls, 0);
    },
  );

  testWidgets(
    'quotes include route context and orders retain saved coordinates',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      repo.quoteHandler = (values) async {
        requests.add(values);
        return {'success': true, 'quote': checkoutPage().props['quote']};
      };
      final page = WebPage(
        'Checkout/Index',
        jsonDecode(jsonEncode(checkoutPage().props)) as Map<String, dynamic>,
      );
      (page.props['addresses'] as List).first.addAll({
        'latitude': '14.055000',
        'longitude': '121.325000',
      });
      await open(tester, page);
      expect(requests.last, containsPair('logistics_company_id', 41));
      expect(requests.last, containsPair('shipping_postal_code', '4000'));
      expect(requests.last, containsPair('destination_barangay', 'San Rafael'));
      await press(tester, find.widgetWithText(FilledButton, 'Review order'));
      await press(tester, find.byType(CheckboxListTile).last);
      await press(tester, find.widgetWithText(FilledButton, 'Place order'));
      expect(repo.submittedOrder?['shipping_latitude'], '14.055000');
      expect(repo.submittedOrder?['shipping_longitude'], '121.325000');
      expect(repo.submittedOrder?['logistics_company_id'], 41);
    },
  );

  testWidgets(
    'an unavailable company clears the selection and requires a fresh choice',
    (tester) async {
      await open(tester, checkoutPage());
      repo.quoteHandler = (_) async => throw const BackendException(
        'Company no longer serves this address.',
        status: 422,
        data: {
          'logisticsCompanies': [
            {'id': 42, 'name': 'Another company'},
            {'id': 43, 'name': 'Third company'},
          ],
        },
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Postal code'),
        '4001',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final company = tester.widget<DropdownButtonFormField<int>>(
        find.byType(DropdownButtonFormField<int>),
      );
      expect(company.initialValue, isNull);
      final dropdown = tester.widget<DropdownButton<int>>(
        find.byType(DropdownButton<int>),
      );
      expect(dropdown.items!.map((item) => item.value), [42, 43]);
      expect(
        tester
            .widgetList<FilledButton>(
              find.widgetWithText(FilledButton, 'Review order'),
            )
            .every((button) => button.onPressed == null),
        isTrue,
      );
      expect(repo.orderCalls, 0);
    },
  );

  testWidgets('an older company response cannot replace a newer route', (
    tester,
  ) async {
    await open(tester, checkoutPage());
    final pending = <Completer<Map<String, dynamic>>>[];
    repo.quoteHandler = (_) {
      final next = Completer<Map<String, dynamic>>();
      pending.add(next);
      return next.future;
    };
    final postal = find.widgetWithText(TextFormField, 'Postal code');
    await tester.enterText(postal, '4001');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(postal, '4002');
    await tester.pump(const Duration(milliseconds: 400));
    pending.last.complete({
      'success': true,
      'quote': checkoutPage().props['quote'],
      'logisticsCompanies': [
        {'id': 41, 'name': 'Current company'},
      ],
    });
    await tester.pump();
    pending.first.complete({
      'success': true,
      'quote': checkoutPage().props['quote'],
      'logisticsCompanies': [],
    });
    await tester.pumpAndSettle();
    final company = tester.widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    );
    expect(company.initialValue, 41);
    expect(
      tester
          .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
          .items!
          .single
          .value,
      41,
    );
  });

  testWidgets('late GPS cannot overwrite coordinates the buyer edited', (
    tester,
  ) async {
    final pending = Completer<BuyerLocation>();
    await open(tester, checkoutPage(), location: () => pending.future);
    tester
        .widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Use current location'),
        )
        .onPressed!();
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Latitude'),
      '14.10',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Longitude'),
      '121.20',
    );
    pending.complete((latitude: 15.0, longitude: 122.0, accuracy: 10.0));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'Latitude'))
          .controller!
          .text,
      '14.10',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Longitude'),
          )
          .controller!
          .text,
      '121.20',
    );
    expect(find.textContaining('Location pinned.'), findsNothing);
  });
}
