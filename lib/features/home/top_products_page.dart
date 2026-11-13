import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../products/product_model.dart';
import '../products/product_page.dart';
import '../products/product_widgets.dart';
import 'product_card.dart';

class TopProductsPage extends StatefulWidget {
  const TopProductsPage({
    super.key,
    required this.repository,
    required this.initial,
  });

  final BuyerRepository repository;
  final WebPage initial;

  @override
  State<TopProductsPage> createState() => _TopProductsPageState();
}

class _TopProductsPageState extends State<TopProductsPage> {
  late WebPage _page = widget.initial;
  bool _loading = false;
  String? _error;

  List<Map<String, dynamic>> get _collections =>
      mapsOf(_page.props['collections'])
          .where(
            (row) =>
                row['title'] is String &&
                (row['title'] as String).trim().isNotEmpty,
          )
          .toList();

  Map<String, dynamic> get _activeCollection =>
      mapOf(_page.props['activeCollection']);

  List<Map<String, dynamic>> get _products =>
      completeRelatedProducts(_page.props['products']) ?? const [];

  Future<void> _selectCollection(Map<String, dynamic> collection) async {
    final targetUrl = collection['target_url']?.toString().trim();
    if (_loading || targetUrl == null || targetUrl.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await widget.repository.document(targetUrl);
      widget.repository.requireNoErrors(next);
      if (next.component != 'Buyer/TopProducts' ||
          completeRelatedProducts(next.props['products']) == null) {
        throw const BackendException(
          'Top products could not be confirmed. Try again.',
        );
      }
      if (!mounted) return;
      setState(() => _page = next);
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTitle =
        _activeCollection['title']?.toString().trim().isNotEmpty == true
        ? _activeCollection['title'].toString().trim()
        : 'Top Curated Picks';
    final activeDepartment =
        _activeCollection['category_name']?.toString().trim().isNotEmpty == true
        ? _activeCollection['category_name'].toString().trim()
        : 'Marketplace';
    final activeSubSlug = _activeCollection['sub_slug']?.toString() ?? '';
    final products = _products;

    return Scaffold(
      appBar: AppBar(title: const Text('Top Products')),
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
                          if (_loading) const LinearProgressIndicator(),
                          if (_error != null) ...[
                            Notice(_error!, error: true),
                            const SizedBox(height: 12),
                          ],
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  BagooTheme.ink,
                                  Color(0xFF1E293B),
                                  Color(0xFF9E0B30),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: BagooTheme.crimson,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.auto_awesome_rounded,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const Text(
                                      'TOP PRODUCTS',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: BagooTheme.crimson,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: const Text(
                                        'ALGORITHMIC PICKS',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Curated bestsellers ranked by sales velocity, repeat orders, and verified buyer ratings.',
                                  style: TextStyle(
                                    color: Color(0xFFCBD5E1),
                                    fontSize: 12.5,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.28),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.14,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    'Department: $activeDepartment · $activeTitle',
                                    style: const TextStyle(
                                      color: Color(0xFFFCD34D),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_collections.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final collection in _collections)
                                  ChoiceChip(
                                    avatar: const Icon(
                                      Icons.local_fire_department_rounded,
                                      size: 16,
                                      color: BagooTheme.crimson,
                                    ),
                                    label: Text(collection['title'].toString()),
                                    selected:
                                        activeSubSlug.isNotEmpty &&
                                        collection['sub_slug']?.toString() ==
                                            activeSubSlug,
                                    selectedColor: BagooTheme.rose,
                                    onSelected: _loading
                                        ? null
                                        : (_) => _selectCollection(collection),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(child: ProductHeading(activeTitle)),
                              Text(
                                '${products.length} Products Ranked',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: BagooTheme.muted,
                                ),
                              ),
                            ],
                          ),
                          if (products.isEmpty)
                            const ProductPanel(
                              child: Text(
                                'No ranked items in this niche yet.',
                                style: TextStyle(color: BagooTheme.muted),
                              ),
                            )
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
                                  rankBadge: '#${index + 1}',
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
