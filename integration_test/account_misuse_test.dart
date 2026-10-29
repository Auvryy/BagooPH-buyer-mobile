import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/account_settings_misuse_test.dart' as accounts;
import '../test/contact_form_misuse_test.dart' as contacts;
import '../test/numeric_form_misuse_test.dart' as numeric;
import '../test/profile_form_misuse_test.dart' as profile;
import '../test/session_activity_misuse_test.dart' as sessions;
import '../test/support/no_network.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = NoNetworkHttpOverrides();
  group('Native account settings', accounts.main);
  group('Native login activity', sessions.main);
  group('Native contact fields', contacts.main);
  group('Native integer fields', numeric.main);
  group('Native password and credit forms', profile.main);
}
