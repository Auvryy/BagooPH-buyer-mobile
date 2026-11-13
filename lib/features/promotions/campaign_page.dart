import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_actions.dart';
import '../../core/buyer_repository.dart';
import '../../core/resource_ids.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../home/product_card.dart';
import '../products/product_model.dart';
import '../products/product_page.dart';
import '../products/product_widgets.dart';

class CampaignPage extends StatefulWidget {
  const CampaignPage({
    super.key,
    required this.repository,
    required this.initial,
  });

  final BuyerRepository repository;
  final WebPage initial;

  @override
  State<CampaignPage> createState() => _CampaignPageState();
}

class _CampaignPageState extends State<CampaignPage> {
  String _activeFilter = 'all';
  String _selectedCategory = 'all';
  final Set<String> _claimedCodes = <String>{};
  final Set<String> _claimingCodes = <String>{};

  Map<String, dynamic> get _campaign => mapOf(widget.initial.props['campaign']);

  List<Map<String, dynamic>> get _products =>
      completeRelatedProducts(widget.initial.props['products']) ?? const [];

  List<Map<String, dynamic>> get _categories =>
      mapsOf(widget.initial.props['categories'])
          .where(
            (row) =>
                row['name'] is String &&
                (row['name'] as String).trim().isNotEmpty &&
                row['slug'] is String &&
                (row['slug'] as String).trim().isNotEmpty,
          )
          .toList();

  List<Map<String, dynamic>> get _vouchers => mapsOf(_campaign['vouchers'])
      .where(
        (row) =>
            row['code'] is String && (row['code'] as String).trim().isNotEmpty,
      )
      .toList();

  @override
  void initState() {
    super.initState();
    for (final voucher in _vouchers) {
      if (voucher['is_saved'] == true) {
        _claimedCodes.add(voucher['code'].toString());
      }
    }
  }

  List<Map<String, dynamic>> get _filteredProducts =>
      _products.where((product) {
        if (_selectedCategory != 'all') {
          final categorySlug = mapOf(product['category'])['slug']?.toString();
          if (categorySlug != _selectedCategory) return false;
        }
        if (_activeFilter == 'under_500') {
          final price = amount(product['price']) ?? 0;
          return price <= 500;
        }
        if (_activeFilter == 'deep_discount') {
          final discount =
              amount(product['discount_pct']) ??
              ProductPrice(product).discount?.toDouble() ??
              0;
          return discount >= 20;
        }
        return true;
      }).toList();

