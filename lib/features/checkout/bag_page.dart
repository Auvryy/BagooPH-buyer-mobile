import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_actions.dart';
import '../../core/verification_prompt.dart';
import '../../core/buyer_account_scope.dart';
import '../../core/buyer_repository.dart';
import '../../core/numeric_input.dart';
import '../../core/strict_datetime.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../home/product_card.dart';
import '../products/product_page.dart';
import '../products/product_widgets.dart';
import 'bag_controller.dart';
import 'commerce_details.dart';
import 'checkout_page.dart';

class BagPage extends StatefulWidget {
  const BagPage({
    super.key,
    required this.repository,
    this.voucherCode,
    this.account,
    this.initialSelection = const [],
    this.active = true,
    this.onBrowse,
  });
  final BuyerRepository repository;
  final String? voucherCode;
  final BuyerAccountScope? account;
  final List<int> initialSelection;
  final bool active;
  final VoidCallback? onBrowse;
  @override
  State<BagPage> createState() => _BagPageState();
}

class _BagPageState extends State<BagPage> {
  int _revision = 0;

  @override
  Widget build(BuildContext context) => _BagContents(
    key: ValueKey(_revision),
    settings: widget,
    onReopen: () => setState(() => _revision++),
  );
}

// Reopening creates a new session-bound state. Retained callbacks belong to the
// disposed contents and cannot apply their old item or draft to the new Bag.
class _BagContents extends StatefulWidget {
  const _BagContents({
    super.key,
    required this.settings,
    required this.onReopen,
  });
  final BagPage settings;
  final VoidCallback onReopen;
  BuyerRepository get repository => settings.repository;
  String? get voucherCode => settings.voucherCode;
  List<int> get initialSelection => settings.initialSelection;
  bool get active => settings.active;
  VoidCallback? get onBrowse => settings.onBrowse;

  @override
  State<_BagContents> createState() => _BagContentsState();
}

