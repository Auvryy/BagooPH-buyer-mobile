import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/features/home/search_controller.dart';
import 'package:bagoo_buyer_mobile/features/home/search_filters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'duplicate browse filter values invalidate the whole choice list',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SearchFiltersForm(
                value: const SearchFilters(
                  category: 'bags',
                  location: 'laguna',
                ),
                categories: const [
                  {'slug': 'bags', 'name': 'Bags'},
                  {'slug': 'bags', 'name': 'Bags duplicate'},
                  {'slug': 'tech', 'name': 'Technology'},
                ],
                locations: const [
                  {'value': 'laguna', 'label': 'Laguna'},
                  {'value': 'laguna', 'label': 'Laguna duplicate'},
                  {'value': 'rizal', 'label': 'Rizal'},
                ],
                onApply: (_) {},
                onReset: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final filters = tester
          .widgetList<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .toList();
      expect(filters, hasLength(2));
      expect(filters.map((filter) => filter.initialValue), ['', '']);
      final dropdowns = tester
          .widgetList<DropdownButton<String>>(
            find.byType(DropdownButton<String>),
          )
          .toList();
      expect(
        dropdowns.map(
          (dropdown) => dropdown.items?.map((item) => item.value).toList(),
        ),
        [
          <String?>[''],
          <String?>[''],
        ],
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('search price fields reject malformed typing and pastes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SearchFiltersForm(
              value: const SearchFilters(),
              categories: const [],
              locations: const [],
              onApply: (_) {},
              onReset: () {},
            ),
          ),
        ),
      ),
    );

    for (final label in ['Minimum price', 'Maximum price']) {
      final field = find.widgetWithText(TextFormField, label);
      await tester.ensureVisible(field);
      final controller = tester.widget<TextFormField>(field).controller!;
      await tester.enterText(field, '12.50');
      await tester.pump();
      expect(controller.text, '12.50');

      for (final invalid in [
        '-1',
        '+1',
        'NaN',
        'Infinity',
        '1e2',
        '1.234',
        '1,000',
        '₱12.50',
        '.5',
      ]) {
        await tester.enterText(field, invalid);
        await tester.pump();
        expect(controller.text, '12.50', reason: '$label: $invalid');
      }

      await tester.enterText(field, '12.');
      await tester.pump();
      expect(controller.text, '12.');
      await tester.enterText(field, '');
      await tester.pump();
      expect(controller.text, isEmpty);
    }
    expect(tester.takeException(), isNull);
  });

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
