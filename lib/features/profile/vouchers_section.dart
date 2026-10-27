import 'package:flutter/material.dart';

import '../../core/web_session.dart';
import '../checkout/bag_page.dart';
import '../products/product_widgets.dart';
import '../home/product_card.dart';
import 'profile_repository.dart';
import 'profile_widgets.dart';

class VouchersSection extends StatelessWidget {
  const VouchersSection({
    super.key,
    required this.repository,
    required this.page,
    required this.onQuery,
    required this.reload,
    this.loading = false,
  });
  final ProfileRepository repository;
  final WebPage page;
  final void Function(String tab, int page) onQuery;
  final Future<void> Function() reload;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    final collection = mapOf(page.props['voucherCollection']);
    final current = collection['tab']?.toString() ?? 'available';
    final counts = mapOf(collection['counts']);
    final offers = mapOf(collection['offers']);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ProfilePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProfileHeading(
                'My Vouchers & Promos',
                'Saved vouchers are bookmarks. Availability is checked again at checkout; no stock, use or discount is reserved.',
                Icons.local_offer_outlined,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tab in {
                    'available': 'Available',
                    'saved': 'Saved',
                    'used': 'Used',
                    'expired': 'Expired',
                  }.entries)
                    ChoiceChip(
                      label: Text('${tab.value} (${counts[tab.key] ?? 0})'),
                      selected: current == tab.key,
                      onSelected: loading ? null : (_) => onQuery(tab.key, 1),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              if (loading) const LinearProgressIndicator(),
              if (mapsOf(offers['data']).isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      const Icon(Icons.local_offer_outlined, size: 40),
                      const SizedBox(height: 16),
                      Text(
                        'No $current vouchers',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        current == 'saved'
                            ? 'Save a shop or Bagoo offer to find its terms here.'
                            : current == 'used'
                            ? 'Offers you actually use at checkout will appear here.'
                            : current == 'expired'
                            ? 'Expired vouchers you saved or used will appear here.'
                            : 'Shop and Bagoo offers will appear here when available.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, height: 1.7),
                      ),
                    ],
                  ),
                ),
              for (final offer in mapsOf(offers['data']))
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OfferTile(
                      key: ValueKey(
                        '$current:${offer['revision_id']}:${offer['saved_id']}',
                      ),
                      offer: offer,
                      repository: repository.buyer,
                      canSave:
                          page.props['canUsePortal'] == true &&
                          (!loading) &&
                          (offer['saved_id'] != null ||
                              offer['eligible'] != false),
                      onSaved: reload,
                      onUse: offer['eligible'] == false || loading
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => BagPage(
                                  repository: repository.buyer,
                                  voucherCode: offer['code']?.toString(),
                                ),
                              ),
                            ),
                    ),
                    if (offer['unavailable_reason'] != null)
                      Text(
                        offer['unavailable_reason'].toString(),
                        style: const TextStyle(fontSize: 12, height: 1.7),
                      ),
                    for (final use in mapsOf(offer['uses']))
                      Text(
                        'Used ${readableDateTime(use['used_at'])} · Saved ${pesos(use['saving'])}',
                        style: const TextStyle(fontSize: 12, height: 1.7),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ProfilePagination(
                offers,
                (number) => onQuery(current, number),
                disabled: loading,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
