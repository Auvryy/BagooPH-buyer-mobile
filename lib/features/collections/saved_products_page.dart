import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_actions.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../engagement/engagement_repository.dart';
import '../home/product_card.dart';
import '../home/search_controller.dart';
import '../products/product_page.dart';

class SavedProductsPage extends StatefulWidget {
  const SavedProductsPage({
    super.key,
    required this.repository,
    required this.ownerId,
    this.onSearch,
  });

  final BuyerRepository repository;
  final int ownerId;
  final ValueChanged<SearchFilters>? onSearch;

  @override
  State<SavedProductsPage> createState() => _SavedProductsPageState();
}

class _SavedProductsPageState extends State<SavedProductsPage> {
  WebPage? _page;
  String? _error;
  bool _loading = true;
  int _number = 1;
  int _generation = 0;
  int _scope = 0;
  late int _identityEpoch;
  final Set<int> _removing = {};

  Map<String, dynamic> get _entries => mapOf(_page?.props['entries']);
  List<Map<String, dynamic>> get _rows => mapsOf(_entries['data']);

  @override
  void initState() {
    super.initState();
    _identityEpoch = widget.repository.session.identityEpoch;
    _load();
  }

  @override
  void didUpdateWidget(SavedProductsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.ownerId != widget.ownerId) {
      _scope++;
      _identityEpoch = widget.repository.session.identityEpoch;
      _page = null;
      _removing.clear();
      _load();
    }
  }

  void _deny(String message) {
    if (!mounted) return;
    _generation++;
    _scope++;
    setState(() {
      _page = null;
      _error = message;
      _loading = false;
      _removing.clear();
    });
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load({int page = 1}) async {
    if (!mounted) return;
    if (_identityEpoch != widget.repository.session.identityEpoch) {
      _deny(
        'Your account changed. Reopen your saved products after signing in.',
      );
      return;
    }
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await BuyerEngagementRepository(widget.repository)
          .savedProducts(page: page);
      if (!mounted || generation != _generation) {
        return;
      }
      if (result.user?['id'] != widget.ownerId ||
          _identityEpoch != widget.repository.session.identityEpoch) {
        throw const BackendException(
          'Your account changed. Sign in again to view your saved products.',
          status: 401,
        );
      }
      setState(() {
        _page = result;
        _number = (mapOf(result.props['entries'])['current_page'] as num)
            .toInt();
      });
    } on BackendException catch (e) {
      if (mounted && generation == _generation) {
        if ([401, 403, 404, 419].contains(e.status)) {
          _deny(e.message);
        } else {
          setState(() => _error = e.message);
        }
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _remove(int id) async {
    if (_removing.contains(id)) return;
    if (_identityEpoch != widget.repository.session.identityEpoch) {
      _deny(
        'Your account changed. Reopen your saved products after signing in.',
      );
      return;
    }
    final scope = _scope;
    setState(() => _removing.add(id));
    try {
      await widget.repository.saveProduct(id, false);
      if (!mounted || scope != _scope) return;
      if (_identityEpoch != widget.repository.session.identityEpoch) {
        _deny(
          'Your account changed. Reopen your saved products after signing in.',
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product removed from saved products.')),
      );
      await _load(page: _number);
    } on BackendException catch (e) {
      if (mounted && scope == _scope) {
        if ([401, 403, 404, 419].contains(e.status)) {
          _deny(e.message);
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    } finally {
      if (mounted && scope == _scope) setState(() => _removing.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Saved products'),
      actions: [
        IconButton(
          tooltip: 'Refresh saved products',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          final scaled = MediaQuery.textScalerOf(context).scale(14) / 14;
          final columns = productColumns(constraints.maxWidth, scaled);
          final width = constraints.maxWidth.clamp(0, 1280).toDouble();
          final cardWidth =
              (width - (wide ? 56 : 32) - 14 * (columns - 1)) / columns;
          return RefreshIndicator(
            onRefresh: _load,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    wide ? 28 : 16,
                    20,
                    wide ? 28 : 16,
                    32,
                  ),
                  children: [
                    _heading(),
                    if (_loading && _page == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 52),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (_error != null) _errorPanel(),
                    if (_page != null && !_loading && _rows.isEmpty)
                      _EmptySavedProducts(
                        onBrowse: widget.onSearch == null ? null : _browse,
                      ),
                    if (_page != null && _rows.isNotEmpty) ...[
                      if (_loading) const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _rows.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisExtent:
                              cardWidth + productCardBodyHeight * scaled,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        itemBuilder: (context, index) {
                          final entry = _rows[index];
                          final product = mapOf(entry['product']);
                          final id = (entry['product_id'] as num).toInt();
                          if (product.isEmpty) {
                            return _UnavailableSavedProduct(
                              reason: entry['unavailable_reason']?.toString() ?? 'This saved product is currently unavailable.',
                              removing: _removing.contains(id),
                              onRemove: () => _remove(id),
                            );
                          }
                          return ProductCard(
                            product: product,
                            session: widget.repository.session,
                            saved: true,
                            saving: _removing.contains(id),
                            saveLabel: 'Remove from saved products',
                            onSave: () => _remove(id),
                            onTap: () =>
                                _openProduct(product['slug']?.toString() ?? ''),
                          );
                        },
                      ),
                      _Paginator(
                        current: _number,
                        last: (_entries['last_page'] as num?)?.toInt() ?? 1,
                        busy: _loading,
                        onPage: (page) => _load(page: page),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _heading() => Container(
    padding: const EdgeInsets.all(20),
    margin: const EdgeInsets.only(bottom: 18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: BagooTheme.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Saved products',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Keep products here for later. Saving does not reserve stock.',
          style: TextStyle(height: 1.5, color: BagooTheme.muted),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: widget.onSearch == null ? null : _browse,
          icon: const Icon(Icons.shopping_bag_outlined),
          label: const Text('Continue shopping'),
        ),
      ],
    ),
  );

  Future<void> _openProduct(String slug) async {
    if (slug.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductPage(repository: widget.repository, slug: slug),
      ),
    );
    if (mounted) await _load(page: _number);
  }

  void _browse() {
    Navigator.of(context).pop();
    widget.onSearch?.call(const SearchFilters());
  }

  Widget _errorPanel() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFF1B7C5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Notice(_error!, error: true),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
            if (_error!.toLowerCase().contains('sign in') ||
                _error!.toLowerCase().contains('account changed'))
              OutlinedButton(
                onPressed: () => BuyerActions.login(context),
                child: const Text('Sign in'),
              ),
          ],
        ),
      ],
    ),
  );
}

class _UnavailableSavedProduct extends StatelessWidget {
  const _UnavailableSavedProduct({
    required this.reason,
    required this.removing,
    required this.onRemove,
  });

  final String reason;
  final bool removing;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: BagooTheme.border),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.inventory_2_outlined,
          size: 34,
          color: BagooTheme.muted,
        ),
        const SizedBox(height: 10),
        const Text(
          'Saved product unavailable',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          reason,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            height: 1.5,
            color: BagooTheme.muted,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: removing ? null : onRemove,
          icon: removing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_outline),
          label: const Text('Remove'),
        ),
      ],
    ),
  );
}

