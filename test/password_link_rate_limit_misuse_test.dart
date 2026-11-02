import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/auth/password_link_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';
import 'support/widget_helpers.dart';

class RateLimitedPasswordLinkRepository extends FakeBuyerRepository {
  int linkRequests = 0;
  int resetRequests = 0;

  BackendException get rateLimit => BackendException(
    'Wait before trying this password recovery action again.',
    status: 429,
    data: const {'cooldown': 10},
    retryAt: DateTime.now().toUtc().add(const Duration(seconds: 45)),
  );

  @override
  Future<void> sendPasswordLink(String email) async {
    linkRequests++;
    throw rateLimit;
  }

  @override
  Future<void> resetPasswordLink(
    String email,
    String token,
    String password,
    String confirmation,
  ) async {
    resetRequests++;
    throw rateLimit;
  }
}

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  testWidgets('password-link email request honors Retry-After', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 1100);
    addTearDown(tester.view.reset);
    final repository = RateLimitedPasswordLinkRepository();
    addTearDown(repository.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: PasswordLinkPage(repository: repository, onComplete: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      field('Recovery email address'),
      'buyer@example.test',
    );
    await press(
      tester,
      find.widgetWithText(FilledButton, 'Send password reset link'),
    );

    expect(repository.linkRequests, 1);
    expect(
      find.text('Wait before trying this password recovery action again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Try again in '), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('password-link submission honors Retry-After', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 1100);
    addTearDown(tester.view.reset);
    final repository = RateLimitedPasswordLinkRepository();
    addTearDown(repository.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: PasswordLinkPage(
          repository: repository,
          initialLink: Uri.parse(
            'http://backend.test/reset-password/test-reset-token-123456?email=buyer%40example.test&role=buyer',
          ),
          onComplete: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(field('New password'), 'Password!123');
    await tester.enterText(field('Confirm new password'), 'Password!123');
    await press(tester, find.widgetWithText(FilledButton, 'Save new password'));

    expect(repository.resetRequests, 1);
    expect(
      find.text('Wait before trying this password recovery action again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Try again in '), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
}
