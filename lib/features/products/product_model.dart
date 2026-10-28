import 'dart:math' as math;

import '../../core/web_session.dart';

double? amount(dynamic value) {
  final number = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  return number != null && number.isFinite ? number : null;
}

int cents(dynamic value) => ((amount(value) ?? 0) * 100).round();
String pesos(dynamic value) {
  final number = amount(value);
  if (number == null) {
    return 'Price unavailable';
  }
  final pieces = number.toStringAsFixed(2).split('.');
  return '₱${pieces.first.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}.${pieces[1]}';
}

double? recordedRating(dynamic value) {
  final result = amount(value);
  return result != null && result >= 1 && result <= 5 ? result : null;
}

String ratingLabel(dynamic value) =>
    recordedRating(value)?.toStringAsFixed(1) ?? 'No ratings yet';

class ProductPrice {
  ProductPrice(this.product);
  final Map<String, dynamic> product;
  Map<String, dynamic> get range => mapOf(product['price_range']);
  Map<String, dynamic> get sale =>
      mapOf(mapOf(product['sale_offer'])['active']);
  double get minimum =>
      amount(range['min']) ??
      amount(mapOf(product['sale_offer'])['effective_price']) ??
      amount(product['price']) ??
      0;
  double get maximum => amount(range['max']) ?? minimum;
  bool get ranged => maximum > minimum;
  double? get comparison {
    final regular =
        amount(range['regular_min']) ?? amount(product['price']) ?? minimum;
    if (sale.isNotEmpty && minimum < regular) {
      return regular;
    }
    final comparison = amount(product['compare_at_price']);
    return comparison == null
        ? null
        : regular + comparison - (amount(product['price']) ?? regular);
  }

  int? get discount => !ranged && comparison != null && comparison! > minimum
      ? ((comparison! - minimum) / comparison! * 100).round()
      : null;
  String get label =>
      ranged ? '${pesos(minimum)} – ${pesos(maximum)}' : pesos(minimum);
}

String productPrice(Map<String, dynamic> product) =>
    ProductPrice(product).label;

class ProductSelection {
  ProductSelection(this.page);
  WebPage page;
  String? color;
  String? size;
  String quantityText = '1';
  Map<String, dynamic> get product => mapOf(page.props['product']);
  Map<String, dynamic> get variants => mapOf(page.props['variations']);
  List<Map<String, dynamic>> get colors => mapsOf(variants['colors']);
  List<Map<String, dynamic>> get sizes => mapsOf(variants['sizes']);
  List<Map<String, dynamic>> get combinations =>
      mapsOf(variants['combinations']);
  bool get hasMatrix => variants['combinations'] is List;
  bool get complete =>
      (colors.isEmpty || color != null) && (sizes.isEmpty || size != null);
  Map<String, dynamic> get colorOption =>
      colors.where((o) => o['name'] == color).firstOrNull ?? {};
  Map<String, dynamic> get sizeOption =>
      sizes.where((o) => o['name'] == size).firstOrNull ?? {};
  Map<String, dynamic> get combination =>
      combinations
          .where((o) => o['color'] == color && o['size'] == size)
          .firstOrNull ??
      {};
  bool get vacation => mapOf(product['shop'])['vacation_mode'] == true;
  bool get approved =>
      !page.isCached &&
      page.user?['role'] == 'buyer' &&
      page.user?['status'] == 'active' &&
      ['approved', 'verified'].contains(page.user?['kyc_status']);
  bool get canChangeBag =>
      !page.isCached &&
      (page.user == null ||
          page.user?['role'] == 'buyer' &&
              ['active', 'pending_approval'].contains(page.user?['status']));
  bool colorAvailable(String option) =>
      !colors.any((row) => row['name'] == option && row['in_stock'] == false) &&
      (!hasMatrix ||
          combinations.any(
            (row) => row['color'] == option && (amount(row['stock']) ?? 0) > 0,
          ));
  int get totalStock => (amount(product['stock']) ?? 0).toInt();
  int get stock => hasMatrix
      ? (amount(combination['stock']) ?? (complete ? 0 : totalStock)).toInt()
      : math.min(
          totalStock,
          (amount(sizeOption['stock']) ?? totalStock).toInt(),
        );
  bool sizeAvailable(String option) => !hasMatrix
      ? (amount(
                  sizes
                      .where((row) => row['name'] == option)
                      .firstOrNull?['stock'],
                ) ??
                totalStock) >
            0
      : combinations.any(
          (o) =>
              o['size'] == option &&
              (color == null || o['color'] == color) &&
              (amount(o['stock']) ?? 0) > 0,
        );
  List<Map<String, dynamic>> get cart => mapsOf(page.props['cartQuantities']);
  int get totalInBag =>
      cart.fold(0, (n, row) => n + (amount(row['quantity']) ?? 0).toInt());
  int get lineInBag => cart
      .where((row) => row['color'] == color && row['size'] == size)
      .fold(0, (n, row) => n + (amount(row['quantity']) ?? 0).toInt());
  int get maxQuantity {
    if (vacation || colorOption['in_stock'] == false) {
      return 0;
    }
    final scoped = hasMatrix
        ? lineInBag
        : size != null
        ? cart
              .where((row) => row['size'] == size)
              .fold(0, (n, row) => n + (amount(row['quantity']) ?? 0).toInt())
        : totalInBag;
    return [
      99 - lineInBag,
      totalStock - totalInBag,
      (amount(page.props['purchaseAllowance']) ?? 2147483647).toInt() -
          totalInBag,
      stock - scoped,
    ].reduce(math.min).clamp(0, 99);
  }

