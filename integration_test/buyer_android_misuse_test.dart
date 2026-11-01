import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'account_misuse_test.dart' as account;
import 'bag_misuse_test.dart' as bag;
import 'checkout_misuse_test.dart' as checkout;
import 'return_misuse_test.dart' as returns;
import 'private_pdf_misuse_test.dart' as documents;
import 'voucher_misuse_test.dart' as vouchers;
import '../test/buyer_discovery_parity_test.dart' as discovery;
import '../test/buyer_post_purchase_test.dart' as purchases;
import '../test/buyer_links_test.dart' as links;
import '../test/profile_root_misuse_test.dart' as profile_root;
import '../test/bag_product_navigation_test.dart' as bag_navigation;
import '../test/chat_updates_test.dart' as chat;
import '../test/google_auth_widgets_test.dart' as google;
import '../test/notifications_lifecycle_test.dart' as notices;
import '../test/parcel_tracking_page_test.dart' as tracking;
import '../test/support_assistant_test.dart' as support;
import '../test/support/no_network.dart';

// Runs native widgets on the phone with synthetic accounts and blocked network
// requests. Physical provider/permission and deployed-contract checks are separate.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = NoNetworkHttpOverrides();
  group('Android account and addresses', account.main);
  group('Android Bag', bag.main);
  group('Android Bag product navigation', bag_navigation.main);
  group('Android checkout', checkout.main);
  group('Android returns', returns.main);
  group('Android private documents', documents.main);
  group('Android vouchers', vouchers.main);
  group('Android discovery', discovery.main);
  group('Android purchases', purchases.main);
  group('Android incoming links', links.main);
  group('Android profile ownership', profile_root.main);
  group('Android conversation updates', chat.main);
  group('Android Google UI safeguards', google.main);
  group('Android notices', notices.main);
  group('Android tracking', tracking.main);
  group('Android support', support.main);
}
