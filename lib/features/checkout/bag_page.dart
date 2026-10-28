import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_actions.dart';
import '../../core/buyer_repository.dart';
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
    this.initialSelection = const [],
    this.active = true,
    this.onBrowse,
  });
  final BuyerRepository repository;
  final String? voucherCode;
  final List<int> initialSelection;
  final bool active;
  final VoidCallback? onBrowse;
  @override
  State<BagPage> createState() => _BagPageState();
}

class _BagPageState extends State<BagPage> {
  late final BagController _bag;
  final _search = TextEditingController();
  String _sort = 'recent', _filter = 'all';
  bool _opening = false, _refreshOnIdle = false;
  @override
  void initState() {
    super.initState();
    _bag = BagController(
      widget.repository,
      initialSelection: widget.initialSelection,
    );
    _bag.addListener(_onIdle);
    _bag.load();
  }

  void _onIdle() {
    if (_refreshOnIdle && !_bag.busy && widget.active) {
      _refreshOnIdle = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bag.load();
      });
    }
  }

  @override
  void didUpdateWidget(BagPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      if (_bag.busy) {
        _refreshOnIdle = true;
      } else {
        _bag.load();
      }
    }
  }

  @override
  void dispose() {
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
          DateTime.tryParse(
            (a['updated_at'] ?? a['created_at'])?.toString() ?? '',
          )?.millisecondsSinceEpoch ??
          0;
      final bTime =
          DateTime.tryParse(
            (b['updated_at'] ?? b['created_at'])?.toString() ?? '',
          )?.millisecondsSinceEpoch ??
          0;
      final result = bTime.compareTo(aTime);
      return result == 0 ? (b['id'] as num).compareTo(a['id'] as num) : result;
    });
    return rows;
  }

  Future<void> _product(Map<String, dynamic> item) async {
    final slug = mapOf(item['product'])['slug'];
    if (slug == null || _bag.busy || _opening) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ProductPage(repository: widget.repository, slug: slug.toString()),
      ),
    );
    if (mounted) await _bag.load();
  }

  Future<void> _quantity(Map<String, dynamic> item) async {
    final maximum = bagMaximumQuantity(item, _bag.items);
    if (maximum < 1 || _bag.busy) return;
    final quantity = await showDialog<int>(
      context: context,
      builder: (_) => _BagQuantityDialog(item: item, maximum: maximum),
    );
    if (mounted && quantity != null && quantity != item['quantity']) {
      final saved = await _bag.change((item['id'] as num).toInt(), quantity);
      if (mounted && saved) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bag quantity updated.')));
      }
    }
  }

  Future<void> _remove(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Remove from your Bag?'),
        content: Text(
          mapOf(item['product'])['name']?.toString() ?? 'This item',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep item'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final saved = await _bag.change((item['id'] as num).toInt(), null);
      if (mounted && saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item removed from your Bag.')),
        );
      }
    }
  }

  Future<void> _checkout({String? code}) async {
    if (_bag.data?.user == null) {
      BuyerActions.login(context, destination: 'cart');
      return;
    }
    if (!_bag.approved || !_bag.ready || _opening) return;
    setState(() => _opening = true);
    try {
      final page = await widget.repository.checkout(
        _bag.selected.toList()..sort(),
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CheckoutPage(
            repository: widget.repository,
            initial: page,
            voucherCode: code ?? widget.voucherCode,
          ),
        ),
      );
      if (mounted) await _bag.load();
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
        !_bag.ready || _opening || (_bag.data?.user != null && !_bag.approved)
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
                  onUse: _bag.approved && _bag.ready && !_opening
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
    final id = (item['id'] as num).toInt();
    final available = item['available_for_purchase'] == true;
    final maximum = bagMaximumQuantity(item, _bag.items);
    final disabled = _bag.busy || _opening || !_bag.canChange;
    final priced = mapsOf(_bag.quote?['items'])
        .where((row) => row['id'] == id)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _bag.selected.contains(id),
                semanticLabel: 'Select ${product['name'] ?? 'Bag item'}',
                onChanged: _bag.busy || _opening || !available
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
                          _bag.busy || _opening || product['slug'] == null
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
                    : () => _bag.change(
                        id,
                        (item['quantity'] as num).toInt() - 1,
                      ),
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
                    : () => _bag.change(
                        id,
                        (item['quantity'] as num).toInt() + 1,
                      ),
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
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Search your Bag',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear Bag search',
                          onPressed: () => setState(_search.clear),
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
                onChanged: (v) => setState(() => _sort = v!),
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
                      onSelected: (_) => setState(() => _filter = filter.key),
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
                  onChanged: _bag.busy || _opening || _bag.selectable.isEmpty
                      ? null
                      : (v) => _bag.select(
                          _bag.selectable.map((i) => (i['id'] as num).toInt()),
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
                  onPressed: () => setState(() {
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
                  onChanged: _bag.busy || _opening
                      ? null
                      : (v) => _bag.select(
                          group.map((i) => (i['id'] as num).toInt()),
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
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('Shopping Bag'),
        actions: [
          IconButton(
            tooltip: 'Refresh Bag',
            onPressed: _bag.busy || _opening ? null : _bag.load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
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
                              padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                              child: _summary(),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: content),
                          if (_bag.items.isNotEmpty &&
                              MediaQuery.viewInsetsOf(context).bottom == 0)
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
    ),
  );
}

class _BagQuantityDialog extends StatefulWidget {
  const _BagQuantityDialog({required this.item, required this.maximum});
  final Map<String, dynamic> item;
  final int maximum;
  @override
  State<_BagQuantityDialog> createState() => _BagQuantityDialogState();
}

class _BagQuantityDialogState extends State<_BagQuantityDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _field;
  @override
  void initState() {
    super.initState();
    _field = TextEditingController(text: '${widget.item['quantity']}');
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Update quantity'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              mapOf(widget.item['product'])['name']?.toString() ?? 'Bag item',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _field,
              autofocus: true,
              maxLength: 2,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Quantity',
                helperText: 'Up to ${widget.maximum} available',
                counterText: '',
              ),
              validator: (value) =>
                  RegExp(r'^[1-9][0-9]?$').hasMatch(value ?? '') &&
                      int.parse(value!) <= widget.maximum
                  ? null
                  : 'Choose 1 to ${widget.maximum} units.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, int.parse(_field.text));
          }
        },
        child: const Text('Update'),
      ),
    ],
  );
}
