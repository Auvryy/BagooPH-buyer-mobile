import 'dart:io';

import 'package:bagoo_buyer_mobile/features/checkout/checkout_page.dart';
import 'package:bagoo_buyer_mobile/features/products/product_page.dart';
import 'package:bagoo_buyer_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/collections_misuse_test.dart' as collections;
import '../test/contact_form_misuse_test.dart' as contacts;
import '../test/profile_form_misuse_test.dart' as profile;
import '../test/support/fake_buyer_repository.dart';
import '../test/support/no_network.dart';

Future<void> press(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      220,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
  }
  if (target.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(target.first);
    await tester.pumpAndSettle();
  }
  expect(target.hitTestable(), findsWidgets);
  await tester.tap(target.hitTestable().first);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = NoNetworkHttpOverrides();
  group('Native contact forms', contacts.main);
  group('Native account forms', profile.main);
  group('Native collection lifecycle', collections.main);

  testWidgets(
    'native buyer login and purchase require valid input and review',
    (tester) async {
      final repository = FakeBuyerRepository();
      addTearDown(repository.session.close);
      await tester.pumpWidget(MainApp(repository: repository));
      await press(tester, find.widgetWithText(FilledButton, 'Log In'));
      expect(repository.loginCalls, 0);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'buyer@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'Example!123',
      );
      await press(tester, find.widgetWithText(FilledButton, 'Log In'));
      expect(repository.loginCalls, 1);
      await press(tester, find.text('Everyday bag 1'));
      expect(find.byType(ProductPage), findsOneWidget);
      await press(tester, find.widgetWithText(FilledButton, 'Buy Now'));
      expect(find.byType(CheckoutPage), findsOneWidget);
      expect(repository.orderCalls, 0);
      final phone = find.widgetWithText(
        TextFormField,
        'Philippine mobile number',
      );
      await tester.enterText(phone, '0917');
      await press(tester, find.widgetWithText(FilledButton, 'Review order'));
      expect(find.text('Confirm your order'), findsNothing);
      expect(repository.orderCalls, 0);
      await tester.enterText(phone, '09171234567');
      await press(tester, find.widgetWithText(FilledButton, 'Review order'));
      expect(find.text('Confirm your order'), findsOneWidget);
      expect(repository.orderCalls, 0);
      await press(tester, find.byType(CheckboxListTile).last);
      await press(tester, find.widgetWithText(FilledButton, 'Place order'));
      expect(repository.orderCalls, 1);
      expect(find.text('Order #TEST-1 successfully placed.'), findsOneWidget);
    },
  );
}
