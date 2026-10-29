import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/contact_input.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../../core/device_actions.dart';
import '../products/product_widgets.dart';
import 'location_picker.dart';
import 'order_result_page.dart';
import '../home/product_card.dart';
import 'checkout_widgets.dart';
import 'purchase_quote.dart';
import 'voucher_selection.dart';
import 'voucher_picker.dart';
import 'commerce_details.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({
    super.key,
    required this.repository,
    required this.initial,
    this.voucherCode,
    this.captureLocation = captureBuyerLocation,
  });
  final BuyerRepository repository;
  final WebPage initial;
  final String? voucherCode;
  final Future<BuyerLocation> Function() captureLocation;
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _form = GlobalKey<FormState>();
  final _summary = GlobalKey();
  final _contentKey = GlobalKey();
  final _fieldKeys = <String, GlobalKey<FormFieldState<String>>>{};
  final _fieldFocus = <String, FocusNode>{};
  bool _choosingBest = false;
  bool _voucherProblem = false;
  String? _voucherFeedback;
  final _fields = {
    for (final k in [
      'recipient_name',
      'recipient_phone',
      'shipping_address',
      'shipping_postal_code',
      'landmark',
      'notes',
      'voucher_code',
      'shipping_latitude',
      'shipping_longitude',
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
  int? _company;
  bool _hasCompanyContract = false;
  List<Map<String, dynamic>> _companies = [];
  bool _locating = false;
  String? _locationFeedback;
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
    _hasCompanyContract = _page.props.containsKey('logisticsCompanies');
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
    try {
      _readCompanies(_page.props);
    } on BackendException catch (e) {
      _error = e.message;
    }
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
    if (_hasCompanyContract) 'logistics_company_id': _company,
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
    'shipping_postal_code': _fields['shipping_postal_code']!.text.trim(),
    'destination_barangay': _location['barangay'],
    if (_hasCompanyContract) 'logistics_company_id': _company,
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
    _fields['shipping_latitude']!.text = address?['latitude']?.toString() ?? '';
    _fields['shipping_longitude']!.text =
        address?['longitude']?.toString() ?? '';
    _locationFeedback = null;
    _hub = null;
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

  void _readCompanies(Map<String, dynamic> data) {
    final raw = data['logisticsCompanies'];
    if (raw == null) return;
    final rows = mapsOf(raw);
    if (raw is! List ||
        rows.length != raw.length ||
        rows.any(
          (row) =>
              row['id'] is! num ||
              !(row['id'] as num).isFinite ||
              row['id'] <= 0 ||
              row['id'] != (row['id'] as num).toInt() ||
              row['name'] is! String ||
              (row['name'] as String).trim().isEmpty,
        ) ||
        rows.map((row) => row['id']).toSet().length != rows.length) {
      throw const BackendException(
        'Delivery choices could not be confirmed. Refresh checkout.',
      );
    }
    _companies = rows;
    _hasCompanyContract = true;
    if (_fields['shipping_postal_code']!.text.trim().length == 4 &&
        !_companies.any((row) => row['id'] == _company)) {
      _company = null;
      _hub = null;
    }
    if (_company == null && _companies.length == 1) {
      _company = (_companies.single['id'] as num).toInt();
    }
  }

  String get _locationDraft => jsonEncode([
    _fields['shipping_address']!.text,
    _location,
    _fields['shipping_latitude']!.text,
    _fields['shipping_longitude']!.text,
  ]);

  Future<void> _captureLocation() async {
    if (_locating || _frozen || _submitting) return;
    final address = _locationDraft;
    setState(() {
      _locating = true;
      _locationFeedback = null;
    });
    try {
      final position = await widget.captureLocation();
      if (!mounted || _frozen || address != _locationDraft) {
        return;
      }
      setState(() {
        _fields['shipping_latitude']!.text = position.latitude.toStringAsFixed(
          6,
        );
        _fields['shipping_longitude']!.text = position.longitude
            .toStringAsFixed(6);
        _locationFeedback =
            'Location pinned. Reported accuracy: ${position.accuracy.round()} m. Check that this is the recipient’s location.';
      });
      _edit();
    } on BackendException catch (e) {
      if (mounted) setState(() => _locationFeedback = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _locationFeedback =
              'Location is unavailable. You can enter coordinates manually.',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  VoucherSelection get _vouchers => VoucherSelection(
    code: _fields['voucher_code']!.text.trim().toUpperCase(),
    platform: _platformVoucher,
    shops: Map.of(_shopVouchers),
  );
  List<Map<String, dynamic>> get _applied => !_ready
      ? []
      : _quote['vouchers'] is List
      ? mapsOf(_quote['vouchers'])
      : _quote['voucher'] is Map
      ? [mapOf(_quote['voucher'])]
      : [];
  void _setVouchers(VoucherSelection value) {
    _fields['voucher_code']!.text = value.code;
    _platformVoucher = value.platform;
    _shopVouchers
      ..clear()
      ..addAll(value.shops);
  }

  Future<bool> _updateQuote({bool repair = true}) async {
    if (_frozen) return _ready;
    final generation = ++_generation;
    final body = _quoteInput;
    setState(() {
      _quoting = true;
      _ready = false;
      _error = null;
    });
    try {
      Map<String, dynamic> data;
      try {
        data = await widget.repository.quote(body);
      } on BackendException catch (e) {
        if (mounted && generation == _generation) {
          setState(() => _readCompanies(e.data));
        }
        if (e.status != 422 ||
            e.data['quote'] is! Map ||
            e.data['validSelection'] is! Map) {
          rethrow;
        }
        data = e.data;
      }
      if (!mounted || generation != _generation) return false;
      setState(() => _readCompanies(data));
      final quote = checkedPurchaseQuote(data['quote'], itemIds: _ids);
      final errors = mapOf(data['selectionErrors']);
      if (data['validSelection'] is Map) {
        final valid = VoucherSelection.checked(data['validSelection']);
        if (jsonEncode(_vouchers.values) != jsonEncode(valid.values)) {
          setState(() {
            _setVouchers(valid);
            if (errors.isNotEmpty) {
              _voucherProblem = true;
              _voucherFeedback =
                  '${errors.values.join(' ')} Your other voucher choices are retained.';
            }
          });
          if (repair) return await _updateQuote(repair: false);
          throw const BackendException(
            'Vouchers changed again. Review your choices and refresh the quote.',
          );
        }
      }
      if (data['success'] != true ||
          errors.isNotEmpty ||
          quote['voucher_error'] != null) {
        throw BackendException(
          errors.isNotEmpty
              ? errors.values.join(' ')
              : quote['voucher_error']?.toString() ??
                    'The checkout total could not be confirmed.',
        );
      }
      setState(() {
        _quote = quote;
        _offers = mapsOf(data['availableVouchers']);
        _ready = !_hasCompanyContract || _company != null;
        if (!_ready) {
          _error =
              'Choose a serving logistics company before reviewing this order.';
        }
      });
      return _ready;
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

  Future<void> _pickVoucher({int? shopId, required String title}) async {
    final requested = jsonEncode(_quoteInput);
    final current = shopId == null
        ? _platformVoucher
        : _shopVouchers['$shopId'];
    final selected = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => VoucherPickerPage(
          repository: widget.repository,
          values: _quoteInput,
          title: title,
          shopId: shopId,
          selectedRevision: current,
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (requested != jsonEncode(_quoteInput) || _frozen || _submitting) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Checkout changed. Choose a voucher again for the current selection.',
          ),
        ),
      );
      return;
    }
    final next = selected['remove'] == true
        ? _vouchers.remove(shopId?.toString(), _applied)
        : _vouchers.choose(selected, _applied);
    setState(() {
      _setVouchers(next);
      _voucherFeedback = null;
      _voucherProblem = false;
    });
    _edit();
  }

  Future<void> _bestVouchers() async {
    if (_choosingBest || !_ready || _frozen || _submitting) return;
    final requested = jsonEncode(_quoteInput);
    setState(() {
      _choosingBest = true;
      _voucherFeedback = null;
      _voucherProblem = false;
    });
    try {
      final result = await widget.repository.bestVouchers(_quoteInput);
      if (!mounted) return;
      if (requested != jsonEncode(_quoteInput) || _frozen) {
        setState(() {
          _voucherProblem = true;
          _voucherFeedback = 'Checkout changed. Compare vouchers again for the updated items and delivery.';
        });
        return;
      }
      checkedPurchaseQuote(result['quote'], itemIds: _ids);
      final next = VoucherSelection.checked(result['selection']);
      setState(() {
        _setVouchers(next);
        _voucherFeedback = 'The best available voucher combination is selected. Review the updated total.';
      });
      _edit();
    } on BackendException catch (e) {
      if (mounted && requested == jsonEncode(_quoteInput)) {
        setState(() {
          _voucherProblem = true;
          _voucherFeedback = e.message;
        });
      }
    } finally {
      if (mounted) setState(() => _choosingBest = false);
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
        setState(() {
          _page = fresh;
          _hasCompanyContract = fresh.props.containsKey('logisticsCompanies');
          _readCompanies(fresh.props);
        });
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
    if (_submitting || _quoting || _choosingBest) {
      return;
    }
    if (!_frozen) {
      if (!_form.currentState!.validate() || _locationLoading) {
        setState(
          () => _error = 'Complete the recipient and address fields, and wait for location choices.',
        );
        final invalid = _fieldKeys.entries
            .where((entry) => entry.value.currentState?.hasError == true)
            .firstOrNull;
        if (invalid != null && invalid.value.currentContext != null) {
          _fieldFocus[invalid.key]?.requestFocus();
          Scrollable.ensureVisible(
            invalid.value.currentContext!,
            alignment: .15,
          );
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Check the highlighted delivery and recipient fields.',
            ),
          ),
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
                  for (final item in _items) ...[
                    Text(
                      '${mapOf(item['product'])['name']} × ${mapOf(payload['item_quantities'])[item['id'].toString()] ?? item['quantity']}',
                    ),
                    PriceSegments(
                      segments: mapsOf(
                        mapsOf(_quote['items'])
                            .where((row) => row['id'] == item['id'])
                            .firstOrNull?['price_segments'],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_hasCompanyContract)
                    Text(
                      'Logistics: ${_companies.where((row) => row['id'] == payload['logistics_company_id']).firstOrNull?['name'] ?? 'Recorded company'}',
                    ),
                  const SizedBox(height: 12),
                  Text(
                    payload['delivery_type'] == 'hub_self_pickup'
                        ? 'Self-pickup: ${mapsOf(_page.props['pickupHubs']).where((h) => h['id'] == payload['pickup_hub_id']).firstOrNull?['name'] ?? 'Selected Bayan Hub'}'
                        : 'Doorstep delivery',
                  ),
                  const SizedBox(height: 12),
                  CheckoutDiscounts(quote: _quote),
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
      key: _fieldKeys.putIfAbsent(
        key,
        () => GlobalKey<FormFieldState<String>>(),
      ),
      focusNode: _fieldFocus.putIfAbsent(key, FocusNode.new),
      controller: _fields[key],
      keyboardType: keyboard,
      inputFormatters: keyboard == TextInputType.phone
          ? [mobileNumberFormatter]
          : null,
      enabled: !_submitting && !_frozen,
      onChanged: (_) {
        if (key == 'voucher_code') _voucherFeedback = null;
        if (key == 'shipping_address') {
          _fields['shipping_latitude']!.clear();
          _fields['shipping_longitude']!.clear();
          _locationFeedback = null;
        }
        _edit();
      },
      maxLength: {
        'recipient_name': 100,
        'shipping_address': 500,
        'landmark': 255,
        'notes': 500,
        'voucher_code': 50,
      }[key],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        errorText: _fieldErrors[key],
        errorMaxLines: 4,
        counterText: '',
      ),
      validator: (v) {
        final value = v?.trim() ?? '';
        if (key == 'shipping_latitude' || key == 'shipping_longitude') {
          final other =
              _fields[key == 'shipping_latitude'
                      ? 'shipping_longitude'
                      : 'shipping_latitude']!
                  .text
                  .trim();
          if (value.isEmpty && other.isNotEmpty) {
            return 'Enter both coordinates or clear both.';
          }
          if (value.isEmpty) return null;
          final coordinate = double.tryParse(value);
          final limit = key == 'shipping_latitude' ? 90 : 180;
          if (!RegExp(r'^-?[0-9]{1,3}(\.[0-9]{1,6})?$').hasMatch(value) ||
              coordinate == null ||
              !coordinate.isFinite ||
              coordinate.abs() > limit) {
            return 'Use a coordinate from -$limit to $limit, up to six decimal places.';
          }
          return null;
        }
        if (required && value.isEmpty) return 'Enter ${label.toLowerCase()}.';
        if (value.isEmpty) return null;
        final minimum =
            {'recipient_name': 2, 'shipping_address': 5, 'landmark': 5}[key] ??
            1;
        if (value.length < minimum) return 'Use at least $minimum characters.';
        if (key == 'shipping_postal_code' &&
            !RegExp(r'^[0-9]{4}$').hasMatch(value)) {
          return 'Enter a four-digit postal code.';
        }
        if (key == 'recipient_phone') {
          return mobileNumberValidator(v);
        }
        if (key == 'voucher_code' &&
            !RegExp(r'^[A-Z0-9_-]+$').hasMatch(value.toUpperCase())) {
          return 'Use letters, numbers, underscores or hyphens.';
        }
        return null;
      },
    ),
  );
  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    for (final c in _fields.values) {
      c.dispose();
    }
    for (final node in _fieldFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _reviewButton() => SubmitButton(
    label: _submitting
        ? 'Placing order…'
        : _frozen
        ? 'Review safe retry'
        : 'Review order',
    busy: _submitting,
    onPressed:
        _choosingBest ||
            _quoting ||
            (!_ready && !_frozen) ||
            _locationLoading ||
            _locating
        ? null
        : _review,
  );

  Widget _itemsPanel() => ProductPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProductHeading('Selected items (${_items.length})'),
        for (final item in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox.square(
                        dimension: 56,
                        child: RemoteImage(
                          thumbnail: true,
                          uri: imageUri(
                            widget.repository.session,
                            mapOf(item['product'])['featured_image'],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mapOf(
                                  mapOf(item['product'])['shop'],
                                )['name']?.toString() ??
                                'Shop',
                            style: const TextStyle(
                              fontSize: 12,
                              color: BagooTheme.muted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            mapOf(item['product'])['name']?.toString() ??
                                'Product',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          Text(
                            [
                              item['color'],
                              item['size'],
                            ].whereType<String>().join(' · '),
                            style: const TextStyle(fontSize: 12, height: 1.6),
                          ),
                          Text(
                            'Quantity ${mapOf(_page.props['itemQuantities'])[item['id'].toString()] ?? item['quantity']}',
                            style: const TextStyle(fontSize: 12, height: 1.6),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (!_ready)
                  const Text(
                    'Updating selected item prices…',
                    style: TextStyle(fontSize: 12),
                  )
                else
                  PriceSegments(
                    segments: mapsOf(
                      mapsOf(_quote['items'])
                          .where((row) => row['id'] == item['id'])
                          .firstOrNull?['price_segments'],
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _vouchersPanel() => ProductPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProductHeading('Vouchers & promos'),
        _field('voucher_code', 'Voucher code (optional)', required: false),
        if (_voucherFeedback != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Notice(_voucherFeedback!, error: _voucherProblem),
          ),
        if (_applied.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final offer in _applied)
                InputChip(
                  label: Text(
                    '${offer['code']} · ${offer['issuer'] == 'platform' ? 'Bagoo' : offer['shop_name'] ?? 'Shop'}',
                  ),
                  deleteButtonTooltipMessage: 'Remove ${offer['code']}',
                  onDeleted: () {
                    final next = _vouchers.remove(
                      offer['issuer'] == 'platform'
                          ? null
                          : offer['shop_id'].toString(),
                      _applied,
                    );
                    setState(() {
                      _setVouchers(next);
                      _voucherFeedback = null;
                    });
                    _edit();
                  },
                ),
            ],
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: !_ready || _choosingBest ? null : _bestVouchers,
          icon: const Icon(Icons.auto_awesome_outlined, size: 20),
          label: Text(
            _choosingBest ? 'Comparing vouchers…' : 'Use best vouchers',
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.local_offer_outlined),
          title: const Text(
            'Bagoo voucher',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            _platformVoucher == null
                ? 'Choose a platform offer'
                : 'Platform voucher selected',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right),
          enabled: _ready && !_choosingBest,
          onTap: () => _pickVoucher(title: 'Bagoo vouchers'),
        ),
        for (final shop in mapsOf(_quote['shops']))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storefront_outlined),
            title: Text(
              '${shop['shop_name']} vouchers',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              _shopVouchers[shop['shop_id'].toString()] == null
                  ? 'Choose a shop offer'
                  : 'Shop voucher selected',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            enabled: _ready && !_choosingBest,
            onTap: () => _pickVoucher(
              shopId: (shop['shop_id'] as num).toInt(),
              title: '${shop['shop_name']} vouchers',
            ),
          ),
        const SizedBox(height: 8),
        Text(
          '${_offers.length} offers in the current quote. Each shop and Bagoo can have their own voucher slot. Availability is checked again before ordering.',
          style: const TextStyle(
            fontSize: 12,
            height: 1.7,
            color: BagooTheme.muted,
          ),
        ),
      ],
    ),
  );

  Widget _paymentPanel() => ProductPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProductHeading('Payment method'),
        CheckoutChoice(
          title: 'Cash on Delivery',
          description: 'Pay the assigned rider or pickup counter when receiving your parcel.',
          icon: Icons.payments_outlined,
          selected: _payment == 'cod',
          onTap: () => setState(() => _payment = 'cod'),
        ),
        CheckoutChoice(
          title: 'Bagoo Wallet',
          description: _page.props['walletBalanceCents'] == null
              ? 'Your wallet balance is unavailable.'
              : 'Available virtual credits: ${pesos((amount(_page.props['walletBalanceCents']) ?? 0) / 100)}. Review and confirm wallet payment after placing the order. Unpaid wallet orders expire after one hour.',
          icon: Icons.account_balance_wallet_outlined,
          selected: _payment == 'wallet',
          onTap: _page.props['walletBalanceCents'] == null
              ? null
              : () => setState(() => _payment = 'wallet'),
        ),
      ],
    ),
  );

  Widget _money(
    String label,
    dynamic value, {
    bool total = false,
    bool discount = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 16,
      runSpacing: 4,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: total ? FontWeight.w800 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
        Text(
          _ready
              ? '${discount ? '-' : ''}${pesos(value)}'
              : _quoting
              ? 'Updating…'
              : 'Unavailable',
          style: TextStyle(
            fontSize: total ? 23 : 14,
            fontWeight: FontWeight.w800,
            color: total ? BagooTheme.strong : BagooTheme.ink,
          ),
        ),
      ],
    ),
  );
  Widget _summaryPanel() => ProductPanel(
    key: _summary,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProductHeading('Payment summary'),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Semantics(
              liveRegion: true,
              child: Notice(_error!, error: true),
            ),
          ),
        if (_fieldErrors.containsKey('checkout_token'))
          TextButton(
            onPressed: _submitting ? null : _reload,
            child: const Text('Reload checkout and review updated prices'),
          ),
        if (_frozen && !_submitting)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Notice(
              'The previous result was not confirmed. Your exact checkout details are retained for a safe retry. Check your orders before starting a different checkout.',
              error: true,
            ),
          ),
        if (_quoting)
          const LinearProgressIndicator(
            semanticsLabel: 'Updating checkout quote',
          ),
        _money('Subtotal', _quote['subtotal']),
        if (_ready) CheckoutDiscounts(quote: _quote),
        _money('Delivery', _quote['shipping_fee']),
        if ((amount(_quote['discount']) ?? 0) >
            (amount(_quote['shipping_discount']) ?? 0))
          _money(
            'Product discount',
            (amount(_quote['discount']) ?? 0) -
                (amount(_quote['shipping_discount']) ?? 0),
            discount: true,
          ),
        if ((amount(_quote['shipping_discount']) ?? 0) > 0)
          _money(
            'Shipping discount',
            _quote['shipping_discount'],
            discount: true,
          ),
        const Divider(height: 24),
        _money('Total', _quote['total'], total: true),
        const Text(
          'Shipping is calculated separately for each shop.',
          style: TextStyle(fontSize: 12, height: 1.7, color: BagooTheme.muted),
        ),
        if (_ready)
          for (final shop in mapsOf(_quote['shops']))
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    shop['shop_name'].toString(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  _money('Shop subtotal', shop['subtotal']),
                  ShippingCalculation(
                    calculation: mapOf(shop['shipping_quote']),
                    selfPickup: _delivery == 'hub_self_pickup',
                  ),
                  CheckoutDiscounts(quote: _quote, shopId: shop['shop_id']),
                  _money('Shop delivery', shop['shipping']),
                  if ((amount(shop['discount']) ?? 0) > 0)
                    _money('Shop savings', shop['discount'], discount: true),
                  _money('Shop total', shop['total']),
                ],
              ),
            ),
        const SizedBox(height: 20),
        _reviewButton(),
        const SizedBox(height: 12),
        const Text(
          'You will review and confirm your order before it is placed. Vouchers do not reserve discounts or stock.',
          style: TextStyle(fontSize: 12, height: 1.7, color: BagooTheme.muted),
        ),
        if (!_ready && !_quoting && !_frozen)
          TextButton(
            onPressed: () => _updateQuote(),
            child: const Text('Retry checkout quote'),
          ),
        if (_frozen)
          TextButton(
            onPressed: _submitting
                ? null
                : () async {
                    try {
                      final page = await widget.repository.document(
                        '/buyer/orders',
                      );
                      widget.repository.requireNoErrors(page);
                      if (![
                            'Buyer/Orders',
                            'Buyer/Profile',
                          ].contains(page.component) ||
                          page.props['orders'] is! Map) {
                        throw const BackendException(
                          'Your recorded orders could not load. Sign in again if needed.',
                        );
                      }
                      if (mounted) {
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
                      if (mounted) setState(() => _error = e.message);
                    }
                  },
            child: const Text('Check my orders'),
          ),
      ],
    ),
  );

  Widget _deliveryPanel() => ProductPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProductHeading('Delivery method'),
        const SizedBox(height: 12),
        if (_hasCompanyContract) ...[
          DropdownButtonFormField<int>(
            key: ValueKey(
              'company-$_company-${_companies.map((row) => row['id']).join('-')}',
            ),
            initialValue: _companies.any((row) => row['id'] == _company)
                ? _company
                : null,
            isExpanded: true,
            isDense: false,
            itemHeight: null,
            decoration: InputDecoration(
              labelText: 'Logistics company',
              errorText: _fieldErrors['logistics_company_id'],
            ),
            selectedItemBuilder: (_) => [
              for (final company in _companies)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Tooltip(
                    message: company['name'].toString(),
                    child: Text(
                      company['name'].toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
            items: [
              for (final company in _companies)
                DropdownMenuItem(
                  value: (company['id'] as num).toInt(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(company['name'].toString()),
                  ),
                ),
            ],
            onChanged: _frozen || _submitting
                ? null
                : (value) {
                    setState(() {
                      _company = value;
                      _hub = null;
                    });
                    _edit();
                  },
            validator: (_) =>
                _company == null ? 'Choose a serving logistics company.' : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _companies.isEmpty
                  ? 'No company choices are currently available. Complete or review the address and refresh the quote.'
                  : 'Companies must serve both seller and recipient. Shipping uses the greater of actual and volumetric weight.',
              style: const TextStyle(fontSize: 12, height: 1.7),
            ),
          ),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Your delivery partner and fees are assigned by Bagoo and confirmed in the quote.',
              style: TextStyle(fontSize: 12, height: 1.7),
            ),
          ),
        CheckoutChoice(
          title: 'Doorstep delivery',
          description: 'Delivered to your recipient address. Shipping is calculated separately for each shop.',
          icon: Icons.local_shipping_outlined,
          selected: _delivery == 'doorstep',
          onTap: () {
            setState(() => _delivery = 'doorstep');
            _edit();
          },
        ),
        CheckoutChoice(
          title: 'Bayan Hub self-pickup',
          description: 'Collect from an eligible municipal hub when your parcel is ready.',
          icon: Icons.storefront_outlined,
          selected: _delivery == 'hub_self_pickup',
          onTap: () {
            setState(() => _delivery = 'hub_self_pickup');
            _edit();
          },
        ),
        if (_delivery == 'hub_self_pickup') ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('hub-$_company-$_hub'),
            initialValue: _hub,
            isExpanded: true,
            itemHeight: null,
            decoration: const InputDecoration(labelText: 'Pickup Bayan Hub'),
            items: mapsOf(_page.props['pickupHubs'])
                .where(
                  (hub) =>
                      !_hasCompanyContract ||
                      hub['logistics_company_id'] == _company,
                )
                .map(
                  (h) => DropdownMenuItem(
                    value: h['id'].toString(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '${h['name']} · ${h['city_municipality']}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              setState(() => _hub = v);
              _edit();
            },
            validator: (v) => _delivery == 'hub_self_pickup' && v == null
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
  );
  Widget _addressPanel() => ProductPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProductHeading('Recipient and delivery address'),
        if (_addresses.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('address-choice-$_address'),
            initialValue: _address,
            isExpanded: true,
            itemHeight: null,
            decoration: const InputDecoration(labelText: 'Saved address'),
            items: [
              const DropdownMenuItem(
                value: 'new',
                child: Text('Use a new address'),
              ),
              for (final a in _addresses)
                DropdownMenuItem(
                  value: a['id'].toString(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '${a['recipient_name']} · ${a['street']}, ${a['city']}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
            ],
            onChanged: (v) => _applyAddress(
              _addresses.where((a) => a['id'].toString() == v).firstOrNull,
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
            final changed = jsonEncode(_location) != jsonEncode(value);
            setState(() => _location = value);
            if (changed) {
              _fields['shipping_latitude']!.clear();
              _fields['shipping_longitude']!.clear();
              _locationFeedback = null;
              _hub = null;
              _edit();
            }
          },
        ),
        _field('shipping_address', 'Street / house / unit'),
        _field(
          'shipping_postal_code',
          'Postal code',
          keyboard: TextInputType.number,
        ),
        _field('landmark', 'Landmark (optional)', required: false),
        const Text(
          'Delivery coordinates (optional)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Pin the recipient’s location only. The address and available delivery route are checked separately.',
            style: TextStyle(fontSize: 12, height: 1.7),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _locating || _frozen || _submitting
              ? null
              : _captureLocation,
          icon: const Icon(Icons.my_location_outlined),
          label: Text(_locating ? 'Finding location…' : 'Use current location'),
        ),
        if (_locationFeedback != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _locationFeedback!,
              style: const TextStyle(fontSize: 12, height: 1.7),
            ),
          ),
        _field(
          'shipping_latitude',
          'Latitude',
          required: false,
          keyboard: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
        ),
        _field(
          'shipping_longitude',
          'Longitude',
          required: false,
          keyboard: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
        ),
        _field('notes', 'Delivery notes (optional)', required: false),
        if (_address == 'new')
          CheckboxListTile(
            value: _saveAddress,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged:
                _addresses.length >=
                    ((_page.props['addressBookLimit'] as num?)?.toInt() ?? 10)
                ? null
                : (v) {
                    setState(() => _saveAddress = v ?? false);
                    _edit();
                  },
            title: const Text(
              'Save this address for future orders',
              style: TextStyle(fontSize: 13),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: LayoutBuilder(
            builder: (context, box) {
              final wide =
                  box.maxWidth >= 1100 &&
                  MediaQuery.textScalerOf(context).scale(16) < 24;
              final details = Column(
                key: _contentKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ProductPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Checkout details',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Choose delivery and payment. You’ll review everything before placing your order.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.7,
                            color: BagooTheme.muted,
                          ),
                        ),
                        SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            Chip(
                              label: Text('1 · Details'),
                              backgroundColor: BagooTheme.rose,
                            ),
                            ExcludeSemantics(
                              child: Icon(
                                Icons.chevron_right_rounded,
                                color: BagooTheme.muted,
                              ),
                            ),
                            Chip(label: Text('2 · Review')),
                          ],
                        ),
                      ],
                    ),
                  ),
                  AbsorbPointer(
                    absorbing: _submitting || _frozen,
                    child: Column(
                      children: [
                        _deliveryPanel(),
                        _addressPanel(),
                        _itemsPanel(),
                        _vouchersPanel(),
                        _paymentPanel(),
                      ],
                    ),
                  ),
                ],
              );
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1380),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.all(24),
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                children: [details],
                              ),
                            ),
                            SizedBox(
                              width: 360,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  0,
                                  24,
                                  24,
                                  24,
                                ),
                                child: _summaryPanel(),
                              ),
                            ),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          children: [
                            Column(children: [details, _summaryPanel()]),
                          ],
                        ),
                ),
              );
            },
          ),
        ),
      ),
      bottomNavigationBar:
          MediaQuery.sizeOf(context).width < 1100 &&
              MediaQuery.viewInsetsOf(context).bottom == 0
          ? SafeArea(
              top: false,
              child: Material(
                color: Colors.white,
                shape: const Border(top: BorderSide(color: BagooTheme.line)),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .4,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _ready
                              ? pesos(_quote['total'])
                              : _quoting
                              ? 'Updating total…'
                              : 'Total unavailable',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: BagooTheme.strong,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _reviewButton(),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : null,
    ),
  );
}
