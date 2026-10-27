import 'package:flutter/material.dart';

import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';

class LocationPicker extends StatefulWidget {
  const LocationPicker({
    super.key,
    required this.repository,
    required this.initial,
    required this.onChanged,
    required this.onLoading,
    this.disabled = false,
  });
  final BuyerRepository repository;
  final Map<String, String> initial;
  final ValueChanged<Map<String, String>> onChanged;
  final ValueChanged<bool> onLoading;
  final bool disabled;
  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  late Map<String, String> _values;
  Map<String, dynamic> _options = {};
  bool _busy = true;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _values = Map.of(widget.initial);
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation && _busy) {
        widget.onLoading(true);
      }
    });
    try {
      final query = Uri(
        queryParameters: {
          for (final k in ['region', 'province', 'city'])
            if ((_values[k] ?? '').isNotEmpty) k: _values[k]!,
        },
      ).query;
      final options = await widget.repository.session.jsonGet(
        '/address-locations${query.isEmpty ? '' : '?$query'}',
      );
      if (!mounted || generation != _generation) {
        return;
      }
      if (![
        'regions',
        'provinces',
        'cities',
        'barangays',
      ].every((k) => options[k] is List)) {
        throw const BackendException('Location choices are unavailable.');
      }
      setState(() {
        _options = options;
        final resolved = mapOf(options['resolved']);
        for (final k in ['region', 'province', 'city']) {
          if (resolved[k] is String) {
            _values[k] = resolved[k] as String;
          }
        }
      });
      widget.onChanged(Map.of(_values));
    } on BackendException catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
        widget.onLoading(_error != null);
      }
    }
  }

  void _change(String field, String? value) {
    final order = ['region', 'province', 'city', 'barangay'];
    setState(() {
      _values[field] = value ?? '';
      for (final k in order.skip(order.indexOf(field) + 1)) {
        _values[k] = '';
      }
    });
    widget.onChanged(Map.of(_values));
    if (field != 'barangay') {
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) ...[
        Notice(_error!, error: true),
        TextButton(
          onPressed: widget.disabled ? null : _load,
          child: const Text('Retry location choices'),
        ),
      ],
      for (final entry in const {
        'region': ('regions', 'Region'),
        'province': ('provinces', 'Province / area'),
        'city': ('cities', 'City / municipality'),
        'barangay': ('barangays', 'Barangay'),
      }.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: DropdownButtonFormField<String>(
            key: ValueKey(
              '${entry.key}:${_values[entry.key]}:${mapsOf(_options[entry.value.$1]).length}',
            ),
            initialValue:
                mapsOf(_options[entry.value.$1])
                    .any((o) => o['value'] == _values[entry.key])
                ? _values[entry.key]
                : null,
            isExpanded: true,
            itemHeight: null,
            decoration: InputDecoration(labelText: entry.value.$2),
            items: mapsOf(_options[entry.value.$1])
                .map(
                  (o) => DropdownMenuItem(
                    value: o['value'].toString(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        o['label'].toString(),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: _busy || widget.disabled
                ? null
                : (v) => _change(entry.key, v),
            validator: (v) => v == null || v.isEmpty
                ? 'Choose ${entry.value.$2.toLowerCase()}.'
                : null,
          ),
        ),
    ],
  );
}
