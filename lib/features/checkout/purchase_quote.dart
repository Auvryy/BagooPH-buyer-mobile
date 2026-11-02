import '../../core/web_session.dart';
import '../../core/resource_ids.dart';
import '../products/product_model.dart';

bool _optionalPositiveQuantity(Map<String, dynamic> row, String key) {
  if (!row.containsKey(key)) return true;
  final value = row[key];
  return value is int && value > 0;
}

bool _optionalNonnegativeAmount(Map<String, dynamic> row, String key) {
  if (!row.containsKey(key)) return true;
  final value = amount(row[key]);
  return value != null && value >= 0;
}

bool _validPriceSegment(Object? value) {
  final segment = mapOf(value);
  final quantity = segment['quantity'];
  final unitPrice = amount(segment['unit_price']);
  final subtotal = amount(segment['subtotal']);
  return value is Map &&
      quantity is int &&
      quantity > 0 &&
      unitPrice != null &&
      unitPrice >= 0 &&
      subtotal != null &&
      subtotal >= 0 &&
      (unitPrice * quantity * 100).round() == (subtotal * 100).round();
}

bool _validQuoteLine(Map<String, dynamic> row) {
  if (!_optionalPositiveQuantity(row, 'quantity') ||
      !_optionalNonnegativeAmount(row, 'unit_price') ||
      !_optionalNonnegativeAmount(row, 'subtotal')) {
    return false;
  }
  final rawSegments = row['price_segments'];
  if (rawSegments != null && rawSegments is! List) return false;
  final segments = mapsOf(rawSegments);
  if (rawSegments is List &&
      (segments.length != rawSegments.length ||
          segments.any((segment) => !_validPriceSegment(segment)))) {
    return false;
  }
  if (segments.isNotEmpty) {
    final segmentQuantity = segments.fold<int>(
      0,
      (sum, segment) => sum + (segment['quantity'] as int),
    );
    final segmentSubtotal = segments.fold<double>(
      0,
      (sum, segment) => sum + amount(segment['subtotal'])!,
    );
    final lineQuantity = row['quantity'];
    final lineUnitPrice = amount(row['unit_price']);
    final lineSubtotal = amount(row['subtotal']);
    if (lineQuantity != null && lineQuantity != segmentQuantity ||
        lineUnitPrice != null &&
            (lineUnitPrice * 100).round() !=
                (amount(segments.first['unit_price'])! * 100).round() ||
        lineSubtotal != null &&
            (lineSubtotal * 100).round() != (segmentSubtotal * 100).round()) {
      return false;
    }
  }
  final hasLineDetails =
      row.containsKey('quantity') &&
      row.containsKey('unit_price') &&
      row.containsKey('subtotal');
  return segments.isNotEmpty || hasLineDetails;
}

bool _validVoucherOffer(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) return false;
  final offer = Map<String, dynamic>.from(value);
  final issuer = offer['issuer'];
  final shopId = offer['shop_id'];
  final discountType = offer['discount_type'];
  final discountTypes = issuer == 'platform'
      ? const {'fixed', 'percent', 'free_shipping'}
      : const {'fixed', 'percent'};
  return positiveResourceId(offer['id']) != null &&
      positiveResourceId(offer['revision_id']) != null &&
      offer['code'] is String &&
      (offer['code'] as String).trim().isNotEmpty &&
      offer['name'] is String &&
      (offer['name'] as String).trim().isNotEmpty &&
      const {'platform', 'shop'}.contains(issuer) &&
      discountTypes.contains(discountType) &&
      (issuer == 'platform'
          ? shopId == null
          : positiveResourceId(shopId) != null) &&
      (offer['shop_name'] == null || offer['shop_name'] is String) &&
      const {'all', 'selected'}.contains(offer['product_scope']);
}

