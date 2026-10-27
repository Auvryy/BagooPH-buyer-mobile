import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';

String normalizeTrackingNumber(String value) {
  final number = value.trim();
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$').hasMatch(number)) {
    throw const BackendException(
      'Check the tracking number.',
      fields: {
        'number': 'Enter 1–64 letters, numbers, hyphens, or underscores, starting with a letter or number.',
      },
    );
  }
  return number.toUpperCase();
}

DateTime? _instant(Object? value) {
  if (value is! String ||
      !RegExp(r'(Z|[+-]\d{2}:\d{2})$', caseSensitive: false).hasMatch(value)) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

String trackingTime(DateTime? instant, {String missing = 'Not recorded'}) {
  if (instant == null) return missing;
  final time = instant.toUtc().add(const Duration(hours: 8));
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final day = time.day;
  final month = months[time.month - 1];
  final year = time.year;
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final period = time.hour < 12 ? 'AM' : 'PM';
  return '$day $month $year, $hour:$minute $period';
}

class TrackingMilestone {
  const TrackingMilestone({
    required this.label,
    required this.location,
    required this.recordedAt,
  });

  final String label;
  final String location;
  final DateTime? recordedAt;
}

class PublicParcel {
  const PublicParcel({
    required this.number,
    required this.status,
    required this.statusLabel,
    required this.deliveryArea,
    required this.recipientName,
    required this.recipientPhone,
    required this.estimatedDeliveryAt,
    required this.deliveredAt,
    required this.milestones,
  });

  final String number;
  final String status;
  final String statusLabel;
  final String deliveryArea;
  final String recipientName;
  final String recipientPhone;
  final DateTime? estimatedDeliveryAt;
  final DateTime? deliveredAt;
  final List<TrackingMilestone> milestones;
}

class TrackingLookup {
  const TrackingLookup({
    required this.number,
    required this.observedAt,
    required this.parcel,
  });

  final String number;
  final DateTime? observedAt;
  final PublicParcel? parcel;
}

class TrackingRepository {
  TrackingRepository(this.buyer);

  final BuyerRepository buyer;
  static const _unconfirmed = BackendException(
    'The tracking details could not be confirmed. Please try again.',
  );

  Future<TrackingLookup> lookup(String input) async {
    final number = normalizeTrackingNumber(input);
    final path = Uri(
      path: '/track',
      queryParameters: {'number': number},
    ).toString();
    final page = await buyer.document(path);
    buyer.requireNoErrors(page);
    final props = page.props;
    if (page.component != 'Public/Tracking' ||
        props['searchedNumber'] != number ||
        props['notFound'] is! bool ||
        props['statusLabels'] is! Map ||
        props['checkpointLabels'] is! Map) {
      throw _unconfirmed;
    }
    final validation = props['validationMessage'];
    if (validation != null) {
      if (validation is! String || validation.trim().isEmpty) {
        throw _unconfirmed;
      }
      throw BackendException(validation, fields: {'number': validation});
    }
    final observedAt = _instant(props['observedAt']);
    if (props['notFound'] == true) {
      if (props['parcel'] != null) throw _unconfirmed;
      return TrackingLookup(
        number: number,
        observedAt: observedAt,
        parcel: null,
      );
    }
    if (props['parcel'] is! Map) throw _unconfirmed;
    final parcel = mapOf(props['parcel']);
    final status = parcel['status'];
    if (parcel['tracking_number'] != number ||
        status is! String ||
        status.trim().isEmpty ||
        parcel['checkpoints'] is! List) {
      throw _unconfirmed;
    }
    final statusLabels = mapOf(props['statusLabels']);
    final checkpointLabels = mapOf(props['checkpointLabels']);
    final milestones = <TrackingMilestone>[];
    for (final item in parcel['checkpoints'] as List) {
      if (item is! Map) throw _unconfirmed;
      final checkpoint = mapOf(item);
      if (checkpoint['checkpoint_type'] is! String ||
          checkpoint['location_name'] is! String ||
          checkpoint['created_at'] is! String) {
        throw _unconfirmed;
      }
      milestones.add(
        TrackingMilestone(
          label: _text(
            checkpointLabels[checkpoint['checkpoint_type']],
            'Parcel milestone',
          ),
          location: checkpoint['location_name'] as String,
          recordedAt: _instant(checkpoint['created_at']),
        ),
      );
    }
    return TrackingLookup(
      number: number,
      observedAt: observedAt,
      parcel: PublicParcel(
        number: number,
        status: status,
        statusLabel: _text(statusLabels[status], 'Status recorded'),
        deliveryArea: _text(
          parcel['delivery_address'],
          'Delivery area protected',
        ),
        recipientName: _text(
          parcel['delivery_recipient_name'],
          'Recipient protected',
        ),
        recipientPhone: _text(parcel['delivery_phone'], 'Phone protected'),
        estimatedDeliveryAt: _instant(parcel['estimated_delivery_at']),
        deliveredAt: _instant(parcel['delivered_at']),
        milestones: List.unmodifiable(milestones.reversed),
      ),
    );
  }

  String _text(Object? value, String fallback) =>
      value is String && value.trim().isNotEmpty ? value.trim() : fallback;
}
