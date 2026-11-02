import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/features/home/search_controller.dart';
import 'package:bagoo_buyer_mobile/features/home/search_filters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final value in [
    '-1',
    '+1',
    'NaN',
    'Infinity',
    '-Infinity',
    '1e2',
    '1.234',
    '100000000',
    '100000000.00',
    '₱500',
    '1,000',
    '500\u200b',
  ]) {
    test('price filter rejects invalid amount $value', () {
      expect(SearchFilters.priceError(value), isNotNull);
    });
  }

  for (final value in ['', '0', '0.01', '99999999.99', ' 1.2 ']) {
    test('price filter accepts valid amount $value', () {
      expect(SearchFilters.priceError(value), isNull);
    });
  }

  testWidgets('invalid price fields cannot be applied', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 900);
    addTearDown(tester.view.reset);

    final applied = <SearchFilters>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SearchFiltersForm(
              value: const SearchFilters(),
              categories: const [],
              locations: const [],
              onApply: applied.add,
              onReset: () {},
            ),
          ),
        ),
      ),
    );

    final minimum = find.widgetWithText(TextFormField, 'Minimum price');
    final maximum = find.widgetWithText(TextFormField, 'Maximum price');
    final minimumController = tester.widget<TextFormField>(minimum).controller!;
    final maximumController = tester.widget<TextFormField>(maximum).controller!;
    final apply = find.widgetWithText(FilledButton, 'Apply filters');

    final invalidRanges = [
      (minimum: '-1', maximum: '', reason: 'negative amount'),
      (minimum: 'NaN', maximum: '', reason: 'NaN'),
      (minimum: 'Infinity', maximum: '', reason: 'infinity'),
      (minimum: '1e2', maximum: '', reason: 'scientific notation'),
      (minimum: '1.234', maximum: '', reason: 'more than two decimals'),
      (minimum: '100000000.00', maximum: '', reason: 'over the allowed cap'),
      (minimum: '100', maximum: '99', reason: 'maximum below minimum'),
    ];

    for (final range in invalidRanges) {
      minimumController.text = range.minimum;
      maximumController.text = range.maximum;
      await tester.pumpAndSettle();
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(applied, isEmpty, reason: range.reason);
    }

    // A valid boundary still applies after the rejected cases.
    minimumController.text = '0';
    maximumController.text = '99999999.99';
    await tester.pumpAndSettle();
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(applied, hasLength(1));
    expect(applied.single.minimum, '0');
    expect(applied.single.maximum, '99999999.99');
    expect(tester.takeException(), isNull);
  });
}
