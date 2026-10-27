import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/buyer_actions.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../products/product_page.dart';
import 'home_controller.dart';
import 'product_card.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.repository});
  final BuyerRepository repository;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final HomeController _catalogue;
  final _text = TextEditingController();
  Timer? _debounce;
  final _saving = <int>{};
  @override
  void initState() {
    super.initState();
    _catalogue = HomeController(widget.repository);
    _catalogue.load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    _catalogue.dispose();
    super.dispose();
  }

  void _search() {
    _debounce?.cancel();
    _catalogue.filter(query: _text.text);
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
    if (_catalogue.user == null) {
      BuyerActions.login(context, productSlug: product['slug'].toString());
      return;
    }
    final id = (product['id'] as num).toInt();
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _catalogue,
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final count = productColumns(box.maxWidth, scale);
        final width = (box.maxWidth - 32 - (count - 1) * 14) / count;
        return RefreshIndicator(
          onRefresh: _catalogue.load,
          child: CustomScrollView(
            key: const PageStorageKey('buyer-search'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
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
                        'Search products across the BagooPH marketplace.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.7,
                          color: BagooTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _text,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _search(),
                        onChanged: (_) {
                          _debounce?.cancel();
                          _debounce = Timer(
                            const Duration(milliseconds: 450),
                            _search,
                          );
                        },
                        decoration: InputDecoration(
                          labelText: 'Search the marketplace',
                          hintText: 'Products, brands, or something new',
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
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        initialValue: _catalogue.sort,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Sort results',
                        ),
                        items: [
                          for (final option in {
                            'relevance': 'Recommended',
                            'top_sales': 'Top sales',
                            'newest': 'Latest',
                            'price_asc': 'Price: low to high',
                            'price_desc': 'Price: high to low',
                          }.entries)
                            DropdownMenuItem(
                              value: option.key,
                              child: Text(option.value),
                            ),
                        ],
                        onChanged: (value) => _catalogue.filter(order: value),
                      ),
                      const SizedBox(height: 16),
                      if (_catalogue.categories.isNotEmpty)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: const Text('All departments'),
                                  selected: _catalogue.category.isEmpty,
                                  onSelected: (_) =>
                                      _catalogue.filter(department: ''),
                                ),
                              ),
                              for (final category in _catalogue.categories)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(category['name'].toString()),
                                    selected:
                                        _catalogue.category == category['slug'],
                                    onSelected: (_) => _catalogue.filter(
                                      department: category['slug'].toString(),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),
                      if (_catalogue.loading) const LinearProgressIndicator(),
                      if (_catalogue.error != null) ...[
                        Notice(_catalogue.error!, error: true),
                        TextButton(
                          onPressed: _catalogue.load,
                          child: const Text('Try again'),
                        ),
                      ] else if (!_catalogue.loading)
                        Text(
                          '${_catalogue.total} ${_catalogue.search.isEmpty ? 'products to discover' : 'results for “${_catalogue.search}”'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            height: 1.7,
                          ),
                        ),
                      if (!_catalogue.loading &&
                          _catalogue.error == null &&
                          _catalogue.products.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 48,
                                color: BagooTheme.muted,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No matching products',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Try another search or department.',
                                textAlign: TextAlign.center,
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
                  itemCount: _catalogue.loading
                      ? 0
                      : _catalogue.products.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: count,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    mainAxisExtent: width + productCardBodyHeight * scale,
                  ),
                  itemBuilder: (context, index) {
                    final product = _catalogue.products[index];
                    final id = (product['id'] as num).toInt();
                    final saved =
                        (_catalogue.data?.props['savedProductIds'] as List? ??
                                [])
                            .contains(id);
                    return ProductCard(
                      product: product,
                      session: widget.repository.session,
                      onTap: () => _open(product),
                      saved: saved,
                      saving: _saving.contains(id),
                      saveLabel: _catalogue.user == null
                          ? 'Sign in to save'
                          : !_canSave
                          ? 'Approval required'
                          : saved
                          ? 'Remove from saved'
                          : 'Save product',
                      onSave: _catalogue.user != null && !_canSave
                          ? null
                          : () => _save(product, saved),
                    );
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      if (_catalogue.moreError != null)
                        Notice(_catalogue.moreError!, error: true),
                      if (_catalogue.hasMore)
                        OutlinedButton(
                          onPressed:
                              _catalogue.loading || _catalogue.loadingMore
                              ? null
                              : () => _catalogue.load(more: true),
                          child: Text(
                            _catalogue.loadingMore
                                ? 'Loading…'
                                : 'Load more products',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