class _BagContentsState extends State<_BagContents>
    with WidgetsBindingObserver {
  late final BuyerAccountScope _checkoutAccount;
  late final BagController _bag;
  final _search = TextEditingController();
  String _sort = 'recent', _filter = 'all';
  bool _opening = false, _refreshOnIdle = false, _modalOpen = false;
  bool _accessEnded = false, _reopening = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkoutAccount =
        (widget.settings.account ??
                BuyerAccountScope(widget.repository.session))
            .fork();
    _bag = BagController(
      widget.repository,
      initialSelection: widget.initialSelection,
    );
    _bag.addListener(_onIdle);
    if (_checkoutAccount.isCurrent &&
        identical(_checkoutAccount.session, widget.repository.session)) {
      _bag.load();
    } else {
      _bag.invalidate(notify: false);
    }
  }

  void _onIdle() {
    if (!_ensureAccount(notify: false)) return;
    if (_refreshOnIdle && !_bag.busy && widget.active) {
      _refreshOnIdle = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ensureAccount()) _bag.load();
      });
    }
  }

  @override
  void didUpdateWidget(_BagContents oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_ensureAccount(notify: false)) {
      // Notify an independent dialog route after the current build finishes.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bag.invalidate();
      });
      return;
    }
    if (widget.active && !oldWidget.active) {
      if (_bag.busy) {
        _refreshOnIdle = true;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.active && _ensureAccount()) _bag.load();
        });
      }
    }
  }

  bool _ensureAccount({bool notify = true}) {
    if (!mounted) return false;
    if (!identical(_bag.repository, widget.repository) ||
        !_checkoutAccount.isCurrent ||
        !identical(_checkoutAccount.session, widget.repository.session)) {
      _bag.invalidate(notify: notify);
    }
    final current = _bag.ensureCurrent(notify: notify);
    if (!current && !_accessEnded) {
      _accessEnded = true;
      _checkoutAccount.invalidate();
      _search.clear();
      _sort = 'recent';
      _filter = 'all';
      _refreshOnIdle = false;
    }
    return current;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_ensureAccount()) {
      setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checkoutAccount.invalidate();
    _bag.removeListener(_onIdle);
    _bag.dispose();
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _displayed {
    final query = _search.text.trim().toLowerCase();
    final rows = _bag.items.where((item) {
      final product = mapOf(item['product']);
      return '${product['name']} ${mapOf(product['shop'])['name']} ${item['color']} ${item['size']}'
              .toLowerCase()
              .contains(query) &&
          (_filter == 'all' ||
              (_filter == 'selected'
                  ? _bag.selected.contains(item['id'])
                  : !_bag.selected.contains(item['id'])));
    }).toList();
    rows.sort((a, b) {
      if (_sort == 'name') {
        return mapOf(
          a['product'],
        )['name'].toString().compareTo(mapOf(b['product'])['name'].toString());
      }
      if (_sort == 'price_low' || _sort == 'price_high') {
        final result = (amount(a['unit_price']) ?? 0).compareTo(
          amount(b['unit_price']) ?? 0,
        );
        return _sort == 'price_high' ? -result : result;
      }
      final aTime =
          strictDateTime(a['updated_at'] ?? a['created_at'])
              ?.millisecondsSinceEpoch ??
          0;
      final bTime =
          strictDateTime(b['updated_at'] ?? b['created_at'])
              ?.millisecondsSinceEpoch ??
          0;
      final result = bTime.compareTo(aTime);
      return result == 0 ? (b['id'] as num).compareTo(a['id'] as num) : result;
    });
    return rows;
  }

  Future<void> _product(Map<String, dynamic> item) async {
    if (!_ensureAccount() || _modalOpen) return;
    final slug = mapOf(item['product'])['slug'];
    if (slug == null || _bag.busy || _opening) return;
    setState(() => _opening = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ProductPage(repository: widget.repository, slug: slug.toString()),
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
    if (mounted && _ensureAccount()) await _bag.load();
  }

  Future<void> _step(int id, int quantity) async {
    if (!_ensureAccount() || _modalOpen || _opening) return;
    await _bag.change(id, quantity);
  }

  void _editFilters(VoidCallback update) {
    if (!_ensureAccount() || _modalOpen) return;
    setState(update);
  }

  void _reopen() {
    if (!mounted || _reopening || _modalOpen) return;
    _reopening = true;
    widget.onReopen();
  }

  Future<void> _quantity(Map<String, dynamic> item) async {
    if (!_ensureAccount() || _modalOpen || _opening || !_bag.canChange) return;
    final id = item['id'];
    final current = _bag.items.where((row) => row['id'] == id).firstOrNull;
    if (id is! int || current == null) return;
    final maximum = bagMaximumQuantity(current, _bag.items);
    if (maximum < 1 || _bag.busy) return;
    setState(() => _modalOpen = true);
    int? quantity;
    try {
      quantity = await showDialog<int>(
        context: context,
        builder: (_) => _BagQuantityDialog(
          bag: _bag,
          id: id,
          ensureAccount: _ensureAccount,
        ),
      );
    } finally {
      if (mounted) setState(() => _modalOpen = false);
    }
    if (!mounted || !_ensureAccount()) return;
    final latest = _bag.items.where((row) => row['id'] == id).firstOrNull;
    if (quantity != null && quantity != latest?['quantity']) {
      final saved = await _bag.change(id, quantity);
      if (mounted && _ensureAccount() && saved) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bag quantity updated.')));
      }
    }
  }

  Future<void> _remove(Map<String, dynamic> item) async {
    if (!_ensureAccount() ||
        _modalOpen ||
        _opening ||
        _bag.busy ||
        !_bag.canChange) {
      return;
    }
    final id = item['id'];
    if (id is! int || !_bag.items.any((row) => row['id'] == id)) return;
    setState(() => _modalOpen = true);
    bool? confirmed;
    var decided = false;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) {
          void decide(bool remove) {
            if (decided ||
                !dialog.mounted ||
                ModalRoute.of(dialog)?.isCurrent != true) {
              return;
            }
            if (remove && (!_ensureAccount() || !_bag.canChange || _bag.busy)) {
              return;
            }
            decided = true;
            Navigator.pop(dialog, remove);
          }

          return ListenableBuilder(
            listenable: _bag,
            builder: (_, _) {
              final current = _bag.items
                  .where((row) => row['id'] == id)
                  .firstOrNull;
              if (!_ensureAccount(notify: false) ||
                  !_bag.canChange ||
                  current == null) {
                return _changedBagDialog(onClose: () => decide(false));
              }
              return AlertDialog(
                title: const Text('Remove from your Bag?'),
                content: Text(
                  mapOf(current['product'])['name']?.toString() ?? 'This item',
                ),
                actions: [
                  TextButton(
                    onPressed: () => decide(false),
                    child: const Text('Keep item'),
                  ),
                  FilledButton(
                    onPressed: _bag.busy ? null : () => decide(true),
                    child: const Text('Remove'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      if (mounted) setState(() => _modalOpen = false);
    }
    if (!mounted || !_ensureAccount()) return;
    if (confirmed == true) {
      final saved = await _bag.change(id, null);
      if (mounted && _ensureAccount() && saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item removed from your Bag.')),
        );
      }
    }
  }

  Future<void> _checkout({String? code}) async {
    if (!_ensureAccount() || _modalOpen) return;
    if (_bag.data?.user == null) {
      BuyerActions.login(context, destination: 'cart');
      return;
    }
    if (!_bag.approved) {
      setState(() => _modalOpen = true);
      try {
        final review = await showBuyerVerificationPrompt(
          context,
          _bag.data!.user!,
        );
        if (review && mounted && _ensureAccount()) {
          _checkoutAccount.check(page: _bag.data!);
          if (mounted) BuyerActions.reviewVerification(context);
        }
      } on BackendException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      } finally {
        if (mounted) setState(() => _modalOpen = false);
      }
      return;
    }
    if (!_bag.ready || _opening) return;
    setState(() => _opening = true);
    try {
      if (!identical(_checkoutAccount.session, widget.repository.session)) {
        _checkoutAccount.invalidate();
      }
      _checkoutAccount.check(page: _bag.data!);
      final page = await widget.repository.checkout(
        _bag.selected.toList()..sort(),
      );
      if (!mounted) return;
      if (!identical(_checkoutAccount.session, widget.repository.session)) {
        _checkoutAccount.invalidate();
      }
      _checkoutAccount.check(page: page);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CheckoutPage(
            repository: widget.repository,
            initial: page,
            voucherCode: code ?? widget.voucherCode,
            account: _checkoutAccount,
          ),
        ),
      );
      if (mounted && _ensureAccount()) await _bag.load();
    } on BackendException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Widget _row(String label, String value, {bool total = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: total ? 15 : 13,
              height: 1.6,
              fontWeight: total ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: total ? 22 : 14,
              height: 1.4,
              color: total ? BagooTheme.strong : BagooTheme.ink,
            ),
          ),
        ),
      ],
    ),
  );
  String _price(String key) => _bag.selected.isEmpty
      ? pesos(0)
      : _bag.quote == null
      ? _bag.quoting
            ? 'Updating…'
            : 'Unavailable'
      : pesos(_bag.quote![key]);
  Widget _button() => FilledButton.icon(
    onPressed:
        _opening ||
            _modalOpen ||
            !_bag.isCurrent ||
            _bag.busy ||
            (_bag.data?.user == null || _bag.approved) && !_bag.ready
        ? null
        : _checkout,
    icon: const Icon(Icons.arrow_forward),
    label: Text(
      _opening
          ? 'Opening checkout…'
          : _bag.data?.user == null
          ? 'Sign in to checkout'
          : 'Checkout (${_bag.selected.length})',
    ),
  );
  Widget _summary() => ProductPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProductHeading('Order summary'),
        Text(
          '${_bag.selected.length} selected of ${_bag.items.length} items',
          style: const TextStyle(color: BagooTheme.muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        if (_bag.quoting)
          const LinearProgressIndicator(
            semanticsLabel: 'Updating selected Bag total',
          ),
        _row('Merchandise subtotal', _price('subtotal')),
        _row('Delivery estimate', _price('shipping_fee')),
        const Divider(height: 24),
        _row('Total estimate', _price('total'), total: true),
        if (_bag.quoteError != null) ...[
          Notice(_bag.quoteError!, error: true),
          TextButton(
            onPressed: _bag.busy ? null : _bag.refreshQuote,
            child: const Text('Retry selected total'),
          ),
        ],
        for (final shop in mapsOf(_bag.quote?['shops']))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  shop['shop_name'].toString(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                _row('Shop delivery', pesos(shop['shipping'])),
              ],
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          'Delivery is calculated separately for each shop. Your destination, vouchers and final total are confirmed at checkout.',
          style: TextStyle(fontSize: 12, height: 1.7, color: BagooTheme.muted),
        ),
        if (_bag.data?.user != null && !_bag.approved) ...[
          const SizedBox(height: 16),
          const Notice(
            'Checkout requires an active approved buyer account. You can review your account in Profile.',
          ),
        ],
        const SizedBox(height: 20),
        _button(),
        if (_bag.offers.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              '${_bag.offers.length} shop and Bagoo offers',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            children: [
              for (final offer in _bag.offers)
                OfferTile(
                  key: ValueKey('${offer['revision_id']}:${offer['saved_id']}'),
                  offer: offer,
                  repository: widget.repository,
                  canSave: _bag.approved || _bag.data?.user == null,
                  onSignIn: _bag.data?.user == null
                      ? () => BuyerActions.login(context, destination: 'cart')
                      : null,
                  onUse: _bag.approved && _bag.ready && !_opening && !_modalOpen
                      ? () => _checkout(code: offer['code']?.toString())
                      : null,
                ),
            ],
          ),
      ],
    ),
  );
  Widget _item(Map<String, dynamic> item) {
    final product = mapOf(item['product']);
    final id = item['id'] as int;
    final available = item['available_for_purchase'] == true;
    final maximum = bagMaximumQuantity(item, _bag.items);
    final disabled = _bag.busy || _opening || _modalOpen || !_bag.canChange;
    final priced = mapsOf(_bag.quote?['items'])
        .where((row) => row['id'] == id)
        .firstOrNull;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bag.selected.contains(id) ? BagooTheme.rose : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _bag.selected.contains(id)
              ? const Color(0xFFF4C8D2)
              : BagooTheme.line,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _bag.selected.contains(id),
                semanticLabel: 'Select ${product['name'] ?? 'Bag item'}',
                onChanged: _bag.busy || _opening || _modalOpen || !available
                    ? null
                    : (v) => _bag.select([id], v == true),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox.square(
                  dimension: 72,
                  child: RemoteImage(
                    thumbnail: true,
                    uri: imageUri(
                      widget.repository.session,
                      product['featured_image'],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton(
                      onPressed:
                          _bag.busy ||
                              _opening ||
                              _modalOpen ||
                              product['slug'] == null
                          ? null
                          : () => _product(item),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft,
                      ),
                      child: Text(
                        product['name']?.toString() ?? 'Unavailable product',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          height: 1.5,
                        ),
                      ),
                    ),
                    Text(
                      [
                        item['color'],
                        item['size'],
                      ].whereType<String>().join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: BagooTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      pesos(item['unit_price']),
                      style: const TextStyle(
                        color: BagooTheme.strong,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!available)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Notice(
                item['unavailable_reason']?.toString() ??
                    'This item is unavailable for purchase.',
                error: true,
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Decrease Bag quantity',
                onPressed:
                    disabled || !available || (item['quantity'] as num) <= 1
                    ? null
                    : () => _step(id, (item['quantity'] as num).toInt() - 1),
                icon: const Icon(Icons.remove),
              ),
              OutlinedButton(
                onPressed: disabled || maximum < 1
                    ? null
                    : () => _quantity(item),
                child: Text('Quantity ${item['quantity']}'),
              ),
              IconButton(
                tooltip: 'Increase Bag quantity',
                onPressed:
                    disabled ||
                        !available ||
                        (item['quantity'] as num) >= maximum
                    ? null
                    : () => _step(id, (item['quantity'] as num).toInt() + 1),
                icon: const Icon(Icons.add),
              ),
              TextButton.icon(
                onPressed: disabled ? null : () => _remove(item),
                icon: const Icon(Icons.delete_outline, size: 20),
                label: const Text('Remove'),
              ),
            ],
          ),
          if (priced != null && _bag.quote != null)
            PriceSegments(segments: mapsOf(priced['price_segments'])),
          if (priced != null && _bag.quote != null)
            _row(
              'Selected line total',
              pesos(
                priced['subtotal'] ??
                    mapsOf(priced['price_segments']).fold<double>(
                      0,
                      (sum, segment) =>
                          sum + (amount(segment['subtotal']) ?? 0),
                    ),
              ),
            ),
          if (_bag.itemErrors[id] != null) ...[
            Notice(_bag.itemErrors[id]!, error: true),
            TextButton(
              onPressed: _bag.busy ? null : _bag.load,
              child: const Text('Reload Bag to check this item'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _items(bool wide) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final item in _displayed) {
      final product = mapOf(item['product']);
      final key =
          (product['shop_id'] ?? mapOf(product['shop'])['id'] ?? 'unavailable')
              .toString();
      groups.putIfAbsent(key, () => []).add(item);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (_bag.busy) const LinearProgressIndicator(),
        if (_bag.error != null) ...[
          Notice(_bag.error!, error: true),
          TextButton(
            onPressed: _bag.busy ? null : _bag.load,
            child: const Text('Refresh Bag'),
          ),
        ],
        ProductPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProductHeading('Your Shopping Bag'),
              Text(
                '${_bag.items.length} item${_bag.items.length == 1 ? '' : 's'} · Choose what to check out.',
                style: const TextStyle(
                  fontSize: 13,
                  color: BagooTheme.muted,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _search,
                onChanged: (_) => _editFilters(() {}),
                decoration: InputDecoration(
                  labelText: 'Search your Bag',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear Bag search',
                          onPressed: () => _editFilters(_search.clear),
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _sort,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Sort items'),
                items: [
                  for (final sort in {
                    'recent': 'Recently added',
                    'price_low': 'Price: low to high',
                    'price_high': 'Price: high to low',
                    'name': 'Product name',
                  }.entries)
                    DropdownMenuItem(value: sort.key, child: Text(sort.value)),
                ],
                onChanged: (v) => _editFilters(() => _sort = v!),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final filter in {
                    'all': 'All',
                    'selected': 'Selected',
                    'unselected': 'Unselected',
                  }.entries)
                    ChoiceChip(
                      label: Text(filter.value),
                      selected: _filter == filter.key,
                      showCheckmark: false,
                      side: BorderSide(
                        color: _filter == filter.key
                            ? BagooTheme.strong
                            : BagooTheme.line,
                      ),
                      labelStyle: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        color: _filter == filter.key
                            ? BagooTheme.strong
                            : BagooTheme.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) =>
                          _editFilters(() => _filter = filter.key),
                    ),
                ],
              ),
              if (_bag.items.isNotEmpty)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'Select all available items',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  value:
                      _bag.selected.isNotEmpty &&
                      _bag.selected.length == _bag.selectable.length,
                  onChanged:
                      _bag.busy ||
                          _opening ||
                          _modalOpen ||
                          _bag.selectable.isEmpty
                      ? null
                      : (v) => _bag.select(
                          _bag.selectable.map((i) => i['id'] as int),
                          v == true,
                        ),
                ),
            ],
          ),
        ),
        if (_bag.data != null && !_bag.busy && _bag.items.isEmpty)
          ProductPanel(
            child: Column(
              children: [
                const Icon(
                  Icons.shopping_bag_outlined,
                  size: 56,
                  color: BagooTheme.crimson,
                ),
                const SizedBox(height: 20),
                const ProductHeading('Your Bag is empty'),
                const Text(
                  'Find something you love and add it to your Bag.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed:
                      widget.onBrowse ?? () => Navigator.maybePop(context),
                  child: const Text('Continue shopping'),
                ),
              ],
            ),
          ),
        if (_bag.items.isNotEmpty && groups.isEmpty)
          ProductPanel(
            child: Column(
              children: [
                const ProductHeading('No matching Bag items'),
                TextButton(
                  onPressed: () => _editFilters(() {
                    _search.clear();
                    _filter = 'all';
                  }),
                  child: const Text('Show all Bag items'),
                ),
              ],
            ),
          ),
        for (final group in groups.values)
          ProductPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  secondary: const ExcludeSemantics(
                    child: Icon(
                      Icons.storefront_outlined,
                      color: BagooTheme.strong,
                    ),
                  ),
                  title: Text(
                    mapOf(
                          mapOf(group.first['product'])['shop'],
                        )['name']?.toString() ??
                        'Unavailable shop',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  value:
                      group
                          .where((i) => i['available_for_purchase'] == true)
                          .isNotEmpty &&
                      group
                          .where((i) => i['available_for_purchase'] == true)
                          .every((i) => _bag.selected.contains(i['id'])),
                  onChanged: _bag.busy || _opening || _modalOpen
                      ? null
                      : (v) => _bag.select(
                          group.map((i) => i['id'] as int),
                          v == true,
                        ),
                ),
                const Divider(),
                for (final item in group) _item(item),
              ],
            ),
          ),
        if (!wide && _bag.items.isNotEmpty) _summary(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _bag,
    builder: (context, _) {
      final current = _ensureAccount(notify: false);
      return Scaffold(
        appBar: AppBar(
          backgroundColor: BagooTheme.strong,
          foregroundColor: Colors.white,
          title: const Text(
            'Shopping Bag',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh Bag',
              onPressed: !current || _bag.busy || _opening || _modalOpen
                  ? null
                  : _bag.load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: !current
            ? SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Notice(
                          _bag.error ?? 'Your Bag session ended.',
                          error: true,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _reopen,
                          child: const Text('Reopen Bag'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : SafeArea(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final wide =
                        box.maxWidth >= 1050 &&
                        MediaQuery.textScalerOf(context).scale(16) < 24;
                    final content = RefreshIndicator(
                      onRefresh: _bag.load,
                      child: _items(wide),
                    );
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1320),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: content),
                                  SizedBox(
                                    width: 340,
                                    child: SingleChildScrollView(
                                      padding: const EdgeInsets.fromLTRB(
                                        0,
                                        16,
                                        16,
                                        16,
                                      ),
                                      child: _summary(),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  Expanded(child: content),
                                  if (_bag.items.isNotEmpty &&
                                      MediaQuery.viewInsetsOf(context).bottom ==
                                          0)
                                    Material(
                                      color: Colors.white,
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            _row(
                                              'Selected (${_bag.selected.length})',
                                              _price('total'),
                                              total: true,
                                            ),
                                            const SizedBox(height: 8),
                                            _button(),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    );
                  },
                ),
              ),
      );
    },
  );
}

Widget _changedBagDialog({required VoidCallback onClose}) => AlertDialog(
  title: const Text('Bag changed'),
  content: const SingleChildScrollView(
    child: Text('Close this dialog and review your Bag before continuing.'),
  ),
  actions: [TextButton(onPressed: onClose, child: const Text('Close'))],
);

class _BagQuantityDialog extends StatefulWidget {
  const _BagQuantityDialog({
    required this.bag,
    required this.id,
    required this.ensureAccount,
  });
  final BagController bag;
  final int id;
  final bool Function({bool notify}) ensureAccount;
  @override
  State<_BagQuantityDialog> createState() => _BagQuantityDialogState();
}

class _BagQuantityDialogState extends State<_BagQuantityDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _field;
  bool _decided = false;

  Map<String, dynamic>? get _item =>
      widget.bag.items.where((row) => row['id'] == widget.id).firstOrNull;
  bool get _canDecide =>
      mounted && !_decided && ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    _field = TextEditingController(text: '${_item?['quantity'] ?? ''}');
  }

  void _close() {
    if (!_canDecide) return;
    _decided = true;
    Navigator.pop(context);
  }

  void _update() {
    if (!_canDecide ||
        !widget.ensureAccount() ||
        !widget.bag.canChange ||
        widget.bag.busy ||
        _item == null) {
      return;
    }
    if (_form.currentState?.validate() != true) return;
    _decided = true;
    Navigator.pop(context, int.parse(_field.text));
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.bag,
    builder: (_, _) {
      final item = _item;
      final maximum = item == null
          ? 0
          : bagMaximumQuantity(item, widget.bag.items);
      if (!widget.ensureAccount(notify: false) ||
          !widget.bag.canChange ||
          item == null ||
          maximum < 1) {
        _field.clear();
        return _changedBagDialog(onClose: _close);
      }
      return AlertDialog(
        title: const Text('Update quantity'),
        content: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(mapOf(item['product'])['name']?.toString() ?? 'Bag item'),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _field,
                  autofocus: true,
                  maxLength: 2,
                  keyboardType: TextInputType.number,
                  inputFormatters: [unsignedIntegerFormatter],
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    helperText: 'Up to $maximum available',
                    counterText: '',
                  ),
                  validator: (value) =>
                      RegExp(r'^[1-9][0-9]?$').hasMatch(value ?? '') &&
                          int.parse(value!) <= maximum
                      ? null
                      : 'Choose 1 to $maximum units.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: _close, child: const Text('Cancel')),
          FilledButton(
            onPressed: widget.bag.busy ? null : _update,
            child: const Text('Update'),
          ),
        ],
      );
    },
  );
}
