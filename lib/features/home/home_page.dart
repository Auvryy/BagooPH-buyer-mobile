import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import 'campaigns.dart';
import 'home_controller.dart';
import 'product_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.onLogin,
    required this.onLogout,
    this.initial,
  });
  final BuyerRepository repository;
  final VoidCallback onLogin;
  final Future<void> Function() onLogout;
  final WebPage? initial;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final HomeController _home;
  final _search = TextEditingController();
  int _tab = 0;
  bool _signingOut = false;
  String? _logoutError;
  @override
  void initState() {
    super.initState();
    _home = HomeController(widget.repository, initial: widget.initial);
    if (widget.initial != null && widget.initial!.component != 'Buyer/Home') {
      _tab = 2;
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
      appBar: AppBar(
        toolbarHeight: 72,
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Brand(size: 32),
        ),
        actions: [
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
                onPressed: () => setState(() => _tab = 2),
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
            child: switch (_tab) {
              1 => _departments(),
              2 => _account(),
              _ => _marketplace(),
            },
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: BagooTheme.strong),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(
              Icons.grid_view_rounded,
              color: BagooTheme.strong,
            ),
            label: 'Departments',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: BagooTheme.strong),
            label: 'Account',
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
        final scaled = MediaQuery.textScalerOf(context).scale(16) / 16;
        final count = (constraints.maxWidth / (scaled > 1.4 ? 280 : 185))
            .floor()
            .clamp(1, 5);
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
                            'Your account needs attention. Review its status on the BagooPH website.',
                        error: true,
                      ),
                      TextButton(
                        onPressed: () => setState(() => _tab = 2),
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
              // Rows size themselves to their content, including large system text.
              // SliverList lazily builds only visible rows of the responsive grid.
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontal),
                sliver: SliverList.builder(
                  itemCount: (_home.products.length / count).ceil(),
                  itemBuilder: (context, row) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int column = 0; column < count; column++) ...[
                          if (column > 0) const SizedBox(width: 12),
                          Expanded(
                            child: row * count + column < _home.products.length
                                ? ProductCard(
                                    product:
                                        _home.products[row * count + column],
                                    session: widget.repository.session,
                                    onTap: () => showProduct(
                                      context,
                                      _home.products[row * count + column],
                                      widget.repository.session,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
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

  Widget _departments() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        'Shop by department',
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text(
        'Explore the BagooPH marketplace.',
        style: TextStyle(color: BagooTheme.muted),
      ),
      const SizedBox(height: 24),
      if (_home.loading) const LinearProgressIndicator(),
      if (_home.error != null) ...[
        Notice(_home.error!, error: true),
        TextButton(onPressed: _home.load, child: const Text('Try again')),
      ],
      for (final category in _home.categories)
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: BagooTheme.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: ExcludeSemantics(
              child: Icon(categoryIcon(category), color: BagooTheme.strong),
            ),
            title: Text(
              category['name'].toString(),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _selectCategory(category['slug'].toString()),
          ),
        ),
    ],
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
            mapOf(_home.data!.props['status'])['message']?.toString() ??
                'Review your account status on the BagooPH website.',
            error: true,
          ),
          const SizedBox(height: 16),
        ],
        const Text(
          'Manage delivery addresses, identity verification, purchases, and account settings on the BagooPH website.',
          style: TextStyle(height: 1.7, color: BagooTheme.muted),
        ),
        const SizedBox(height: 24),
        if (_logoutError != null) Notice(_logoutError!, error: true),
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
