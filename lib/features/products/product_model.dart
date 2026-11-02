import 'dart:math' as math;

import '../../core/count_metadata.dart';
import '../../core/web_session.dart';
import '../../core/resource_ids.dart';

int? _stockCount(Object? value) {
  final count = nonNegativeCount(value);
  return count != null && count <= 99999 ? count : null;
}

Map<String, dynamic>? _stringKeyedMap(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) return null;
  return Map<String, dynamic>.from(value);
}

List<Map<String, dynamic>>? _stringKeyedRows(Object? value) {
  if (value is! List) return null;
  final rows = <Map<String, dynamic>>[];
  for (final item in value) {
    final row = _stringKeyedMap(item);
    if (row == null) return null;
    rows.add(row);
  }
  return rows;
}

bool _moneyWithin(Object? value, {required double min, required double max}) {
  final number = amount(value);
  if (number == null || number < min || number > max) return false;
  final centsValue = number * 100;
  return centsValue.isFinite &&
      (centsValue - centsValue.round()).abs() < 0.000001;
}

double? amount(dynamic value) {
  final number = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  return number != null && number.isFinite ? number : null;
}

double? _positivePrice(dynamic value) {
  final number = amount(value);
  return number != null && number > 0 ? number : null;
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
  double? get minimum =>
      _positivePrice(range['min']) ??
      _positivePrice(mapOf(product['sale_offer'])['effective_price']) ??
      _positivePrice(product['price']);
  double? get maximum => _positivePrice(range['max']) ?? minimum;
  bool get ranged => minimum != null && maximum != null && maximum! > minimum!;
  double? get comparison {
    final lowest = minimum;
    if (lowest == null) return null;
    final regular =
        _positivePrice(range['regular_min']) ??
        _positivePrice(product['price']) ??
        lowest;
    if (sale.isNotEmpty && lowest < regular) {
      return regular;
    }
    final comparison = _positivePrice(product['compare_at_price']);
    return comparison == null
        ? null
        : regular + comparison - (_positivePrice(product['price']) ?? regular);
  }

  int? get discount {
    final lowest = minimum;
    final compareAt = comparison;
    return lowest != null && !ranged && compareAt != null && compareAt > lowest
        ? ((compareAt - lowest) / compareAt * 100).round()
        : null;
  }

  String get label {
    final lowest = minimum;
    if (lowest == null) return 'Price unavailable';
    final highest = maximum ?? lowest;
    return highest > lowest
        ? '${pesos(lowest)} – ${pesos(highest)}'
        : pesos(lowest);
  }
}

List<Map<String, dynamic>>? completeProductCards(Object? raw) {
  if (raw is! List || raw.length > 24) return null;
  final rows = <Map<String, dynamic>>[];
  final ids = <int>{};
  final slugs = <String>{};
  for (final row in raw) {
    if (row is! Map || row.keys.any((key) => key is! String)) return null;
    final product = Map<String, dynamic>.from(row);
    final id = positiveResourceId(product['id']);
    final slug = product['slug'];
    final name = product['name'];
    if (id == null ||
        !ids.add(id) ||
        slug is! String ||
        slug.trim().isEmpty ||
        slug != slug.trim() ||
        !slugs.add(slug.toLowerCase()) ||
        name is! String ||
        name.trim().isEmpty ||
        _stockCount(product['stock']) == null) {
      return null;
    }
    rows.add(product);
  }
  return rows;
}

List<Map<String, dynamic>>? completeRelatedProducts(Object? raw) =>
    completeProductCards(raw);

String productPrice(Map<String, dynamic> product) =>
    ProductPrice(product).label;

