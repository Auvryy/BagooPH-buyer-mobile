import '../../core/web_session.dart';

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
    final shops = data['shop_voucher_revision_ids'];
    // PHP emits [] for an empty map; populated slot maps are JSON objects.
    if (!data.containsKey('voucher_code') ||
        !data.containsKey('platform_voucher_revision_id') ||
        (data['voucher_code'] != null && data['voucher_code'] is! String) ||
        platform != null &&
            (platform is! num ||
                platform <= 0 ||
                platform != platform.toInt()) ||
        !(shops is Map || shops is List && shops.isEmpty)) {
      throw const BackendException(
        'The voucher selection could not be confirmed. Refresh checkout.',
      );
    }
    final slots = mapOf(shops);
    final result = <String, int>{};
    for (final entry in slots.entries) {
      if (int.tryParse(entry.key) == null ||
          int.parse(entry.key) <= 0 ||
          entry.value != null &&
              (entry.value is! num ||
                  entry.value <= 0 ||
                  entry.value != entry.value.toInt())) {
        throw const BackendException(
          'The shop voucher selection could not be confirmed.',
        );
      }
      if (entry.value != null) result[entry.key] = (entry.value as num).toInt();
    }
    return VoucherSelection(
      code: data['voucher_code']?.toString() ?? '',
      platform: (platform as num?)?.toInt(),
      shops: result,
    );
  }
  VoucherSelection _materialize(List<Map<String, dynamic>> applied) {
    var platformId = platform;
    final shopIds = Map.of(shops);
    if (code.isNotEmpty) {
      for (final offer in applied) {
        final revision = (offer['revision_id'] as num?)?.toInt();
        if (revision == null) continue;
        if (offer['issuer'] == 'platform') {
          platformId = revision;
        } else if (offer['shop_id'] != null) {
          shopIds[offer['shop_id'].toString()] = revision;
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
    final revision = (offer['revision_id'] as num?)?.toInt();
    if (revision == null) return current;
    return offer['issuer'] == 'platform'
        ? VoucherSelection(platform: revision, shops: current.shops)
        : VoucherSelection(
            platform: current.platform,
            shops: {...current.shops, offer['shop_id'].toString(): revision},
          );
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
