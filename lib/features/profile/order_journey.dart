import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/web_session.dart';
import '../products/product_widgets.dart';

const _packing = [
  'confirmed',
  'preparing',
  'seller_pack',
  'ready_for_pickup',
  'handover_fulfillment_confirmed',
];
const _shipped = [
  'courier_pickup',
  'picked_up',
  'handover_holder_acknowledged',
  'arrived_at_origin_hub',
  'in_transit_to_mother_hub',
  'arrived_at_mother_hub',
  'sorted_to_line_haul',
  'in_transit_to_destination_hub',
  'arrived_at_destination_hub',
  'sorted_to_barangay_bin',
  'assigned_to_rider',
  'out_for_delivery',
  'ready_for_hub_pickup',
];
const _handover = ['delivered', 'doorstep_handover', 'customer_collected'];
const _receipt = [
  'completed',
  'buyer_confirmed',
  'buyer_completed',
  'delivery_completed',
];

List<Map<String, dynamic>> _history(Map<String, dynamic> tracking) {
  final seen = <dynamic>{};
  final history = mapsOf(tracking['history'])
      .where((event) => event['id'] == null || seen.add(event['id']))
      .toList();
  history.sort(
    (a, b) => _time(a['created_at']).compareTo(_time(b['created_at'])),
  );
  return history;
}

int _time(dynamic value) =>
    DateTime.tryParse(value?.toString() ?? '')?.millisecondsSinceEpoch ??
    8640000000000000;

List<Map<String, dynamic>> buyerJourneyEntries(
  Map<String, dynamic> tracking,
  List<Map<String, dynamic>> notices,
) {
  final entries = [
    for (final event in _history(tracking))
      <String, dynamic>{
        'checkpoint': event,
        'label': event['label'],
        'location': event['location'],
        'created_at': event['created_at'],
        'notices': <Map<String, dynamic>>[],
      },
  ];
  final seen = <dynamic>{};
  for (final notice in notices) {
    if (notice['id'] is! String || !seen.add(notice['id'])) continue;
    var target = notice['checkpoint_id'] == null
        ? null
        : entries
              .where(
                (entry) =>
                    mapOf(entry['checkpoint'])['id'] == notice['checkpoint_id'],
              )
              .firstOrNull;
    if (target == null &&
        notice['type'] == 'order-event' &&
        notice['milestone'] != null) {
      final types =
          {
            'placed': ['placed', 'order_placed'],
            'preparing': ['preparing', 'seller_pack'],
            'completed': _receipt,
          }[notice['milestone']] ??
          [notice['milestone']];
      final candidates = entries
          .where((entry) => types.contains(mapOf(entry['checkpoint'])['type']))
          .toList();
      if (candidates.length == 1) target = candidates.single;
    }
    if (target != null) {
      (target['notices'] as List<Map<String, dynamic>>).add(notice);
    } else {
      entries.add({
        'checkpoint': null,
        'label': mapOf(notice['data'])['title'],
        'created_at': notice['created_at'],
        'notices': [notice],
      });
    }
  }
  entries.sort(
    (a, b) => _time(a['created_at']).compareTo(_time(b['created_at'])),
  );
  return entries;
}

