import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../home/product_card.dart';
import 'product_model.dart';

class ProductPanel extends StatelessWidget {
  const ProductPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x070F172A),
          blurRadius: 10,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class ProductHeading extends StatelessWidget {
  const ProductHeading(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          height: 1.4,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class Stars extends StatelessWidget {
  const Stars(this.value, {super.key});
  final dynamic value;
  @override
  Widget build(BuildContext context) => Semantics(
    label: recordedRating(value) == null
        ? 'No ratings yet'
        : '${ratingLabel(value)} out of 5 stars',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          5,
          (i) => Icon(
            recordedRating(value) != null && i < recordedRating(value)!.round()
                ? Icons.star_rounded
                : Icons.star_border_rounded,
            color: BagooTheme.crimson,
            size: 17,
          ),
        ),
      ),
    ),
  );
}

class ImageViewer extends StatelessWidget {
  const ImageViewer({
    super.key,
    required this.session,
    required this.source,
    required this.label,
    this.private = false,
  });
  final WebSession session;
  final String source;
  final String label;
  final bool private;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(label)),
    body: SafeArea(
      child: Center(
        child: InteractiveViewer(
          minScale: .5,
          maxScale: 5,
          child: RemoteImage(
            uri: imageUri(session, source),
            fit: BoxFit.contain,
            headers: private ? session.imageHeaders(source) : null,
          ),
        ),
      ),
    ),
  );
}

void viewImage(
  BuildContext context,
  WebSession session,
  String source,
  String label, {
  bool private = false,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ImageViewer(
        session: session,
        source: source,
        label: label,
        private: private,
      ),
    ),
  );
}

String readableDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) {
    return 'Date unavailable';
  }
  final manila = date.toUtc().add(const Duration(hours: 8));
  return '${manila.day}/${manila.month}/${manila.year}';
}

String readableDateTime(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return 'Not provided';
  final manila = date.toUtc().add(const Duration(hours: 8));
  return '${readableDate(value)} ${manila.hour.toString().padLeft(2, '0')}:${manila.minute.toString().padLeft(2, '0')} PHT';
}

class OfferTile extends StatefulWidget {
  const OfferTile({
    super.key,
    required this.offer,
    required this.repository,
    this.onUse,
    this.onSignIn,
    this.canSave = true,
    this.onSaved,
  });
  final Map<String, dynamic> offer;
  final BuyerRepository repository;
  final VoidCallback? onUse;
  final VoidCallback? onSignIn;
  final bool canSave;
  final Future<void> Function()? onSaved;
  @override
  State<OfferTile> createState() => _OfferTileState();
}

class _OfferTileState extends State<OfferTile> {
  bool _busy = false;
  dynamic _saved;
  String? _error;
  @override
  void initState() {
    super.initState();
    _saved = widget.offer['saved_id'];
  }

  Future<void> _save() async {
    if (_busy) {
      return;
    }
    if (widget.onSignIn != null) {
      widget.onSignIn!();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.repository.session.jsonPost(
        _saved == null
            ? '/buyer/saved-vouchers/${widget.offer['revision_id']}'
            : '/buyer/saved-vouchers/$_saved',
        {},
        method: _saved == null ? 'POST' : 'DELETE',
      );
      if (_saved == null
          ? data['saved_id'] is! num
          : data['saved_id'] != null || !data.containsKey('saved_id')) {
        throw const BackendException('The voucher change was not confirmed.');
      }
      if (mounted) {
        setState(() => _saved = data['saved_id']);
        await widget.onSaved?.call();
      }
    } on BackendException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    final discount = o['discount_type'] == 'free_shipping'
        ? 'Shipping discount'
        : o['discount_type'] == 'percent'
        ? '${o['discount_value']}% off'
        : '${pesos(o['discount_value'])} off';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: BagooTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            o['name']?.toString() ?? discount,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            discount,
            style: const TextStyle(
              color: BagooTheme.strong,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'Minimum spend ${pesos(o['min_spend'])}',
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
          if (o['max_discount'] != null)
            Text(
              'Maximum discount ${pesos(o['max_discount'])}',
              style: const TextStyle(fontSize: 12),
            ),
          if (o['expires_at'] != null)
            Text(
              'Expires ${readableDate(o['expires_at'])} · Philippine time',
              style: const TextStyle(fontSize: 12, height: 1.6),
            ),
          if (o['description'] != null)
            Text(
              o['description'].toString(),
              style: const TextStyle(fontSize: 12, height: 1.6),
            ),
          if (o['product_scope'] == 'selected') ...[
            const Text(
              'Selected products only',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            for (final p in mapsOf(o['eligible_products']))
              Text(p['name'].toString(), style: const TextStyle(fontSize: 12)),
          ],
          Text(
            o['code']?.toString() ?? '',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (o['unavailable_reason'] != null)
            Text(
              o['unavailable_reason'].toString(),
              style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
            ),
          Wrap(
            spacing: 8,
            children: [
              if (widget.onUse != null)
                TextButton(
                  onPressed: o['eligible'] == false ? null : widget.onUse,
                  child: const Text('Use voucher'),
                ),
              if (o['revision_id'] != null)
                TextButton(
                  onPressed: _busy || !widget.canSave ? null : _save,
                  child: Text(
                    _busy
                        ? 'Saving…'
                        : _saved == null
                        ? 'Save voucher'
                        : 'Remove voucher',
                  ),
                ),
            ],
          ),
          if (_error != null) Notice(_error!, error: true),
        ],
      ),
    );
  }
}
