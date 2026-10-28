import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_actions.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../engagement/engagement_repository.dart';
import '../home/product_card.dart';
import '../home/search_controller.dart';
import '../products/shop_page.dart';

class FollowedShopsPage extends StatefulWidget {
  const FollowedShopsPage({
    super.key,
    required this.repository,
    required this.ownerId,
    this.onSearch,
  });

  final BuyerRepository repository;
  final int ownerId;
  final ValueChanged<SearchFilters>? onSearch;

  @override
  State<FollowedShopsPage> createState() => _FollowedShopsPageState();
}

class _FollowedShopsPageState extends State<FollowedShopsPage> {
  WebPage? _page;
  String? _error;
  bool _loading = true;
  int _number = 1;
  int _generation = 0;
  final Set<int> _unfollowing = {};

  Map<String, dynamic> get _entries => mapOf(_page?.props['entries']);
  List<Map<String, dynamic>> get _rows => mapsOf(_entries['data']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load({int page = 1}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await BuyerEngagementRepository(widget.repository)
          .followedShops(page: page);
      if (!mounted || generation != _generation) {
        return;
      }
      if (result.user?['id'] != widget.ownerId) {
        throw const BackendException(
          'Your account changed. Sign in again to view followed shops.',
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
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _unfollow(int id) async {
    if (_unfollowing.contains(id)) return;
    setState(() => _unfollowing.add(id));
    try {
      final result = await widget.repository.session.jsonPost(
        '/buyer/followed-shops/$id',
        {},
        method: 'DELETE',
      );
      if (result['shop_id'] != id || result['following'] != false) {
        throw const BackendException('The unfollow change was not confirmed.');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shop removed from followed shops.')),
        );
      }
      await _load(page: _number);
    } on BackendException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _unfollowing.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Followed shops'),
      actions: [
        IconButton(
          tooltip: 'Refresh followed shops',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final width = constraints.maxWidth.clamp(0, 1280).toDouble();
          final columns = width >= 900
              ? 3
              : width >= 600
              ? 2
              : 1;
          return RefreshIndicator(
            onRefresh: _load,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    width >= 720 ? 28 : 16,
                    20,
                    width >= 720 ? 28 : 16,
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
                      _EmptyFollowedShops(
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
                          mainAxisExtent: 248 * scale,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        itemBuilder: (context, index) {
                          final entry = _rows[index];
                          final shop = mapOf(entry['shop']);
                          final id = (entry['shop_id'] as num).toInt();
                          return _FollowedShopCard(
                            shop: shop,
                            session: widget.repository.session,
                            busy: _unfollowing.contains(id),
                            onUnfollow: () => _unfollow(id),
                            onOpen: shop['slug'] is String
                                ? () => _openShop(shop['slug'].toString())
                                : null,
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
          'Followed shops',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Return to the stores you want to keep up with.',
          style: TextStyle(height: 1.5, color: BagooTheme.muted),
        ),
        SizedBox(height: 10),
        TextButton.icon(
          onPressed: widget.onSearch == null ? null : _browse,
          icon: Icon(Icons.storefront_outlined),
          label: Text('Browse shops'),
        ),
      ],
    ),
  );

  void _browse() {
    Navigator.of(context).pop();
    widget.onSearch?.call(const SearchFilters());
  }

  Future<void> _openShop(String slug) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShopPage(repository: widget.repository, slug: slug),
      ),
    );
    if (mounted) await _load(page: _number);
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

class _FollowedShopCard extends StatelessWidget {
  const _FollowedShopCard({
    required this.shop,
    required this.session,
    required this.busy,
    required this.onUnfollow,
    required this.onOpen,
  });

  final Map<String, dynamic> shop;
  final WebSession session;
  final bool busy;
  final VoidCallback onUnfollow;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: BagooTheme.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShopMark(shop: shop, session: session),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shop['name']?.toString() ?? 'Shop unavailable',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            shop['description']?.toString().trim().isNotEmpty ==
                                    true
                                ? shop['description'].toString()
                                : shop.isEmpty
                                ? 'This shop is no longer available. You can remove it from this list.'
                                : 'Visit this shop to browse its current catalogue.',
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: BagooTheme.muted,
                            ),
                          ),
                          if (shop.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Text(
                                'Shop currently unavailable',
                                style: TextStyle(
                                  color: BagooTheme.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
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
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (onOpen != null)
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.storefront_outlined),
                    label: const Text('Visit shop'),
                  ),
                )
              else
                const Expanded(
                  child: Text(
                    'Shop unavailable',
                    style: TextStyle(color: BagooTheme.muted),
                  ),
                ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Unfollow shop',
                onPressed: busy ? null : onUnfollow,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.favorite, color: BagooTheme.strong),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ShopMark extends StatelessWidget {
  const _ShopMark({required this.shop, required this.session});

  final Map<String, dynamic> shop;
  final WebSession session;

  @override
  Widget build(BuildContext context) {
    final uri = imageUri(session, shop['logo']);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.square(
        dimension: 54,
        child: uri == null
            ? const ColoredBox(
                color: BagooTheme.rose,
                child: Icon(
                  Icons.storefront_outlined,
                  color: BagooTheme.strong,
                ),
              )
            : RemoteImage(uri: uri, thumbnail: true),
      ),
    );
  }
}

class _EmptyFollowedShops extends StatelessWidget {
  const _EmptyFollowedShops({required this.onBrowse});

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
        const Icon(
          Icons.storefront_outlined,
          size: 40,
          color: BagooTheme.strong,
        ),
        const SizedBox(height: 12),
        Text(
          'No followed shops yet',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Follow a shop from its storefront to keep it here.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.5, color: BagooTheme.muted),
        ),
        if (onBrowse != null) ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onBrowse,
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Browse shops'),
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
