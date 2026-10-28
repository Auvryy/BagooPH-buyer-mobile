import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../../core/catalogue_pages.dart';
import 'campaigns.dart';
import 'home_controller.dart';
import 'product_card.dart';
import 'search_page.dart';
import 'search_controller.dart';
import 'search_filters.dart';
import 'about_page.dart';
import '../products/product_widgets.dart';
import '../support/support_assistant_page.dart';
import '../engagement/buyer_destination_router.dart';
import '../engagement/engagement_repository.dart';
import '../notifications/notifications_page.dart';
import '../tracking/parcel_tracking_page.dart';
import '../products/product_page.dart';
import '../checkout/bag_page.dart';
import '../profile/profile_page.dart';
import '../../core/buyer_actions.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.onLogin,
    required this.onLogout,
    this.initial,
    this.initialProductSlug,
    this.onProductRestored,
    this.initialDestination = 0,
    this.onDestinationRestored,
  });
  final BuyerRepository repository;
  final VoidCallback onLogin;
  final Future<void> Function() onLogout;
  final WebPage? initial;
  final String? initialProductSlug;
  final VoidCallback? onProductRestored;
  final int initialDestination;
  final VoidCallback? onDestinationRestored;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final HomeController _home;
  final _search = TextEditingController();
  int _tab = 0;
  final _visited = <int>{0};
  SearchFilters? _searchRequest;
  int? _notificationCount;
  Object? _notificationOwner;
  int _notificationGeneration = 0;
  String _profileSection = 'overview';
  int _profileSectionRequest = 0;
  bool _openingTracking = false;
  bool _openingFilters = false;
  void _selectTab(int tab) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _tab = tab;
      _visited.add(tab);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _home = HomeController(widget.repository, initial: widget.initial);
    _home.addListener(_homeChanged);
    _homeChanged();
    _tab = widget.initialDestination;
    _visited.add(_tab);
    if (_tab != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDestinationRestored?.call();
      });
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _home.removeListener(_homeChanged);
    _home.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_home.loading) {
      unawaited(_home.load());
    }
    if (state == AppLifecycleState.resumed && _home.user?['id'] is num) {
      unawaited(_refreshNotificationSummary(_home.user!['id']));
    }
  }

  Future<void> _advancedFilters() async {
    if (_openingFilters) return;
    setState(() => _openingFilters = true);
    try {
      final page = await widget.repository.search(const {});
      if (!mounted) return;
      final filters = await showBuyerSearchFilters(
        context,
        value: SearchFilters(
          query: _search.text.trim(),
          category: _home.category,
          sort: _home.sort,
        ),
        categories: mapsOf(page.props['categories']),
        locations: mapsOf(page.props['locations']),
      );
      if (mounted && filters != null) _openSearchFilters(filters);
    } on BackendException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _openingFilters = false);
    }
  }

  Future<void> _openBuyerHref(String href) async {
    try {
      await BuyerDestinationRouter.openHref(
        context,
        widget.repository,
        href,
        onSearch: _openSearchFilters,
        onProfileSection: _openProfileSection,
      );
    } on BackendException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  void _selectCategory(String slug) {
    _openSearch(category: slug);
  }

  void _openSearch({String query = '', String category = ''}) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _searchRequest = SearchFilters(query: query.trim(), category: category);
      _tab = 2;
      _visited.add(2);
    });
  }

  void _openSearchFilters(SearchFilters filters) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _searchRequest = filters;
      _tab = 2;
      _visited.add(2);
    });
  }

  void _openProfileSection(String section) {
    setState(() {
      _profileSection = section;
      _profileSectionRequest++;
      _tab = 3;
      _visited.add(3);
    });
  }

  void _homeChanged() {
    final owner = _home.user?['id'];
    if (owner == _notificationOwner) return;
    _notificationOwner = owner;
    _notificationGeneration++;
    if (owner is num) {
      unawaited(_refreshNotificationSummary(owner));
    } else if (mounted) {
      setState(() => _notificationCount = null);
    }
  }

  Future<void> _refreshNotificationSummary(Object owner) async {
    final generation = ++_notificationGeneration;
    try {
      final response = await BuyerEngagementRepository(widget.repository)
          .notificationPreview();
      final summary = mapOf(response['summary']);
      final count = (summary['unread'] as num).toInt();
      if (mounted &&
          generation == _notificationGeneration &&
          owner == _home.user?['id']) {
        setState(() => _notificationCount = count);
      }
    } on BackendException {
      if (mounted && generation == _notificationGeneration) {
        setState(() => _notificationCount = null);
      }
    }
  }

  Future<void> _openTracking() async {
    if (_openingTracking) return;
    setState(() => _openingTracking = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ParcelTrackingPage(repository: widget.repository),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingTracking = false);
    }
  }

  Future<void> _openNotifications() async {
    final user = _home.user;
    if (user == null) {
      widget.onLogin();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsPage(
          repository: widget.repository,
          ownerId: (user['id'] as num).toInt(),
          onSearch: _openSearchFilters,
          onProfileSection: _openProfileSection,
          onSummaryChanged: (count) {
            if (mounted && _home.user?['id'] == user['id']) {
              setState(() => _notificationCount = count);
            }
          },
        ),
      ),
    );
    if (mounted && _home.user?['id'] is num) {
      await _refreshNotificationSummary(_home.user!['id']);
    }
  }

  void _openBanner(Map<String, dynamic> banner) {
    unawaited(_openBannerDestination(banner));
  }

  Future<void> _openBannerDestination(Map<String, dynamic> banner) async {
    final measurement = mapOf(banner['measurement']);
    if (measurement.isNotEmpty) {
      unawaited(
        BuyerEngagementRepository(widget.repository)
            .reportAdvertisementClick(measurement)
            .catchError((_) {}),
      );
    }
    try {
      await BuyerDestinationRouter.openHref(
        context,
        widget.repository,
        banner['href']?.toString(),
        onSearch: _openSearchFilters,
        onProfileSection: _openProfileSection,
      );
    } on BackendException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
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
                if (_home.user != null)
                  IconButton(
                    tooltip: _notificationCount == null
                        ? 'Notifications'
                        : _notificationCount == 0
                        ? 'Notifications'
                        : 'Notifications, $_notificationCount unread',
                    onPressed: _openNotifications,
                    icon: Badge(
                      isLabelVisible:
                          _notificationCount != null && _notificationCount! > 0,
                      label: Text(
                        _notificationCount != null && _notificationCount! > 99
                            ? '99+'
                            : '${_notificationCount ?? 0}',
                      ),
                      child: const Icon(Icons.notifications_outlined),
                    ),
                  ),
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
                      tooltip: 'Your profile',
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
                  BagPage(
                    repository: widget.repository,
                    active: _tab == 1,
                    onBrowse: () => _selectTab(2),
                  )
                else
                  const SizedBox.shrink(),
                if (_visited.contains(2))
                  SearchPage(
                    repository: widget.repository,
                    request: _searchRequest,
                  )
                else
                  const SizedBox.shrink(),
                if (_visited.contains(3))
                  ProfilePage(
                    key: ValueKey(
                      'buyer-profile-${_home.user?['id'] ?? 'guest'}',
                    ),
                    repository: widget.repository,
                    user: _home.user,
                    initial: widget.initial,
                    active: _tab == 3,
                    initialSection: _profileSection,
                    sectionRequest: _profileSectionRequest,
                    onSearch: _openSearchFilters,
                    onLogin: () =>
                        BuyerActions.login(context, destination: 'profile'),
                    onLogout: widget.onLogout,
                    onUserChanged: (user) {
                      if (mounted) {
                        setState(() {
                          _home.data?.props['auth'] = {
                            ...mapOf(_home.data?.props['auth']),
                            'user': user,
                          };
                        });
                        _homeChanged();
                      }
                    },
                  )
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
                      maxLength: 100,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (value) => _openSearch(query: value),
                      decoration: InputDecoration(
                        labelText: 'Search products',
                        counterText: '',
                        hintText: 'What are you looking for?',
                        prefixIcon: const ExcludeSemantics(
                          child: Icon(Icons.search_rounded),
                        ),
                        suffixIcon: IconButton(
                          tooltip: 'Search marketplace',
                          onPressed: () => _openSearch(query: _search.text),
                          icon: const Icon(Icons.arrow_forward_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _openingFilters ? null : _advancedFilters,
                      icon: const Icon(Icons.tune),
                      label: Text(
                        _openingFilters
                            ? 'Loading filters…'
                            : 'Filter products',
                      ),
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _openingTracking ? null : _openTracking,
                          icon: const Icon(Icons.local_shipping_outlined),
                          label: const Text('Track a parcel'),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            final user = _home.user;
                            if (user == null) {
                              widget.onLogin();
                              return;
                            }
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SupportAssistantPage(
                                  repository: widget.repository,
                                  user: user,
                                  available: _canSave,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.help_outline),
                          label: const Text('Help & Support'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  AboutBagooPage(repository: widget.repository),
                            ),
                          ),
                          child: const Text('About BagooPH'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
                          onOpen: _openBanner,
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
                        if (mapOf(
                              _home.data!.props['buyerApplication'],
                            )['can_use_portal'] !=
                            true)
                          ProductPanel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Application: ${mapOf(mapOf(_home.data!.props['buyerApplication'])['user'])['kyc_status']?.toString().replaceAll('_', ' ') ?? 'Under review'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  mapOf(
                                        mapOf(
                                          _home.data!.props['buyerApplication'],
                                        )['user'],
                                      )['kyc_feedback']?.toString() ??
                                      'Browse and use your Bag while approval is pending. Checkout requires approval.',
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _openProfileSection('identity'),
                                  child: const Text(
                                    'Review or correct application',
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _openBuyerHref('/account/status'),
                                  child: const Text('View account status'),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 20),
                      ],
                      if (mapOf(_home.data!.props['activeShipment']).isNotEmpty)
                        ProductPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const ProductHeading('Your delivery'),
                              Text(
                                'Order ${mapOf(_home.data!.props['activeShipment'])['order_number']} · ${mapOf(_home.data!.props['activeShipment'])['item_name']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${mapOf(_home.data!.props['activeShipment'])['status']?.toString().replaceAll('_', ' ')} · ${mapOf(_home.data!.props['activeShipment'])['courier_name'] ?? 'Courier to be assigned'}',
                              ),
                              Text(
                                'Estimated arrival: ${mapOf(_home.data!.props['activeShipment'])['estimated_delivery'] ?? 'Not yet available'}',
                              ),
                              TextButton(
                                onPressed: () => _openBuyerHref(
                                  '/buyer/orders/${mapOf(_home.data!.props['activeShipment'])['order_id']}',
                                ),
                                child: const Text('View delivery'),
                              ),
                            ],
                          ),
                        ),
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
            if (!_home.loading &&
                _home.error == null &&
                _home.isMarketplace &&
                mapsOf(_home.data?.props['relatedProducts']).isNotEmpty) ...[
              const SliverPadding(
                padding: EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: ProductHeading('You may also like'),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontal),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) => SliverGrid.builder(
                    itemCount: mapsOf(_home.data?.props['relatedProducts'])
                        .length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: count,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      mainAxisExtent:
                          (constraints.crossAxisExtent - (count - 1) * 14) /
                              count +
                          productCardBodyHeight * scaled,
                    ),
                    itemBuilder: (_, index) => _card(
                      mapsOf(_home.data?.props['relatedProducts'])[index],
                    ),
                  ),
                ),
              ),
            ],
            SliverPadding(
              padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 32),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    if (_home.moreError != null)
                      Notice(_home.moreError!, error: true),
                    if (!_home.loading &&
                        _home.error == null &&
                        _home.isMarketplace)
                      CataloguePages(
                        current: _home.currentPage,
                        last: _home.lastPage,
                        total: _home.total,
                        from: _home.from,
                        to: _home.to,
                        busy: _home.loadingMore,
                        onPage: (number) => _home.load(pageNumber: number),
                      ),
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
