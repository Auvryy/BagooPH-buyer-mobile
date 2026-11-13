import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_actions.dart';
import '../../core/count_metadata.dart';
import '../../core/buyer_repository.dart';
import '../../core/pagination_metadata.dart';
import '../../core/resource_ids.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../../core/catalogue_pages.dart';
import '../home/search_controller.dart';
import '../checkout/bag_page.dart';
import '../home/product_card.dart';
import 'product_model.dart';
import 'product_page.dart';
import 'product_widgets.dart';

List<Map<String, dynamic>> _completeStoreCategoryChoices(Object? raw) {
  if (raw is! List) return const [];
  final rows = <Map<String, dynamic>>[];
  final ids = <int>{};
  final names = <String>{};
  final parentIds = <int, int?>{};
  for (final row in raw) {
    if (row is! Map || row.keys.any((key) => key is! String)) {
      return const [];
    }
    final category = Map<String, dynamic>.from(row);
    final id = positiveResourceId(category['id']);
    final name = category['name'];
    final parentValue = category['parent_id'];
    final parentId = parentValue == null
        ? null
        : positiveResourceId(parentValue);
    if (id == null ||
        !ids.add(id) ||
        name is! String ||
        name.trim().isEmpty ||
        !names.add(name.trim().toLowerCase()) ||
        parentValue != null && parentId == null) {
      return const [];
    }
    parentIds[id] = parentId;
    rows.add(category);
  }
  if (rows.any((row) {
    final id = row['id'] as int;
    final parent = parentIds[id];
    return parent != null &&
        (parent == id || !ids.contains(parent) || parentIds[parent] != null);
  })) {
    return const [];
  }
  return rows;
}

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
  bool? _filtersExpanded;
  String? _error;
  int _number = 1;
  int _last = 1;
  int _generation = 0;
  int _total = 0;
  late int _identityEpoch;
  int? _from, _to;
  String _category = '', _storeCategory = 'all', _sort = 'relevance';
  @override
  void initState() {
    super.initState();
    _identityEpoch = widget.repository.session.identityEpoch;
    _storeCategory = widget.storeCategory;
    _load();
  }

  Future<void> _load({bool more = false, int? number}) async {
    final session = widget.repository.session;
    final epoch = session.identityEpoch;
    if (_identityEpoch != epoch) {
      setState(() {
        _identityEpoch = epoch;
        _clearAccountPage();
      });
    }
    final generation = ++_generation;
    final search = _search.text.trim();
    if (search.runes.length > 100) {
      setState(() {
        _busy = false;
        _error = 'Use no more than 100 characters to search this shop.';
      });
      return;
    }
    final requestedPage = more ? _number + 1 : number ?? 1;
    if (!isValidBuyerPageRequest(requestedPage)) {
      setState(() {
        _busy = false;
        _error = 'Choose a valid product page.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.repository.shop(
        widget.slug,
        page: requestedPage,
        search: search,
        category: _category,
        storeCategory: _storeCategory,
        sort: _sort,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      if (epoch != session.identityEpoch) {
        await _reloadForIdentityChange(epoch);
        return;
      }
      final feed = mapOf(page.props['products']);
      final rows = completeProductCards(feed['data']);
      if (rows == null) {
        throw const BackendException(
          'Shop products could not be confirmed. Refresh and try again.',
        );
      }
      final pagination = parseContractPaginationMetadata(
        feed,
        rowCount: rows.length,
        requestedPage: requestedPage,
        pageSize: 18,
      );
      if (pagination == null) {
        throw const BackendException(
          'Shop pagination could not be confirmed. Refresh and try again.',
        );
      }
      setState(() {
        _page = page;
        if (!more) {
          _products.clear();
        }
        final ids = _products.map((product) => product['id']).toSet();
        _products.addAll(rows.where((product) => ids.add(product['id'])));
        _number = pagination.currentPage;
        _last = pagination.lastPage;
        _total = pagination.total;
        _from = more ? _from ?? pagination.from : pagination.from;
        _to = pagination.to;
      });
    } on BackendException catch (e) {
      if (mounted && generation == _generation) {
        if (epoch != session.identityEpoch) {
          await _reloadForIdentityChange(epoch);
          return;
        }
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  void _clearAccountPage() {
    _generation++;
    _page = null;
    _products.clear();
    _saving.clear();
    _following = false;
    _number = 1;
    _last = 1;
    _total = 0;
    _from = null;
    _to = null;
    _error = null;
  }

  Future<void> _reloadForIdentityChange(int previousEpoch) async {
    if (!mounted ||
        previousEpoch == widget.repository.session.identityEpoch ||
        _identityEpoch == widget.repository.session.identityEpoch) {
      return;
    }
    setState(() {
      _identityEpoch = widget.repository.session.identityEpoch;
      _clearAccountPage();
    });
    await _load();
  }

  Future<bool> _ensureIdentity() async {
    final epoch = widget.repository.session.identityEpoch;
    if (_identityEpoch == epoch) return true;
    await _reloadForIdentityChange(_identityEpoch);
    return false;
  }

  bool get _eligible =>
      _page?.user?['role'] == 'buyer' &&
      _page?.user?['status'] == 'active' &&
      ['approved', 'verified'].contains(_page?.user?['kyc_status']);
  Future<void> _follow() async {
    if (!await _ensureIdentity()) return;
    if (!mounted) return;
    if (_page?.user == null) {
      BuyerActions.login(context);
      return;
    }
    if (!_eligible || _following) {
      return;
    }
    final shop = mapOf(_page?.props['shop']);
    final next = _page?.props['isFollowing'] != true;
    final session = widget.repository.session;
    final epoch = session.identityEpoch;
    setState(() => _following = true);
    try {
      final result = await session.jsonPost(
        '/buyer/followed-shops/${shop['id']}',
        {},
        method: next ? 'POST' : 'DELETE',
      );
      if (!mounted) return;
      if (epoch != session.identityEpoch) {
        await _reloadForIdentityChange(epoch);
        return;
      }
      if (result['following'] != next) {
        throw const BackendException('The follow change was not confirmed.');
      }
      setState(() {
        _page?.props['isFollowing'] = next;
        if (result['followers'] is int && (result['followers'] as int) >= 0) {
          _page?.props['followerCount'] = result['followers'];
        }
      });
    } on BackendException catch (e) {
      if (mounted) {
        if (epoch != session.identityEpoch) {
          await _reloadForIdentityChange(epoch);
        } else {
          setState(() => _error = e.message);
        }
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
    final departmentChoices = completeSearchFilterChoices(
      _page?.props['categories'],
      valueKey: 'slug',
      labelKey: 'name',
    );
    final storeCategoryChoices = _completeStoreCategoryChoices(
      _page?.props.containsKey('storeCategories') == true
          ? _page?.props['storeCategories']
          : _page?.props['storeTags'],
    );
    final productCount = nonNegativeCount(shop['products_count']) ?? _total;
    final followerCount = nonNegativeCount(_page?.props['followerCount']);
    final reviewCount = nonNegativeCount(stats['review_count']);
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
            final filtersExpanded = _filtersExpanded ?? box.maxWidth >= 760;
            final activeFilters = [
              _category.isNotEmpty,
              _storeCategory != 'all',
              _sort != 'relevance',
            ].where((active) => active).length;
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
                                Row(
                                  children: [
                                    if (shop['logo'] != null) ...[
                                      SizedBox.square(
                                        dimension: 40,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: RemoteImage(
                                            uri: imageUri(
                                              widget.repository.session,
                                              shop['logo'],
                                            ),
                                            thumbnail: true,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    Expanded(
                                      child: Text(
                                        shop['name']?.toString() ?? '',
                                        style: const TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
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
                                  'Rating ${ratingLabel(stats['rating'])} · $productCount products',
                                ),
                                Text(
                                  '${followerCount ?? '—'} followers · ${reviewCount ?? '—'} reviews',
                                  style: const TextStyle(height: 1.7),
                                ),
                                Text(
                                  'Reply rate: ${stats['response_rate'] ?? 'Not available'} · Opened: ${stats['joined'] == null ? 'Not available' : readableDate(stats['joined'])}',
                                  style: const TextStyle(height: 1.7),
                                ),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        foregroundColor: BagooTheme.crimson,
                                        backgroundColor: BagooTheme.rose,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                      onPressed:
                                          _following ||
                                              (_page?.user != null &&
                                                  !_eligible)
                                          ? null
                                          : _follow,
                                      icon: const Icon(
                                        Icons.storefront_outlined,
                                      ),
                                      label: Text(
                                        _following
                                            ? 'Saving…'
                                            : _page?.props['isFollowing'] ==
                                                  true
                                            ? 'Unfollow shop'
                                            : 'Follow shop',
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: BagooTheme.rose,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: const Color(0xFFFECDD3),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.verified_outlined,
                                            size: 13,
                                            color: BagooTheme.crimson,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Verified',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                              color: BagooTheme.crimson,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
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
                          maxLength: 100,
                          onSubmitted: (_) => _load(),
                          decoration: InputDecoration(
                            labelText: 'Search this shop',
                            counterText: '',
                            suffixIcon: IconButton(
                              tooltip: 'Search shop',
                              onPressed: _load,
                              icon: const Icon(Icons.search),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_page != null) ...[
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '$_total products',
                                style: const TextStyle(
                                  color: BagooTheme.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              OutlinedButton.icon(
                                key: const ValueKey('shop-filter-toggle'),
                                onPressed: () => setState(
                                  () => _filtersExpanded = !filtersExpanded,
                                ),
                                icon: Icon(
                                  filtersExpanded
                                      ? Icons.expand_less_rounded
                                      : Icons.tune_rounded,
                                ),
                                label: Text(
                                  filtersExpanded
                                      ? 'Hide filters'
                                      : activeFilters == 0
                                      ? 'Filter & sort'
                                      : 'Filter & sort ($activeFilters)',
                                ),
                              ),
                            ],
                          ),
                          if (filtersExpanded) ...[
                            const SizedBox(height: 12),
                            _filter('Department', _category, {
                              '': 'All departments',
                              for (final row in departmentChoices)
                                row['slug'].toString(): row['name'].toString(),
                            }, (value) => _category = value),
                            _filter('Store category', _storeCategory, {
                              'all': 'All products',
                              'uncategorized': 'Uncategorized',
                              for (final root in storeCategoryChoices.where(
                                (row) => row['parent_id'] == null,
                              )) ...{
                                root['id'].toString(): root['name'].toString(),
                                for (final child in storeCategoryChoices.where(
                                  (row) => row['parent_id'] == root['id'],
                                ))
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
                      final id = product['id'] as int;
                      final saved = positiveResourceIds(
                        _page?.props['savedProductIds'],
                      ).contains(id);
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
                                if (_saving.contains(id)) return;
                                if (_identityEpoch !=
                                    widget.repository.session.identityEpoch) {
                                  await _reloadForIdentityChange(
                                    _identityEpoch,
                                  );
                                  return;
                                }
                                if (!context.mounted) return;
                                if (_page?.user == null) {
                                  BuyerActions.login(
                                    context,
                                    productSlug: product['slug'].toString(),
                                  );
                                  return;
                                }
                                final session = widget.repository.session;
                                final epoch = session.identityEpoch;
                                setState(() => _saving.add(id));
                                try {
                                  await widget.repository.saveProduct(
                                    id,
                                    !saved,
                                  );
                                  if (!mounted) return;
                                  if (epoch != session.identityEpoch) {
                                    await _reloadForIdentityChange(epoch);
                                    return;
                                  }
                                  if (mounted) {
                                    final ids = positiveResourceIds(
                                      _page?.props['savedProductIds'],
                                    );
                                    saved ? ids.remove(id) : ids.add(id);
                                    setState(
                                      () => _page?.props['savedProductIds'] =
                                          ids.toList(),
                                    );
                                  }
                                } on BackendException catch (e) {
                                  if (mounted) {
                                    if (epoch != session.identityEpoch) {
                                      await _reloadForIdentityChange(epoch);
                                    } else {
                                      setState(() => _error = e.message);
                                    }
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
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final narrow = constraints.maxWidth <= 400;
      final compactSelection = narrow && media.textScaler.scale(14) >= 21;
      final selectedLabel = (choices[value] ?? '').trim();
      final compactedLabel = _compactShopFilterValue(label, selectedLabel);
      final hasKnownCompactLabel =
          compactSelection && compactedLabel != selectedLabel;
      final availableSelectionWidth = (constraints.maxWidth - 72).clamp(
        0.0,
        constraints.maxWidth,
      );
      final discloseSelection =
          narrow &&
          !hasKnownCompactLabel &&
          _shopFilterValueExceedsWidth(
            context,
            selectedLabel,
            availableSelectionWidth,
          );
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          key: ValueKey('$label-$value-${choices.keys.join(',')}'),
          initialValue: choices.containsKey(value) ? value : null,
          isExpanded: true,
          itemHeight: null,
          decoration: InputDecoration(
            labelText: label,
            helper: discloseSelection ? Text('Selected: $selectedLabel') : null,
          ),
          selectedItemBuilder: (_) => [
            for (final row in choices.entries)
              Semantics(
                label: row.value.trim(),
                child: ExcludeSemantics(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      row.value.trim() == selectedLabel && discloseSelection
                          ? 'Selected'
                          : compactSelection
                          ? _compactShopFilterValue(label, row.value.trim())
                          : row.value.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
          ],
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
    },
  );
}

String _compactShopFilterValue(String label, String value) =>
    switch ((label, value)) {
      ('Department', 'All departments') => 'All',
      ('Store category', 'All products') => 'All',
      ('Sort products', 'Recommended') => 'Suggested',
      ('Sort products', 'Price: low to high') => 'Low price',
      ('Sort products', 'Price: high to low') => 'High price',
      _ => value,
    };

bool _shopFilterValueExceedsWidth(
  BuildContext context,
  String value,
  double width,
) {
  if (value.isEmpty || width <= 0) return false;
  final painter = TextPainter(
    text: TextSpan(text: value, style: Theme.of(context).textTheme.titleMedium),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout(maxWidth: width);
  final overflow = painter.didExceedMaxLines;
  painter.dispose();
  return overflow;
}
