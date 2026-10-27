import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_actions.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../home/product_card.dart';
import '../products/product_page.dart';
import '../products/product_widgets.dart';

class PromotionPage extends StatelessWidget {
  const PromotionPage({
    super.key,
    required this.repository,
    required this.initial,
    required this.onOpenDestination,
    required this.onProfileSection,
  });

  final BuyerRepository repository;
  final WebPage initial;
  final Future<void> Function(String? href) onOpenDestination;
  final ValueChanged<String> onProfileSection;

  Map<String, dynamic> get promotion => mapOf(initial.props['promotion']);
  List<Map<String, dynamic>> get products => mapsOf(initial.props['products']);

  @override
  Widget build(BuildContext context) {
    final available = promotion['available'] == true;
    final offer = mapOf(promotion['offer']);
    final target = mapOf(promotion['target']);
    final user = initial.user;
    final image = imageUri(repository.session, promotion['image']);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          available
              ? promotion['title']?.toString() ?? 'Promotion'
              : 'Promotion unavailable',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final contentWidth =
                constraints.maxWidth.clamp(0, 1220).toDouble() -
                (wide ? 56.0 : 32.0);
            final columns = productColumns(contentWidth, scale);
            final cardWidth = (contentWidth - 14 * (columns - 1)) / columns;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1220),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        wide ? 28 : 16,
                        20,
                        wide ? 28 : 16,
                        28,
                      ),
                      sliver: SliverList.list(
                        children: [
                          TextButton.icon(
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Continue shopping'),
                            style: TextButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (!available)
                            _UnavailablePromotion(
                              onBrowse: () =>
                                  _openDestination(context, '/buyer/search'),
                            )
                          else ...[
                            _PromotionHeading(promotion: promotion),
                            if (image != null) ...[
                              const SizedBox(height: 20),
                              Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 900,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Semantics(
                                      image: true,
                                      label:
                                          promotion['alt_text']?.toString() ??
                                          promotion['title']?.toString() ??
                                          'Promotion artwork',
                                      child: ExcludeSemantics(
                                        child: RemoteImage(
                                          uri: image,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (offer.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              _OfferPanel(
                                offer: offer,
                                onViewVouchers: () {
                                  if (user == null) {
                                    BuyerActions.login(context);
                                  } else {
                                    onProfileSection('vouchers');
                                  }
                                },
                                signedIn: user != null,
                              ),
                            ],
                            if (target['url'] is String &&
                                target['url'].toString().isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  onPressed: () => _openDestination(
                                    context,
                                    target['url'].toString(),
                                  ),
                                  icon: const Icon(Icons.arrow_forward_rounded),
                                  label: Text(
                                    'Explore ${target['label'] ?? 'promotion'}',
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 30),
                            const ProductHeading('Products in this promotion'),
                            if (products.isEmpty)
                              const _EmptyPromotionProducts()
                            else
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: products.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      mainAxisExtent:
                                          cardWidth +
                                          productCardBodyHeight * scale,
                                      crossAxisSpacing: 14,
                                      mainAxisSpacing: 14,
                                    ),
                                itemBuilder: (context, index) {
                                  final product = products[index];
                                  return ProductCard(
                                    product: product,
                                    session: repository.session,
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => ProductPage(
                                          repository: repository,
                                          slug: product['slug'].toString(),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openDestination(BuildContext context, String? href) async {
    try {
      await onOpenDestination(href);
    } on BackendException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _PromotionHeading extends StatelessWidget {
  const _PromotionHeading({required this.promotion});

  final Map<String, dynamic> promotion;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        promotion['title']?.toString() ?? 'Featured promotion',
        style: const TextStyle(
          fontSize: 28,
          height: 1.25,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.calendar_month_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_manilaDate(promotion['starts_at'])} – ${_manilaDate(promotion['ends_at'])} (Manila)',
              style: const TextStyle(fontSize: 13, color: BagooTheme.muted),
            ),
          ),
        ],
      ),
      if (promotion['summary'] is String &&
          promotion['summary'].toString().trim().isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(
          promotion['summary'].toString(),
          style: const TextStyle(height: 1.6, color: BagooTheme.muted),
        ),
      ],
    ],
  );
}

class _OfferPanel extends StatelessWidget {
  const _OfferPanel({
    required this.offer,
    required this.signedIn,
    required this.onViewVouchers,
  });

  final Map<String, dynamic> offer;
  final bool signedIn;
  final VoidCallback onViewVouchers;

  @override
  Widget build(BuildContext context) {
    final type = offer['discount_type']?.toString();
    final value = type == 'percentage'
        ? '${((amount(offer['percentage_bps']) ?? 0) / 100).toStringAsFixed(0)}% off'
        : '${_pesoCents(offer['value_cents'])} off';
    final minimum = amount(offer['minimum_cents']);
    final maximum = amount(offer['maximum_cents']);
    final limit = amount(offer['per_buyer_limit']);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: BagooTheme.rose,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1CCD6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.local_offer_outlined, color: BagooTheme.strong),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      offer['name']?.toString() ?? 'Promotion offer',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (offer['shop_name'] is String &&
                        offer['shop_name'].toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Offered by ${offer['shop_name']}',
                          style: const TextStyle(color: BagooTheme.muted),
                        ),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: BagooTheme.strong,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (offer['code'] is String)
            _OfferDetail(
              label: 'Voucher code',
              value: offer['code'].toString(),
            ),
          if (offer['description'] is String &&
              offer['description'].toString().trim().isNotEmpty)
            _OfferDetail(
              label: 'Terms',
              value: offer['description'].toString(),
            ),
          if (offer['starts_at'] is String && offer['ends_at'] is String)
            _OfferDetail(
              label: 'Voucher validity',
              value:
                  '${_manilaDate(offer['starts_at'])} – ${_manilaDate(offer['ends_at'])} (Manila)',
            ),
          if (minimum != null && minimum > 0)
            _OfferDetail(label: 'Minimum spend', value: _pesoCents(minimum)),
          if (maximum != null && maximum > 0)
            _OfferDetail(label: 'Maximum discount', value: _pesoCents(maximum)),
          if (limit != null && limit > 0)
            _OfferDetail(label: 'Uses per buyer', value: '${limit.toInt()}'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onViewVouchers,
            icon: const Icon(Icons.account_circle_outlined),
            label: Text(
              signedIn ? 'View my vouchers' : 'Sign in to view vouchers',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Eligibility and the final discount are confirmed by Bagoo at checkout.',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: BagooTheme.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferDetail extends StatelessWidget {
  const _OfferDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text('$label: $value', style: const TextStyle(height: 1.45)),
  );
}

class _UnavailablePromotion extends StatelessWidget {
  const _UnavailablePromotion({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    constraints: const BoxConstraints(minHeight: 320),
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: BagooTheme.border),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.local_offer_outlined,
          size: 38,
          color: BagooTheme.muted,
        ),
        const SizedBox(height: 14),
        const Text(
          'This promotion is no longer available',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'It may have ended or its products or offer may have changed. Browse the marketplace for current offers.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.6, color: BagooTheme.muted),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onBrowse,
          icon: const Icon(Icons.search),
          label: const Text('Browse products'),
        ),
      ],
    ),
  );
}

class _EmptyPromotionProducts extends StatelessWidget {
  const _EmptyPromotionProducts();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: BagooTheme.border),
    ),
    child: const Text(
      'No products are currently available in this promotion. Continue browsing for more choices.',
      textAlign: TextAlign.center,
      style: TextStyle(height: 1.6, color: BagooTheme.muted),
    ),
  );
}

String _pesoCents(dynamic raw) {
  final cents = amount(raw);
  if (cents == null) return 'Price unavailable';
  final value = (cents / 100).toStringAsFixed(2);
  return '₱$value';
}

String _manilaDate(dynamic raw) {
  final parsed = DateTime.tryParse(raw?.toString() ?? '');
  if (parsed == null) return 'Date unavailable';
  final date = parsed.toUtc().add(const Duration(hours: 8));
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final suffix = date.hour < 12 ? 'AM' : 'PM';
  return '${date.day} ${months[date.month - 1]} ${date.year}, $hour:$minute $suffix';
}
