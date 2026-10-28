import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../products/product_model.dart';
export '../products/product_model.dart' show amount, pesos, productPrice;

const productCardBodyHeight = 200.0;

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

/// One open target per product, with an independent accessible save control.
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
  final bool saved, saving;
  final String saveLabel;
  final double? bodyExtent;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final pricing = ProductPrice(product);
    final out = (amount(product['stock']) ?? 0) <= 0;
    final shop = mapOf(product['shop']);
    final name = product['name']?.toString() ?? 'Product';
    final location = shop['city']?.toString().trim();
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BagooTheme.panelRadius),
        side: const BorderSide(color: BagooTheme.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InkWell(
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
                          thumbnail: true,
                        ),
                      ),
                      if (out || shop['vacation_mode'] == true)
                        Positioned(
                          top: 8,
                          left: 8,
                          right: 64,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (out)
                                _Badge(
                                  'Out of stock',
                                  color: BagooTheme.ink,
                                  textColor: Colors.white,
                                ),
                              if (shop['vacation_mode'] == true)
                                const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: _Badge(
                                    'On vacation',
                                    color: Color(0xFFFFF4DF),
                                    textColor: Color(0xFF92400E),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Wrap(
                          children: [
                            Semantics(
                              label: 'Cash on Delivery',
                              child: ExcludeSemantics(
                                child: _ribbon(
                                  'COD',
                                  BagooTheme.crimson,
                                  Colors.white,
                                  icon: Icons.local_shipping_outlined,
                                ),
                              ),
                            ),
                            if (pricing.discount != null)
                              _ribbon(
                                '-${pricing.discount}%',
                                const Color(0xFFFBBF24),
                                BagooTheme.ink,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: bodyExtent ?? productCardBodyHeight * scale,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 36 * scale,
                          child: Tooltip(
                            message: name,
                            child: Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.25,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 56 * scale,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pricing.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                  color: BagooTheme.strong,
                                ),
                              ),
                              if (pricing.discount != null)
                                Text(
                                  pesos(pricing.comparison),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    height: 1.2,
                                    color: BagooTheme.muted,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 32 * scale,
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
                                      ' ${ratingLabel(product['rating'])}${(amount(product['sales_count']) ?? 0) > 0 ? ' · ${product['sales_count']} sold' : ''}',
                                ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
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
                                size: 14,
                                color: BagooTheme.muted,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                location == null || location.isEmpty
                                    ? 'Location unavailable'
                                    : location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.3,
                                  color: BagooTheme.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        if (error != null)
                          Tooltip(
                            message: error!,
                            child: Text(
                              error!,
                              semanticsLabel: error,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFBE123C),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: IconButton.filledTonal(
              tooltip: saving ? 'Saving product' : saveLabel,
              onPressed: saving ? null : onSave,
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: Colors.white,
                foregroundColor: BagooTheme.strong,
                disabledBackgroundColor: const Color(0xFFF1F5F9),
              ),
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      saved
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 21,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ribbon(
    String label,
    Color background,
    Color foreground, {
    IconData? icon,
  }) => ClipPath(
    clipper: const _Ribbon(),
    child: Container(
      color: background,
      padding: const EdgeInsets.fromLTRB(8, 5, 14, 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: foreground,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, {required this.color, required this.textColor});
  final String label;
  final Color color, textColor;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        height: 1.2,
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
