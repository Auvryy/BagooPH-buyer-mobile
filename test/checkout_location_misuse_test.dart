import 'dart:async';
import 'dart:io';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/device_actions.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/checkout_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/checkout_fixtures.dart';
import 'support/fake_buyer_repository.dart';
import 'support/no_network.dart';
import 'support/widget_helpers.dart';

void main() {
  final originalOverrides = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = NoNetworkHttpOverrides());
  tearDownAll(() => HttpOverrides.global = originalOverrides);
  late FakeBuyerRepository repository;
  setUp(() {
    repository = FakeBuyerRepository();
    repository.quoteHandler = (_) async => confirmedQuote();
    repository.orderHandler = (_) async => ownedOrderResult();
  });
  tearDown(() => repository.session.close());

  void check(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }

  Finder coordinate(String label) => find.widgetWithText(TextFormField, label);
  String value(WidgetTester tester, String label) =>
      tester.widget<TextFormField>(coordinate(label)).controller!.text;
  Future<void> open(
    WidgetTester tester, {
    Future<BuyerLocation> Function()? capture,
  }) async {
    final page = ownedCheckout();
    ((page.props['addresses'] as List).first as Map<String, dynamic>).addAll({
      'latitude': '14.2500',
      'longitude': '121.1500',
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: CheckoutPage(
          repository: repository,
          initial: page,
          captureLocation:
              capture ??
              () async => (latitude: 14.0, longitude: 121.0, accuracy: 10.0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(value(tester, 'Latitude'), '14.2500');
    expect(value(tester, 'Longitude'), '121.1500');
  }

  Future<void> startCapture(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final button = find.widgetWithText(OutlinedButton, 'Use current location');
    await Scrollable.ensureVisible(tester.element(button), alignment: .5);
    await tester.pumpAndSettle();
    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button);
    await tester.pump();
  }

  final invalidPositions = <String, BuyerLocation>{
    'NaN latitude': (latitude: double.nan, longitude: 122.0, accuracy: 10.0),
    'infinite latitude': (
      latitude: double.infinity,
      longitude: 122.0,
      accuracy: 10.0,
    ),
    'latitude outside range': (
      latitude: 91.0,
      longitude: 122.0,
      accuracy: 10.0,
    ),
    'infinite longitude': (
      latitude: 15.0,
      longitude: double.infinity,
      accuracy: 10.0,
    ),
    'longitude outside range': (
      latitude: 15.0,
      longitude: 181.0,
      accuracy: 10.0,
    ),
    'NaN accuracy': (latitude: 15.0, longitude: 122.0, accuracy: double.nan),
    'infinite accuracy': (
      latitude: 15.0,
      longitude: 122.0,
      accuracy: double.infinity,
    ),
    'negative accuracy': (latitude: 15.0, longitude: 122.0, accuracy: -1.0),
  };
  for (final entry in invalidPositions.entries) {
    check('invalid GPS ${entry.key} preserves the previous recipient pin', (
      tester,
    ) async {
      await open(tester, capture: () async => entry.value);
      await startCapture(tester);
      await tester.pumpAndSettle();
      expect(value(tester, 'Latitude'), '14.2500');
      expect(value(tester, 'Longitude'), '121.1500');
      expect(find.textContaining('Location pinned.'), findsNothing);
      expect(repository.orderCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final pair in [
    ('14.1234567', '121.1234567'),
    ('0014.2500000', '0121.1500000'),
  ]) {
    check('manual coordinates accepted by the server remain usable: $pair', (
      tester,
    ) async {
      await open(tester);
      for (final field in {'Latitude': pair.$1, 'Longitude': pair.$2}.entries) {
        await Scrollable.ensureVisible(
          tester.element(coordinate(field.key)),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        await tester.enterText(coordinate(field.key), field.value);
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await press(tester, find.widgetWithText(FilledButton, 'Review order'));
      expect(find.text('Confirm your order'), findsOneWidget);
      await press(tester, find.byType(CheckboxListTile).last);
      await press(tester, find.widgetWithText(FilledButton, 'Place order'));
      expect(repository.orderCalls, 1);
      expect(repository.submittedOrder?['shipping_latitude'], pair.$1);
      expect(repository.submittedOrder?['shipping_longitude'], pair.$2);
    });
  }

  check('coordinate fields reject malformed edits but allow signed drafts', (
    tester,
  ) async {
    await open(tester);
    final latitude = coordinate('Latitude');
    await Scrollable.ensureVisible(tester.element(latitude), alignment: .5);
    await tester.pumpAndSettle();
    await tester.enterText(latitude, '-14.125');
    expect(value(tester, 'Latitude'), '-14.125');
    await tester.enterText(latitude, '-14.12345678');
    expect(value(tester, 'Latitude'), '-14.125');
    await tester.enterText(latitude, 'NaN');
    expect(value(tester, 'Latitude'), '-14.125');
    await tester.enterText(latitude, '+14.25');
    expect(value(tester, 'Latitude'), '-14.125');

    await tester.enterText(latitude, '-');
    expect(value(tester, 'Latitude'), '-');
    await tester.enterText(latitude, '');
    expect(value(tester, 'Latitude'), isEmpty);

    final longitude = coordinate('Longitude');
    await Scrollable.ensureVisible(tester.element(longitude), alignment: .5);
    await tester.pumpAndSettle();
    await tester.enterText(longitude, '-180.0000000');
    expect(value(tester, 'Longitude'), '-180.0000000');
    await tester.enterText(longitude, '-180.00000001');
    expect(value(tester, 'Longitude'), '-180.0000000');
  });

  for (final invalid in [
    '+14.25',
    '.5',
    '1e1',
    'NaN',
    'Infinity',
    '14.12345678',
    '91',
  ]) {
    check('manual coordinate format cannot bypass the server rule: $invalid', (
      tester,
    ) async {
      await open(tester);
      tester.widget<TextFormField>(coordinate('Latitude')).controller!.text =
          invalid;
      await press(tester, find.widgetWithText(FilledButton, 'Review order'));
      expect(find.text('Confirm your order'), findsNothing);
      expect(repository.orderCalls, 0);
    });
  }

  check('longitude outside the server range cannot open order review', (
    tester,
  ) async {
    await open(tester);
    tester.widget<TextFormField>(coordinate('Longitude')).controller!.text =
        '-181';
    await press(tester, find.widgetWithText(FilledButton, 'Review order'));
    expect(find.text('Confirm your order'), findsNothing);
    expect(repository.orderCalls, 0);
  });

  for (final entry in {
    'Recipient name': 'Recipient2',
    'Street / house / unit': '123 <script>road</script>',
    'Delivery notes (optional)': 'javascript:alert(1)',
  }.entries) {
    check('checkout rejects unsafe ${entry.key} before review', (tester) async {
      await open(tester);
      tester.widget<TextFormField>(coordinate(entry.key)).controller!.text =
          entry.value;
      await press(tester, find.widgetWithText(FilledButton, 'Review order'));
      expect(find.text('Confirm your order'), findsNothing);
      expect(repository.orderCalls, 0);
    });
  }

  check('a queued review activation cannot confirm while GPS is pending', (
    tester,
  ) async {
    final pending = Completer<BuyerLocation>();
    try {
      await open(tester, capture: () => pending.future);
      final review = tester
          .widget<FilledButton>(
            find
                .widgetWithText(FilledButton, 'Review order')
                .hitTestable()
                .first,
          )
          .onPressed!;
      await startCapture(tester);
      expect(
        tester
            .widgetList<FilledButton>(
              find.widgetWithText(FilledButton, 'Review order'),
            )
            .every((button) => button.onPressed == null),
        isTrue,
      );
      review();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Confirm your order'), findsNothing);
      expect(repository.orderCalls, 0);
    } finally {
      pending.complete((latitude: 15.0, longitude: 122.0, accuracy: 10.0));
      await tester.pumpAndSettle();
    }
  });

  check('valid coordinate boundaries and zero accuracy are accepted', (
    tester,
  ) async {
    await open(
      tester,
      capture: () async => (latitude: 90.0, longitude: -180.0, accuracy: 0.0),
    );
    await startCapture(tester);
    await tester.pumpAndSettle();
    expect(value(tester, 'Latitude'), '90.000000');
    expect(value(tester, 'Longitude'), '-180.000000');
    expect(
      find.textContaining('Location pinned. Reported accuracy: 0 m.'),
      findsOneWidget,
    );
    expect(repository.orderCalls, 0);
  });

  check(
    'permission feedback preserves the existing pin and allows manual entry',
    (tester) async {
      await open(
        tester,
        capture: () async => throw const BackendException(
          'Location permission is unavailable. Enter coordinates manually.',
        ),
      );
      await startCapture(tester);
      await tester.pumpAndSettle();
      expect(value(tester, 'Latitude'), '14.2500');
      expect(value(tester, 'Longitude'), '121.1500');
      expect(
        find.textContaining('Location permission is unavailable.'),
        findsOneWidget,
      );
    },
  );

  check('duplicate location activations capture once', (tester) async {
    final pending = Completer<BuyerLocation>();
    int calls = 0;
    await open(
      tester,
      capture: () {
        calls++;
        return pending.future;
      },
    );
    final capture = tester
        .widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Use current location'),
        )
        .onPressed!;
    for (var index = 0; index < 8; index++) {
      capture();
    }
    await tester.pump();
    expect(calls, 1);
    pending.complete((latitude: 15.0, longitude: 122.0, accuracy: 10.0));
    await tester.pumpAndSettle();
    expect(value(tester, 'Latitude'), '15.000000');
  });

  check('explicit order review includes the recipient coordinates', (
    tester,
  ) async {
    await open(tester);
    await press(tester, find.widgetWithText(FilledButton, 'Review order'));
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('14.2500, 121.1500'),
      ),
      findsOneWidget,
    );
    expect(repository.orderCalls, 0);
  });
}
