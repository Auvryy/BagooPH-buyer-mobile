import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_actions.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../home/product_card.dart';
import '../products/product_page.dart';
import '../products/product_widgets.dart';
import 'checkout_page.dart';

class BagPage extends StatefulWidget {
  const BagPage({
    super.key,
    required this.repository,
    this.voucherCode,
    this.initialSelection = const [],
    this.active = true,
  });
  final BuyerRepository repository;
  final String? voucherCode;
  final List<int> initialSelection;
  final bool active;
  @override
  State<BagPage> createState() => _BagPageState();
}

class _BagPageState extends State<BagPage> {
  WebPage? _page;
  final _selected = <int>{};
  bool _busy = false;
  bool _refreshOnIdle = false;
  String? _error;
  List<Map<String, dynamic>> get _items => mapsOf(_page?.props['items']);
  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialSelection);
    _load();
  }

  @override
  void didUpdateWidget(BagPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      if (_busy) {
        _refreshOnIdle = true;
      } else {
        _load();
      }
    }
  }

  void _idle() {
    if (!mounted) return;
    setState(() => _busy = false);
    if (_refreshOnIdle && widget.active) {
      _refreshOnIdle = false;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.repository.bag();
      if (mounted) {
        setState(() {
          _page = page;
          _selected.removeWhere(
            (id) => !_items.any(
              (i) => i['id'] == id && i['available_for_purchase'] != false,
            ),
          );
        });
      }
    } on BackendException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) {
        _idle();
      }
    }
  }

  Future<void> _change(int id, int? quantity) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.repository.changeBagItem(id, quantity);
      if (mounted) {
        setState(() {
          _page = page;
          if (quantity == null) {
            _selected.remove(id);
          }
        });
      }
    } on BackendException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.fields.isEmpty
              ? e.message
              : e.fields.values.join('\n'),
        );
      }
    } finally {
      if (mounted) {
        _idle();
      }
    }
  }

  Future<void> _checkout() async {
    if (_page?.user == null) {
      BuyerActions.login(context);
      return;
    }
    if (_busy || _selected.isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.repository.checkout(_selected.toList());
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CheckoutPage(
            repository: widget.repository,
            initial: page,
            voucherCode: widget.voucherCode,
          ),
        ),
      );
      if (mounted) {
        await _load();
      }
    } on BackendException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) {
        _idle();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Shopping Bag'),
      actions: [
        IconButton(
          tooltip: 'Refresh Bag',
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) ...[
                Notice(_error!, error: true),
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('Refresh Bag'),
                ),
              ],
              if (_page != null && _items.isEmpty)
                const ProductPanel(
                  child: Column(
                    children: [
                      Icon(
                        Icons.shopping_bag_outlined,
                        size: 48,
                        color: BagooTheme.crimson,
                      ),
                      SizedBox(height: 16),
                      ProductHeading('Your Bag is empty'),
                      Text('Discover a product and add it to your Bag.'),
                    ],
                  ),
                ),
              if (_items.isNotEmpty)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Select available items'),
                  value:
                      _selected.length ==
                          _items
                              .where(
                                (i) => i['available_for_purchase'] != false,
                              )
                              .length &&
                      _selected.isNotEmpty,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _selected.clear();
                          if (v == true) {
                            _selected.addAll(
                              _items
                                  .where(
                                    (i) => i['available_for_purchase'] != false,
                                  )
                                  .map((i) => (i['id'] as num).toInt()),
                            );
                          }
                        }),
                ),
              for (final item in _items)
                ProductPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          mapOf(item['product'])['name']?.toString() ??
                              'Unavailable product',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        value: _selected.contains(item['id']),
                        onChanged:
                            _busy || item['available_for_purchase'] == false
                            ? null
                            : (v) => setState(() {
                                if (v == true) {
                                  _selected.add((item['id'] as num).toInt());
                                } else {
                                  _selected.remove(item['id']);
                                }
                              }),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox.square(
                            dimension: 80,
                            child: RemoteImage(
                              uri: imageUri(
                                widget.repository.session,
                                mapOf(item['product'])['featured_image'],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mapOf(
                                        mapOf(item['product'])['shop'],
                                      )['name']?.toString() ??
                                      '',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: BagooTheme.muted,
                                  ),
                                ),
                                Text(
                                  [
                                    item['color'],
                                    item['size'],
                                  ].whereType<String>().join(' · '),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  pesos(item['unit_price']),
                                  style: const TextStyle(
                                    color: BagooTheme.strong,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (item['available_for_purchase'] == false)
                                  Text(
                                    item['unavailable_reason']?.toString() ??
                                        'This item is unavailable.',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFBE123C),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
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
                                _busy ||
                                    (item['quantity'] as num) <= 1 ||
                                    item['available_for_purchase'] == false
                                ? null
                                : () => _change(
                                    (item['id'] as num).toInt(),
                                    (item['quantity'] as num).toInt() - 1,
                                  ),
                            icon: const Icon(Icons.remove),
                          ),
                          Text('Quantity ${item['quantity']}'),
                          IconButton(
                            tooltip: 'Increase Bag quantity',
                            onPressed:
                                _busy ||
                                    (item['quantity'] as num) >= 99 ||
                                    item['available_for_purchase'] == false
                                ? null
                                : () => _change(
                                    (item['id'] as num).toInt(),
                                    (item['quantity'] as num).toInt() + 1,
                                  ),
                            icon: const Icon(Icons.add),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _change(
                                    (item['id'] as num).toInt(),
                                    null,
                                  ),
                            child: const Text('Remove'),
                          ),
                          if (mapOf(item['product'])['slug'] != null)
                            TextButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ProductPage(
                                    repository: widget.repository,
                                    slug: mapOf(
                                      item['product'],
                                    )['slug'].toString(),
                                  ),
                                ),
                              ),
                              child: const Text('View product'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              const Text(
                'Final prices, delivery fees, and discounts are confirmed in checkout.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: BagooTheme.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _busy || _selected.isEmpty ? null : _checkout,
          child: Text('Checkout (${_selected.length})'),
        ),
      ),
    ),
  );
}
