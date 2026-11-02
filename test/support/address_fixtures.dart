import 'package:bagoo_buyer_mobile/core/web_session.dart';

import 'account_fixtures.dart';

Map<String, dynamic> deliveryAddress({int id = 2, bool isDefault = false}) => {
  'id': id,
  'recipient_name': isDefault ? 'Default recipient' : 'Private recipient',
  'phone': '09171234567',
  'street': '123 Test Street',
  'region': '0400000000',
  'province': 'Laguna',
  'city': 'San Pablo City',
  'barangay': 'San Rafael',
  'postal_code': '4000',
  'landmark': 'Near test school',
  'latitude': 14.0689,
  'longitude': 121.3250,
  'type': 'Home',
  'is_default': isDefault,
};

WebPage addressPage({int owner = 7, bool eligible = true}) {
  final page = accountPage(owner: owner);
  page.props.addAll({
    'canUsePortal': eligible,
    'addressBookLimit': 10,
    'addresses': [deliveryAddress(id: 1, isDefault: true), deliveryAddress()],
  });
  return page;
}

Map<String, dynamic> addressLocationOptions() => {
  'regions': [
    {'value': '0400000000', 'label': 'CALABARZON'},
  ],
  'provinces': [
    {'value': 'Laguna', 'label': 'Laguna'},
  ],
  'cities': [
    {'value': 'San Pablo City', 'label': 'San Pablo City'},
  ],
  'barangays': [
    {'value': 'San Rafael', 'label': 'San Rafael'},
    {'value': 'San Antonio', 'label': 'San Antonio'},
  ],
  'resolved': {
    'region': '0400000000',
    'province': 'Laguna',
    'city': 'San Pablo City',
  },
};