class ProductSelection {
  ProductSelection(this.page) {
    if (positiveResourceId(_stringKeyedMap(page.props['product'])?['id']) ==
        null) {
      throw const BackendException('This product could not be confirmed.');
    }
  }
  WebPage page;
  String? color;
  String? size;
  String quantityText = '1';
  Map<String, dynamic> get product =>
      _stringKeyedMap(page.props['product']) ?? const {};
  Map<String, dynamic> get variants =>
      _stringKeyedMap(page.props['variations']) ?? const {};
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
  bool get inventoryCountsValid {
    if (_stockCount(product['stock']) == null) return false;

    final variantData = _stringKeyedMap(page.props['variations']);
    if (variantData == null) return false;
    final rawColors = variantData['colors'];
    final rawSizes = variantData['sizes'];
    if ((!variantData.containsKey('colors') &&
            !variantData.containsKey('sizes')) ||
        variantData.containsKey('colors') && rawColors is! List ||
        variantData.containsKey('sizes') && rawSizes is! List) {
      return false;
    }

    final allowance = page.props['purchaseAllowance'];
    if (allowance != null && nonNegativeCount(allowance) == null) return false;

    final rawCart = page.props['cartQuantities'];
    if (rawCart != null) {
      final rows = _stringKeyedRows(rawCart);
      if (rows == null ||
          rows.any(
            (row) =>
                row['quantity'] is! int ||
                (row['quantity'] as int) < 1 ||
                (row['quantity'] as int) > 99,
          )) {
        return false;
      }
    }

    if (rawColors != null) {
      final rows = _stringKeyedRows(rawColors);
      if (rows == null) return false;
      final names = <String>{};
      if (rows.any((row) {
        final name = row['name'], inStock = row['in_stock'];
        return name is! String ||
            name.trim().isEmpty ||
            !names.add(name) ||
            inStock != null && inStock is! bool;
      })) {
        return false;
      }
    }

    if (rawSizes != null) {
      final rows = _stringKeyedRows(rawSizes);
      if (rows == null) return false;
      final names = <String>{};
      if (rows.any((row) {
        final name = row['name'];
        return name is! String ||
            name.trim().isEmpty ||
            !names.add(name) ||
            row['stock'] != null && _stockCount(row['stock']) == null;
      })) {
        return false;
      }
    }

    final rawCombinations = variantData['combinations'];
    if (rawCombinations != null) {
      final rows = _stringKeyedRows(rawCombinations);
      if (rows == null) return false;
      final pairs = <(String?, String?)>{};
      if (rows.any((row) {
        final color = row['color'], size = row['size'];
        if ((color != null && color is! String) ||
            (size != null && size is! String)) {
          return true;
        }
        return _stockCount(row['stock']) == null ||
            !pairs.add((color as String?, size as String?));
      })) {
        return false;
      }
    }
    return true;
  }

  bool get pricingDataValid {
    final variantData = _stringKeyedMap(page.props['variations']);
    if (variantData == null) return false;
    final pricingMode = variantData['pricing_mode'];
    if (pricingMode != null &&
        pricingMode != 'surcharge' &&
        pricingMode != 'independent') {
      return false;
    }

    final rawCombinations = variantData['combinations'];
    if (rawCombinations != null) {
      final rows = _stringKeyedRows(rawCombinations);
      if (rows == null) return false;
      for (final row in rows) {
        if (pricingMode == 'independent') {
          if (!_moneyWithin(row['price'], min: 1, max: 1000000)) return false;
        } else if (row['extra_price'] != null &&
            !_moneyWithin(row['extra_price'], min: 0, max: 99999999.99)) {
          return false;
        }
      }
      if (pricingMode == 'independent' && rows.isEmpty) return false;
    } else {
      if (pricingMode == 'independent') return false;
      final rawSizes = variantData['sizes'];
      if (rawSizes != null) {
        final sizes = _stringKeyedRows(rawSizes);
        if (sizes == null ||
            sizes.any(
              (row) =>
                  row['extra_price'] != null &&
                  !_moneyWithin(row['extra_price'], min: 0, max: 99999999.99),
            )) {
          return false;
        }
      }
    }

    final rawSaleOffer = product['sale_offer'];
    if (rawSaleOffer != null) {
      final saleOffer = _stringKeyedMap(rawSaleOffer);
      if (saleOffer == null) return false;
      if (saleOffer.containsKey('effective_price') &&
          !_moneyWithin(
            saleOffer['effective_price'],
            min: 0.01,
            max: 99999999.99,
          )) {
        return false;
      }
      final rawActiveSale = saleOffer['active'];
      if (rawActiveSale != null) {
        final activeSale = _stringKeyedMap(rawActiveSale);
        if (activeSale == null) return false;
        final discountType = activeSale['discount_type'];
        if (discountType == 'percentage') {
          final percentage = activeSale['percentage'];
          if (percentage is! int || percentage < 1 || percentage > 99) {
            return false;
          }
          if (activeSale.containsKey('price') &&
              !_moneyWithin(activeSale['price'], min: 0.01, max: 99999999.99)) {
            return false;
          }
        } else if (discountType != 'fixed' ||
            !_moneyWithin(activeSale['price'], min: 0.01, max: 99999999.99)) {
          return false;
        }
      }
    }
    return true;
  }

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
      inventoryCountsValid &&
      !colors.any((row) => row['name'] == option && row['in_stock'] == false) &&
      (!hasMatrix ||
          combinations.any(
            (row) => row['color'] == option && _stockCount(row['stock'])! > 0,
          ));
  int get totalStock => _stockCount(product['stock']) ?? 0;
  int get stock {
    if (!inventoryCountsValid) return 0;
    if (hasMatrix) {
      return _stockCount(combination['stock']) ?? (complete ? 0 : totalStock);
    }
    final selectedStock = sizeOption['stock'];
    return math.min(
      totalStock,
      selectedStock == null ? totalStock : _stockCount(selectedStock)!,
    );
  }

