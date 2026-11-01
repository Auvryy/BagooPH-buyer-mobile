import 'dart:convert';

import 'package:bagoo_buyer_mobile/core/web_session.dart';

import 'fake_buyer_repository.dart';

String checkoutToken({int version = 2}) => checkoutFixtureToken(version);

WebPage ownedCheckout({int owner = 7}) {
  final props =
      jsonDecode(jsonEncode(checkoutPage().props)) as Map<String, dynamic>;
  props['checkoutToken'] = checkoutToken();
  (props['auth'] as Map)['user']['id'] = owner;
  (props['user'] as Map)['id'] = owner;
  return WebPage('Checkout/Index', props);
}

Map<String, dynamic> confirmedQuote() => {
  'success': true,
  'quote': checkoutPage().props['quote'],
  'availableVouchers': <Map<String, dynamic>>[],
};

WebPage ownedOrderResult({int owner = 7}) => WebPage('Buyer/Profile', {
  'auth': {
    'user': {...buyer, 'id': owner},
  },
  'user': {...buyer, 'id': owner},
  'flash': {'success': 'Order PRIVATE-41 recorded.'},
  'orders': {'data': <Map<String, dynamic>>[]},
});
