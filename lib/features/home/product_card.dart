import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/count_metadata.dart';
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
    this.rankBadge,
  });

  final Map<String, dynamic> product;
  final WebSession session;
  final VoidCallback onTap;
  final VoidCallback? onSave;
  final bool saved, saving;
  final String saveLabel;
  final double? bodyExtent;
  final String? error;
  final String? rankBadge;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final pricing = ProductPrice(product);
    final out = (amount(product['stock']) ?? 0) <= 0;
    final salesCount = nonNegativeCount(product['sales_count']);
    final shop = mapOf(product['shop']);
    final name = product['name']?.toString() ?? 'Product';
    final location = shop['city']?.toString().trim();
    final isHot =
        !out &&
        pricing.discount == null &&
        (rankBadge == null || rankBadge!.trim().isEmpty) &&
        (salesCount ?? 0) > 1000;
    final recorded = recordedRating(product['rating']);

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BagooTheme.controlRadius),
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
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: BagooTheme.canvas,
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFF1F5F9)),
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ExcludeSemantics(
                          child: RemoteImage(
                            uri: imageUri(session, product['featured_image']),
                            thumbnail: true,
                          ),
                        ),
                        if (out) const ColoredBox(color: Color(0x4D0F172A)),
                        Positioned(
                          top: 6,
                          left: 6,
                          right: 54,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (rankBadge != null &&
                                  rankBadge!.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: _Badge(
                                    rankBadge!.trim(),
                                    color: BagooTheme.ink,
                                    textColor: Colors.white,
                                  ),
                                ),
                              if (out)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 4),
                                  child: _Badge(
                                    'Out of stock',
                                    color: BagooTheme.crimson,
                                    textColor: Colors.white,
                                  ),
                                ),
                              if (pricing.discount != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: _Badge(
                                    '-${pricing.discount}%',
                                    color: BagooTheme.crimson,
                                    textColor: Colors.white,
                                    icon: Icons.local_fire_department_rounded,
                                  ),
                                ),
                              if (isHot)
                                const _Badge(
                                  'HOT',
                                  color: Color(0xFFF97316),
                                  textColor: Colors.white,
                                  icon: Icons.auto_awesome_rounded,
                                ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 6,
                          bottom: 6,
                          right: 8,
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (shop['vacation_mode'] == true)
                                const _Badge(
                                  'On vacation',
                                  color: Color(0xFFF59E0B),
                                  textColor: Colors.white,
                                ),
                              if (!out)
                                Semantics(
                                  label: 'Cash on Delivery',
                                  child: ExcludeSemantics(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.95,
                                        ),
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(
                                          color: const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.local_shipping_outlined,
                                            size: 11,
                                            color: BagooTheme.crimson,
                                          ),
                                          SizedBox(width: 3),
                                          Text(
                                            'Express',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF334155),
                                              height: 1.0,
                                            ),
                                          ),
                                        ],
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
                    padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
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
                                fontSize: 13.5,
                                height: 1.25,
                                fontWeight: FontWeight.w700,
                                color: BagooTheme.ink,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 54 * scale,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pricing.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.18,
                                  fontWeight: FontWeight.w900,
                                  color: BagooTheme.crimson,
                                ),
                              ),
                              if (pricing.discount != null)
                                Text(
                                  pesos(pricing.comparison),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    height: 1.18,
                                    color: BagooTheme.muted,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          height: 1,
                          color: const Color(0xFFF1F5F9),
                          margin: const EdgeInsets.only(bottom: 4),
                        ),
                        SizedBox(
                          height: 30 * scale,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Icon(
                                    recorded == null
                                        ? Icons.star_border_rounded
                                        : Icons.star_rounded,
                                    size: 14,
                                    color: recorded == null
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFFF59E0B),
                                  ),
                                ),
                                TextSpan(
                                  text:
                                      ' ${ratingLabel(product['rating'])}'
                                      '${salesCount != null && salesCount > 0 ? ' · $salesCount sold' : ''}',
                                ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.25,
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
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                location == null || location.isEmpty
                                    ? 'Location unavailable'
                                    : location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  height: 1.25,
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
            top: 2,
            right: 2,
            child: _WishlistOrbButton(
              saving: saving,
              saved: saved,
              saveLabel: saveLabel,
              onSave: onSave,
            ),
          ),
        ],
      ),
    );
  }
}