  String? get quantityError {
    if (!complete) {
      return 'Choose each product option before continuing.';
    }
    if (!RegExp(r'^[1-9][0-9]?$').hasMatch(quantityText)) {
      return 'Enter a whole quantity from 1 to 99.';
    }
    if (maxQuantity < 1) {
      return stock <= 0
          ? 'This selection is out of stock.'
          : 'The available quantity is already in your Bag or the shop has paused purchases.';
    }
    if (int.parse(quantityText) > maxQuantity) {
      return 'Only $maxQuantity more can be added.';
    }
    return null;
  }

  int get quantity => int.tryParse(quantityText) ?? 1;
  double get regular {
    if (!complete) {
      return amount(mapOf(product['price_range'])['regular_min']) ??
          amount(product['price']) ??
          0;
    }
    if (variants['pricing_mode'] == 'independent' && combination.isNotEmpty) {
      return amount(combination['price']) ?? 0;
    }
    return (cents(product['price']) +
            cents(combination['extra_price'] ?? sizeOption['extra_price'])) /
        100;
  }

  double get price {
    if (!complete) {
      return ProductPrice(product).minimum;
    }
    final sale = ProductPrice(product).sale;
    if (sale.isEmpty) {
      return regular;
    }
    if (sale['discount_type'] == 'percentage' &&
        amount(sale['percentage']) != null) {
      return math.max(
            1,
            ((cents(regular) * (100 - amount(sale['percentage'])!) + 50) / 100)
                .floor(),
          ) /
          100;
    }
    final minimum = cents(
      mapOf(product['price_range'])['regular_min'] ?? product['price'],
    );
    return math.max(
          1,
          cents(regular) - math.max(0, minimum - cents(sale['price'])),
        ) /
        100;
  }

  double? get comparison {
    if (ProductPrice(product).sale.isNotEmpty && price < regular) {
      return regular;
    }
    return cents(product['compare_at_price']) > cents(product['price'])
        ? (cents(regular) +
                  cents(product['compare_at_price']) -
                  cents(product['price'])) /
              100
        : null;
  }

  String get priceLabel => !complete && ProductPrice(product).ranged
      ? productPrice(product)
      : pesos(price);
  List<String> get gallery => <dynamic>[
    product['featured_image'],
    ...mapsOf(product['images']).map((i) => i['image_url']),
    ...colors.map((c) => c['image_url']),
  ].whereType<String>().where((s) => s.isNotEmpty).toSet().toList();
}
