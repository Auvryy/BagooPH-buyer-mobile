import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/bag_test.dart' as bag;
import '../test/buyer_post_purchase_test.dart' as payments;
import '../test/checkout_account_misuse_test.dart' as accounts;
import '../test/checkout_logistics_test.dart' as logistics;
import '../test/checkout_navigation_misuse_test.dart' as navigation;
import '../test/checkout_widgets_test.dart' as checkout;
import '../test/location_picker_misuse_test.dart' as locations;
import '../test/product_widgets_test.dart' as products;
import '../test/support/no_network.dart';
import '../test/voucher_picker_test.dart' as vouchers;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = NoNetworkHttpOverrides();
  group('Native checkout account access', accounts.main);
  group('Native checkout navigation', navigation.main);
  group('Native checkout quote and retry', checkout.main);
  group('Native checkout logistics', logistics.main);
  group('Native purchase controls', products.main);
  group('Native shopping Bag', bag.main);
  group('Native payment and purchase replies', payments.main);
  group('Native voucher choices', vouchers.main);
  group('Native location label layout', locations.main);
}
