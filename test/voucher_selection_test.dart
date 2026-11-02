import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/voucher_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const applied = [
    {'issuer': 'platform', 'revision_id': 11},
    {'issuer': 'shop', 'shop_id': 2, 'revision_id': 22},
  ];
  test('choosing a shop voucher retains the voucher applied by code in other slots', () {
    const current = VoucherSelection(code: 'PLATFORM');
    final next = current.choose({
      'issuer': 'shop',
      'shop_id': 3,
      'revision_id': 33,
    }, applied);
    expect(next.code, '');
    expect(next.platform, 11);
    expect(next.shops, {'2': 22, '3': 33});
    expect(current.code, 'PLATFORM');
    expect(current.shops, isEmpty);
  });
  test('removing one slot retains every other applied choice', () {
    const current = VoucherSelection(code: 'PLATFORM');
    final next = current.remove('2', applied);
    expect(next.code, '');
    expect(next.platform, 11);
    expect(next.shops, isEmpty);
    final noPlatform = current.remove(null, applied);
    expect(noPlatform.platform, isNull);
    expect(noPlatform.shops, {'2': 22});
  });
  test(
    'malformed applied revision IDs are not truncated into other vouchers',
    () {
      const current = VoucherSelection(code: 'PLATFORM');
      final next = current.remove(null, [
        {'issuer': 'platform', 'revision_id': 11.5},
        {'issuer': 'shop', 'shop_id': 2, 'revision_id': '22'},
      ]);
      expect(next.platform, isNull);
      expect(next.shops, isEmpty);
    },
  );
  test(
    'malformed voucher offers cannot become a different selected voucher',
    () {
      const current = VoucherSelection();
      expect(
        current.choose({
          'issuer': 'platform',
          'revision_id': 11.5,
        }, const []).platform,
        isNull,
      );
      expect(
        current.choose({
          'issuer': 'shop',
          'shop_id': 2.5,
          'revision_id': 22,
        }, const []).shops,
        isEmpty,
      );
    },
  );
  test(
    'server repair accepts empty PHP maps and rejects malformed slot IDs',
    () {
      final next = VoucherSelection.checked({
        'voucher_code': null,
        'platform_voucher_revision_id': 11,
        'shop_voucher_revision_ids': {'2': null, '3': 33},
      });
      expect(next.platform, 11);
      expect(next.shops, {'3': 33});
      expect(
        VoucherSelection.checked({
          'voucher_code': null,
          'platform_voucher_revision_id': null,
          'shop_voucher_revision_ids': [],
        }).shops,
        isEmpty,
      );
      expect(
        () => VoucherSelection.checked({
          'voucher_code': null,
          'platform_voucher_revision_id': -1,
          'shop_voucher_revision_ids': {},
        }),
        throwsA(isA<BackendException>()),
      );
      for (final id in [11.0, '11', 2147483648]) {
        expect(
          () => VoucherSelection.checked({
            'voucher_code': null,
            'platform_voucher_revision_id': id,
            'shop_voucher_revision_ids': {},
          }),
          throwsA(isA<BackendException>()),
          reason: '$id',
        );
      }
      for (final shopId in ['02', '+2', '2147483648']) {
        expect(
          () => VoucherSelection.checked({
            'voucher_code': null,
            'platform_voucher_revision_id': null,
            'shop_voucher_revision_ids': {shopId: null},
          }),
          throwsA(isA<BackendException>()),
          reason: shopId,
        );
      }
    },
  );
}
