import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/buyer_actions.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../../core/catalogue_pages.dart';
import '../../core/cached_catalogue_notice.dart';
import '../products/product_page.dart';
import '../products/product_widgets.dart';
import 'search_controller.dart';
import 'search_filters.dart';
import 'product_card.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.repository, this.request});
  final BuyerRepository repository;
  final SearchFilters? request;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final CatalogueSearchController _catalogue;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  final _saving = <int>{};
  SearchFilters get filters => _catalogue.filters;
  @override
  void initState() {
    super.initState();
    _catalogue = CatalogueSearchController(widget.repository);
    if (widget.request != null) {
      _text.text = widget.request!.query;
      _catalogue.apply(widget.request!);
    } else {
      _catalogue.load();
    }
  }

  @override
  void didUpdateWidget(SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final request = widget.request;
    if (request != null && request != oldWidget.request) {
      _debounce?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.request == request) {
          _text.text = request.query;
          _apply(request);
        }
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    _scroll.dispose();
    _catalogue.dispose();
    super.dispose();
  }

  void _apply(SearchFilters value) {
    _debounce?.cancel();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _catalogue.apply(value);
  }

  void _search() => _apply(filters.copyWith(query: _text.text));
  void _reset() => _apply(SearchFilters(query: _text.text.trim()));
  Future<void> _filters() async {
    _debounce?.cancel();
    final selected = await showBuyerSearchFilters(
      context,
      value: filters.copyWith(query: _text.text.trim()),
      categories: _catalogue.categories,
      locations: _catalogue.locations,
    );
    if (mounted && selected != null) _apply(selected);
  }

  Future<void> _open(Map<String, dynamic> product) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductPage(
          repository: widget.repository,
          slug: product['slug'].toString(),
        ),
      ),
    );
    if (mounted) await _catalogue.load();
  }

  bool get _canSave =>
      _catalogue.user?['role'] == 'buyer' &&
      _catalogue.user?['status'] == 'active' &&
      ['approved', 'verified'].contains(_catalogue.user?['kyc_status']);
  Future<void> _save(Map<String, dynamic> product, bool saved) async {
    if (_catalogue.data?.isCached == true) return;
    if (_catalogue.user == null) {
      BuyerActions.login(context, productSlug: product['slug'].toString());
      return;
    }
    final id = (product['id'] as num).toInt();
    if (_saving.contains(id)) return;
    setState(() => _saving.add(id));
    try {
      await widget.repository.saveProduct(id, !saved);
      if (!mounted) return;
      final ids = Set<dynamic>.from(
        _catalogue.data?.props['savedProductIds'] as List? ?? [],
      );
      saved ? ids.remove(id) : ids.add(id);
      setState(() => _catalogue.data?.props['savedProductIds'] = ids.toList());
    } on BackendException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  Widget _card(Map<String, dynamic> product) {
    final id = (product['id'] as num).toInt();
    final saved = (_catalogue.data?.props['savedProductIds'] as List? ?? [])
        .contains(id);
    return ProductCard(
      product: product,
      session: widget.repository.session,
      onTap: () => _open(product),
      saved: saved,
      saving: _saving.contains(id),
      saveLabel: _catalogue.data?.isCached == true
          ? 'Connect to save'
          : _catalogue.user == null
          ? 'Sign in to save'
          : !_canSave
          ? 'Approval required'
          : saved
          ? 'Remove from saved'
          : 'Save product',
      onSave:
          _catalogue.data?.isCached == true ||
              _catalogue.user != null && !_canSave
          ? null
          : () => _save(product, saved),
    );
  }

  Widget _chips() {
    String label(
      List<Map<String, dynamic>> rows,
      String field,
      String value,
      String title,
    ) =>
        rows.where((r) => r[field] == value).firstOrNull?[title]?.toString() ??
        value;
    final chips = <(String, SearchFilters)>[
      if (filters.category.isNotEmpty)
        (
          label(_catalogue.categories, 'slug', filters.category, 'name'),
          filters.copyWith(category: ''),
        ),
      if (filters.location.isNotEmpty)
        (
          label(_catalogue.locations, 'value', filters.location, 'label'),
          filters.copyWith(location: ''),
        ),
      if (filters.minimum.isNotEmpty || filters.maximum.isNotEmpty)
        (
          '₱${filters.minimum.isEmpty ? '0' : filters.minimum} – ${filters.maximum.isEmpty ? 'Any' : '₱${filters.maximum}'}',
          filters.copyWith(minimum: '', maximum: ''),
        ),
      if (filters.inStock) ('In stock', filters.copyWith(inStock: false)),
      if (filters.rating.isNotEmpty)
        ('${filters.rating}+ stars', filters.copyWith(rating: '')),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final chip in chips)
          InputChip(
            label: Text(chip.$1),
            deleteButtonTooltipMessage: 'Remove ${chip.$1} filter',
            onDeleted: () => _apply(chip.$2),
          ),
        if (chips.isNotEmpty || filters.sort != 'relevance')
          TextButton(onPressed: _reset, child: const Text('Reset filters')),
      ],
    );
  }

  Widget _results(bool wide) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final count = productColumns(box.maxWidth, scale);
      final width = (box.maxWidth - 32 - (count - 1) * 14) / count;
      final related = !_catalogue.loading && _catalogue.error == null
          ? _catalogue.related
          : <Map<String, dynamic>>[];
      return RefreshIndicator(
        onRefresh: _catalogue.load,
        child: CustomScrollView(
          controller: _scroll,
          key: const PageStorageKey('buyer-search'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: ProductPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Find your next favorite',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Discover products from Bagoo shops.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.7,
                          color: BagooTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _text,
                        maxLength: 100,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) {
                          FocusScope.of(context).unfocus();
                          _search();
                        },
                        onChanged: (_) {
                          setState(() {});
                          _debounce?.cancel();
                          _debounce = Timer(
                            const Duration(milliseconds: 450),
                            _search,
                          );
                        },
                        decoration: InputDecoration(
                          labelText: 'Search the marketplace',
                          hintText: 'Products, shops, or departments',
                          counterText: '',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            tooltip: _text.text.isEmpty
                                ? 'Search products'
                                : 'Clear search',
                            onPressed: () {
                              if (_text.text.isNotEmpty) _text.clear();
                              _search();
                            },
                            icon: Icon(
                              _text.text.isEmpty
                                  ? Icons.arrow_forward
                                  : Icons.close,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!wide) ...[
                        OutlinedButton.icon(
                          onPressed: _catalogue.data == null ? null : _filters,
                          icon: const Icon(Icons.tune),
                          label: Text(
                            'Filters${filters.count == 0 ? '' : ' (${filters.count})'}',
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      DropdownButtonFormField<String>(
                        key: ValueKey(filters.sort),
                        initialValue: filters.sort,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Sort results',
                        ),
                        items: [
                          for (final sort in searchSorts.entries)
                            DropdownMenuItem(
                              value: sort.key,
                              child: Text(sort.value),
                            ),
                        ],
                        onChanged: (value) => _apply(
                          filters.copyWith(
                            sort: value,
                            query: _text.text.trim(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _chips(),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_catalogue.loading)
                      const LinearProgressIndicator(
                        semanticsLabel: 'Searching products',
                      ),
                    if (_catalogue.data?.cachedAt case final savedAt?)
                      CachedCatalogueNotice(
                        savedAt: savedAt,
                        onRefresh: _catalogue.loading ? null : _catalogue.load,
                      ),
                    if (_catalogue.error != null) ...[
                      Notice(_catalogue.error!, error: true),
                      TextButton(
                        onPressed: _catalogue.load,
                        child: const Text('Try again'),
                      ),
                    ],
                    if (!_catalogue.loading && _catalogue.error == null)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          '${_catalogue.total} ${filters.query.trim().isEmpty ? 'products to discover' : 'results for “${filters.query.trim()}”'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            height: 1.7,
                          ),
                        ),
                      ),
                    if (!_catalogue.loading &&
                        _catalogue.error == null &&
                        _catalogue.products.isEmpty)
                      ProductPanel(
                        child: Column(
                          children: [
                            const Icon(
                              Icons.search_off,
                              size: 44,
                              color: BagooTheme.muted,
                            ),
                            const SizedBox(height: 12),
                            const ProductHeading('No matching products'),
                            const Text(
                              'Try another search or broaden your filters.',
                              textAlign: TextAlign.center,
                            ),
                            if (_catalogue.suggestions.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              const Text('Did you mean?'),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final suggestion
                                      in _catalogue.suggestions)
                                    ActionChip(
                                      label: Text(suggestion),
                                      onPressed: () {
                                        _text.text = suggestion;
                                        _search();
                                      },
                                    ),
                                ],
                              ),
                            ],
                            TextButton(
                              onPressed: () {
                                _text.clear();
                                _apply(const SearchFilters());
                              },
                              child: const Text('Browse all products'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid.builder(
                itemCount: _catalogue.loading || _catalogue.error != null
                    ? 0
                    : _catalogue.products.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: count,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  mainAxisExtent: width + productCardBodyHeight * scale,
                ),
                itemBuilder: (_, index) => _card(_catalogue.products[index]),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    if (_catalogue.moreError != null)
                      Notice(_catalogue.moreError!, error: true),
                    if (!_catalogue.loading && _catalogue.error == null)
                      CataloguePages(
                        current: _catalogue.currentPage,
                        last: _catalogue.lastPage,
                        total: _catalogue.total,
                        from: _catalogue.from,
                        to: _catalogue.to,
                        busy: _catalogue.loadingMore,
                        onPage: (number) {
                          _catalogue.load(pageNumber: number);
                          if (_scroll.hasClients) _scroll.jumpTo(0);
                        },
                      ),
                    const SizedBox(height: 12),
                    if (_catalogue.hasMore && _catalogue.error == null)
                      OutlinedButton.icon(
                        onPressed: _catalogue.loading || _catalogue.loadingMore
                            ? null
                            : () => _catalogue.load(more: true),
                        icon: const Icon(Icons.expand_more),
                        label: Text(
                          _catalogue.loadingMore
                              ? 'Loading…'
                              : 'Load more products',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (related.isNotEmpty) ...[
              const SliverPadding(
                padding: EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: ProductHeading('You may also like'),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverGrid.builder(
                  itemCount: related.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: count,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    mainAxisExtent: width + productCardBodyHeight * scale,
                  ),
                  itemBuilder: (_, index) => _card(related[index]),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _catalogue,
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final wide =
            box.maxWidth >= 1050 &&
            MediaQuery.textScalerOf(context).scale(16) < 24;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1500),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 300,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
                          child: ProductPanel(
                            child: SearchFiltersForm(
                              key: ValueKey(filters.parameters.toString()),
                              value: filters,
                              categories: _catalogue.categories,
                              locations: _catalogue.locations,
                              onApply: _apply,
                              onReset: _reset,
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: _results(true)),
                    ],
                  )
                : _results(false),
          ),
        );
      },
    ),
  );
}
