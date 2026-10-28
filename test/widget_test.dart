import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';

Future<void> press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Finder input(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
Finder field(String label) =>
    find.descendant(of: input(label), matching: find.byType(EditableText));

void main() {
  late FakeBuyerRepository repository;
  setUp(() => repository = FakeBuyerRepository());
  tearDown(() => repository.session.close());

  testWidgets(
    'requires valid login fields and preserves rejected credentials',
    (tester) async {
      await tester.pumpWidget(MainApp(repository: repository));
      await press(tester, find.widgetWithText(FilledButton, 'Log In'));
      expect(repository.loginCalls, 0);
      expect(find.text('Enter your email address.'), findsOneWidget);
      repository.loginError = const BackendException(
        'Please check the highlighted fields.',
        fields: {'email': 'Buyer credentials rejected.'},
      );
      await tester.enterText(field('Email address'), 'buyer@example.test');
      await tester.enterText(field('Password'), 'invalid');
      await press(tester, find.widgetWithText(FilledButton, 'Log In'));
      expect(
        find.descendant(
          of: input('Email address'),
          matching: find.text('Buyer credentials rejected.'),
        ),
        findsOneWidget,
      );
      expect(find.text('invalid'), findsOneWidget);
      expect(find.text('Recommended for you'), findsNothing);
    },
  );

  testWidgets(
    'successful login opens real feed state and logout returns to login',
    (tester) async {
      await tester.pumpWidget(MainApp(repository: repository));
      await tester.enterText(field('Email address'), 'buyer@example.test');
      await tester.enterText(field('Password'), 'Password!123');
      await press(tester, find.widgetWithText(FilledButton, 'Log In'));
      expect(repository.loginCalls, 1);
      expect(find.text('Recommended for you'), findsOneWidget);
      await press(tester, find.text('Profile'));
      expect(find.text('Test Buyer'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Log out'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await press(tester, find.text('Log out'));
      expect(find.text('You have been logged out.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Log In'), findsOneWidget);
    },
  );

  testWidgets(
    'guest browsing submits search and department selection to backend',
    (tester) async {
      await tester.pumpWidget(MainApp(repository: repository));
      await press(tester, find.text('Browse the marketplace'));
      await tester.enterText(find.byType(TextField).first, 'tea & coffee');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(repository.searchRequests.last['search'], 'tea & coffee');
      expect(input('Search the marketplace'), findsOneWidget);
      await press(tester, find.text('Filters'));
      final departments = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Departments',
      );
      await tester.ensureVisible(departments);
      await tester.pumpAndSettle();
      await tester.tap(departments);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Electronics and Gadgets').last);
      await tester.pumpAndSettle();
      final apply = find.widgetWithText(FilledButton, 'Apply filters');
      await tester.ensureVisible(apply);
      await tester.pumpAndSettle();
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(repository.searchRequests.last['category'], 'electronics');
      expect(repository.searchRequests.last['search'], 'tea & coffee');
    },
  );

  testWidgets(
    'registration validates both steps and requires a server-issued email token',
    (tester) async {
      await tester.pumpWidget(MainApp(repository: repository));
      await press(tester, find.text('Sign Up'));
      await tester.enterText(field('First name'), 'Test');
      await tester.enterText(field('Last name'), 'Buyer');
      await press(tester, find.byType(DropdownButtonFormField<String>));
      await press(tester, find.text('Other').last);
      await tester.enterText(field('Email address'), 'buyer@example.test');
      await tester.enterText(field('Password'), 'Password!123');
      await tester.enterText(field('Confirm password'), 'Password!123');
      await press(tester, find.widgetWithText(FilledButton, 'Continue'));
      expect(repository.validationCalls, 1);
      await press(tester, input('Birth date'));
      await press(tester, find.text('OK'));
      await press(tester, find.byType(CheckboxListTile));
      await press(
        tester,
        find.widgetWithText(FilledButton, 'Verify email & create account'),
      );
      expect(repository.sendCalls, 1);
      expect(repository.registerCalls, 0);
      await tester.enterText(field('Verification code'), '000000');
      await press(tester, find.widgetWithText(FilledButton, 'Verify email'));
      expect(find.text('Incorrect code.'), findsOneWidget);
      expect(repository.registerCalls, 0);
      await tester.enterText(field('Verification code'), '123456');
      await press(tester, find.widgetWithText(FilledButton, 'Verify email'));
      expect(repository.registerCalls, 1);
      expect(find.text('Recommended for you'), findsOneWidget);
    },
  );

  testWidgets(
    'password recovery verifies email before allowing password change',
    (tester) async {
      await tester.pumpWidget(MainApp(repository: repository));
      await press(tester, find.text('Forgot password?'));
      await tester.enterText(
        field('Registered email address'),
        'buyer@example.test',
      );
      await press(
        tester,
        find.widgetWithText(FilledButton, 'Send verification code'),
      );
      expect(repository.resetCalls, 0);
      await tester.enterText(field('Verification code'), '123456');
      await press(tester, find.widgetWithText(FilledButton, 'Verify email'));
      await tester.enterText(field('New password'), 'Password!123');
      await tester.enterText(field('Confirm new password'), 'Password!123');
      await press(
        tester,
        find.widgetWithText(FilledButton, 'Save new password'),
      );
      expect(repository.resetCalls, 1);
      expect(
        find.text(
          'Password reset successfully. Please log in with your new password.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('keyboard and reduced motion keep auth usable', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    });
    await tester.pumpWidget(MainApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.ensureVisible(field('Password'));
    await tester.tap(field('Password'));
    await tester.enterText(field('Password'), 'Password!123');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.widgetWithText(FilledButton, 'Log In')).width,
      greaterThan(48),
    );
  });

  testWidgets('restricted login retains the server account-status page', (
    tester,
  ) async {
    final restricted = _RestrictedRepository();
    addTearDown(restricted.session.close);
    await tester.pumpWidget(MainApp(repository: restricted));
    await tester.enterText(field('Email address'), 'buyer@example.test');
    await tester.enterText(field('Password'), 'Password!123');
    await press(tester, find.widgetWithText(FilledButton, 'Log In'));
    expect(find.text('Your account needs review.'), findsOneWidget);
    expect(restricted.homeRequests, isEmpty);
  });

  for (final scenario in [
    (size: const Size(320, 640), scale: 1.0),
    (size: const Size(375, 812), scale: 1.0),
    (size: const Size(812, 375), scale: 1.0),
    (size: const Size(1024, 768), scale: 1.0),
    (size: const Size(375, 812), scale: 2.0),
    (size: const Size(1024, 768), scale: 2.0),
  ]) {
    testWidgets(
      'auth and marketplace reflow at ${scenario.size}, text ${scenario.scale}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = scenario.size;
        tester.platformDispatcher.textScaleFactorTestValue = scenario.scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        await tester.pumpWidget(MainApp(repository: repository));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await press(tester, find.text('Sign Up'));
        expect(tester.takeException(), isNull);
        await press(tester, find.text('Back to log in'));
        await press(tester, find.text('Browse the marketplace'));
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _RestrictedRepository extends FakeBuyerRepository {
  _RestrictedRepository() {
    (session as FakeSession).profileResponse = const WebPage(
      'Auth/AccountStatus',
      {
        'auth': {'user': buyer},
        'status': {'message': 'Your account needs review.'},
      },
    );
  }
  @override
  Future<WebPage> login(
    String email,
    String password, {
    bool remember = false,
  }) async => const WebPage('Auth/AccountStatus', {
    'auth': {'user': buyer},
    'status': {'message': 'Your account needs review.'},
  });
}
