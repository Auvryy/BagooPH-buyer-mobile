import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../products/product_widgets.dart';
import 'search_controller.dart';

Future<SearchFilters?> showBuyerSearchFilters(
  BuildContext context, {
  required SearchFilters value,
  required List<Map<String, dynamic>> categories,
  required List<Map<String, dynamic>> locations,
}) => showModalBottomSheet<SearchFilters>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (sheet) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
    child: SizedBox(
      height: MediaQuery.sizeOf(sheet).height * .82,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Close filters without applying',
              onPressed: () => Navigator.pop(sheet),
              icon: const Icon(Icons.close),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SearchFiltersForm(
                value: value,
                categories: categories,
                locations: locations,
                onApply: (filters) => Navigator.pop(sheet, filters),
                onReset: () =>
                    Navigator.pop(sheet, SearchFilters(query: value.query)),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);

class SearchFiltersForm extends StatefulWidget {
  const SearchFiltersForm({
    super.key,
    required this.value,
    required this.categories,
    required this.locations,
    required this.onApply,
    required this.onReset,
  });
  final SearchFilters value;
  final List<Map<String, dynamic>> categories, locations;
  final ValueChanged<SearchFilters> onApply;
  final VoidCallback onReset;
  @override
  State<SearchFiltersForm> createState() => _SearchFiltersFormState();
}

class _SearchFiltersFormState extends State<SearchFiltersForm> {
  final _form = GlobalKey<FormState>();
  late SearchFilters _draft;
  late final TextEditingController _min, _max;
  @override
  void initState() {
    super.initState();
    _draft = widget.value;
    _min = TextEditingController(text: _draft.minimum);
    _max = TextEditingController(text: _draft.maximum);
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
    ),
  );
  Widget _choice(
    String label,
    String selected,
    List<Map<String, dynamic>> rows,
    String id,
    String name,
    ValueChanged<String> changed,
  ) => DropdownButtonFormField<String>(
    initialValue: rows.any((row) => row[id] == selected) ? selected : '',
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      DropdownMenuItem(value: '', child: Text('All ${label.toLowerCase()}')),
      for (final row in rows)
        DropdownMenuItem(
          value: row[id].toString(),
          child: Text(
            row[name].toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: (value) => setState(() => changed(value ?? '')),
  );
  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const ExcludeSemantics(
              child: Icon(Icons.tune, color: BagooTheme.strong),
            ),
            const SizedBox(width: 10),
            const Expanded(child: ProductHeading('Filter by')),
            TextButton(onPressed: widget.onReset, child: const Text('Reset')),
          ],
        ),
        const SizedBox(height: 16),
        _choice(
          'Departments',
          _draft.category,
          widget.categories,
          'slug',
          'name',
          (v) => _draft = _draft.copyWith(category: v),
        ),
        _label('Ships from'),
        _choice(
          'Provinces and areas',
          _draft.location,
          widget.locations,
          'value',
          'label',
          (v) => _draft = _draft.copyWith(location: v),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Based on the shop’s confirmed pickup area.',
            style: TextStyle(
              fontSize: 12,
              color: BagooTheme.muted,
              height: 1.6,
            ),
          ),
        ),
        _label('Price range'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in const [
              ('Under ₱500', '', '500'),
              ('₱500–₱1,500', '500', '1500'),
              ('₱1,500–₱5,000', '1500', '5000'),
              ('₱5,000 and up', '5000', ''),
            ])
              ActionChip(
                label: Text(preset.$1),
                onPressed: () => setState(() {
                  _min.text = preset.$2;
                  _max.text = preset.$3;
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _min,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Minimum price',
            prefixText: '₱ ',
          ),
          validator: SearchFilters.priceError,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _max,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Maximum price',
            prefixText: '₱ ',
          ),
          validator: (value) {
            final error = SearchFilters.priceError(value);
            if (error != null) return error;
            final min = double.tryParse(_min.text.trim()),
                max = double.tryParse(value?.trim() ?? '');
            return min != null && max != null && min > max
                ? 'Maximum must be at least minimum.'
                : null;
          },
        ),
        const SizedBox(height: 16),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'In stock only',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          value: _draft.inStock,
          onChanged: (v) =>
              setState(() => _draft = _draft.copyWith(inStock: v)),
        ),
        _label('Minimum verified rating'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final rating in {
              '': 'Any rating',
              '3': '3+ stars',
              '4': '4+ stars',
              '4.5': '4.5+ stars',
              '5': '5 stars',
            }.entries)
              ChoiceChip(
                label: Text(rating.value),
                selected: _draft.rating == rating.key,
                onSelected: (_) => setState(
                  () => _draft = _draft.copyWith(rating: rating.key),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () {
            if (_form.currentState!.validate()) {
              FocusManager.instance.primaryFocus?.unfocus();
              widget.onApply(
                _draft.copyWith(
                  minimum: _min.text.trim(),
                  maximum: _max.text.trim(),
                ),
              );
            }
          },
          icon: const Icon(Icons.check),
          label: const Text('Apply filters'),
        ),
      ],
    ),
  );
}