  bool sizeAvailable(String option) {
    if (!inventoryCountsValid) return false;
    if (!hasMatrix) {
      final optionStock = sizes
          .where((row) => row['name'] == option)
          .firstOrNull?['stock'];
      return (optionStock == null ? totalStock : _stockCount(optionStock)!) > 0;
    }
    return combinations.any(
      (row) =>
          row['size'] == option &&
          (color == null || row['color'] == color) &&
          _stockCount(row['stock'])! > 0,
    );
  }

  List<Map<String, dynamic>> get cart => mapsOf(page.props['cartQuantities']);
  int get totalInBag => inventoryCountsValid
      ? cart.fold(0, (n, row) => n + (row['quantity'] as int))
      : 0;
  int get lineInBag => cart
      .where((row) => row['color'] == color && row['size'] == size)
      .fold(0, (n, row) => n + (row['quantity'] as int));
  int get maxQuantity {
    if (!inventoryCountsValid ||
        !pricingDataValid ||
        ProductPrice(product).minimum == null ||
        vacation ||
        colorOption['in_stock'] == false) {
      return 0;
    }
    final scoped = hasMatrix
        ? lineInBag
        : size != null
        ? cart
              .where((row) => row['size'] == size)
              .fold(0, (n, row) => n + (row['quantity'] as int))
        : totalInBag;
    return [
      99 - lineInBag,
      totalStock - totalInBag,
      (nonNegativeCount(page.props['purchaseAllowance']) ?? 2147483647) -
          totalInBag,
      stock - scoped,
    ].reduce(math.min).clamp(0, 99);
  }

  String? get quantityError {
    if (ProductPrice(product).minimum == null) {
      return 'Price could not be confirmed. Refresh this product.';
    }
    if (!pricingDataValid) {
      return 'Price could not be confirmed. Refresh this product.';
    }
    if (!inventoryCountsValid) {
      return 'Available stock and Bag quantities could not be confirmed. Refresh this product.';
    }
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
      return ProductPrice(product).minimum ?? 0;
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
    if (!pricingDataValid) return null;
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

  String get priceLabel {
    final pricing = ProductPrice(product);
    if (pricing.minimum == null || !pricingDataValid) {
      return 'Price unavailable';
    }
    return !complete && pricing.ranged ? pricing.label : pesos(price);
  }

  List<String> get gallery => <dynamic>[
    product['featured_image'],
    ...mapsOf(product['images']).map((i) => i['image_url']),
    ...colors.map((c) => c['image_url']),
  ].whereType<String>().where((s) => s.isNotEmpty).toSet().toList();
}
