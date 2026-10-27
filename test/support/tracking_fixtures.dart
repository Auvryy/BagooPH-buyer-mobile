import 'package:bagoo_buyer_mobile/core/web_session.dart';

Map<String, dynamic> publicTrackingProps({
  String number = 'BAGOO-1',
  String status = 'delivered',
  bool notFound = false,
  String observedAt = '2026-10-27T08:30:00Z',
}) => {
  'searchedNumber': number,
  'notFound': notFound,
  'validationMessage': null,
  'observedAt': observedAt,
  'statusLabels': {
    'delivered': 'Delivered · awaiting buyer confirmation',
    'completed': 'Buyer confirmed receipt',
    'delivery_failed': 'Delivery issue',
  },
  'checkpointLabels': {
    'courier_pickup': 'Collected from seller',
    'delivered': 'Doorstep handover recorded',
  },
  'availableActions': ['unrelated_action'],
  'private_note': 'HIDDEN PRIVATE NOTE',
  'parcel': notFound
      ? null
      : <String, dynamic>{
          'tracking_number': number,
          'status': status,
          'order_status': status,
          'delivery_recipient_name': 'B*** T***',
          'delivery_phone': '*** *** 1234',
          'delivery_address': 'Protected location, Test city, Test province',
          'estimated_delivery_at': '2026-10-28T02:00:00Z',
          'delivered_at': '2026-10-27T08:00:00Z',
          'full_address': 'HIDDEN FULL ADDRESS',
          'buyer_email': 'hidden@example.test',
          'checkpoints': [
            {
              'checkpoint_type': 'courier_pickup',
              'location_name': 'Seller pickup',
              'created_at': '2026-10-26T02:00:00Z',
            },
            {
              'checkpoint_type': 'delivered',
              'location_name': 'Recipient handoff',
              'created_at': '2026-10-27T08:00:00Z',
            },
          ],
        },
};

WebPage publicTrackingPage({
  String number = 'BAGOO-1',
  String status = 'delivered',
  bool notFound = false,
  String observedAt = '2026-10-27T08:30:00Z',
}) => WebPage(
  'Public/Tracking',
  publicTrackingProps(
    number: number,
    status: status,
    notFound: notFound,
    observedAt: observedAt,
  ),
);
