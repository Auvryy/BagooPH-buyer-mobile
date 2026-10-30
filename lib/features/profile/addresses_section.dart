import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/buyer_account_scope.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../checkout/location_picker.dart';
import 'profile_repository.dart';
import 'profile_widgets.dart';

class AddressesSection extends StatefulWidget {
  const AddressesSection({
    super.key,
    required this.repository,
    required this.page,
    required this.onChanged,
  });
  final ProfileRepository repository;
  final WebPage page;
  final ValueChanged<WebPage> onChanged;
  @override
  State<AddressesSection> createState() => _AddressesSectionState();
}

class _AddressesSectionState extends BuyerProfileFormState<AddressesSection> {
  @override
  ProfileRepository get accountRepository => widget.repository;
  @override
  WebPage get accountPage => widget.page;
  @override
  void clearBuyerDraft() => _confirming = false;
  bool _confirming = false;
  bool get _pending => busy || _confirming;

  List<Map<String, dynamic>> get addresses =>
      mapsOf(widget.page.props['addresses']);
  bool get eligible => widget.page.props['canUsePortal'] == true;
  int get limit =>
      (widget.page.props['addressBookLimit'] as num?)?.toInt() ?? 10;
  Future<void> _edit([Map<String, dynamic>? address]) async {
    if (_pending || !eligible || !ensureBuyerAccess()) return;
    await perform(() async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _AddressEditor(
            repository: widget.repository,
            page: widget.page,
            account: accountScope,
            canChange: () =>
                mounted &&
                hasBuyerAccess &&
                eligible &&
                (address == null
                    ? addresses.length < limit
                    : addresses.any((saved) => saved['id'] == address['id'])),
            address: address,
            count: addresses.length,
            limit: limit,
            onChanged: widget.onChanged,
          ),
        ),
      );
      return null;
    }, validate: false);
  }

  Future<void> _change(Map<String, dynamic> address, bool remove) async {
    if (_pending || !eligible || !ensureBuyerAccess()) return;
    if (remove) {
      setState(() => _confirming = true);
      try {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => _AddressDeleteConfirmation(
            account: accountScope,
            address: address,
          ),
        );
        if (confirmed != true) return;
      } finally {
        if (mounted) setState(() => _confirming = false);
      }
    }
    if (!mounted) return;
    await perform(() async {
      if (!eligible) {
        throw const BackendException(
          'An active approved buyer account is required to change delivery addresses.',
        );
      }
      final page = await widget.repository.mutate(
        '/buyer/addresses/${address['id']}${remove ? '' : '/default'}',
        {},
        method: remove ? 'DELETE' : 'POST',
        tab: 'addresses',
      );
      checkBuyerAccount(result: page);
      if (mounted) widget.onChanged(page);
      return mapOf(page.props['flash'])['success']?.toString();
    }, validate: false);
  }

  @override
  Widget build(BuildContext context) => content([
    ProfileHeading(
      'Delivery Address Book',
      '${addresses.length} of $limit addresses saved. Changes apply to future deliveries; existing orders keep their original address.',
      Icons.location_on_outlined,
    ),
    if (!eligible)
      const Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: Notice(
          'An active approved buyer account is required to change delivery addresses.',
        ),
      ),
    OutlinedButton.icon(
      onPressed: _pending || !eligible || addresses.length >= limit
          ? null
          : _edit,
      icon: const Icon(Icons.add),
      label: const Text('Add delivery address'),
    ),
    const SizedBox(height: 24),
    if (addresses.isEmpty)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Text(
          'No delivery addresses saved yet.',
          textAlign: TextAlign.center,
        ),
      ),
    for (final address in addresses)
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    address['recipient_name']?.toString() ?? 'Recipient',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.5,
                    ),
                  ),
                ),
                if (address['is_default'] == true)
                  const Chip(
                    label: Text('Default', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
            Text(
              '${address['phone']} · ${address['type'] ?? 'Home'}',
              style: const TextStyle(fontSize: 13, height: 1.7),
            ),
            Text(
              [
                address['street'],
                address['barangay'],
                address['city'],
                address['province'],
                address['postal_code'],
              ].where((v) => v != null && v.toString().isNotEmpty).join(', '),
              style: const TextStyle(height: 1.7),
            ),
            if (address['landmark'] != null)
              Text(
                'Landmark: ${address['landmark']}',
                style: const TextStyle(fontSize: 12, height: 1.7),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: _pending || !eligible
                      ? null
                      : () => _edit(address),
                  child: const Text('Edit'),
                ),
                if (address['is_default'] != true) ...[
                  TextButton(
                    onPressed: _pending || !eligible
                        ? null
                        : () => _change(address, false),
                    child: const Text('Set as default'),
                  ),
                  TextButton(
                    onPressed: _pending || !eligible
                        ? null
                        : () => _change(address, true),
                    child: const Text('Delete'),
                  ),
                ],
              ],
            ),
            if (address['is_default'] == true)
              const Text(
                'Choose another default before deleting this address.',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
            const Divider(height: 28),
          ],
        ),
      ),
  ]);
}

