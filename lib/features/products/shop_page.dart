import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_actions.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../../core/catalogue_pages.dart';
import '../home/search_controller.dart';
import '../checkout/bag_page.dart';
import '../home/product_card.dart';
import 'product_model.dart';
import 'product_page.dart';
import 'product_widgets.dart';

class ShopPage extends StatefulWidget {
  const ShopPage({
    super.key,
    required this.repository,
    required this.slug,
    this.storeCategory = 'all',
  });
  final BuyerRepository repository;
  final String slug;
  final String storeCategory;
  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  WebPage? _page;
  final _search = TextEditingController();
  final List<Map<String, dynamic>> _products = [];
  final _saving = <int>{};
  bool _busy = false;
  bool _following = false;
  String? _error;
  int _number = 1;
  int _last = 1;
  int _generation = 0;
  int _total = 0;
  int? _from, _to;
  String _category = '', _storeCategory = 'all', _sort = 'relevance';
  @override
  void initState() {
    super.initState();
    _storeCategory = widget.storeCategory;
    _load();
  }

  Future<void> _load({bool more = false, int? number}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.repository.shop(
        widget.slug,
        page: more ? _number + 1 : number ?? 1,
        search: _search.text.trim(),
        category: _category,
        storeCategory: _storeCategory,
        sort: _sort,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      final feed = mapOf(page.props['products']);
      setState(() {
        _page = page;
        if (!more) {
          _products.clear();
        }
        _products.addAll(mapsOf(feed['data']));
        _number = (feed['current_page'] as num?)?.toInt() ?? 1;
        _last = (feed['last_page'] as num?)?.toInt() ?? 1;
        _total = (feed['total'] as num?)?.toInt() ?? _products.length;
        _from = more
            ? _from ?? (feed['from'] as num?)?.toInt()
            : (feed['from'] as num?)?.toInt();
        _to = (feed['to'] as num?)?.toInt();
      });
    } on BackendException catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  bool get _eligible =>
      _page?.user?['role'] == 'buyer' &&
      _page?.user?['status'] == 'active' &&
      ['approved', 'verified'].contains(_page?.user?['kyc_status']);
  Future<void> _follow() async {
    if (_page?.user == null) {
      BuyerActions.login(context);
      return;
    }
    if (!_eligible || _following) {
      return;
    }
    final shop = mapOf(_page?.props['shop']);
    final next = _page?.props['isFollowing'] != true;
    setState(() => _following = true);
    try {
      final result = await widget.repository.session.jsonPost(
        '/buyer/followed-shops/${shop['id']}',
        {},
        method: next ? 'POST' : 'DELETE',
      );
      if (result['following'] != next) {
        throw const BackendException('The follow change was not confirmed.');
      }
      if (mounted) {
        setState(() {
          _page?.props['isFollowing'] = next;
          if (result['followers'] is num) {
            _page?.props['followerCount'] = result['followers'];
          }
        });
      }
    } on BackendException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _following = false);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shop = mapOf(_page?.props['shop']);
    final stats = mapOf(_page?.props['shopStats']);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          shop['name']?.toString() ?? 'Shop',
          style: const TextStyle(fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final columns = productColumns(box.maxWidth, scale);
            final width = (box.maxWidth - 32 - (columns - 1) * 14) / columns;
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_busy) const LinearProgressIndicator(),
                        if (_error != null) ...[
                          Notice(_error!, error: true),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Try again'),
                          ),
                        ],
                        if (_page != null)
                          ProductPanel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (shop['banner'] != null)
                                  AspectRatio(
                                    aspectRatio: 3,
                                    child: RemoteImage(
                                      uri: imageUri(
                                        widget.repository.session,
                                        shop['banner'],
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                Text(
                                  shop['name']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  shop['description']?.toString() ?? '',
                                  style: const TextStyle(
                                    height: 1.6,
                                    color: BagooTheme.muted,
                                  ),
                                ),
                                Text(
                                  [
                                            shop['address'],
                                            shop['barangay'],
                                            shop['city'],
                                            shop['province'],
                                            shop['postal_code'],
                                          ]
                                          .whereType<String>()
                                          .where((value) => value.isNotEmpty)
                                          .join(', ')
                                          .isNotEmpty
                                      ? [
                                              shop['address'],
                                              shop['barangay'],
                                              shop['city'],
                                              shop['province'],
                                              shop['postal_code'],
                                            ]
                                            .whereType<String>()
                                            .where((value) => value.isNotEmpty)
                                            .join(', ')
                                      : 'Location unavailable',
                                ),
                                Text(
                                  'Rating ${ratingLabel(stats['rating'])} · ${shop['products_count'] ?? _total} products',
                                ),
                                Text(
                                  '${_page?.props['followerCount'] ?? 0} followers · ${stats['review_count'] ?? 0} reviews',
                                  style: const TextStyle(height: 1.7),
                                ),
                                Text(
                                  'Reply rate: ${stats['response_rate'] ?? 'Not available'} · Opened: ${stats['joined'] == null ? 'Not available' : readableDate(stats['joined'])}',
                                  style: const TextStyle(height: 1.7),
                                ),
                                TextButton.icon(
                                  onPressed:
                                      _following ||
                                          (_page?.user != null && !_eligible)
                                      ? null
                                      : _follow,
                                  icon: const Icon(Icons.storefront_outlined),
                                  label: Text(
                                    _following
                                        ? 'Saving…'
                                        : _page?.props['isFollowing'] == true
                                        ? 'Unfollow shop'
                                        : 'Follow shop',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        for (final offer in mapsOf(_page?.props['shopOffers']))
                          OfferTile(
                            offer: offer,
                            repository: widget.repository,
                            canSave: _page?.user == null || _eligible,
                            onSignIn: _page?.user == null
                                ? () => BuyerActions.login(context)
                                : null,
                            onUse: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => BagPage(
                                  repository: widget.repository,
                                  voucherCode: offer['code']?.toString(),
                                ),
                              ),
                            ),
                          ),
                        TextField(
                          controller: _search,
                          onSubmitted: (_) => _load(),
                          decoration: InputDecoration(
                            labelText: 'Search this shop',
                            suffixIcon: IconButton(
                              tooltip: 'Search shop',
                              onPressed: _load,
                              icon: const Icon(Icons.search),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_page != null) ...[
                          _filter('Department', _category, {
                            '': 'All departments',
                            for (final row in mapsOf(
                              _page?.props['categories'],
                            ))
                              row['slug'].toString(): row['name'].toString(),
                          }, (value) => _category = value),
                          _filter('Store category', _storeCategory, {
                            'all': 'All products',
                            'uncategorized': 'Uncategorized',
                            for (final root in mapsOf(
                              _page?.props['storeCategories'],
                            ).where((row) => row['parent_id'] == null)) ...{
                              root['id'].toString(): root['name'].toString(),
                              for (final child in mapsOf(
                                _page?.props['storeCategories'],
                              ).where((row) => row['parent_id'] == root['id']))
                                child['id'].toString(): '  ${child['name']}',
                            },
                          }, (value) => _storeCategory = value),
                          _filter(
                            'Sort products',
                            _sort,
                            searchSorts,
                            (value) => _sort = value,
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () {
                                _search.clear();
                                _category = '';
                                _storeCategory = 'all';
                                _sort = 'relevance';
                                _load();
                              },
                              child: const Text('Reset shop filters'),
                            ),
                          ),
                        ],
                        if (!_busy && _page != null && _products.isEmpty)
                          const Text('No products match your search.'),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid.builder(
                    itemCount: _products.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: width + productCardBodyHeight * scale,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemBuilder: (context, i) {
                      final product = _products[i];
                      final id = (product['id'] as num).toInt();
                      final saved =
                          (_page?.props['savedProductIds'] as List? ?? [])
                              .contains(id);
                      return ProductCard(
                        product: product,
                        session: widget.repository.session,
                        saved: saved,
                        saving: _saving.contains(id),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ProductPage(
                              repository: widget.repository,
                              slug: product['slug'].toString(),
                            ),
                          ),
                        ),
                        saveLabel: _page?.user == null
                            ? 'Sign in to save'
                            : !_eligible
                            ? 'Approval required'
                            : saved
                            ? 'Remove from saved'
                            : 'Save product',
                        onSave: _page?.user != null && !_eligible
                            ? null
                            : () async {
                                if (_page?.user == null) {
                                  BuyerActions.login(
                                    context,
                                    productSlug: product['slug'].toString(),
                                  );
                                  return;
                                }
                                setState(() => _saving.add(id));
                                try {
                                  await widget.repository.saveProduct(
                                    id,
                                    !saved,
                                  );
                                  if (mounted) {
                                    final ids = Set<dynamic>.from(
                                      _page?.props['savedProductIds']
                                              as List? ??
                                          [],
                                    );
                                    saved ? ids.remove(id) : ids.add(id);
                                    setState(
                                      () => _page?.props['savedProductIds'] =
                                          ids.toList(),
                                    );
                                  }
                                } on BackendException catch (e) {
                                  if (mounted) {
                                    setState(() => _error = e.message);
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _saving.remove(id));
                                  }
                                }
                              },
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        CataloguePages(
                          current: _number,
                          last: _last,
                          total: _total,
                          from: _from,
                          to: _to,
                          busy: _busy,
                          onPage: (number) => _load(number: number),
                        ),
                        if (_number < _last)
                          OutlinedButton(
                            onPressed: _busy ? null : () => _load(more: true),
                            child: const Text('Load more products'),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _filter(
    String label,
    String value,
    Map<String, String> choices,
    ValueChanged<String> change,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label-$value-${choices.keys.join(',')}'),
      initialValue: choices.containsKey(value) ? value : null,
      isExpanded: true,
      itemHeight: null,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final row in choices.entries)
          DropdownMenuItem(
            value: row.key,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(row.value),
            ),
          ),
      ],
      onChanged: _busy
          ? null
          : (value) {
              if (value != null) {
                change(value);
                _load();
              }
            },
    ),
  );
}
