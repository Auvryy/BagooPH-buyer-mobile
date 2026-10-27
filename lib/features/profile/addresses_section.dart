import 'dart:convert';

import 'package:flutter/material.dart';

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

class _AddressesSectionState extends ProfileFormState<AddressesSection> {
  List<Map<String, dynamic>> get addresses =>
      mapsOf(widget.page.props['addresses']);
  bool get eligible => widget.page.props['canUsePortal'] == true;
  int get limit =>
      (widget.page.props['addressBookLimit'] as num?)?.toInt() ?? 10;
  Future<void> _edit([Map<String, dynamic>? address]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AddressEditor(
          repository: widget.repository,
          user: mapOf(widget.page.props['user']),
          address: address,
          count: addresses.length,
          limit: limit,
          onChanged: widget.onChanged,
        ),
      ),
    );
  }

  Future<void> _change(Map<String, dynamic> address, bool remove) async {
    if (remove &&
        !await confirmAction(
          context,
          'Delete this address?',
          '${address['recipient_name']} · ${address['street']}, ${address['city']}\nExisting orders keep their delivery details.',
          'Delete address',
        )) {
      return;
    }
    await perform(() async {
      final page = await widget.repository.mutate(
        '/buyer/addresses/${address['id']}${remove ? '' : '/default'}',
        {},
        method: remove ? 'DELETE' : 'POST',
        tab: 'addresses',
      );
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
      onPressed: busy || !eligible || addresses.length >= limit ? null : _edit,
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
                  onPressed: busy || !eligible ? null : () => _edit(address),
                  child: const Text('Edit'),
                ),
                if (address['is_default'] != true) ...[
                  TextButton(
                    onPressed: busy || !eligible
                        ? null
                        : () => _change(address, false),
                    child: const Text('Set as default'),
                  ),
                  TextButton(
                    onPressed: busy || !eligible
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

class _AddressEditor extends StatefulWidget {
  const _AddressEditor({
    required this.repository,
    required this.user,
    required this.address,
    required this.count,
    required this.limit,
    required this.onChanged,
  });
  final ProfileRepository repository;
  final Map<String, dynamic> user;
  final Map<String, dynamic>? address;
  final int count, limit;
  final ValueChanged<WebPage> onChanged;
  @override
  State<_AddressEditor> createState() => _AddressEditorState();
}

class _AddressEditorState extends ProfileFormState<_AddressEditor> {
  late final Map<String, TextEditingController> _fields;
  late Map<String, String> _location;
  late bool _default;
  late String _type;
  bool _loading = true, _initialized = false, _keepCoordinates = true;
  @override
  void initState() {
    super.initState();
    final address = widget.address ?? {};
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
                  ? widget.user['name']?.toString()
                  : key == 'phone'
                  ? widget.user['phone']?.toString()
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
    final page = await widget.repository.mutate(
      '/buyer/addresses${widget.address == null ? '' : '/${widget.address!['id']}'}',
      values,
      method: widget.address == null ? 'POST' : 'PATCH',
      tab: 'addresses',
    );
    if (mounted) {
      widget.onChanged(page);
      Navigator.pop(context);
    }
    return null;
  });
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
                min: 2,
                max: 100,
                autofill: const [AutofillHints.name],
              ),
              field(
                'phone',
                'Mobile number',
                _fields['phone']!,
                max: 20,
                keyboard: TextInputType.phone,
                autofill: const [AutofillHints.telephoneNumber],
              ),
              LocationPicker(
                repository: widget.repository.buyer,
                initial: _location,
                disabled: busy,
                onLoading: (loading) {
                  if (mounted) setState(() => _loading = loading);
                },
                onChanged: (value) {
                  if (_initialized &&
                      jsonEncode(value) != jsonEncode(_location)) {
                    _keepCoordinates = false;
                    _fields['postal_code']!.clear();
                  }
                  _initialized = true;
                  if (mounted) setState(() => _location = value);
                },
              ),
              field(
                'street',
                'Street / house / unit number',
                _fields['street']!,
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
                onChanged: busy
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
                onPressed: _loading ? null : _save,
              ),
            ]),
          ),
        ),
      ),
    ),
  );
}
