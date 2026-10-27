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
    return {
      'offers': {
        'current_page': number,
        'last_page': 2,
        'data': [
          {
            'revision_id': number,
            'code': 'TEST-$number',
            'issuer': 'shop',
            'shop_id': 2,
            'shop_name': 'Test shop',
            'name': 'Selected product offer',
            'discount_type': 'percent',
            'discount_value': 10,
            'min_spend': 0,
            'eligible': number == 2,
            'saving': number == 2 ? 15 : 0,
            'unavailable_reason': number == 1
                ? 'This offer has expired.'
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
