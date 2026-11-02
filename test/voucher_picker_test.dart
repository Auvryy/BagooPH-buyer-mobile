import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/features/checkout/voucher_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';
import 'support/widget_helpers.dart';

class PickerRepository extends FakeBuyerRepository {
  final selections = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> voucherChoices(
    Map<String, dynamic> values,
  ) async {
    selections.add(Map.of(values));
    final number = values['voucher_page'] as int;
    final rowCount = number == 1 ? 12 : 1;
    final from = (number - 1) * 12 + 1;
    return {
      'offers': {
        'current_page': number,
        'last_page': 2,
        'per_page': 12,
        'total': 13,
        'from': from,
        'to': from + rowCount - 1,
        'data': [
          for (var index = 0; index < rowCount; index++)
            {
              'revision_id': number == 1 ? (index == 0 ? 1 : 100 + index) : 2,
              'code': 'TEST-$number-$index',
              'issuer': 'shop',
              'shop_id': 2,
              'shop_name': 'Test shop',
              'name': 'Selected product offer',
              'discount_type': 'percent',
              'discount_value': 10,
              'product_scope': 'all',
              'eligible_products': <Map<String, dynamic>>[],
              'min_spend': 0,
              'eligible': number == 2,
              'saving': number == 2 ? 15 : 0,
              'unavailable_reason': number == 1
                  ? index == 0
                        ? 'This offer has expired.'
                        : 'This offer is unavailable.'
                  : null,
            },
        ],
      },
    };
  }
}

void main() {
  testWidgets(
    'native voucher picker pages within a slot and returns only an eligible choice',
    (tester) async {
      tester.view.physicalSize = const Size(375, 820);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repo = PickerRepository();
      addTearDown(repo.session.close);
      Map<String, dynamic>? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    selected = await Navigator.of(context)
                        .push<Map<String, dynamic>>(
                          MaterialPageRoute(
                            builder: (_) => VoucherPickerPage(
                              repository: repo,
                              values: const {
                                'item_ids': [1],
                                'delivery_type': 'doorstep',
                              },
                              shopId: 2,
                              title: 'Shop vouchers',
                            ),
                          ),
                        );
                  },
                  child: const Text('Choose voucher'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose voucher'));
      await tester.pumpAndSettle();
      expect(find.text('Use voucher'), findsNothing);
      expect(find.text('This offer has expired.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Next'),
        600,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 25,
      );
      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      await press(tester, find.text('Next'));
      await press(tester, find.text('Use voucher'));
      expect(selected?['revision_id'], 2);
      expect(repo.selections.map((request) => request['voucher_page']), [1, 2]);
      expect(
        repo.selections.every(
          (request) =>
              request['shop_id'] == 2 && request['delivery_type'] == 'doorstep',
        ),
        true,
      );
      expect(repo.orderCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
