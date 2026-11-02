import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/auth/verification_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';

class RateLimitedCodeRepository extends FakeBuyerRepository {
  int resendCalls = 0;

  @override
  Future<Map<String, dynamic>> sendCode(
    String email,
    String purpose, {
    bool resend = false,
  }) async {
    if (!resend) return {'cooldown': 0};
    resendCalls++;
    throw BackendException(
      'Wait before requesting another code.',
      status: 429,
      data: const {'cooldown': 10},
      retryAt: DateTime.now().toUtc().add(const Duration(seconds: 45)),
    );
  }
}

class RateLimitedVerificationRepository extends FakeBuyerRepository {
  int verifyCalls = 0;

  @override
  Future<String> verifyCode(String email, String purpose, String code) async {
    verifyCalls++;
    throw BackendException(
      'Wait before trying another code.',
      status: 429,
      data: const {'cooldown': 10},
      retryAt: DateTime.now().toUtc().add(const Duration(seconds: 45)),
    );
  }
}

void main() {
  testWidgets('a rate-limited code resend honors Retry-After', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 1100);
    addTearDown(tester.view.reset);
    final repository = RateLimitedCodeRepository();
    addTearDown(repository.session.close);
    await tester.pumpWidget(
      MaterialApp(
        home: VerificationPage(
          repository: repository,
          email: 'buyer@example.test',
          purpose: 'password_reset',
          cooldown: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Resend code'));
    await tester.pumpAndSettle();

    expect(repository.resendCalls, 1);
    expect(find.text('Wait before requesting another code.'), findsOneWidget);
    expect(find.byType(TextButton), findsNWidgets(2));
    expect(find.textContaining('Resend code in '), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byType(TextButton).first).onPressed,
      isNull,
    );
  });

  testWidgets('a rate-limited code verification blocks repeat attempts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 1100);
    addTearDown(tester.view.reset);
    final repository = RateLimitedVerificationRepository();
    addTearDown(repository.session.close);
    await tester.pumpWidget(
      MaterialApp(
        home: VerificationPage(
          repository: repository,
          email: 'buyer@example.test',
          purpose: 'password_reset',
          cooldown: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Verification code'),
      '123456',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Verify email'));
    await tester.pumpAndSettle();

    expect(repository.verifyCalls, 1);
    expect(find.text('Wait before trying another code.'), findsOneWidget);
    expect(find.textContaining('Verify in '), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
}
