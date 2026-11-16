import 'package:flutter/material.dart';

import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../checkout/bag_page.dart';

/// The heart on product cards works like the website: it adds one to the Bag
/// (first in-stock colour and size), and a filled heart opens the Bag.
class BagHeartChoice {
  const BagHeartChoice({this.color, this.size, required this.available});
  final String? color, size;
  final bool available;
}

num _number(dynamic value) =>
    value is num ? value : num.tryParse('$value') ?? 0;

/// Mirrors resources/js/Components/BagHeartButton.tsx default-variant rules.
BagHeartChoice bagHeartChoice(Map<String, dynamic> product) {
  final variants = mapOf(product['variants']);
  final combinations = mapsOf(variants['combinations']);
  final colors = mapsOf(variants['colors']);
  final sizes = mapsOf(variants['sizes']);
  final combination = combinations
      .where((row) => _number(row['stock']) > 0)
      .firstOrNull;
  final color =
      (combination?['color'] ??
              colors.where((c) => c['in_stock'] != false).firstOrNull?['name'])
          ?.toString();
  final size =
      (combination?['size'] ??
              sizes
                  .where((s) => _number(s['stock'] ?? product['stock']) > 0)
                  .firstOrNull?['name'])
          ?.toString();
  final hasVariant = combinations.isNotEmpty
      ? combination != null
      : (colors.isEmpty || color != null) && (sizes.isEmpty || size != null);
  final vacation = mapOf(product['shop'])['vacation_mode'] == true;
  return BagHeartChoice(
    color: color,
    size: size,
    available: _number(product['stock']) > 0 && hasVariant && !vacation,
  );
}

/// The Bag line id for this product from the page's shared props, if any.
int? bagLineFor(Map<String, dynamic>? props, Object? productId) {
  final lines = mapOf(props?['cartItemIdsByProduct']);
  final value = lines['$productId'];
  return value is int ? value : int.tryParse('${value ?? ''}');
}

/// Adds one to the Bag and records the new line in [props] so the heart fills.
Future<void> addHeartToBag(
  BuyerRepository repository,
  Map<String, dynamic> product,
  Map<String, dynamic>? props,
) async {
  final choice = bagHeartChoice(product);
  if (!choice.available) {
    throw const BackendException('This product is currently unavailable.');
  }
  final page = await repository.addToBag(
    product,
    1,
    color: choice.color,
    size: choice.size,
  );
  final lines = Map<String, dynamic>.from(
    mapOf(page.props['cartItemIdsByProduct']),
  );
  if (props != null) {
    props['cartItemIdsByProduct'] = lines.isNotEmpty
        ? lines
        : {...mapOf(props['cartItemIdsByProduct']), '${product['id']}': -1};
  }
}

void openBag(BuildContext context, BuyerRepository repository) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => BagPage(repository: repository)),
  );
}

String bagHeartLabel({required bool inBag, required bool available}) => inBag
    ? 'In your Bag · open Bag'
    : available
    ? 'Add one to Bag'
    : 'Currently unavailable';