/// Web role-model Flash Deal card with discount pill and selling-fast meter.
class FlashDealCard extends StatelessWidget {
  const FlashDealCard({
    super.key,
    required this.product,
    required this.session,
    required this.onTap,
    this.onSave,
    this.saved = false,
    this.saving = false,
    this.saveLabel = 'Sign in to save',
  });

  final Map<String, dynamic> product;
  final WebSession session;
  final VoidCallback onTap;
  final VoidCallback? onSave;
  final bool saved, saving;
  final String saveLabel;

  @override
  Widget build(BuildContext context) {
    final pricing = ProductPrice(product);
    final name = product['name']?.toString() ?? 'Flash Deal';
    final stock = (amount(product['stock']) ?? 15).round();
    final clampedStock = stock <= 0 ? 5 : stock.clamp(1, 95);
    final soldRatio = ((100 - clampedStock) / 100).clamp(0.18, 0.94);
    final stockLabel = stock > 0 && stock < 10
        ? 'ONLY $stock LEFT'
        : 'SELLING FAST';

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BagooTheme.controlRadius),
        side: const BorderSide(color: Color(0xFFFECDD3)),
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
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: BagooTheme.canvas,
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFFFF1F2)),
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ExcludeSemantics(
                          child: RemoteImage(
                            uri: imageUri(session, product['featured_image']),
                            thumbnail: true,
                          ),
                        ),
                        Positioned(
                          top: 6,
                          left: 6,
                          right: 54,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: _Badge(
                              pricing.discount != null
                                  ? '-${pricing.discount}%'
                                  : 'FLASH',
                              color: BagooTheme.crimson,
                              textColor: Colors.white,
                              icon: Icons.local_fire_department_rounded,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: BagooTheme.ink,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pricing.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: BagooTheme.crimson,
                          height: 1.15,
                        ),
                      ),
                      if (pricing.discount != null)
                        Text(
                          pesos(pricing.comparison),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: BagooTheme.muted,
                            decoration: TextDecoration.lineThrough,
                            height: 1.1,
                          ),
                        )
                      else
                        const SizedBox(height: 12),
                      const SizedBox(height: 6),
                      Container(
                        height: 16,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE4E6),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFFECDD3)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: soldRatio,
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      BagooTheme.crimson,
                                      Color(0xFFF97316),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.bolt_rounded,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Text(
                                      stockLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.3,
                                        height: 1.0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: _WishlistOrbButton(
              saving: saving,
              saved: saved,
              saveLabel: saveLabel,
              onSave: onSave,
            ),
          ),
        ],
      ),
    );
  }
}

class _WishlistOrbButton extends StatelessWidget {
  const _WishlistOrbButton({
    required this.saving,
    required this.saved,
    required this.saveLabel,
    required this.onSave,
  });

  final bool saving;
  final bool saved;
  final String saveLabel;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: saving ? 'Saving product' : saveLabel,
      onPressed: saving ? null : onSave,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      icon: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: saved
              ? const Color(0xFFFFF1F2).withValues(alpha: 0.96)
              : Colors.white.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          border: Border.all(
            color: saved ? const Color(0xFFFECDD3) : const Color(0xFFE2E8F0),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: saving
            ? const SizedBox.square(
                dimension: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: BagooTheme.crimson,
                ),
              )
            : Icon(
                saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: 17,
                color: saved ? BagooTheme.crimson : const Color(0xFF475569),
              ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(
    this.label, {
    required this.color,
    required this.textColor,
    this.icon,
  });

  final String label;
  final Color color, textColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: textColor),
          const SizedBox(width: 2.5),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              height: 1.15,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
        ),
      ],
    ),
  );
}

int productColumns(double width, double scale) => scale > 1.4
    ? (width / 280).floor().clamp(1, 4)
    : width >= 1200
    ? 5
    : width >= 900
    ? 4
    : width >= 640
    ? 3
    : width >= 300
    ? 2
    : 1;
