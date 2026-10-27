import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import 'profile_repository.dart';
import 'profile_widgets.dart';
import 'personal_section.dart';
import 'email_section.dart';
import 'identity_section.dart';
import 'sessions_section.dart';
import 'addresses_section.dart';
import 'wallet_section.dart';
import 'vouchers_section.dart';
import 'purchases_section.dart';
import 'order_detail_page.dart';
import 'inbox_page.dart';
import 'returns_page.dart';
import '../collections/followed_shops_page.dart';
import '../collections/saved_products_page.dart';
import '../home/search_controller.dart';
import '../notifications/notifications_page.dart';
import '../support/support_assistant_page.dart';
import '../tracking/parcel_tracking_page.dart';

const _sections = {
  'overview': 'Profile',
  'orders': 'My Purchases & Orders',
  'personal': 'Personal info',
  'emails': 'Email addresses',
  'password': 'Password',
  'identity': 'Identity correction',
  'sessions': 'Login activity',
  'addresses': 'Delivery Address Book',
  'wallet': 'Bagoo Wallet',
  'vouchers': 'Vouchers & Promos',
};

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.repository,
    required this.user,
    required this.onLogin,
    required this.onLogout,
    required this.onUserChanged,
    this.initial,
    this.active = true,
    this.initialSection = 'overview',
    this.sectionRequest = 0,
    this.onSearch,
    this.onNotificationCountChanged,
  });
  final BuyerRepository repository;
  final Map<String, dynamic>? user;
  final VoidCallback onLogin;
  final Future<void> Function() onLogout;
  final ValueChanged<Map<String, dynamic>> onUserChanged;
  final WebPage? initial;
  final bool active;
  final String initialSection;
  final int sectionRequest;
  final ValueChanged<SearchFilters>? onSearch;
  final ValueChanged<int>? onNotificationCountChanged;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final ProfileRepository _repository;
  final _contentKey = GlobalKey();
  final _visited = <String>{'overview'};
  final _query = <String, String>{};
  WebPage? _page;
  String _section = 'overview';
  String? _error, _message;
  bool _loading = false, _signingOut = false, _accountExpanded = true;
  bool _openingSupport = false;
  bool _openingTracking = false;
  int _generation = 0, _activityRefresh = 0;
  Map<String, dynamic> get user =>
      _page == null ? widget.user ?? {} : mapOf(_page!.props['user']);
  bool get _accountSection => [
    'personal',
    'emails',
    'password',
    'identity',
    'sessions',
  ].contains(_section);
  String get _tab =>
      _accountSection || _section == 'overview' || _section == 'sessions'
      ? 'account'
      : _section;
  @override
  void initState() {
    super.initState();
    _repository = ProfileRepository(widget.repository);
    if (_sections.containsKey(widget.initialSection)) {
      _section = widget.initialSection;
      _visited.add(_section);
    }
    if (widget.initial?.component == 'Buyer/Profile') {
      try {
        _page = _repository.checked(widget.initial!);
      } on BackendException catch (e) {
        _error = e.message;
      }
    }
    if (widget.user != null) _load();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  void didUpdateWidget(ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sectionChanged = widget.sectionRequest != oldWidget.sectionRequest;
    if (sectionChanged) {
      _select(
        _sections.containsKey(widget.initialSection)
            ? widget.initialSection
            : 'overview',
      );
      unawaited(_load());
    }
    if (widget.active &&
        !oldWidget.active &&
        widget.user != null &&
        !_loading &&
        !sectionChanged) {
      _load(refreshActivity: false);
    }
  }

  Future<void> _load({bool refreshActivity = true}) async {
    if (!mounted || widget.user == null) return;
    final generation = ++_generation;
    final owner = widget.user!['id'];
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var page = await _repository.load(tab: _tab, query: Map.of(_query));
      final corrected = <String, String>{};
      for (final entry in {
        'page': mapOf(page.props['orders']),
        'wallet_page': mapOf(mapOf(page.props['wallet'])['transactions']),
        'voucher_page': mapOf(mapOf(page.props['voucherCollection'])['offers']),
      }.entries) {
        final current = (entry.value['current_page'] as num?)?.toInt() ?? 1;
        final last = (entry.value['last_page'] as num?)?.toInt() ?? 1;
        if (current > last && last >= 1) corrected[entry.key] = '$last';
      }
      if (corrected.isNotEmpty && mounted && generation == _generation) {
        _query.addAll(corrected);
        page = await _repository.load(tab: _tab, query: Map.of(_query));
      }
      if (!mounted ||
          generation != _generation ||
          owner != widget.user?['id']) {
        return;
      }
      if (page.user?['id'] != owner) {
        throw const BackendException(
          'The signed-in account changed. Sign in again to load your own profile.',
          status: 401,
        );
      }
      setState(() {
        _page = page;
        _error = null;
        if (refreshActivity && _section == 'sessions') _activityRefresh++;
      });
      widget.onUserChanged(mapOf(page.props['user']));
    } on BackendException catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = e.message;
          if (e.status == 401 || e.status == 419) _page = null;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _accept(WebPage page) {
    _repository.checked(page);
    if (!mounted || page.user?['id'] != widget.user?['id']) return;
    _generation++;
    setState(() {
      _page = page;
      _loading = false;
      _error = null;
      _message = mapOf(page.props['flash'])['success']?.toString();
    });
    widget.onUserChanged(mapOf(page.props['user']));
  }

  void _select(String section) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _section = section;
      _visited.add(section);
      _message = null;
    });
  }

  void _ordersQuery(String status, int number) {
    _query.addAll({'order_status': status, 'page': '$number'});
    _select('orders');
    _load();
  }

  void _vouchersQuery(String tab, int number) {
    _query.addAll({'voucher_tab': tab, 'voucher_page': '$number'});
    _select('vouchers');
    _load();
  }

  Future<void> _order(int id) async {
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OrderDetailPage(repository: _repository, orderId: id),
        ),
      );
      if (mounted) await _load();
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _logout() async {
    if (_signingOut) return;
    setState(() {
      _signingOut = true;
      _error = null;
    });
    try {
      await widget.onLogout();
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _shortcut(bool messages) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => messages
            ? InboxPage(repository: _repository)
            : ReturnsPage(repository: _repository),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openTracking() async {
    if (_openingTracking || _signingOut) return;
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

  Future<void> _openSupport() async {
    if (_loading || _openingSupport || _signingOut || _page == null) return;
    final userId = user['id'];
    if (userId is! num) {
      widget.onLogin();
      return;
    }
    setState(() => _openingSupport = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SupportAssistantPage(
            repository: widget.repository,
            user: Map<String, dynamic>.from(user),
            available: _page?.props['canUsePortal'] == true,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingSupport = false);
    }
    if (mounted) await _load();
  }

  Future<void> _openEngagement(String destination) async {
    final userId = widget.user?['id'];
    if (userId is! num) {
      widget.onLogin();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => switch (destination) {
          'saved' => SavedProductsPage(
            repository: widget.repository,
            ownerId: userId.toInt(),
            onSearch: widget.onSearch,
          ),
          'followed' => FollowedShopsPage(
            repository: widget.repository,
            ownerId: userId.toInt(),
            onSearch: widget.onSearch,
          ),
          _ => NotificationsPage(
            repository: widget.repository,
            ownerId: userId.toInt(),
            onSearch: widget.onSearch,
            onProfileSection: (section) {
              _select(section);
              unawaited(_load());
            },
            onSummaryChanged: (count) {
              if (mounted && widget.user?['id'] == userId) {
                widget.onNotificationCountChanged?.call(count);
              }
            },
          ),
        },
      ),
    );
  }

  Widget _identity() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: 'Edit your profile photo',
          child: InkWell(
            onTap: () => _select('personal'),
            borderRadius: BorderRadius.circular(14),
            child: ProfileAvatar(user, _repository.session),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user['name']?.toString() ?? 'Buyer',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user['email']?.toString() ?? '',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: BagooTheme.muted,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                identityLabel(user),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: reviewed(user)
                      ? const Color(0xFF047857)
                      : BagooTheme.strong,
                  height: 1.6,
                ),
              ),
              if (user['status'] != 'active')
                Text(
                  'Account: ${user['status'].toString().replaceAll('_', ' ')}',
                  style: const TextStyle(fontSize: 12, height: 1.7),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _link(
    String section,
    String title,
    IconData icon, {
    String? count,
    bool nested = false,
  }) {
    final selected = _section == section;
    return Padding(
      padding: EdgeInsets.only(top: 4, left: nested ? 16 : 0),
      child: Semantics(
        selected: selected,
        child: Material(
          color: selected ? BagooTheme.crimson : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: _signingOut ? null : () => _select(section),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      icon,
                      color: selected ? Colors.white : BagooTheme.muted,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : BagooTheme.ink,
                        height: 1.5,
                      ),
                    ),
                  ),
                  if (count != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        count,
                        style: TextStyle(
                          fontSize: 11,
                          color: selected ? Colors.white : BagooTheme.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _menu() => [
    _identity(),
    const SizedBox(height: 20),
    _link(
      'orders',
      'My Purchases & Orders',
      Icons.inventory_2_outlined,
      count: _page?.props['ordersCount']?.toString(),
    ),
    Padding(
      padding: const EdgeInsets.only(left: 16, top: 4),
      child: TextButton.icon(
        onPressed: _signingOut
            ? null
            : () => _ordersQuery('delivery_failed', 1),
        icon: const Icon(Icons.error_outline, size: 18),
        label: const Text('Order issues'),
      ),
    ),
    const Divider(height: 24),
    ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: const ExcludeSemantics(
        child: Icon(Icons.manage_accounts_outlined, size: 22),
      ),
      title: const Text(
        'My Account & Security',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
      trailing: Icon(
        _accountExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
      ),
      onTap: () => setState(() => _accountExpanded = !_accountExpanded),
    ),
    if (_accountExpanded) ...[
      _link('personal', 'Personal info', Icons.person_outline, nested: true),
      _link('emails', 'Email addresses', Icons.mail_outline, nested: true),
      _link('password', 'Password', Icons.key_outlined, nested: true),
      _link('identity', 'Identity correction', Icons.fingerprint, nested: true),
      _link('sessions', 'Login activity', Icons.devices_outlined, nested: true),
    ],
    const Divider(height: 24),
    _link(
      'addresses',
      'Delivery Address Book',
      Icons.location_on_outlined,
      count: _page == null
          ? null
          : mapsOf(_page!.props['addresses']).length.toString(),
    ),
    _link('wallet', 'Bagoo Wallet', Icons.account_balance_wallet_outlined),
    _link(
      'vouchers',
      'Vouchers & Promos',
      Icons.local_offer_outlined,
      count: _page?.props['availableVoucherCount']?.toString(),
    ),
    const Divider(height: 24),
    ListTile(
      leading: const ExcludeSemantics(
        child: Icon(Icons.favorite_border, size: 20),
      ),
      title: const Text(
        'Saved products',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      enabled: !_signingOut,
      onTap: () => _openEngagement('saved'),
    ),
    ListTile(
      leading: const ExcludeSemantics(
        child: Icon(Icons.storefront_outlined, size: 20),
      ),
      title: const Text(
        'Followed shops',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      enabled: !_signingOut,
      onTap: () => _openEngagement('followed'),
    ),
    ListTile(
      leading: const ExcludeSemantics(
        child: Icon(Icons.notifications_none, size: 20),
      ),
      title: const Text(
        'Notifications',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      enabled: !_signingOut,
      onTap: () => _openEngagement('notifications'),
    ),
    ListTile(
      leading: const ExcludeSemantics(
        child: Icon(Icons.support_agent_outlined, size: 20),
      ),
      title: const Text(
        'Help & Support',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: const Text('Ask Bagoo or message Customer Care'),
      trailing: const Icon(Icons.chevron_right, size: 18),
      enabled: !_signingOut && !_loading && !_openingSupport && _page != null,
      onTap: _openSupport,
    ),
    ListTile(
      leading: const ExcludeSemantics(
        child: Icon(Icons.local_shipping_outlined, size: 20),
      ),
      title: const Text(
        'Track a parcel',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: const Text('Look up a waybill tracking number'),
      trailing: const Icon(Icons.chevron_right, size: 18),
      enabled: !_signingOut && !_openingTracking,
      onTap: _openTracking,
    ),
    const Divider(height: 24),
    ListTile(
      leading: const ExcludeSemantics(
        child: Icon(Icons.chat_bubble_outline, size: 20),
      ),
      title: const Text(
        'Store & Courier Messages',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      enabled: !_signingOut && _page?.props['canUsePortal'] == true,
      onTap: () => _shortcut(true),
    ),
    ListTile(
      leading: const ExcludeSemantics(
        child: Icon(Icons.assignment_return_outlined, size: 20),
      ),
      title: const Text(
        'Returns & Refunds',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      enabled: !_signingOut,
      onTap: () => _shortcut(false),
    ),
    const Divider(height: 24),
    OutlinedButton.icon(
      onPressed: _signingOut ? null : _logout,
      icon: const Icon(Icons.logout),
      label: Text(_signingOut ? 'Signing out…' : 'Log out'),
    ),
  ];
  Widget _overview(bool wide) => ListView(
    key: const PageStorageKey('profile-overview'),
    padding: const EdgeInsets.all(16),
    children: [
      if (!wide)
        ProfilePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProfileHeading(
                'Your profile',
                'Your purchases, personal information, and account settings.',
                Icons.person_outline,
              ),
              _identity(),
            ],
          ),
        ),
      ProfilePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'My Purchases',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: () => _select('orders'),
                  child: const Text('View all'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, box) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                final columns = scale > 1.4
                    ? 1
                    : box.maxWidth >= 500
                    ? 4
                    : 2;
                final width = (box.maxWidth - (columns - 1) * 8) / columns;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final status in {
                      'to_pay': (
                        Icons.account_balance_wallet_outlined,
                        'To pay',
                      ),
                      'to_ship': (Icons.inventory_2_outlined, 'To ship'),
                      'in_transit': (
                        Icons.local_shipping_outlined,
                        'In transit',
                      ),
                      'delivered': (Icons.task_alt_outlined, 'Delivered'),
                    }.entries)
                      SizedBox(
                        width: width,
                        child: OutlinedButton(
                          onPressed: () => _ordersQuery(status.key, 1),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 8,
                            ),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            children: [
                              ExcludeSemantics(
                                child: Icon(status.value.$1, size: 24),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                mapOf(
                                      _page?.props['orderCounts'],
                                    )[status.key]?.toString() ??
                                    '0',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                status.value.$2,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      if (!wide)
        ProfilePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _menu().skip(2).toList(),
          ),
        )
      else
        ProfilePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProfileHeading(
                'Account overview',
                'Manage your profile and shopping activity from the menu.',
                Icons.manage_accounts_outlined,
              ),
              Text(
                user['name']?.toString() ?? '',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                user['email']?.toString() ?? '',
                style: const TextStyle(fontSize: 14, height: 1.7),
              ),
              const SizedBox(height: 20),
              Text(
                'Identity review: ${identityLabel(user)}\nAccount status: ${user['status']?.toString().replaceAll('_', ' ') ?? 'Not recorded'}',
                style: const TextStyle(height: 1.8),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => _select('personal'),
                child: const Text('Manage personal information'),
              ),
            ],
          ),
        ),
    ],
  );
  Widget _workspace(String section, bool wide) {
    if (section == 'overview') return _overview(wide);
    final page = _page!;
    return switch (section) {
      'personal' => PersonalSection(
        repository: _repository,
        page: page,
        onChanged: _accept,
        onIdentity: () => _select('identity'),
      ),
      'emails' => EmailSection(
        repository: _repository,
        page: page,
        reload: _load,
      ),
      'password' => PasswordSection(
        repository: _repository,
        page: page,
        onChanged: _accept,
      ),
      'identity' => IdentitySection(
        repository: _repository,
        page: page,
        onChanged: _accept,
        reload: _load,
      ),
      'sessions' => SessionsSection(
        repository: _repository,
        owner: (user['id'] as num).toInt(),
        active: widget.active && _section == 'sessions',
        refreshVersion: _activityRefresh,
      ),
      'addresses' => AddressesSection(
        repository: _repository,
        page: page,
        onChanged: _accept,
      ),
      'wallet' => WalletSection(
        repository: _repository,
        page: page,
        reload: _load,
        onPage: (number) {
          _query['wallet_page'] = '$number';
          _load();
        },
        onOrder: _order,
      ),
      'vouchers' => VouchersSection(
        repository: _repository,
        page: page,
        onQuery: _vouchersQuery,
        reload: _load,
        loading: _loading,
      ),
      'orders' => PurchasesSection(
        repository: _repository,
        page: page,
        onQuery: _ordersQuery,
        reload: _load,
        loading: _loading,
      ),
      _ => _overview(wide),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (widget.user == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ProfilePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProfileHeading(
                  'Your Bagoo profile',
                  'Sign in to manage your purchases, delivery addresses, wallet, and account settings.',
                  Icons.person_outline,
                ),
                SubmitButton(label: 'Log In', onPressed: widget.onLogin),
              ],
            ),
          ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final wide =
            box.maxWidth >= 1000 &&
            MediaQuery.textScalerOf(context).scale(16) < 24;
        Widget content;
        if (_page == null) {
          content = ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ProfilePanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _identity(),
                    const SizedBox(height: 24),
                    if (_loading)
                      const Center(child: CircularProgressIndicator()),
                    if (!_loading) ...[
                      Text(
                        mapOf(
                              widget.initial?.props['status'],
                            )['message']?.toString() ??
                            'Your profile details could not load. Refresh or sign in again.',
                        style: const TextStyle(height: 1.7),
                      ),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Try again'),
                      ),
                      TextButton(
                        onPressed: widget.onLogin,
                        child: const Text('Sign in again'),
                      ),
                      OutlinedButton(
                        onPressed: _signingOut ? null : _logout,
                        child: const Text('Log out'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        } else {
          final keys = _sections.keys.toList();
          content = IndexedStack(
            key: _contentKey,
            index: keys.indexOf(_section),
            children: [
              for (final key in keys)
                if (_visited.contains(key))
                  _workspace(key, wide)
                else
                  const SizedBox.shrink(),
            ],
          );
        }
        final body = Column(
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null || _message != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: box.maxHeight * .25),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Notice(_error ?? _message!, error: _error != null),
                ),
              ),
            if (!wide && _section != 'overview' && _page != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back to profile',
                      onPressed: () => _select('overview'),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Expanded(
                      child: Text(
                        _sections[_section]!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh profile details',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              )
            else if (_page != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh profile'),
                ),
              ),
            Expanded(child: content),
          ],
        );
        return wide && _page != null
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 310,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        ProfilePanel(
                          padding: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _menu(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: body),
                ],
              )
            : body;
      },
    );
  }
}
