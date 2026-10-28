import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/web_session.dart';
import '../home/product_card.dart';
import '../products/product_model.dart';

class PriceSegments extends StatelessWidget {
  const PriceSegments({super.key, required this.segments});
  final List<Map<String, dynamic>> segments;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final segment in segments)
        Text(
          '${segment['quantity']} × ${pesos(segment['unit_price'])} = ${pesos(segment['subtotal'])}${segment['sale_kind'] == 'flash'
              ? ' · Flash'
              : segment['sale_kind'] == 'store'
              ? ' · Sale'
              : ''}',
          style: const TextStyle(fontSize: 13, height: 1.7),
        ),
    ],
  );
}

class ShippingCalculation extends StatelessWidget {
  const ShippingCalculation({
    super.key,
    required this.calculation,
    this.selfPickup = false,
  });
  final Map<String, dynamic> calculation;
  final bool selfPickup;

  String _kg(dynamic grams) =>
      '${((amount(grams) ?? 0) / 1000).toStringAsFixed(3)} kg';
  String _money(dynamic cents) => pesos((amount(cents) ?? 0) / 100);

  @override
  Widget build(BuildContext context) {
    if (calculation.isEmpty) return const SizedBox.shrink();
    final missing =
        (calculation['missing_measurement_product_ids'] as List? ?? [])
            .isNotEmpty;
    final route = mapsOf(calculation['route']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (calculation['company_name'] is String)
            Text(
              calculation['company_name'],
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          if (missing)
            const Text(
              'Some packed measurements are not recorded. This quote uses the published flat base fee.',
              style: TextStyle(fontSize: 12, height: 1.7),
            )
          else
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                for (final row in {
                  'actual_weight_grams': 'Actual weight',
                  'volumetric_weight_grams': 'Volumetric weight',
                  'billable_weight_grams': 'Billable weight',
                }.entries)
                  Text(
                    '${row.value}: ${_kg(calculation[row.key])}',
                    style: const TextStyle(fontSize: 12, height: 1.7),
                  ),
              ],
            ),
          Text(
            selfPickup
                ? 'Hub collection: no doorstep shipping charge.'
                : 'Base ${_money(calculation['base_fee_cents'])} + ${calculation['additional_kilograms'] ?? 0} additional kg × ${_money(calculation['additional_kg_cents'])}. Included: ${_kg(calculation['included_weight_grams'])}.',
            style: const TextStyle(fontSize: 12, height: 1.7),
          ),
          if (route.isNotEmpty)
            Text(
              'Route: ${route.map((hub) => hub['code']).join(' → ')}${calculation['same_hub_bypass'] == true ? ' · Local child-hub delivery' : ''}',
              style: const TextStyle(fontSize: 12, height: 1.7),
            ),
        ],
      ),
    );
  }
}

class VoucherReceipt extends StatelessWidget {
  const VoucherReceipt({
    super.key,
    required this.receipt,
    this.paymentMethod = 'cod',
  });
  final Map<String, dynamic> receipt;
  final String paymentMethod;

  @override
  Widget build(BuildContext context) {
    if (receipt.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MoneyRow('Merchandise', receipt['merchandise']),
        for (final offer in mapsOf(receipt['discounts']))
          _MoneyRow(
            '${offer['issuer'] == 'shop'
                ? 'Shop voucher'
                : (amount(offer['shipping_discount']) ?? 0) > 0
                ? 'Bagoo shipping discount'
                : 'Bagoo product discount'} · ${offer['code']}',
            -((amount(offer['product_discount']) ?? 0) +
                (amount(offer['shipping_discount']) ?? 0)),
          ),
        if (receipt['legacy_discount'] == true)
          _MoneyRow(
            'Recorded voucher discount',
            -(amount(receipt['total_savings']) ?? 0),
          ),
        _MoneyRow('Shipping before discounts', receipt['shipping_before']),
        _MoneyRow(
          (amount(receipt['shipping_after']) ?? -1) == 0
              ? 'Free shipping'
              : 'Shipping payable',
          receipt['shipping_after'],
        ),
        _MoneyRow('Total savings', receipt['total_savings']),
        const Divider(),
        _MoneyRow(
          paymentMethod == 'wallet' ? 'Total wallet payment' : 'Total COD',
          receipt['total'],
          total: true,
        ),
      ],
    );
  }
}

class CheckoutDiscounts extends StatelessWidget {
  const CheckoutDiscounts({super.key, required this.quote, this.shopId});
  final Map<String, dynamic> quote;
  final dynamic shopId;

  @override
  Widget build(BuildContext context) {
    final redemptions = mapsOf(quote['redemptions']);
    final offers = quote['vouchers'] is List
        ? mapsOf(quote['vouchers'])
        : quote['voucher'] is Map
        ? [mapOf(quote['voucher'])]
        : <Map<String, dynamic>>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final offer in offers)
          Builder(
            builder: (_) {
              final use = redemptions
                  .where((row) => row['revision_id'] == offer['revision_id'])
                  .firstOrNull;
              final allocation = mapsOf(use?['allocations'])
                  .where((row) => row['shop_id'] == shopId)
                  .firstOrNull;
              final cents = shopId == null
                  ? amount(use?['discount_cents'])
                  : (amount(allocation?['product_discount_cents']) ?? 0) +
                        (amount(allocation?['shipping_discount_cents']) ?? 0);
              if (cents == null || cents <= 0) return const SizedBox.shrink();
              return _MoneyRow(
                '${offer['issuer'] == 'shop'
                    ? 'Shop discount'
                    : offer['discount_type'] == 'free_shipping'
                    ? 'Bagoo shipping discount'
                    : 'Bagoo product discount'} · ${offer['code']}${offer['product_scope'] == 'selected' ? ' · Selected products' : ''}',
                -cents / 100,
              );
            },
          ),
      ],
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow(this.label, this.value, {this.total = false});
  final String label;
  final dynamic value;
  final bool total;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 16,
      runSpacing: 4,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: total ? 15 : 12,
            height: 1.6,
            fontWeight: total ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        Text(
          pesos(value),
          style: TextStyle(
            fontSize: total ? 17 : 13,
            height: 1.6,
            fontWeight: FontWeight.w700,
            color: total ? BagooTheme.strong : null,
          ),
        ),
      ],
    ),
  );
}
