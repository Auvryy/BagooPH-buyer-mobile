import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../products/product_model.dart';
import '../products/product_widgets.dart';
import 'location_picker.dart';
import 'order_result_page.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({
    super.key,
    required this.repository,
    required this.initial,
    this.voucherCode,
  });
  final BuyerRepository repository;
  final WebPage initial;
  final String? voucherCode;
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _form = GlobalKey<FormState>();
  final _summary = GlobalKey();
  final _fields = {
    for (final k in [
      'recipient_name',
      'recipient_phone',
      'shipping_address',
      'shipping_postal_code',
      'landmark',
      'notes',
      'voucher_code',
    ])
      k: TextEditingController(),
  };
  late WebPage _page;
  Map<String, dynamic> _quote = {};
  List<Map<String, dynamic>> _offers = [];
  Map<String, String> _location = {
    'region': '',
    'province': '',
    'city': '',
    'barangay': '',
  };
  Map<String, String> _fieldErrors = {};
  Map<String, dynamic>? _submittedPayload;
  String _delivery = 'doorstep';
  String _payment = 'cod';
  String _address = 'new';
  String? _hub;
  int? _platformVoucher;
  final _shopVouchers = <String, int>{};
  bool _saveAddress = false;
  bool _quoting = false;
  bool _ready = false;
  bool _submitting = false;
  bool _locationLoading = true;
  String? _error;
  int _generation = 0;
  Timer? _debounce;
  List<Map<String, dynamic>> get _items => mapsOf(_page.props['items']);
  List<Map<String, dynamic>> get _addresses => mapsOf(_page.props['addresses']);
  List<int> get _ids => _items.map((i) => (i['id'] as num).toInt()).toList();
  bool get _frozen => _submittedPayload != null;
  @override
  void initState() {
    super.initState();
    _page = widget.initial;
    _quote = mapOf(_page.props['quote']);
    _offers = mapsOf(_page.props['availableVouchers']);
    _fields['voucher_code']!.text = widget.voucherCode ?? '';
    final address =
        _addresses
            .where((a) => a['id'] == _page.props['defaultAddressId'])
            .firstOrNull ??
        _addresses.where((a) => a['is_default'] == true).firstOrNull ??
        _addresses.firstOrNull;
    _applyAddress(address, notify: false);
    _updateQuote();
  }

  Map<String, dynamic> get _values => {
    'checkout_token': _page.props['checkoutToken'],
    'item_ids': _ids,
    'item_quantities': _page.props['itemQuantities'] ?? <String, dynamic>{},
    for (final f in _fields.entries)
      f.key: f.key == 'voucher_code'
          ? f.value.text.trim().toUpperCase()
          : f.value.text.trim(),
    'shipping_city': _location['city'],
    'shipping_province': _location['province'],
    'destination_barangay': _location['barangay'],
    'delivery_type': _delivery,
    'pickup_hub_id': _delivery == 'hub_self_pickup'
        ? int.tryParse(_hub ?? '')
        : null,
    'payment_method': _payment,
    'save_address': _saveAddress,
    'platform_voucher_revision_id': _platformVoucher,
    'shop_voucher_revision_ids': Map.of(_shopVouchers),
  };
  Map<String, dynamic> get _quoteInput => {
    'item_ids': _ids,
    'item_quantities': _page.props['itemQuantities'] ?? <String, dynamic>{},
    'delivery_type': _delivery,
    'pickup_hub_id': _delivery == 'hub_self_pickup'
        ? int.tryParse(_hub ?? '')
        : null,
    'shipping_city': _location['city'],
    'shipping_province': _location['province'],
    'code': _fields['voucher_code']!.text.trim().toUpperCase(),
    'platform_voucher_revision_id': _platformVoucher,
    'shop_voucher_revision_ids': Map.of(_shopVouchers),
  };
  void _applyAddress(Map<String, dynamic>? address, {bool notify = true}) {
    final user = mapOf(_page.props['user']);
    _address = address?['id']?.toString() ?? 'new';
    _fields['recipient_name']!.text =
        address?['recipient_name']?.toString() ??
        user['name']?.toString() ??
        '';
    _fields['recipient_phone']!.text =
        address?['phone']?.toString() ?? user['phone']?.toString() ?? '';
    _fields['shipping_address']!.text =
        address?['street']?.toString() ?? user['address']?.toString() ?? '';
    _fields['shipping_postal_code']!.text =
        address?['postal_code']?.toString() ??
        user['postal_code']?.toString() ??
        '';
    _fields['landmark']!.text = address?['landmark']?.toString() ?? '';
    _location = {
      for (final k in ['region', 'province', 'city', 'barangay'])
        k: address?[k]?.toString() ?? user[k]?.toString() ?? '',
    };
    _saveAddress = false;
    if (notify) {
      setState(() {});
      _edit();
    }
  }

  void _edit() {
    if (_frozen) {
      return;
    }
    _generation++;
    setState(() {
      _ready = false;
      _fieldErrors = {};
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _updateQuote);
  }

  Future<bool> _updateQuote() async {
    if (_frozen) {
      return _ready;
    }
    final generation = ++_generation;
    final body = _quoteInput;
    setState(() {
      _quoting = true;
      _ready = false;
      _error = null;
    });
    try {
      final data = await widget.repository.quote(body);
      if (!mounted || generation != _generation) {
        return false;
      }
      final quote = mapOf(data['quote']);
      if (data['success'] != true ||
          data['validSelection'] == false ||
          quote['items'] is! List ||
          quote['shops'] is! List ||
          ![
            'subtotal',
            'shipping_fee',
            'discount',
            'shipping_discount',
            'total',
          ].every((k) => amount(quote[k]) != null && amount(quote[k])! >= 0)) {
        throw const BackendException(
          'The checkout total could not be confirmed.',
        );
      }
      final errors = mapOf(data['selectionErrors']);
      if (errors.isNotEmpty) {
        throw BackendException(errors.values.join('\n'));
      }
      setState(() {
        _quote = quote;
        _offers = mapsOf(data['availableVouchers']);
        _ready = true;
      });
      return true;
    } on BackendException catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = e.fields.isEmpty ? e.message : e.fields.values.join('\n');
          _ready = false;
        });
      }
      return false;
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _quoting = false);
      }
    }
  }

  Future<void> _reload() async {
    if (_submitting) {
      return;
    }
    _submittedPayload = null;
    setState(() {
      _ready = false;
      _error = null;
      _quoting = true;
    });
    try {
      final quantities = mapOf(_page.props['itemQuantities']);
      final quantity = quantities.length == 1 ? quantities.values.first : null;
      final fresh = await widget.repository.document(
        '/checkout?items=${_ids.join(',')}${quantity == null ? '' : '&quantity=$quantity'}',
      );
      widget.repository.requireNoErrors(fresh);
      if (fresh.component != 'Checkout/Index') {
        throw const BackendException(
          'Checkout is no longer available. Check your Bag and orders.',
        );
      }
      if (mounted) {
        setState(() => _page = fresh);
        await _updateQuote();
      }
    } on BackendException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _quoting = false);
      }
    }
  }

  Future<void> _review() async {
    if (_submitting || _quoting) {
      return;
    }
    if (!_frozen) {
      if (!_form.currentState!.validate() || _locationLoading) {
        setState(
          () => _error = 'Complete the recipient and address fields, and wait for location choices.',
        );
        return;
      }
      _debounce?.cancel();
      if (!await _updateQuote() || !mounted) {
        return;
      }
    }
    final payload =
        _submittedPayload ??
        jsonDecode(jsonEncode(_values)) as Map<String, dynamic>;
    bool agreed = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Confirm your order'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${payload['recipient_name']} · ${payload['recipient_phone']}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    [
                      payload['shipping_address'],
                      payload['destination_barangay'],
                      payload['shipping_city'],
                      payload['shipping_province'],
                      payload['shipping_postal_code'],
                    ].join(', '),
                  ),
                  const SizedBox(height: 16),
                  for (final item in _items)
                    Text(
                      '${mapOf(item['product'])['name']} × ${mapOf(payload['item_quantities'])[item['id'].toString()] ?? item['quantity']}',
                    ),
                  const SizedBox(height: 12),
                  Text(
                    payload['delivery_type'] == 'hub_self_pickup'
                        ? 'Self-pickup: ${mapsOf(_page.props['pickupHubs']).where((h) => h['id'] == payload['pickup_hub_id']).firstOrNull?['name'] ?? 'Selected Bayan Hub'}'
                        : 'Doorstep delivery',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Total: ${pesos(_quote['total'])}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: BagooTheme.strong,
                    ),
                  ),
                  Text(
                    payload['payment_method'] == 'wallet'
                        ? 'Bagoo Wallet · virtual credits. Confirm payment after placing the order.'
                        : 'Cash on Delivery. Pay the assigned rider or counter when receiving your parcel.',
                    style: const TextStyle(height: 1.6),
                  ),
                  CheckboxListTile(
                    value: agreed,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) => update(() => agreed = v ?? false),
                    title: const Text(
                      'I reviewed the recipient, selected items, delivery method, payment method, and total.',
                      style: TextStyle(fontSize: 13, height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: agreed ? () => Navigator.pop(context, true) : null,
              child: Text(_frozen ? 'Retry same order' : 'Place order'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted || _submitting) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _submittedPayload = payload;
      _error = null;
    });
    try {
      final page = await widget.repository.placeOrder(payload);
      if (!mounted) {
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              OrderResultPage(repository: widget.repository, initial: page),
        ),
      );
    } on BackendException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.fields.isEmpty ? e.message : e.fields.values.join('\n');
        _fieldErrors = e.fields;
        if (e.status == 422 || e.fields.isNotEmpty) {
          _submittedPayload = null;
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_summary.currentContext != null) {
          Scrollable.ensureVisible(_summary.currentContext!);
        }
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Widget _field(
    String key,
    String label, {
    bool required = true,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: _fields[key],
      keyboardType: keyboard,
      enabled: !_submitting && !_frozen,
      onChanged: (_) => _edit(),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        errorText: _fieldErrors[key],
        errorMaxLines: 4,
      ),
      validator: (v) => required && (v?.trim().isEmpty ?? true)
          ? 'Enter ${label.toLowerCase()}.'
          : key == 'shipping_postal_code' &&
                !RegExp(r'^\d{4}$').hasMatch(v ?? '')
          ? 'Enter a four-digit postal code.'
          : null,
    ),
  );
  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 950),
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AbsorbPointer(
                    absorbing: _submitting || _frozen,
                    child: Column(
                      children: [
                        ProductPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const ProductHeading('Delivery method'),
                              DropdownButtonFormField<String>(
                                initialValue: _delivery,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Delivery method',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'doorstep',
                                    child: Text('Doorstep delivery'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'hub_self_pickup',
                                    child: Text('Self-pickup at Bayan Hub'),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => _delivery = v);
                                    _edit();
                                  }
                                },
                              ),
                              if (_delivery == 'hub_self_pickup') ...[
                                const SizedBox(height: 16),
                                DropdownButtonFormField<String>(
                                  initialValue: _hub,
                                  isExpanded: true,
                                  itemHeight: null,
                                  decoration: const InputDecoration(
                                    labelText: 'Pickup Bayan Hub',
                                  ),
                                  items: mapsOf(_page.props['pickupHubs'])
                                      .map(
                                        (h) => DropdownMenuItem(
                                          value: h['id'].toString(),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            child: Text(
                                              '${h['name']} · ${h['city_municipality']}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) {
                                    setState(() => _hub = v);
                                    _edit();
                                  },
                                  validator: (v) =>
                                      _delivery == 'hub_self_pickup' &&
                                          v == null
                                      ? 'Choose a pickup Bayan Hub.'
                                      : null,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Your parcel follows the hub network. Order tracking will show when collection is ready.',
                                  style: TextStyle(fontSize: 12, height: 1.6),
                                ),
                              ],
                            ],
                          ),
                        ),
                        ProductPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const ProductHeading(
                                'Recipient and delivery address',
                              ),
                              if (_addresses.isNotEmpty) ...[
                                DropdownButtonFormField<String>(
                                  key: ValueKey('address-choice-$_address'),
                                  initialValue: _address,
                                  isExpanded: true,
                                  itemHeight: null,
                                  decoration: const InputDecoration(
                                    labelText: 'Saved address',
                                  ),
                                  items: [
                                    const DropdownMenuItem(
                                      value: 'new',
                                      child: Text('Use a new address'),
                                    ),
                                    for (final a in _addresses)
                                      DropdownMenuItem(
                                        value: a['id'].toString(),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Text(
                                            '${a['recipient_name']} · ${a['street']}, ${a['city']}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                  onChanged: (v) => _applyAddress(
                                    _addresses
                                        .where((a) => a['id'].toString() == v)
                                        .firstOrNull,
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],
                              _field('recipient_name', 'Recipient name'),
                              _field(
                                'recipient_phone',
                                'Philippine mobile number',
                                keyboard: TextInputType.phone,
                              ),
                              LocationPicker(
                                key: ValueKey('address-location-$_address'),
                                repository: widget.repository,
                                initial: _location,
                                disabled: _submitting || _frozen,
                                onLoading: (v) {
                                  if (mounted) {
                                    setState(() => _locationLoading = v);
                                  }
                                },
                                onChanged: (value) {
                                  if (!mounted) {
                                    return;
                                  }
                                  final changed =
                                      jsonEncode(_location) !=
                                      jsonEncode(value);
                                  setState(() => _location = value);
                                  if (changed) {
                                    _edit();
                                  }
                                },
                              ),
                              _field(
                                'shipping_address',
                                'Street / house / unit',
                              ),
                              _field(
                                'shipping_postal_code',
                                'Postal code',
                                keyboard: TextInputType.number,
                              ),
                              _field(
                                'landmark',
                                'Landmark (optional)',
                                required: false,
                              ),
                              _field(
                                'notes',
                                'Delivery notes (optional)',
                                required: false,
                              ),
                              if (_address == 'new')
                                CheckboxListTile(
                                  value: _saveAddress,
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  onChanged:
                                      _addresses.length >=
                                          ((_page.props['addressBookLimit']
                                                      as num?)
                                                  ?.toInt() ??
                                              10)
                                      ? null
                                      : (v) {
                                          setState(
                                            () => _saveAddress = v ?? false,
                                          );
                                          _edit();
                                        },
                                  title: const Text(
                                    'Save this address for future orders',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        ProductPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const ProductHeading('Order summary'),
                              for (final item in _items)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        mapOf(
                                              item['product'],
                                            )['name']?.toString() ??
                                            'Product',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        [
                                          item['color'],
                                          item['size'],
                                        ].whereType<String>().join(' · '),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      for (final segment in mapsOf(
                                        (mapsOf(_quote['items'])
                                                .where(
                                                  (q) => q['id'] == item['id'],
                                                )
                                                .firstOrNull ??
                                            {})['price_segments'],
                                      ))
                                        Text(
                                          _ready
                                              ? '${segment['quantity']} × ${pesos(segment['unit_price'])} = ${pesos(segment['subtotal'])}'
                                              : 'Updating price…',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                    ],
                                  ),
                                ),
                              const Divider(height: 24),
                              _field(
                                'voucher_code',
                                'Voucher code (optional)',
                                required: false,
                              ),
                              if (_platformVoucher != null ||
                                  _shopVouchers.isNotEmpty)
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _platformVoucher = null;
                                      _shopVouchers.clear();
                                    });
                                    _edit();
                                  },
                                  child: const Text('Clear selected vouchers'),
                                ),
                              for (final o in _offers)
                                OfferTile(
                                  offer: o,
                                  repository: widget.repository,
                                  onUse: () {
                                    final id = (o['revision_id'] as num?)
                                        ?.toInt();
                                    if (id == null) {
                                      return;
                                    }
                                    setState(() {
                                      _fields['voucher_code']!.clear();
                                      if (o['issuer'] == 'platform') {
                                        _platformVoucher = id;
                                      } else if (o['shop_id'] != null) {
                                        _shopVouchers[o['shop_id'].toString()] =
                                            id;
                                      }
                                    });
                                    _edit();
                                  },
                                ),
                              const ProductHeading('Payment method'),
                              DropdownButtonFormField<String>(
                                initialValue: _payment,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Pay with',
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: 'cod',
                                    child: Text('Cash on Delivery'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'wallet',
                                    enabled:
                                        _page.props['walletBalanceCents'] !=
                                        null,
                                    child: const Text(
                                      'Bagoo Wallet · virtual credits',
                                    ),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => _payment = v);
                                  }
                                },
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _payment == 'wallet'
                                    ? 'Available virtual credits: ${_page.props['walletBalanceCents'] == null ? 'Unavailable' : pesos((amount(_page.props['walletBalanceCents']) ?? 0) / 100)}. Review and confirm wallet payment after placing the order. Unpaid wallet orders expire after one hour.'
                                    : 'Pay the assigned rider or pickup counter when receiving your parcel.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: BagooTheme.muted,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ProductPanel(
                    key: _summary,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Notice(_error!, error: true),
                          ),
                        if (_fieldErrors.containsKey('checkout_token'))
                          TextButton(
                            onPressed: _reload,
                            child: const Text(
                              'Reload checkout and review updated prices',
                            ),
                          ),
                        if (_frozen && !_submitting)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: Notice(
                              'The previous result was not confirmed. Your exact checkout details are retained for a safe retry. Check your orders before starting a different checkout.',
                              error: true,
                            ),
                          ),
                        if (_quoting) const LinearProgressIndicator(),
                        for (final row in {
                          'Subtotal': _quote['subtotal'],
                          'Delivery': _quote['shipping_fee'],
                          'Product discount': _quote['discount'],
                          'Shipping discount': _quote['shipping_discount'],
                          'Total': _quote['total'],
                        }.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: 16,
                              children: [
                                Text(
                                  row.key,
                                  style: TextStyle(
                                    fontWeight: row.key == 'Total'
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  _ready ? pesos(row.value) : 'Updating…',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: row.key == 'Total'
                                        ? BagooTheme.strong
                                        : BagooTheme.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        for (final shop in mapsOf(_quote['shops']))
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _ready
                                  ? '${shop['shop_name']}: ${pesos(shop['total'])}'
                                  : 'Updating shop total…',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        const SizedBox(height: 20),
                        SubmitButton(
                          label: _submitting
                              ? 'Placing order…'
                              : _frozen
                              ? 'Review safe retry'
                              : 'Review order',
                          busy: _submitting,
                          onPressed:
                              _quoting ||
                                  (!_ready && !_frozen) ||
                                  _locationLoading
                              ? null
                              : _review,
                        ),
                        if (!_ready && !_quoting && !_frozen)
                          TextButton(
                            onPressed: _updateQuote,
                            child: const Text('Retry checkout quote'),
                          ),
                        if (_frozen)
                          TextButton(
                            onPressed: _submitting
                                ? null
                                : () async {
                                    try {
                                      final page = await widget.repository
                                          .document('/buyer/orders');
                                      if (context.mounted) {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => OrderResultPage(
                                              repository: widget.repository,
                                              initial: page,
                                            ),
                                          ),
                                        );
                                      }
                                    } on BackendException catch (e) {
                                      if (mounted) {
                                        setState(() => _error = e.message);
                                      }
                                    }
                                  },
                            child: const Text('Check my orders'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
