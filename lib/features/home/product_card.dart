import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../products/product_model.dart';
export '../products/product_model.dart' show amount, pesos, productPrice;

const productCardBodyHeight = 244.0;

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

/// Matches the web card hierarchy with fixed slots so rows remain aligned.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.session,
    required this.onTap,
    this.onSave,
    this.saved = false,
    this.saving = false,
    this.saveLabel = 'Sign in to save',
    this.bodyExtent,
    this.error,
  });
  final Map<String, dynamic> product;
  final WebSession session;
  final VoidCallback onTap;
  final VoidCallback? onSave;
  final bool saved;
  final bool saving;
  final String saveLabel;
  final double? bodyExtent;
  final String? error;
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final pricing = ProductPrice(product);
    final out = (amount(product['stock']) ?? 0) <= 0;
    final shop = mapOf(product['shop']);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: BagooTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onTap,
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: out ? .7 : 1,
                      child: ExcludeSemantics(
                        child: RemoteImage(
                          uri: imageUri(session, product['featured_image']),
                        ),
                      ),
                    ),
                    if (shop['vacation_mode'] == true)
                      Align(
                        alignment: Alignment.topLeft,
                        child: _Badge(
                          'On vacation',
                          color: const Color(0xFFFFF4DF),
                          textColor: const Color(0xFF92400E),
                        ),
                      ),
                    if (out)
                      Align(
                        alignment: Alignment.topRight,
                        child: _Badge(
                          'Out of stock',
                          color: BagooTheme.ink,
                          textColor: Colors.white,
                        ),
                      ),
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Wrap(
                        children: [
                          Semantics(
                            label: 'Cash on Delivery',
                            child: ExcludeSemantics(
                              child: ClipPath(
                                clipper: const _Ribbon(),
                                child: Container(
                                  color: BagooTheme.crimson,
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    5,
                                    14,
                                    5,
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.local_shipping_outlined,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'COD',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (pricing.discount != null)
                            ClipPath(
                              clipper: const _Ribbon(),
                              child: Container(
                                color: const Color(0xFFFBBF24),
                                padding: const EdgeInsets.fromLTRB(8, 5, 14, 5),
                                child: Text(
                                  '-${pricing.discount}%',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: BagooTheme.ink,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: bodyExtent ?? productCardBodyHeight * scale,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: onTap,
                      child: SizedBox(
                        height: 34 * scale,
                        child: Text(
                          product['name']?.toString() ?? 'Product',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 42 * scale,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            pricing.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              height: 1.2,
                              fontWeight: FontWeight.w900,
                              color: BagooTheme.crimson,
                            ),
                          ),
                          if (pricing.discount != null)
                            Text(
                              pesos(pricing.comparison),
                              style: const TextStyle(
                                fontSize: 10,
                                color: BagooTheme.muted,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 12, color: Color(0xFFE2E8F0)),
                    SizedBox(
                      height: 30 * scale,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Icon(
                                recordedRating(product['rating']) == null
                                    ? Icons.star_border_rounded
                                    : Icons.star_rounded,
                                size: 14,
                                color: const Color(0xFFB45309),
                              ),
                            ),
                            TextSpan(
                              text:
                                  ' ${ratingLabel(product['rating'])}  ·  ${product['sales_count'] ?? 0} sold',
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          color: BagooTheme.muted,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const ExcludeSemantics(
                          child: Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color: BagooTheme.muted,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            (shop['city']?.toString().trim().isNotEmpty ??
                                    false)
                                ? shop['city'].toString()
                                : 'Location unavailable',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.3,
                              color: BagooTheme.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (error != null)
                      Text(
                        error!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFBE123C),
                        ),
                      ),
                    OutlinedButton(
                      onPressed: saving ? null : onSave,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        foregroundColor: BagooTheme.strong,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ExcludeSemantics(
                            child: Icon(
                              saving
                                  ? Icons.hourglass_top
                                  : saved
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              saving ? 'Saving…' : saveLabel,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, {required this.color, required this.textColor});
  final String label;
  final Color color;
  final Color textColor;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(6),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
    ),
  );
}

class _Ribbon extends CustomClipper<Path> {
  const _Ribbon();
  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width - 6, size.height / 2)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();
  @override
  bool shouldReclip(_Ribbon oldClipper) => false;
}

int productColumns(double width, double scale) => scale > 1.4
    ? (width / 280).floor().clamp(1, 4)
    : width >= 1024
    ? 6
    : width >= 768
    ? 4
    : width >= 640
    ? 3
    : 2;
