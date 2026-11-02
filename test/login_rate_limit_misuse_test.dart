import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/auth/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';
import 'support/fake_google_identity.dart';
import 'support/widget_helpers.dart';

class RateLimitedLoginRepository extends FakeBuyerRepository {
  @override
  Future<WebPage> login(
    String email,
    String password, {
    bool remember = false,
  }) async {
    loginCalls++;
    throw BackendException(
      'Wait before trying to sign in again.',
      status: 429,
      data: const {'cooldown': 10},
      retryAt: DateTime.now().toUtc().add(const Duration(seconds: 45)),
    );
  }
}

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  testWidgets('email login honors Retry-After after a rate limit', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 1100);
    addTearDown(tester.view.reset);
    final repository = RateLimitedLoginRepository();
    addTearDown(repository.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: LoginPage(
          repository: repository,
          googleProvider: FakeGoogleIdentity(isAvailable: false),
          onAuthenticated: (_) {},
          onRegister: () {},
          onForgot: () {},
          onBrowse: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(field('Email address'), 'buyer@example.test');
    await tester.enterText(field('Password'), 'incorrect password');
    await press(tester, find.widgetWithText(FilledButton, 'Log In'));

    expect(repository.loginCalls, 1);
    expect(find.text('Wait before trying to sign in again.'), findsOneWidget);
    expect(find.textContaining('Try again in '), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
}