List<({String label, bool recorded, bool current, bool complete, bool missing})>
buyerMilestones(Map<String, dynamic> tracking, Map<String, dynamic> order) {
  final history = _history(tracking);
  bool has(List<String> types) =>
      history.any((event) => types.contains(event['type']));
  final status = tracking['commercial_status'];
  final parcel = tracking['parcel_status'];
  final items = mapsOf(order['items']);
  final reviewed =
      status == 'completed' &&
      items.isNotEmpty &&
      items.every((item) => item['review'] is Map);
  final recorded = [
    DateTime.tryParse(
              (tracking['placed_at'] ?? order['created_at'])?.toString() ?? '',
            ) !=
            null ||
        has(['placed', 'order_placed']),
    has(_packing),
    has(_shipped),
    has(_handover),
    reviewed,
  ];
  final exception =
      ['cancelled', 'returned', 'delivery_failed'].contains(status) ||
      [
        'cancelled',
        'returned',
        'return_to_sender',
        'return_in_transit',
        'failed',
        'delivery_failed',
      ].contains(parcel);
  var current = exception
      ? -1
      : status == 'completed'
      ? reviewed
            ? -1
            : 4
      : status == 'delivered' ||
            ['delivered', 'customer_collected'].contains(parcel)
      ? 3
      : [
              'picked_up',
              'at_sorting_center',
              'sorted',
              'assigned_to_rider',
              'out_for_delivery',
              'shipped',
              'in_transit',
            ].contains(status) ||
            _shipped.contains(parcel)
      ? 2
      : [
              'confirmed',
              'preparing',
              'ready_for_pickup',
              'processing',
              'packaging',
            ].contains(status) ||
            ['assigned', 'assigned_pickup'].contains(parcel)
      ? 1
      : ['placed', 'pending'].contains(status)
      ? 0
      : -1;
  if (current == -1 && !exception && status != 'completed') {
    current = recorded.lastIndexOf(true);
  }
  final labels = [
    'Order placed',
    'Confirmed',
    'Shipped out',
    'Order received',
    reviewed ? 'Review saved' : 'Rate & review',
  ];
  return [
    for (var i = 0; i < labels.length; i++)
      (
        label: labels[i],
        recorded: recorded[i],
        current: current == i,
        complete:
            recorded[i] &&
            (i == 4
                ? reviewed
                : i == 3
                ? has(_receipt)
                : i < current || current == -1),
        missing: !recorded[i] && (current > i || status == 'completed'),
      ),
  ];
}

class OrderJourney extends StatelessWidget {
  const OrderJourney({
    super.key,
    required this.order,
    required this.notices,
    required this.onRead,
    this.busy = false,
  });
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> notices;
  final ValueChanged<String> onRead;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final tracking = mapOf(order['tracking']);
    final entries = buyerJourneyEntries(tracking, notices);
    final unread = notices
        .where((notice) => notice['read_at'] == null)
        .map((notice) => notice['id'])
        .toSet()
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProductHeading('Order milestones'),
        Wrap(
          spacing: 8,
          runSpacing: 12,
          children: [
            for (final step in buyerMilestones(tracking, order))
              Semantics(
                label:
                    '${step.label}: ${step.current
                        ? 'Current'
                        : step.missing
                        ? 'Not recorded'
                        : step.complete
                        ? 'Completed'
                        : 'Upcoming'}',
                child: Chip(
                  avatar: Icon(
                    step.complete
                        ? Icons.check_circle_outline
                        : step.current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: step.current
                        ? const Color(0xFF92400E)
                        : BagooTheme.strong,
                  ),
                  label: Text(
                    '${step.label}${step.missing
                        ? ' · Not recorded'
                        : step.current
                        ? ' · Current'
                        : ''}',
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Last checked: ${readableDateTime(tracking['observed_at'])}\nHolder recorded: ${readableDateTime(tracking['custody_recorded_at'])}',
          style: const TextStyle(fontSize: 12, height: 1.7),
        ),
        const Divider(height: 32),
        ProductHeading(
          'Parcel journey and updates${unread > 0 ? ' · $unread unread' : ''}',
        ),
        if (entries.isEmpty)
          const Text('No checkpoints or order updates are recorded yet.'),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry['label']?.toString() ?? 'Recorded update',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    height: 1.7,
                  ),
                ),
                if (entry['location'] != null)
                  Text(entry['location'].toString()),
                Text(
                  readableDateTime(entry['created_at']),
                  style: const TextStyle(fontSize: 12, height: 1.7),
                ),
                for (final notice in mapsOf(entry['notices'])) ...[
                  if (entry['checkpoint'] == null &&
                      mapOf(notice['data'])['body'] is String)
                    Text(
                      mapOf(notice['data'])['body'],
                      style: const TextStyle(height: 1.7),
                    ),
                  if (notice['read_at'] == null)
                    TextButton(
                      onPressed: busy ? null : () => onRead(notice['id']),
                      child: const Text('Mark update read'),
                    )
                  else
                    Text(
                      'Read ${readableDateTime(notice['read_at'])}',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