class _AddressDeleteConfirmation extends StatefulWidget {
  const _AddressDeleteConfirmation({
    required this.account,
    required this.address,
  });
  final BuyerAccountScope account;
  final Map<String, dynamic> address;
  @override
  State<_AddressDeleteConfirmation> createState() =>
      _AddressDeleteConfirmationState();
}

class _AddressDeleteConfirmationState extends State<_AddressDeleteConfirmation>
    with WidgetsBindingObserver {
  late final BuyerAccountScope _account;
  @override
  void initState() {
    super.initState();
    _account = widget.account.fork();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_account.isCurrent) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _account.invalidate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _account.isCurrent ? 'Delete this address?' : 'Address unavailable',
    ),
    content: SingleChildScrollView(
      child: Text(
        _account.isCurrent
            ? '${widget.address['recipient_name']} · ${widget.address['street']}, ${widget.address['city']}\nExisting orders keep their delivery details.'
            : 'Your buyer account changed or access ended. Reopen the address book from your account.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(_account.isCurrent ? 'Cancel' : 'Close'),
      ),
      if (_account.isCurrent)
        FilledButton(
          onPressed: () => Navigator.pop(context, _account.isCurrent),
          child: const Text('Delete address'),
        ),
    ],
  );
}

class _AddressEditor extends StatefulWidget {
  const _AddressEditor({
    required this.repository,
    required this.page,
    required this.account,
    required this.canChange,
    required this.address,
    required this.count,
    required this.limit,
    required this.onChanged,
  });
  final ProfileRepository repository;
  final WebPage page;
  final BuyerAccountScope account;
  final bool Function() canChange;
  final Map<String, dynamic>? address;
  final int count, limit;
  final ValueChanged<WebPage> onChanged;
  @override
  State<_AddressEditor> createState() => _AddressEditorState();
}

class _AddressEditorState extends BuyerProfileFormState<_AddressEditor> {
  @override
  ProfileRepository get accountRepository => widget.repository;
  @override
  WebPage get accountPage => widget.page;
  @override
  BuyerAccountScope get parentAccountScope => widget.account;

  @override
  void clearBuyerDraft() {
    for (final field in _fields.values) {
      field.clear();
    }
    _location = {};
    _default = false;
    _keepCoordinates = false;
    _needsReview = false;
  }