bool _validCheckoutDiscountMetadata(
  Map<String, dynamic> quote,
  List<Map<String, dynamic>> shops,
) {
  final rawVouchers = quote['vouchers'];
  final rawRedemptions = quote['redemptions'];
  if (rawVouchers is! List ||
      rawRedemptions is! List ||
      !quote.containsKey('voucher') ||
      !quote.containsKey('voucher_error') ||
      rawVouchers.any((row) => !_validVoucherOffer(row))) {
    return false;
  }

  final vouchers = rawVouchers
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();
  final voucher = quote['voucher'];
  if (voucher == null) {
    if (vouchers.length == 1) return false;
  } else if (!_validVoucherOffer(voucher) ||
      vouchers.length != 1 ||
      mapOf(voucher)['revision_id'] != vouchers.single['revision_id']) {
    return false;
  }
  final error = quote['voucher_error'];
  if (error != null && (error is! String || error.trim().isEmpty)) {
    return false;
  }
  if (quote.containsKey('failed_revision_id') &&
      positiveResourceId(quote['failed_revision_id']) == null) {
    return false;
  }

  final voucherRevisionIds = <int>{};
  for (final offer in vouchers) {
    final id = positiveResourceId(offer['revision_id']);
    if (id == null || !voucherRevisionIds.add(id)) return false;
  }

  final shopIds = shops.map((row) => row['shop_id'] as int).toSet();
  final redemptionIds = <int>{};
  final productByShop = <int, int>{};
  final shippingByShop = <int, int>{};
  var redemptionTotal = 0;
  for (final value in rawRedemptions) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      return false;
    }
    final redemption = Map<String, dynamic>.from(value);
    final revisionId = positiveResourceId(redemption['revision_id']);
    final discountCents = redemption['discount_cents'];
    final rawAllocations = redemption['allocations'];
    if (revisionId == null ||
        !redemptionIds.add(revisionId) ||
        discountCents is! int ||
        discountCents <= 0 ||
        rawAllocations is! List ||
        rawAllocations.isEmpty) {
      return false;
    }
    var allocationTotal = 0;
    final allocatedShops = <int>{};
    for (final allocationValue in rawAllocations) {
      if (allocationValue is! Map ||
          allocationValue.keys.any((key) => key is! String)) {
        return false;
      }
      final allocation = Map<String, dynamic>.from(allocationValue);
      final shopId = positiveResourceId(allocation['shop_id']);
      final product = allocation['product_discount_cents'];
      final shipping = allocation['shipping_discount_cents'];
      final sellerExpense = allocation['seller_expense_cents'];
      final platformExpense = allocation['platform_expense_cents'];
      if (shopId == null ||
          !shopIds.contains(shopId) ||
          !allocatedShops.add(shopId) ||
          product is! int ||
          product < 0 ||
          shipping is! int ||
          shipping < 0 ||
          sellerExpense is! int ||
          sellerExpense < 0 ||
          platformExpense is! int ||
          platformExpense < 0 ||
          product + shipping <= 0 ||
          sellerExpense + platformExpense != product + shipping) {
        return false;
      }
      allocationTotal += product + shipping;
      productByShop.update(
        shopId,
        (sum) => sum + product,
        ifAbsent: () => product,
      );
      shippingByShop.update(
        shopId,
        (sum) => sum + shipping,
        ifAbsent: () => shipping,
      );
    }
    if (allocationTotal != discountCents) return false;
    redemptionTotal += discountCents;
  }

  if (redemptionIds.length != voucherRevisionIds.length ||
      !voucherRevisionIds.containsAll(redemptionIds) ||
      redemptionTotal != (amount(quote['discount'])! * 100).round()) {
    return false;
  }
  for (final shop in shops) {
    final shopId = shop['shop_id'] as int;
    final product = amount(shop['product_discount']);
    final shipping = amount(shop['shipping_discount']);
    if (product == null ||
        product < 0 ||
        shipping == null ||
        shipping < 0 ||
        (product * 100).round() != (productByShop[shopId] ?? 0) ||
        (shipping * 100).round() != (shippingByShop[shopId] ?? 0)) {
      return false;
    }
  }
  final shippingDiscount = amount(quote['shipping_discount']);
  return shippingDiscount != null &&
      shippingDiscount >= 0 &&
      (shippingDiscount * 100).round() ==
          shippingByShop.values.fold<int>(0, (sum, value) => sum + value);
}

Map<String, dynamic> checkedPurchaseQuote(
  dynamic value, {
  Iterable<int>? itemIds,
}) {
  final quote = mapOf(value);
  if (quote['items'] is! List ||
      quote['shops'] is! List ||
      ![
        'subtotal',
        'shipping_fee',
        'discount',
        'shipping_discount',
        'total',
      ].every(
        (key) => amount(quote[key]) != null && amount(quote[key])! >= 0,
      )) {
    throw const BackendException(
      'The selected items and total could not be confirmed. Refresh to try again.',
    );
  }
  final rows = requireRowsWithIds(
    quote['items'],
    idKey: 'id',
    error: 'The selected item prices could not be confirmed. Refresh to try again.',
  );
  if (rows.any((row) => !_validQuoteLine(row))) {
    throw const BackendException(
      'The selected item prices could not be confirmed. Refresh to try again.',
    );
  }
  final shops = requireRowsWithIds(
    quote['shops'],
    idKey: 'shop_id',
    error: 'The quoted shop choices could not be confirmed. Refresh checkout.',
  );
  if (!_validCheckoutDiscountMetadata(quote, shops)) {
    throw const BackendException(
      'The voucher discounts could not be confirmed. Refresh checkout.',
    );
  }
  if (itemIds != null) {
    final expected = itemIds.toSet();
    final actual = rows.map((row) => row['id']).toSet();
    if (rows.length != expected.length ||
        actual.length != expected.length ||
        !expected.every(actual.contains)) {
      throw const BackendException(
        'The quote does not match your selected items. Refresh before continuing.',
      );
    }
  }
  return quote;
}
