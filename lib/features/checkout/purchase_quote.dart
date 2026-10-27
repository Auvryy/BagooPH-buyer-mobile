import '../../core/web_session.dart';
import '../products/product_model.dart';

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
  if (itemIds != null) {
    final expected = itemIds.toSet();
    final rows = mapsOf(quote['items']);
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