  late final Map<String, TextEditingController> _fields;
  late Map<String, String> _location;
  late bool _default;
  late String _type;
  bool _loading = true, _keepCoordinates = true;
  bool _needsReview = false;
  @override
  void initState() {
    super.initState();
    final address = widget.address ?? {};
    final user = mapOf(widget.page.props['user']);
    _fields = {
      for (final key in [
        'recipient_name',
        'phone',
        'street',
        'postal_code',
        'landmark',
      ])
        key: TextEditingController(
          text:
              address[key]?.toString() ??
              (key == 'recipient_name'
                  ? user['name']?.toString()
                  : key == 'phone'
                  ? user['phone']?.toString()
                  : '') ??
              '',
        ),
    };
    _location = {
      for (final key in ['region', 'province', 'city', 'barangay'])
        key: address[key]?.toString() ?? '',
    };
    _default = address['is_default'] == true || widget.count == 0;
    _type = address['type']?.toString() ?? 'Home';
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async => perform(() async {
    if (_needsReview) {
      throw const BackendException(
        'Review your saved addresses before adding this address again.',
      );
    }
    if (!widget.canChange()) {
      throw const BackendException(
        'Your address permissions or saved addresses changed. Close this editor and reopen your address book.',
      );
    }
    if (_loading) {
      throw const BackendException(
        'Wait for the current location choices to load.',
      );
    }
    if (widget.address == null && widget.count >= widget.limit) {
      throw BackendException('You can save up to ${widget.limit} addresses.');
    }
    final values = {
      for (final field in _fields.entries) field.key: field.value.text.trim(),
      ..._location,
      'type': _type,
      'is_default': _default,
      'latitude': _keepCoordinates ? mapOf(widget.address)['latitude'] : null,
      'longitude': _keepCoordinates ? mapOf(widget.address)['longitude'] : null,
    };
    late WebPage page;
    try {
      page = await widget.repository.mutate(
        '/buyer/addresses${widget.address == null ? '' : '/${widget.address!['id']}'}',
        values,
        method: widget.address == null ? 'POST' : 'PATCH',
        tab: 'addresses',
      );
    } on BackendException catch (error) {
      if (widget.address == null &&
          (error.status == null ||
              error.status == 408 ||
              error.status! >= 500)) {
        _needsReview = true;
      }
      rethrow;
    } catch (_) {
      if (widget.address == null) _needsReview = true;
      rethrow;
    }
    checkBuyerAccount(result: page);
    if (mounted) {
      widget.onChanged(page);
      Navigator.pop(context);
    }
    return null;
  });

  Future<void> _reviewSaved() async => perform(() async {
    final page = await widget.repository.load(tab: 'addresses');
    checkBuyerAccount(result: page);
    if (mounted) {
      widget.onChanged(page);
      Navigator.pop(context);
    }
    return null;
  }, validate: false);
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.address == null
              ? 'Add delivery address'
              : 'Edit delivery address',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: content([
              const ProfileHeading(
                'Delivery details',
                'These details are for future deliveries. Changing the recipient does not change your registered identity.',
                Icons.location_on_outlined,
              ),
              field(
                'recipient_name',
                'Recipient name',
                _fields['recipient_name']!,
                enabled: !_needsReview,
                min: 2,
                max: 100,
                autofill: const [AutofillHints.name],
              ),
              field(
                'phone',
                'Mobile number',
                _fields['phone']!,
                enabled: !_needsReview,
                max: 20,
                keyboard: TextInputType.phone,
                autofill: const [AutofillHints.telephoneNumber],
              ),
              LocationPicker(
                repository: widget.repository.buyer,
                initial: _location,
                disabled: busy || _needsReview,
                onLoading: (loading) {
                  if (mounted && ensureBuyerAccess()) {
                    setState(() => _loading = loading);
                  }
                },
                onChanged: (value) {
                  if (!mounted || !ensureBuyerAccess()) return;
                  if (jsonEncode(value) != jsonEncode(_location)) {
                    _keepCoordinates = false;
                    _fields['postal_code']!.clear();
                  }
                  setState(() => _location = value);
                },
              ),
              field(
                'street',
                'Street / house / unit number',
                _fields['street']!,
                enabled: !_needsReview,
                min: 5,
                max: 500,
                lines: 3,
                autofill: const [AutofillHints.streetAddressLine1],
                onChanged: (_) => _keepCoordinates = false,
              ),
              field(
                'postal_code',
                'Postal code (optional)',
                _fields['postal_code']!,
                enabled: !_needsReview,
                required: false,
                max: 4,
                keyboard: TextInputType.number,
                check: (v) => v.isEmpty || RegExp(r'^\d{4}$').hasMatch(v)
                    ? null
                    : 'Use a four-digit postal code.',
              ),
              field(
                'landmark',
                'Landmark (optional)',
                _fields['landmark']!,
                enabled: !_needsReview,
                required: false,
                min: 5,
                max: 255,
              ),
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Address type'),
                items: [
                  for (final type in ['Home', 'Office', 'Other'])
                    DropdownMenuItem(value: type, child: Text(type)),
                ],
                onChanged: busy || _needsReview
                    ? null
                    : (value) => setState(() => _type = value!),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _default,
                title: const Text('Use as default delivery address'),
                onChanged:
                    busy ||
                        _needsReview ||
                        widget.address?['is_default'] == true ||
                        widget.count == 0
                    ? null
                    : (value) => setState(() => _default = value ?? false),
              ),
              const SizedBox(height: 16),
              SubmitButton(
                label: widget.address == null
                    ? 'Add address'
                    : 'Save delivery address',
                busy: busy,
                onPressed: _loading || _needsReview ? null : _save,
              ),
              if (_needsReview) ...[
                const SizedBox(height: 16),
                const Notice(
                  'The save result is uncertain. Check your address book before adding this address again.',
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: busy ? null : _reviewSaved,
                  child: const Text('Review saved addresses'),
                ),
              ],
            ]),
          ),
        ),
      ),
    ),
  );
}
