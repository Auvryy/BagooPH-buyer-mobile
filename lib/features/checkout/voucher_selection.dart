import '../../core/web_session.dart';
import '../../core/resource_ids.dart';

int? _voucherResourceId(Object? value) {
  return positiveInt32ResourceId(value);
}

int? _shopSlotId(String key) {
  final id = int.tryParse(key);
  return id != null && id > 0 && id <= 2147483647 && '$id' == key ? id : null;
}

class VoucherSelection {
  const VoucherSelection({
    this.code = '',
    this.platform,
    this.shops = const {},
  });
  final String code;
  final int? platform;
  final Map<String, int> shops;
  Map<String, dynamic> get values => {
    'voucher_code': code,
    'platform_voucher_revision_id': platform,
    'shop_voucher_revision_ids': Map.of(shops),
  };
  factory VoucherSelection.checked(dynamic value) {
    final data = mapOf(value);
    final platform = data['platform_voucher_revision_id'];
    final platformId = platform == null ? null : _voucherResourceId(platform);
    final shops = data['shop_voucher_revision_ids'];
    // PHP emits [] for an empty map; populated slot maps are JSON objects.
    if (!data.containsKey('voucher_code') ||
        !data.containsKey('platform_voucher_revision_id') ||
        (data['voucher_code'] != null && data['voucher_code'] is! String) ||
        platform != null && platformId == null ||
        !(shops is Map || shops is List && shops.isEmpty)) {
      throw const BackendException(
        'The voucher selection could not be confirmed. Refresh checkout.',
      );
    }
    final slots = mapOf(shops);
    final result = <String, int>{};
    for (final entry in slots.entries) {
      final shopId = _shopSlotId(entry.key);
      final revisionId = entry.value == null
          ? null
          : _voucherResourceId(entry.value);
      if (shopId == null || entry.value != null && revisionId == null) {
        throw const BackendException(
          'The shop voucher selection could not be confirmed.',
        );
      }
      if (entry.value != null) {
        result['$shopId'] = revisionId!;
      }
    }
    return VoucherSelection(
      code: data['voucher_code']?.toString() ?? '',
      platform: platformId,
      shops: result,
    );
  }
  VoucherSelection _materialize(List<Map<String, dynamic>> applied) {
    var platformId = platform;
    final shopIds = Map.of(shops);
    if (code.isNotEmpty) {
      for (final offer in applied) {
        final revision = _voucherResourceId(offer['revision_id']);
        if (revision == null) continue;
        if (offer['issuer'] == 'platform') {
          platformId = revision;
        } else if (offer['issuer'] == 'shop') {
          final shopId = _voucherResourceId(offer['shop_id']);
          if (shopId != null) shopIds['$shopId'] = revision;
        }
      }
    }
    return VoucherSelection(platform: platformId, shops: shopIds);
  }

  VoucherSelection choose(
    Map<String, dynamic> offer,
    List<Map<String, dynamic>> applied,
  ) {
    final current = _materialize(applied);
    final revision = _voucherResourceId(offer['revision_id']);
    if (revision == null) return current;
    return offer['issuer'] == 'platform'
        ? VoucherSelection(platform: revision, shops: current.shops)
        : offer['issuer'] == 'shop' &&
              _voucherResourceId(offer['shop_id']) != null
        ? VoucherSelection(
            platform: current.platform,
            shops: {
              ...current.shops,
              '${_voucherResourceId(offer['shop_id'])}': revision,
            },
          )
        : current;
  }

  VoucherSelection remove(String? shop, List<Map<String, dynamic>> applied) {
    final current = _materialize(applied), next = Map.of(current.shops);
    if (shop != null) next.remove(shop);
    return VoucherSelection(
      platform: shop == null ? null : current.platform,
      shops: next,
    );
  }
}
