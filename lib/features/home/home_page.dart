import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import 'campaigns.dart';
import 'home_controller.dart';
import 'product_card.dart';
import 'search_page.dart';
import '../products/product_page.dart';
import '../checkout/bag_page.dart';
import '../checkout/order_result_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.onLogin,
    required this.onLogout,
    this.initial,
    this.initialProductSlug,
    this.onProductRestored,
  });
  final BuyerRepository repository;
  final VoidCallback onLogin;
  final Future<void> Function() onLogout;
  final WebPage? initial;
  final String? initialProductSlug;
  final VoidCallback? onProductRestored;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final HomeController _home;
  final _search = TextEditingController();
  int _tab = 0;
  final _visited = <int>{0};
  void _selectTab(int tab) => setState(() {
    _tab = tab;
    _visited.add(tab);
  });
  bool _signingOut = false;
  String? _logoutError;
  bool _openingOrders = false;

  Future<void> _orders() async {
    setState(() => _openingOrders = true);
    try {
      final page = await widget.repository.document('/buyer/orders');
      widget.repository.requireNoErrors(page);
      if (page.props['orders'] is! Map) {
        throw const BackendException(
          'Your orders are unavailable for this account.',
        );
      }
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              OrderResultPage(repository: widget.repository, initial: page),
        ),
      );
    } on BackendException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _openingOrders = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _home = HomeController(widget.repository, initial: widget.initial);
    if (widget.initialProductSlug != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onProductRestored?.call();
          _openProduct({'slug': widget.initialProductSlug});
        }
      });
    }
    if (widget.initial != null && widget.initial!.component != 'Buyer/Home') {
      _tab = 3;
      _visited.add(3);
    } else {
      _home.load();
    }
  }

  @override
  void dispose() {
    _home.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    if (_signingOut) {
      return;
    }
    setState(() {
      _signingOut = true;
      _logoutError = null;
    });
    try {
      await widget.onLogout();
    } on BackendException catch (e) {
      if (mounted) {
        setState(() => _logoutError = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _signingOut = false);
      }
    }
  }

  void _selectCategory(String slug) {
    setState(() => _tab = 0);
    _home.filter(department: slug);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _home,
    builder: (context, _) => Scaffold(
      appBar: _tab == 1
          ? null
          : AppBar(
              toolbarHeight: 72,
              title: const FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Brand(size: 32),
              ),
              actions: [
                IconButton(
                  tooltip: 'Shopping Bag',
                  icon: const Icon(Icons.shopping_bag_outlined),
                  onPressed: () => _selectTab(1),
                ),
                if (_home.user == null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: TextButton(
                      onPressed: widget.onLogin,
                      child: const Text('Log In'),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: IconButton(
                      tooltip: 'Your account',
                      onPressed: () => _selectTab(3),
                      icon: const Icon(Icons.person_outline_rounded),
                    ),
                  ),
              ],
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(1),
                child: Divider(height: 1),
              ),
            ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: IndexedStack(
              index: _tab,
              children: [
                _marketplace(),
                if (_visited.contains(1))
                  BagPage(repository: widget.repository)
                else
                  const SizedBox.shrink(),
                if (_visited.contains(2))
                  SearchPage(repository: widget.repository)
                else
                  const SizedBox.shrink(),
                if (_visited.contains(3))
                  _account()
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: BagooTheme.strong),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon: Icon(
              Icons.shopping_bag_rounded,
              color: BagooTheme.strong,
            ),
            label: 'Cart',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search, color: BagooTheme.strong),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: BagooTheme.strong),
            label: 'Profile',
          ),
        ],
      ),
    ),
  );

  Widget _marketplace() => RefreshIndicator(
    onRefresh: _home.load,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        final scaled = MediaQuery.textScalerOf(context).scale(14) / 14;
        final count = productColumns(constraints.maxWidth, scaled);
        final horizontal = wide ? 32.0 : 16.0;
        return CustomScrollView(
          key: const PageStorageKey('marketplace'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (value) => _home.filter(query: value),
                      decoration: InputDecoration(
                        labelText: 'Search products',
                        hintText: 'What are you looking for?',
                        prefixIcon: const ExcludeSemantics(
                          child: Icon(Icons.search_rounded),
                        ),
                        suffixIcon: IconButton(
                          tooltip: 'Search marketplace',
                          onPressed: () => _home.filter(query: _search.text),
                          icon: const Icon(Icons.arrow_forward_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_home.loading)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: LinearProgressIndicator(),
                      ),
                    if (_home.error != null) ...[
                      Notice(_home.error!, error: true),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _home.load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again'),
                        ),
                      ),
                    ] else if (_home.data != null && !_home.isMarketplace) ...[
                      Notice(
                        mapOf(
                              _home.data!.props['status'],
                            )['message']?.toString() ??
                            'Your account needs attention. Open Account to review its recorded status.',
                        error: true,
                      ),
                      TextButton(
                        onPressed: () => _selectTab(3),
                        child: const Text('View account'),
                      ),
                    ] else if (!_home.loading && _home.data != null) ...[
                      if (!_home.hasFilters) ...[
                        Campaigns(
                          banners: _home.banners,
                          session: widget.repository.session,
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (_home.categories.isNotEmpty) ...[
                        const Text(
                          'Shop by department',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _categoryChip(
                                '',
                                'All departments',
                                Icons.apps_rounded,
                              ),
                              for (final category in _home.categories)
                                _categoryChip(
                                  category['slug'].toString(),
                                  category['name'].toString(),
                                  categoryIcon(category),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (_home.data!.props['buyerApplication'] != null) ...[
                        const Notice(
                          'You can browse while your account is being reviewed. Checkout requires an approved account.',
                        ),
                        const SizedBox(height: 20),
                      ],
                      const Text(
                        'DAILY DISCOVER',
                        style: TextStyle(
                          color: BagooTheme.strong,
                          letterSpacing: 1.5,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _home.search.isEmpty
                            ? 'Recommended for you'
                            : 'Results for “${_home.search}”',
                        style: const TextStyle(
                          fontSize: 24,
                          height: 1.3,
                          letterSpacing: -.7,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_home.total} active listings',
                        style: const TextStyle(
                          fontSize: 12,
                          color: BagooTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in const {
                            'relevance': 'Daily Discover',
                            'top_sales': 'Top Sales',
                            'top_rated': 'Top Rated',
                            'newest': 'New Arrivals',
                          }.entries)
                            ChoiceChip(
                              label: Text(entry.value),
                              selected: _home.sort == entry.key,
                              selectedColor: BagooTheme.rose,
                              onSelected: (_) => _home.filter(order: entry.key),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth - horizontal * 2,
                            ),
                            child: SizedBox(
                              width: 235,
                              child: DropdownButtonFormField<String>(
                                key: ValueKey(_home.sort),
                                initialValue: _home.sort,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Sort by',
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                items:
                                    const {
                                          'relevance': 'Recommended',
                                          'top_sales': 'Best selling',
                                          'top_rated': 'Highest rated',
                                          'newest': 'Newest first',
                                          'price_asc': 'Price: low to high',
                                          'price_desc': 'Price: high to low',
                                        }.entries
                                        .map(
                                          (e) => DropdownMenuItem(
                                            value: e.key,
                                            child: Text(
                                              e.value,
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    _home.filter(order: value);
                                  }
                                },
                              ),
                            ),
                          ),
                          if (_home.hasFilters)
                            TextButton.icon(
                              onPressed: () {
                                _search.clear();
                                _home.reset();
                              },
                              icon: const Icon(Icons.close, size: 18),
                              label: const Text('Clear filters'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (_home.products.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.search_off_rounded,
                                size: 40,
                                color: BagooTheme.muted,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No products found',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Try another search or department.',
                                style: TextStyle(color: BagooTheme.muted),
                              ),
                              TextButton(
                                onPressed: () {
                                  _search.clear();
                                  _home.reset();
                                },
                                child: const Text('Reset filters'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            if (!_home.loading && _home.error == null && _home.isMarketplace)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontal),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth =
                        (constraints.crossAxisExtent - (count - 1) * 14) /
                        count;
                    return SliverGrid.builder(
                      itemCount: _home.products.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: count,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        mainAxisExtent:
                            cardWidth + productCardBodyHeight * scaled,
                      ),
                      itemBuilder: (context, index) =>
                          _card(_home.products[index]),
                    );
                  },
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 32),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    if (_home.moreError != null)
                      Notice(_home.moreError!, error: true),
                    if (_home.hasMore &&
                        !_home.loading &&
                        _home.error == null &&
                        _home.isMarketplace)
                      OutlinedButton(
                        onPressed: _home.loadingMore
                            ? null
                            : () => _home.load(more: true),
                        child: Text(
                          _home.loadingMore
                              ? 'Loading more…'
                              : _home.moreError == null
                              ? 'Load more products'
                              : 'Retry loading more',
                        ),
                      ),
                    const SizedBox(height: 24),
                    const Text(
                      'BagooPH · Local finds, everyday value',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: BagooTheme.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  final _saving = <int>{};
  final _saveErrors = <int, String>{};
  bool get _canSave =>
      _home.user?['role'] == 'buyer' &&
      _home.user?['status'] == 'active' &&
      ['approved', 'verified'].contains(_home.user?['kyc_status']);
  Widget _card(Map<String, dynamic> product) {
    final id = (product['id'] as num).toInt();
    final saved = (_home.data?.props['savedProductIds'] as List? ?? [])
        .contains(id);
    return ProductCard(
      product: product,
      session: widget.repository.session,
      onTap: () => _openProduct(product),
      saved: saved,
      saving: _saving.contains(id),
      error: _saveErrors[id],
      saveLabel: _home.user == null
          ? 'Sign in to save'
          : !_canSave
          ? 'Approval required'
          : saved
          ? 'Remove from saved'
          : 'Save product',
      onSave: _home.user == null
          ? widget.onLogin
          : !_canSave
          ? null
          : () async {
              setState(() {
                _saving.add(id);
                _saveErrors.remove(id);
              });
              try {
                await widget.repository.saveProduct(id, !saved);
                if (!mounted) {
                  return;
                }
                final ids = Set<dynamic>.from(
                  _home.data?.props['savedProductIds'] as List? ?? [],
                );
                if (saved) {
                  ids.remove(id);
                } else {
                  ids.add(id);
                }
                setState(
                  () => _home.data?.props['savedProductIds'] = ids.toList(),
                );
              } on BackendException catch (e) {
                if (mounted) {
                  setState(() => _saveErrors[id] = e.message);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.message)));
                }
              } finally {
                if (mounted) {
                  setState(() => _saving.remove(id));
                }
              }
            },
    );
  }

  Future<void> _openProduct(Map<String, dynamic> product) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductPage(
          repository: widget.repository,
          slug: product['slug']?.toString() ?? product['id'].toString(),
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (result == true) {
      widget.onLogin();
    } else {
      await _home.load();
    }
  }

  Widget _categoryChip(String slug, String title, IconData icon) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      avatar: ExcludeSemantics(child: Icon(icon, size: 18)),
      label: Text(title),
      selected: _home.category == slug,
      selectedColor: BagooTheme.rose,
      onSelected: (_) => _selectCategory(slug),
    ),
  );

  Widget _account() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        'Your account',
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 24),
      if (_home.user == null) ...[
        const Text(
          'Log in to your buyer account to keep shopping with BagooPH.',
          style: TextStyle(color: BagooTheme.muted, height: 1.6),
        ),
        const SizedBox(height: 24),
        SubmitButton(label: 'Log In', onPressed: widget.onLogin),
      ] else ...[
        Text(
          _home.user!['name']?.toString() ?? 'Buyer',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(_home.user!['email']?.toString() ?? ''),
        const SizedBox(height: 24),
        Text(
          'Account status: ${_home.user!['status'] ?? 'Not provided'}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          'Identity review: ${(_home.user!['kyc_status']?.toString() ?? 'Not provided').replaceAll('_', ' ')}',
        ),
        const SizedBox(height: 24),
        if (_home.data != null && !_home.isMarketplace) ...[
          Notice(
            mapOf(_home.data!.props['status'])['message']?.toString() ?? 'Your account needs attention. Review the recorded status below.',
            error: true,
          ),
          const SizedBox(height: 16),
        ],
        const Text(
          'Your buyer account status and identity review are managed by BagooPH. Checkout requires an active approved account.',
          style: TextStyle(height: 1.7, color: BagooTheme.muted),
        ),
        const SizedBox(height: 24),
        if (_logoutError != null) Notice(_logoutError!, error: true),
        OutlinedButton.icon(
          onPressed: _openingOrders ? null : _orders,
          icon: const Icon(Icons.receipt_long_outlined),
          label: Text(_openingOrders ? 'Loading orders…' : 'Your orders'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _signingOut ? null : _logout,
          icon: const Icon(Icons.logout_rounded),
          label: Text(_signingOut ? 'Signing out…' : 'Log out'),
        ),
      ],
    ],
  );
}

IconData categoryIcon(Map<String, dynamic> category) {
  final text = '${category['name']} ${category['icon']}'.toLowerCase();
  if (text.contains('pet')) {
    return Icons.pets_outlined;
  }
  if (text.contains('electro') || text.contains('gadget')) {
    return Icons.devices_outlined;
  }
  if (text.contains('apparel') || text.contains('shirt')) {
    return Icons.checkroom_outlined;
  }
  if (text.contains('baby') || text.contains('kids')) {
    return Icons.child_care_outlined;
  }
  if (text.contains('home') || text.contains('furniture')) {
    return Icons.chair_outlined;
  }
  if (text.contains('sport')) {
    return Icons.sports_basketball_outlined;
  }
  if (text.contains('beauty') || text.contains('health')) {
    return Icons.spa_outlined;
  }
  if (text.contains('book') || text.contains('school')) {
    return Icons.menu_book_outlined;
  }
  if (text.contains('food')) {
    return Icons.restaurant_outlined;
  }
  if (text.contains('auto') || text.contains('car')) {
    return Icons.directions_car_outlined;
  }
  if (text.contains('watch') || text.contains('jewel')) {
    return Icons.watch_outlined;
  }
  return Icons.shopping_bag_outlined;
}
