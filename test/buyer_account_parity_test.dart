import 'dart:async';
import 'dart:typed_data';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/auth/register_page.dart';
import 'package:bagoo_buyer_mobile/features/auth/password_link_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/account_status_page.dart';
import 'package:bagoo_buyer_mobile/features/home/home_page.dart';
import 'package:bagoo_buyer_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart';
import 'support/widget_helpers.dart';

WebPage statusPage({
  int owner = 7,
  String token =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  bool pending = false,
}) => WebPage('Auth/AccountStatus', {
  'auth': {
    'user': {...buyer, 'id': owner},
  },
  'status': {
    'title': 'Account restricted',
    'message': 'Review this recorded restriction.',
    'account': {...buyer, 'id': owner},
    'sources': [
      {
        'type': 'account',
        'id': owner,
        'source_token': token,
        'name': 'Buyer account',
        'status': 'suspended',
        'reason': 'Review required.',
        'pending_request_id': pending ? 12 : null,
      },
    ],
    'requests': [],
  },
});

class EmailRepository extends FakeBuyerRepository {
  final checks = <String, Completer<bool>>{};
  @override
  Future<bool> registrationEmailAvailable(String email) =>
      (checks[email] = Completer<bool>()).future;
}

class RecognizedRepository extends FakeBuyerRepository {
  @override
  Future<WebPage?> currentSession() async => homePage(signedIn: true);
}

class PasswordRepository extends FakeBuyerRepository {
  int linkResets = 0;
  @override
  Future<void> resetPasswordLink(
    String email,
    String token,
    String password,
    String confirmation,
  ) async {
    expect(email, 'buyer@example.test');
    expect(token, 'test-reset-token-123456');
    expect(password, confirmation);
    linkResets++;
  }
}

void main() {
  testWidgets(
    'opening a buyer reset link requires explicit valid password submission',
    (tester) async {
      final repo = PasswordRepository();
      addTearDown(repo.session.close);
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: PasswordLinkPage(
            repository: repo,
            initialLink: Uri.parse(
              'http://backend.test/reset-password/test-reset-token-123456?email=buyer%40example.test&role=buyer',
            ),
            onComplete: () => completed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.linkResets, 0);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'),
        'Password!123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'),
        'Password!123',
      );
      await press(
        tester,
        find.widgetWithText(FilledButton, 'Save new password'),
      );
      expect(repo.linkResets, 1);
      expect(completed, isTrue);
    },
  );

  testWidgets('foreign reset links cannot open a password submission form', (
    tester,
  ) async {
    final repo = PasswordRepository();
    addTearDown(repo.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: PasswordLinkPage(
          repository: repo,
          initialLink: Uri.parse(
            'https://foreign.example.test/reset-password/test-reset-token-123456?email=buyer%40example.test',
          ),
          onComplete: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'New password'), findsNothing);
    expect(repo.linkResets, 0);
  });
  testWidgets('recognizes an existing buyer session without another login', (
    tester,
  ) async {
    final repo = RecognizedRepository()..signedIn = true;
    addTearDown(repo.session.close);
    await tester.pumpWidget(MainApp(repository: repo));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(repo.loginCalls, 0);
  });

  testWidgets('email availability ignores a rejection for an older address', (
    tester,
  ) async {
    final repo = EmailRepository();
    addTearDown(repo.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: RegisterPage(
          repository: repo,
          onBack: () {},
          onBrowse: () {},
          onComplete: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final email = find.widgetWithText(TextFormField, 'Email address');
    await tester.enterText(email, 'old@example.test');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(email, 'new@example.test');
    await tester.pump(const Duration(milliseconds: 600));
    repo.checks['new@example.test']!.complete(true);
    await tester.pump();
    repo.checks['old@example.test']!.complete(false);
    await tester.pumpAndSettle();
    expect(
      find.text('Email is available for a buyer account.'),
      findsOneWidget,
    );
    expect(find.textContaining('already has a buyer account'), findsNothing);
    expect(repo.registerCalls, 0);
  });

  testWidgets(
    'review conflict retains the draft and cannot submit an old status token',
    (tester) async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      var page = statusPage();
      session.onPage = (_) async => page;
      session.onPost = (_) async =>
          throw const BackendException('Status changed.', status: 409);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: AccountStatusPage(repository: BuyerRepository(session)),
        ),
      );
      await tester.pumpAndSettle();
      final explanation = find.widgetWithText(
        TextFormField,
        'Explain your review request',
      );
      await tester.enterText(
        explanation,
        'Please review my recorded restriction.',
      );
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Request a review'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(session.posts.single.values['subject_id'], 7);
      expect(session.posts.single.values, isNot(contains('user_id')));
      expect(
        tester.widget<TextFormField>(explanation).controller!.text,
        'Please review my recorded restriction.',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Request a review'),
            )
            .onPressed,
        isNull,
      );
      page = statusPage(
        token:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
      await tester.tap(find.byTooltip('Refresh account status'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(explanation).controller!.text,
        isEmpty,
      );
      expect(session.posts, hasLength(1));
    },
  );

  testWidgets('status from a different buyer clears private details', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    var page = statusPage();
    session.onPage = (_) async => page;
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: AccountStatusPage(repository: BuyerRepository(session)),
      ),
    );
    await tester.pumpAndSettle();
    page = statusPage(owner: 8);
    await tester.tap(find.byTooltip('Refresh account status'));
    await tester.pumpAndSettle();
    expect(find.text('Buyer account'), findsNothing);
    expect(find.text('Request a review'), findsNothing);
  });

  test('native registration validates and submits the optional ID as multipart data', () async {
    final session = _RegistrationSession();
    addTearDown(session.close);
    final repository = BuyerRepository(session);
    final document = UploadPart(
      'id_document',
      'sample.pdf',
      Uint8List.fromList([37, 80, 68, 70]),
      'application/pdf',
    );
    const values = {
      'region': '0400000000',
      'province': 'Laguna',
      'city': 'San Pablo City',
      'barangay': 'San Rafael',
      'address': '123 Test Street',
      'postal_code': '4000',
    };
    await repository.validateRegistration(values, files: [document]);
    await repository.register(values, 'verified-test-token', files: [document]);
    expect(session.files.map((file) => file.field), [
      'id_document',
      'id_document',
    ]);
    expect(
      session.values.every(
        (body) =>
            body['role'] == 'buyer' &&
            body['region'] == '0400000000' &&
            body['barangay'] == 'San Rafael',
      ),
      isTrue,
    );
    expect(session.values.last['otp_token'], 'verified-test-token');
  });
}

class _RegistrationSession extends FakeSession {
  final files = <UploadPart>[];
  final values = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> uploadJson(
    String path,
    Map<String, dynamic> body,
    List<UploadPart> uploads, {
    String? referer,
  }) async {
    expect(path, '/register/validate');
    files.addAll(uploads);
    values.add(body);
    return {'valid': true};
  }

  @override
  Future<WebPage> submit(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
    String? referer,
    List<UploadPart>? files,
  }) async {
    expect(path, '/register');
    this.files.addAll(files!);
    values.add(body);
    return homePage(signedIn: true);
  }
}
