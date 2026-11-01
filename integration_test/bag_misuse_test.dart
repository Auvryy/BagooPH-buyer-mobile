import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/bag_account_misuse_test.dart' as accounts;
import '../test/bag_dialog_misuse_test.dart' as dialogs;
import '../test/bag_test.dart' as bag;
import '../test/checkout_navigation_misuse_test.dart' as navigation;
import '../test/support/no_network.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = NoNetworkHttpOverrides();
  group('Bag session and mutation safeguards', accounts.main);
  group('Native Bag dialogs and lifecycle', dialogs.main);
  group('Native Bag stock and layout', bag.main);
  group('Native checkout entry', navigation.main);
}
