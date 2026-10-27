import 'package:flutter/material.dart';

import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../products/product_widgets.dart';
import '../products/product_model.dart' show pesos;

class VoucherPickerPage extends StatefulWidget {
  const VoucherPickerPage({
    super.key,
    required this.repository,
    required this.values,
    required this.title,
    this.shopId,
    this.selectedRevision,
  });
  final BuyerRepository repository;
  final Map<String, dynamic> values;
  final String title;
  final int? shopId, selectedRevision;
  @override
  State<VoucherPickerPage> createState() => _VoucherPickerPageState();
}

class _VoucherPickerPageState extends State<VoucherPickerPage> {
  Map<String, dynamic> _page = {};
  bool _loading = true;
  String? _error;
  int _number = 1;
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.repository.voucherChoices({
        ...widget.values,
        'shop_id': widget.shopId,
        'voucher_page': _number,
      });
      if (mounted) setState(() => _page = mapOf(data['offers']));
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ProductPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ProductHeading('Choose a voucher'),
                    const Text(
                      'Compare the current saving and terms. Selecting an offer updates the checkout quote; it does not reserve a discount.',
                      style: TextStyle(fontSize: 13, height: 1.7),
                    ),
                    if (widget.selectedRevision != null)
                      TextButton(
                        onPressed: () => Navigator.pop(
                          context,
                          <String, dynamic>{'remove': true},
                        ),
                        child: const Text('Remove current voucher'),
                      ),
                  ],
                ),
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) ...[
                Notice(_error!, error: true),
                TextButton(
                  onPressed: _loading ? null : _load,
                  child: const Text('Try again'),
                ),
              ],
              if (!_loading && _error == null && mapsOf(_page['data']).isEmpty)
                const ProductPanel(
                  child: Text('No vouchers are available for this selection.'),
                ),
              if (_error == null)
                for (final offer in mapsOf(_page['data']))
                  ProductPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (offer['revision_id'] == widget.selectedRevision)
                          const Chip(label: Text('Selected voucher')),
                        if (offer['saving'] != null &&
                            offer['eligible'] == true)
                          Text(
                            'Save ${pesos(offer['saving'])}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        OfferTile(
                          key: ValueKey(
                            '${offer['revision_id']}:${offer['saved_id']}',
                          ),
                          offer: offer,
                          repository: widget.repository,
                          onSaved: _load,
                          onUse: _loading || offer['eligible'] != true
                              ? null
                              : () => Navigator.pop(context, offer),
                        ),
                      ],
                    ),
                  ),
              if ((_page['last_page'] as num? ?? 1) > 1)
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _loading || _number <= 1
                          ? null
                          : () {
                              _number--;
                              _load();
                            },
                      child: const Text('Previous'),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Page ${_page['current_page'] ?? _number} of ${_page['last_page']}',
                      ),
                    ),
                    OutlinedButton(
                      onPressed:
                          _loading ||
                              _number >= (_page['last_page'] as num? ?? 1)
                          ? null
                          : () {
                              _number++;
                              _load();
                            },
                      child: const Text('Next'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
