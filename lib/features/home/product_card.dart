import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';

double? amount(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
String pesos(dynamic value) {
  final number = amount(value);
  if (number == null) {
    return 'Price unavailable';
  }
  final pieces = number.toStringAsFixed(2).split('.');
  final grouped = pieces.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return '₱$grouped.${pieces[1]}';
}

String productPrice(Map<String, dynamic> product) {
  final range = mapOf(product['price_range']);
  final minimum =
      amount(range['min']) ??
      amount(mapOf(product['sale_offer'])['effective_price']) ??
      amount(product['price']);
  final maximum = amount(range['max']);
  return maximum != null && minimum != null && maximum > minimum
      ? '${pesos(minimum)} – ${pesos(maximum)}'
      : pesos(minimum);
}

Uri? imageUri(WebSession session, dynamic source) {
  if (source is! String || source.isEmpty) {
    return null;
  }
  try {
    final uri = session.origin.resolve(source);
    return ['http', 'https'].contains(uri.scheme) && uri.userInfo.isEmpty
        ? uri
        : null;
  } on FormatException {
    return null;
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.session,
    required this.onTap,
  });
  final Map<String, dynamic> product;
  final WebSession session;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final rating = amount(product['rating']);
    final count = (product['sales_count'] as num?)?.toInt() ?? 0;
    final shop = mapOf(product['shop']);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: BagooTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ExcludeSemantics(
                    child: RemoteImage(
                      uri: imageUri(session, product['featured_image']),
                    ),
                  ),
                  if ((amount(product['stock']) ?? 0) <= 0)
                    Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: BagooTheme.ink,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Out of stock',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['name']?.toString() ?? 'Product',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    productPrice(product),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: BagooTheme.strong,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const ExcludeSemantics(
                            child: Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: Color(0xFF92400E),
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            rating == null
                                ? 'No reviews'
                                : rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 11,
                              color: BagooTheme.muted,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '$count sold',
                        style: const TextStyle(
                          fontSize: 11,
                          color: BagooTheme.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    shop['city']?.toString() ?? 'Location not provided',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: BagooTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showProduct(
  BuildContext context,
  Map<String, dynamic> product,
  WebSession session,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .8,
    maxChildSize: .95,
    minChildSize: .4,
    builder: (context, controller) => ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: 'Close product',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: AspectRatio(
            aspectRatio: 1.3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: RemoteImage(
                uri: imageUri(session, product['featured_image']),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          product['name']?.toString() ?? 'Product',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(
          productPrice(product),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: BagooTheme.strong,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          mapOf(product['shop'])['name']?.toString() ?? 'Shop not provided',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          mapOf(product['shop'])['city']?.toString() ?? 'Location not provided',
        ),
        const SizedBox(height: 20),
        Text(
          product['description']?.toString() ?? 'No description provided.',
          style: const TextStyle(height: 1.7),
        ),
        const SizedBox(height: 24),
        const Text(
          'Shopping Bag and checkout are available on the BagooPH website.',
          style: TextStyle(fontSize: 13, color: BagooTheme.muted, height: 1.6),
        ),
      ],
    ),
  ),
);
