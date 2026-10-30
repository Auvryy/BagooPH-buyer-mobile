import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/private_document_misuse_test.dart' as documents;
import '../test/return_actions_misuse_test.dart' as actions;
import '../test/return_repayment_misuse_test.dart' as repayments;
import '../test/returns_misuse_test.dart' as returns;
import '../test/support/no_network.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = NoNetworkHttpOverrides();
  group('Native return access and lifecycle', returns.main);
  group('Native return creation and decisions', actions.main);
  group('Native repayment and return navigation', repayments.main);
  group('Native private evidence', documents.main);
}