class _EmptySavedProducts extends StatelessWidget {
  const _EmptySavedProducts({required this.onBrowse});

  final VoidCallback? onBrowse;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: BagooTheme.border),
    ),
    child: Column(
      children: [
        const Icon(Icons.favorite_border, size: 40, color: BagooTheme.strong),
        const SizedBox(height: 12),
        Text(
          'No saved products yet',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Use Save product while browsing the marketplace to keep it here.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.5, color: BagooTheme.muted),
        ),
        if (onBrowse != null) ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onBrowse,
            icon: const Icon(Icons.shopping_bag_outlined),
            label: const Text('Browse products'),
          ),
        ],
      ],
    ),
  );
}

class _Paginator extends StatelessWidget {
  const _Paginator({
    required this.current,
    required this.last,
    required this.busy,
    required this.onPage,
  });

  final int current, last;
  final bool busy;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        OutlinedButton.icon(
          onPressed: busy || current <= 1 ? null : () => onPage(current - 1),
          icon: const Icon(Icons.chevron_left),
          label: const Text('Previous'),
        ),
        Text('Page $current of $last'),
        OutlinedButton.icon(
          onPressed: busy || current >= last ? null : () => onPage(current + 1),
          icon: const Icon(Icons.chevron_right),
          label: const Text('Next'),
        ),
      ],
    ),
  );
}