  Future<void> _claimVoucher(Map<String, dynamic> voucher) async {
    final code = voucher['code'].toString();
    if (_claimedCodes.contains(code) || _claimingCodes.contains(code)) return;
    final user = widget.initial.user;
    final revisionId = positiveResourceId(voucher['revision_id']);
    setState(() => _claimingCodes.add(code));
    try {
      if (revisionId != null && user != null) {
        await widget.repository.session.jsonPost(
          '/buyer/saved-vouchers/$revisionId',
          const {},
        );
      }
      if (!mounted) return;
      setState(() => _claimedCodes.add(code));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Voucher $code saved.')));
    } on BackendException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() => _claimingCodes.remove(code));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _campaign['title']?.toString().trim().isNotEmpty == true
        ? _campaign['title'].toString().trim()
        : 'Campaign Event';
    final badge = _campaign['badge']?.toString().trim().isNotEmpty == true
        ? _campaign['badge'].toString().trim()
        : 'OFFICIAL EVENT';
    final bannerUri = imageUri(
      widget.repository.session,
      _campaign['banner_img'] ?? _campaign['image'],
    );
    final filtered = _filteredProducts;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final horizontal = wide ? 28.0 : 16.0;
            final contentWidth =
                constraints.maxWidth.clamp(0, 1220).toDouble() - horizontal * 2;
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
                        horizontal,
                        16,
                        horizontal,
                        24,
                      ),
                      sliver: SliverList.list(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: BagooTheme.line),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (bannerUri != null)
                                  AspectRatio(
                                    aspectRatio: 16 / 6,
                                    child: ExcludeSemantics(
                                      child: RemoteImage(
                                        uri: bannerUri,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Wrap(
                                    spacing: 10,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: BagooTheme.crimson,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          badge,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        title,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          color: BagooTheme.ink,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_vouchers.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            const ProductHeading('Campaign vouchers'),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                for (final voucher in _vouchers)
                                  _CampaignVoucherCard(
                                    voucher: voucher,
                                    claimed: _claimedCodes.contains(
                                      voucher['code'].toString(),
                                    ),
                                    claiming: _claimingCodes.contains(
                                      voucher['code'].toString(),
                                    ),
                                    onClaim: () {
                                      if (widget.initial.user == null &&
                                          positiveResourceId(
                                                voucher['revision_id'],
                                              ) !=
                                              null) {
                                        BuyerActions.login(context);
                                        return;
                                      }
                                      _claimVoucher(voucher);
                                    },
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('All Campaign Deals'),
                                selected: _activeFilter == 'all',
                                selectedColor: BagooTheme.rose,
                                onSelected: (_) =>
                                    setState(() => _activeFilter = 'all'),
                              ),
                              ChoiceChip(
                                label: const Text('20%+ Off'),
                                selected: _activeFilter == 'deep_discount',
                                selectedColor: BagooTheme.rose,
                                onSelected: (_) => setState(
                                  () => _activeFilter = 'deep_discount',
                                ),
                              ),
                              ChoiceChip(
                                label: const Text('Under ₱500'),
                                selected: _activeFilter == 'under_500',
                                selectedColor: BagooTheme.rose,
                                onSelected: (_) =>
                                    setState(() => _activeFilter = 'under_500'),
                              ),
                            ],
                          ),
                          if (_categories.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: const Text('All Departments'),
                                      selected: _selectedCategory == 'all',
                                      selectedColor: BagooTheme.rose,
                                      onSelected: (_) => setState(
                                        () => _selectedCategory = 'all',
                                      ),
                                    ),
                                  ),
                                  for (final category in _categories)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: Text(
                                          category['name'].toString(),
                                        ),
                                        selected:
                                            _selectedCategory ==
                                            category['slug'].toString(),
                                        selectedColor: BagooTheme.rose,
                                        onSelected: (_) => setState(
                                          () => _selectedCategory =
                                              category['slug'].toString(),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          const ProductHeading('Featured campaign deals'),
                          if (filtered.isEmpty)
                            const ProductPanel(
                              child: Text(
                                'No campaign products match this filter yet.',
                                style: TextStyle(color: BagooTheme.muted),
                              ),
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: filtered.length,
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
                                final product = filtered[index];
                                final eventBadge = product['event_badge']
                                    ?.toString();
                                return ProductCard(
                                  product: product,
                                  rankBadge: eventBadge,
                                  session: widget.repository.session,
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ProductPage(
                                        repository: widget.repository,
                                        slug: product['slug'].toString(),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
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
}

class _CampaignVoucherCard extends StatelessWidget {
  const _CampaignVoucherCard({
    required this.voucher,
    required this.claimed,
    required this.claiming,
    required this.onClaim,
  });

  final Map<String, dynamic> voucher;
  final bool claimed;
  final bool claiming;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final code = voucher['code']?.toString() ?? 'VOUCHER';
    final title = voucher['title']?.toString() ?? 'Campaign Voucher';
    final discount = voucher['discount']?.toString() ?? '';
    final minSpend = voucher['min_spend']?.toString() ?? '';
    final badge = voucher['badge']?.toString() ?? 'LIMITED';

    return Container(
      width: 280,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECDD3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: BagooTheme.rose,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: BagooTheme.crimson,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                code,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: BagooTheme.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (discount.isNotEmpty)
            Text(
              discount,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: BagooTheme.crimson,
              ),
            ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: BagooTheme.ink,
            ),
          ),
          if (minSpend.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              minSpend,
              style: const TextStyle(fontSize: 11.5, color: BagooTheme.muted),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: claimed || claiming ? null : onClaim,
              child: Text(
                claiming
                    ? 'Saving...'
                    : claimed
                    ? 'Claimed'
                    : 'Claim voucher',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
