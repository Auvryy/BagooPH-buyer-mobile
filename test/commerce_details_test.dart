import 'package:bagoo_buyer_mobile/features/checkout/commerce_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('complete voucher receipt shows its recorded discount', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VoucherReceipt(
            receipt: {
              'merchandise': 100,
              'discounts': [
                {
                  'code': 'SHOP-10',
                  'name': 'Shop voucher',
                  'issuer': 'shop',
                  'product_discount': 10,
                  'shipping_discount': 0,
                },
              ],
              'shipping_before': 20,
              'shipping_after': 20,
              'total_savings': 10,
              'total': 110,
              'legacy_discount': false,
            },
          ),
        ),
      ),
    );

    expect(find.textContaining('Shop voucher · SHOP-10'), findsOneWidget);
    expect(find.text('₱110.00'), findsOneWidget);
  });

  testWidgets('voucher receipt hides a partial discount list', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VoucherReceipt(
            receipt: {
              'merchandise': 100,
              'discounts': [
                {
                  'code': 'SHOP-10',
                  'name': 'Shop voucher',
                  'issuer': 'shop',
                  'product_discount': 10,
                  'shipping_discount': 0,
                },
                'malformed allocation',
              ],
              'shipping_before': 20,
              'shipping_after': 20,
              'total_savings': 10,
              'total': 110,
              'legacy_discount': false,
            },
          ),
        ),
      ),
    );

    expect(find.textContaining('Shop voucher · SHOP-10'), findsNothing);
    expect(
      find.text('Voucher receipt details could not be confirmed.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('voucher receipt hides totals that do not match its discounts', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VoucherReceipt(
            receipt: {
              'merchandise': 100,
              'discounts': [
                {
                  'code': 'SHOP-10',
                  'name': 'Shop voucher',
                  'issuer': 'shop',
                  'product_discount': 10,
                  'shipping_discount': 0,
                },
              ],
              'shipping_before': 20,
              'shipping_after': 20,
              'total_savings': 10,
              'total': 999,
              'legacy_discount': false,
            },
          ),
        ),
      ),
    );

    expect(find.text('₱999.00'), findsNothing);
    expect(
      find.text('Voucher receipt details could not be confirmed.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'voucher receipt hides allocation totals that disagree with savings',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VoucherReceipt(
              receipt: {
                'merchandise': 100,
                'discounts': [
                  {
                    'code': 'SHOP-10',
                    'name': 'Shop voucher',
                    'issuer': 'shop',
                    'product_discount': 10,
                    'shipping_discount': 0,
                  },
                ],
                'shipping_before': 20,
                'shipping_after': 20,
                'total_savings': 15,
                'total': 105,
                'legacy_discount': false,
              },
            ),
          ),
        ),
      );

      expect(find.text('₱105.00'), findsNothing);
      expect(
        find.text('Voucher receipt details could not be confirmed.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('legacy voucher receipt keeps aggregate-only savings', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VoucherReceipt(
            receipt: {
              'merchandise': 100,
              'discounts': [],
              'shipping_before': 20,
              'shipping_after': 20,
              'total_savings': 10,
              'total': 110,
              'legacy_discount': true,
            },
          ),
        ),
      ),
    );

    expect(find.textContaining('Recorded voucher discount'), findsOneWidget);
    expect(find.text('₱110.00'), findsOneWidget);
  });

  testWidgets('voucher receipt validates shipping discount arithmetic', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VoucherReceipt(
            receipt: {
              'merchandise': 100,
              'discounts': [
                {
                  'code': 'SHOP-15',
                  'name': 'Shop voucher',
                  'issuer': 'shop',
                  'product_discount': 10,
                  'shipping_discount': 5,
                },
              ],
              'shipping_before': 20,
              'shipping_after': 20,
              'total_savings': 15,
              'total': 105,
              'legacy_discount': false,
            },
          ),
        ),
      ),
    );

    expect(find.text('₱105.00'), findsNothing);
    expect(
      find.text('Voucher receipt details could not be confirmed.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid shipping measurements and fees are not shown as zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShippingCalculation(
            calculation: {
              'actual_weight_grams': double.nan,
              'volumetric_weight_grams': -50,
              'billable_weight_grams': double.infinity,
              'included_weight_grams': double.nan,
              'base_fee_cents': double.nan,
              'additional_kilograms': double.nan,
              'additional_kg_cents': -10,
              'missing_measurement_product_ids': [],
            },
          ),
        ),
      ),
    );

    expect(find.text('Actual weight: Unavailable'), findsOneWidget);
    expect(find.text('Volumetric weight: Unavailable'), findsOneWidget);
    expect(find.text('Billable weight: Unavailable'), findsOneWidget);
    expect(find.textContaining('Included: Unavailable.'), findsOneWidget);
    expect(
      find.textContaining('Base Unavailable + Unavailable additional kg'),
      findsOneWidget,
    );
    expect(find.text('Actual weight: 0.000 kg'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('malformed route rows do not render a partial shipping route', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShippingCalculation(
            calculation: {
              'route': [
                {'code': 'HUB-A'},
                'malformed hub',
              ],
            },
          ),
        ),
      ),
    );

    expect(find.textContaining('Route: HUB-A'), findsNothing);
    expect(find.text('Route details unavailable.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-text route metadata fails closed without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShippingCalculation(
            calculation: {
              'route': [
                {'code': 'HUB-A', 7: 'unexpected'},
              ],
            },
          ),
        ),
      ),
    );

    expect(find.textContaining('Route: HUB-A'), findsNothing);
    expect(find.text('Route details unavailable.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fractional and string shipping measurements are unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShippingCalculation(
            calculation: {
              'actual_weight_grams': '1000',
              'volumetric_weight_grams': 1000.5,
              'billable_weight_grams': 1000,
              'included_weight_grams': 1000.5,
              'base_fee_cents': '6000',
              'additional_kilograms': 1.5,
              'additional_kg_cents': 500.5,
            },
          ),
        ),
      ),
    );

    expect(find.text('Actual weight: Unavailable'), findsOneWidget);
    expect(find.text('Volumetric weight: Unavailable'), findsOneWidget);
    expect(find.text('Billable weight: 1.000 kg'), findsOneWidget);
    expect(find.textContaining('Included: Unavailable.'), findsOneWidget);
    expect(
      find.textContaining('Base Unavailable + Unavailable additional kg'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'malformed measurement IDs show the conservative shipping notice',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShippingCalculation(
              calculation: {'missing_measurement_product_ids': 'not-a-list'},
            ),
          ),
        ),
      );

      expect(
        find.text(
          'Some packed measurements are not recorded. This quote uses the published flat base fee.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
