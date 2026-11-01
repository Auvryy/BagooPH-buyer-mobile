import 'package:bagoo_buyer_mobile/features/auth/login_page.dart';
import 'package:bagoo_buyer_mobile/features/checkout/bag_page.dart';
import 'package:bagoo_buyer_mobile/features/home/home_page.dart';
import 'package:bagoo_buyer_mobile/features/home/search_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_page.dart';
import 'package:bagoo_buyer_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Explicitly opt in with an approved seeded buyer. No order, payment, message,
// email, registration or account-setting mutation is part of this smoke run.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('BAGOO_DEVICE_LIVE_ACCEPTANCE');
  const email = String.fromEnvironment('BAGOO_TEST_BUYER_EMAIL');
  const password = String.fromEnvironment('BAGOO_TEST_BUYER_PASSWORD');

  testWidgets('physical phone guest navigation and seeded buyer login', (
    tester,
  ) async {
    expect(email, isNotEmpty, reason: 'Supply the approved test buyer.');
    expect(password, isNotEmpty, reason: 'Supply the approved test password.');

    Future<void> waitFor(Finder target) async {
      final limit = DateTime.now().add(const Duration(seconds: 60));
      while (target.evaluate().isEmpty && DateTime.now().isBefore(limit)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(target, findsWidgets);
    }

    Future<void> tap(Finder target) async {
      await waitFor(target);
      await tester.ensureVisible(target.first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(target.hitTestable().first);
      await tester.pump(const Duration(milliseconds: 500));
    }

    await tester.pumpWidget(const MainApp());
    await waitFor(find.byType(LoginPage));
    debugPrint('DEVICE CHECK: login screen ready');
    await tap(find.text('Browse the marketplace'));
    await waitFor(find.byType(HomePage));
    debugPrint('DEVICE CHECK: guest home ready');
    await tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Search'),
      ),
    );
    await waitFor(find.byType(SearchPage));
    debugPrint('DEVICE CHECK: search opened');
    await tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Bag'),
      ),
    );
    await waitFor(find.byType(BagPage));
    debugPrint('DEVICE CHECK: Bag opened');
    await tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Profile'),
      ),
    );
    await waitFor(find.byType(ProfilePage));
    debugPrint('DEVICE CHECK: profile opened');
    await tap(find.text('Log In'));
    await waitFor(find.byType(LoginPage));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email address'),
      email,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      password,
    );
    debugPrint('DEVICE CHECK: submitting approved seeded login');
    await tap(find.widgetWithText(FilledButton, 'Log In'));
    await waitFor(find.byType(HomePage));
    await tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Profile'),
      ),
    );
    await waitFor(find.byType(ProfilePage));
    debugPrint('DEVICE CHECK: profile opened');
    expect(
      tester.widget<ProfilePage>(find.byType(ProfilePage)).user?['email'],
      email,
    );
    expect(tester.takeException(), isNull);
  }, skip: !enabled);
}
