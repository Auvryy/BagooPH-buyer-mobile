import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/auth/recovery_page.dart';
import 'package:bagoo_buyer_mobile/features/auth/register_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';
import 'support/widget_helpers.dart';

class RateLimitedCodeRepository extends FakeBuyerRepository {
  @override
  Future<Map<String, dynamic>> sendCode(
    String email,
    String purpose, {
    bool resend = false,
  }) async {
    sendCalls++;
    throw BackendException(
      'Wait before requesting another code.',
      status: 429,
      data: const {'cooldown': 10},
      retryAt: DateTime.now().toUtc().add(const Duration(seconds: 45)),
    );
  }
}

class SuccessfulCodeRepository extends FakeBuyerRepository {
  @override
  Future<Map<String, dynamic>> sendCode(
    String email,
    String purpose, {
    bool resend = false,
  }) async {
    sendCalls++;
    return {'success': true, 'cooldown': 60};
  }
}

class RateLimitedResetPasswordRepository extends FakeBuyerRepository {
  @override
  Future<Map<String, dynamic>> sendCode(
    String email,
    String purpose, {
    bool resend = false,
  }) async {
    sendCalls++;
    return {'success': true, 'cooldown': 60};
  }

  @override
  Future<String> verifyCode(String email, String purpose, String code) async =>
      'verified-reset-token';

  @override
  Future<void> resetPassword(
    String email,
    String token,
    String password,
    String confirmation,
  ) async {
    resetCalls++;
    throw BackendException(
      'Wait before saving another password reset.',
      status: 429,
      data: const {'cooldown': 10},
      retryAt: DateTime.now().toUtc().add(const Duration(seconds: 45)),
    );
  }
}

class RateLimitedRegistrationRepository extends FakeBuyerRepository {
  @override
  Future<Map<String, dynamic>> sendCode(
    String email,
    String purpose, {
    bool resend = false,
  }) async {
    sendCalls++;
    return {'success': true, 'cooldown': 60};
  }

  @override
  Future<String> verifyCode(String email, String purpose, String code) async =>
      'verified-registration-token';

  @override
  Future<WebPage> register(
    Map<String, dynamic> values,
    String token, {
    List<UploadPart>? files,
  }) async {
    registerCalls++;
    throw BackendException(
      'Wait before submitting this registration again.',
      status: 429,
      data: const {'cooldown': 10},
      retryAt: DateTime.now().toUtc().add(const Duration(seconds: 45)),
    );
  }
}

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> openRegistrationReview(WidgetTester tester) async {
  await tester.enterText(field('First name'), 'Test');
  await tester.enterText(field('Last name'), 'Buyer');
  await press(tester, find.byType(DropdownButtonFormField<String>));
  await press(tester, find.text('Other').last);
  await tester.enterText(field('Email address'), 'buyer@example.test');
  await tester.enterText(field('Password'), 'Password!123');
  await tester.enterText(field('Confirm password'), 'Password!123');
  await press(tester, find.widgetWithText(FilledButton, 'Continue'));
  await press(tester, field('Birth date'));
  await press(tester, find.text('OK'));
  await press(tester, find.byType(CheckboxListTile));
}

void main() {
  testWidgets('password recovery honors a rate-limited initial code request', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 1100);
    addTearDown(tester.view.reset);
    final repository = RateLimitedCodeRepository();
    addTearDown(repository.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: RecoveryPage(
          repository: repository,
          onBack: () {},
          onBrowse: () {},
          onComplete: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      field('Registered email address'),
      'buyer@example.test',
    );
    await press(
      tester,
      find.widgetWithText(FilledButton, 'Send verification code'),
    );

    expect(repository.sendCalls, 1);
    expect(find.text('Wait before requesting another code.'), findsOneWidget);
    expect(find.textContaining('Send code in '), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('registration honors a rate-limited initial code request', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 1200);
    addTearDown(tester.view.reset);
    final repository = RateLimitedCodeRepository();
    addTearDown(repository.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: RegisterPage(
          repository: repository,
          onBack: () {},
          onBrowse: () {},
          onComplete: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openRegistrationReview(tester);
    await press(
      tester,
      find.widgetWithText(FilledButton, 'Verify email & create account'),
    );

    expect(repository.sendCalls, 1);
    expect(find.text('Wait before requesting another code.'), findsOneWidget);
    expect(find.textContaining('Send code in '), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
      isNull,
    );
  });

  testWidgets(
    'recovery keeps the code cooldown when verification is cancelled',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 1100);
      addTearDown(tester.view.reset);
      final repository = SuccessfulCodeRepository();
      addTearDown(repository.session.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: RecoveryPage(
            repository: repository,
            onBack: () {},
            onBrowse: () {},
            onComplete: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        field('Registered email address'),
        'buyer@example.test',
      );
      await press(
        tester,
        find.widgetWithText(FilledButton, 'Send verification code'),
      );
      await press(tester, find.text('Use a different email'));

      expect(repository.sendCalls, 1);
      expect(find.textContaining('Send code in '), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'registration keeps the code cooldown when verification is cancelled',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 1200);
      addTearDown(tester.view.reset);
      final repository = SuccessfulCodeRepository();
      addTearDown(repository.session.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: RegisterPage(
            repository: repository,
            onBack: () {},
            onBrowse: () {},
            onComplete: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openRegistrationReview(tester);
      await press(
        tester,
        find.widgetWithText(FilledButton, 'Verify email & create account'),
      );
      await press(tester, find.text('Use a different email'));

      expect(repository.sendCalls, 1);
      expect(find.textContaining('Send code in '), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
        isNull,
      );
    },
  );

  testWidgets('password reset honors Retry-After after code verification', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 1100);
    addTearDown(tester.view.reset);
    final repository = RateLimitedResetPasswordRepository();
    addTearDown(repository.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: RecoveryPage(
          repository: repository,
          onBack: () {},
          onBrowse: () {},
          onComplete: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      field('Registered email address'),
      'buyer@example.test',
    );
    await press(
      tester,
      find.widgetWithText(FilledButton, 'Send verification code'),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Verification code'),
      '123456',
    );
    await press(tester, find.widgetWithText(FilledButton, 'Verify email'));
    await tester.enterText(field('New password'), 'Password!123');
    await tester.enterText(field('Confirm new password'), 'Password!123');
    await press(tester, find.widgetWithText(FilledButton, 'Save new password'));

    expect(repository.resetCalls, 1);
    expect(
      find.text('Wait before saving another password reset.'),
      findsOneWidget,
    );
    expect(find.textContaining('Try again in '), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('registration honors Retry-After after the code is verified', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 1200);
    addTearDown(tester.view.reset);
    final repository = RateLimitedRegistrationRepository();
    addTearDown(repository.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: RegisterPage(
          repository: repository,
          onBack: () {},
          onBrowse: () {},
          onComplete: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openRegistrationReview(tester);
    await press(
      tester,
      find.widgetWithText(FilledButton, 'Verify email & create account'),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Verification code'),
      '123456',
    );
    await press(tester, find.widgetWithText(FilledButton, 'Verify email'));

    expect(repository.registerCalls, 1);
    expect(
      find.text('Wait before submitting this registration again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Try again in '), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
      isNull,
    );
  });
}
