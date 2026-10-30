import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/no_network.dart';
import '../test/voucher_bookmark_misuse_test.dart' as bookmarks;
import '../test/voucher_picker_test.dart' as picker;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = NoNetworkHttpOverrides();
  group('Native voucher bookmarks', bookmarks.main);
  group('Native voucher selection', picker.main);
}
