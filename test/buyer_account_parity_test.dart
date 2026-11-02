import 'dart:async';
import 'dart:typed_data';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/auth/register_page.dart';
import 'package:bagoo_buyer_mobile/features/auth/password_link_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/account_status_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:bagoo_buyer_mobile/features/home/home_page.dart';
import 'package:bagoo_buyer_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart';
import 'support/widget_helpers.dart';

WebPage statusPage({
  Object owner = 7,
  String token =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  bool pending = false,
  Object? sources,
  Object? requests,
  Object? emailUpdate,
}) => WebPage('Auth/AccountStatus', {
  'auth': {
    'user': {...buyer, 'id': owner},
  },
  'status': {
    'title': 'Account restricted',
    'message': 'Review this recorded restriction.',
    'account': {...buyer, 'id': owner},
    'sources':
        sources ??
        [
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
    'requests': requests ?? [],
    'email_update': ?emailUpdate,
  },
});

class EmailRepository extends FakeBuyerRepository {
  final checks = <String, Completer<bool>>{};
  Future<bool> Function(String)? check;
  @override
  Future<bool> registrationEmailAvailable(String email) => check == null
      ? (checks[email] = Completer<bool>()).future
      : check!(email);
}

class InvalidPolicyRepository extends FakeBuyerRepository {
  @override
  Future<WebPage> registration() async => const WebPage('Auth/Register', {
    'birthDateLimits': {'adult_maximum': '2008-10-26', 'today': '2026-10-26'},
    'policies': {
      'required': true,
      'terms_version': '2026-10-12',
      'privacy_version': '2026-10-12',
      'terms_url': '/account',
      'privacy_url': '/privacy/2026-10-12',
    },
  });
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
  test('profile repository requires a positive integer buyer ID', () {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final repository = ProfileRepository(BuyerRepository(session));
    for (final id in [0, -1, 7.5, '7', null]) {
      final page = WebPage('Buyer/Profile', {
        'auth': {
          'user': {...buyer, 'id': id},
        },
        'user': {...buyer, 'id': id},
      });
      expect(
        () => repository.checked(page),
        throwsA(isA<BackendException>()),
        reason: 'invalid buyer ID $id',
      );
    }
  });

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
    'rate-limited email availability does not request on every edit',
    (tester) async {
      final repo = EmailRepository();
      addTearDown(repo.session.close);
      var checks = 0;
      repo.check = (_) async {
        checks++;
        throw BackendException(
          'Email checks are temporarily limited.',
          status: 429,
          retryAt: DateTime.now().add(const Duration(seconds: 30)),
        );
      };
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
      await tester.enterText(email, 'first@example.test');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.enterText(email, 'second@example.test');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(checks, 1);
      expect(find.textContaining('Try again in '), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('invalid policy links block buyer registration', (tester) async {
    final repo = InvalidPolicyRepository();
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

    expect(
      find.textContaining('Account policy links could not be confirmed'),
      findsOneWidget,
    );
    final continueButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(continueButton.onPressed, isNull);
    expect(repo.validationCalls, 0);
    expect(tester.takeException(), isNull);
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

  testWidgets('account review request rejects markup before submission', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onPage = (_) async => statusPage();
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: AccountStatusPage(repository: BuyerRepository(session)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Explain your review request'),
      'Please review <script>alert(1)</script> for this account.',
    );
    tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Request a review'),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    expect(session.posts, isEmpty);
    expect(
      find.text(
        'Use plain text with letters or numbers, without markup or hidden characters.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'account review request waits after a rate limit and keeps draft',
    (tester) async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      session.onPage = (_) async => statusPage();
      session.onPost = (_) async => throw BackendException(
        'Too many account review requests.',
        status: 429,
        retryAt: DateTime.now().add(const Duration(seconds: 30)),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: AccountStatusPage(repository: BuyerRepository(session)),
        ),
      );
      await tester.pumpAndSettle();
      const draft =
          'Please review this restriction after I corrected the details.';
      final field = find.widgetWithText(
        TextFormField,
        'Explain your review request',
      );
      await tester.enterText(field, draft);
      final savedAction = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Request a review'),
          )
          .onPressed!;
      savedAction();
      await tester.pumpAndSettle();
      savedAction();
      await tester.pumpAndSettle();

      final retry = find.ancestor(
        of: find.textContaining('Try again in '),
        matching: find.byType(FilledButton),
      );
      expect(retry, findsOneWidget);
      expect(tester.widget<FilledButton>(retry).onPressed, isNull);
      expect(session.posts, hasLength(1));
      expect(tester.widget<TextFormField>(field).controller!.text, draft);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
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

  testWidgets('malformed restriction rows clear stale review actions', (
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
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Explain your review request'),
      'Please review this restriction after I corrected the details.',
    );
    final staleSubmit = tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Request a review'),
        )
        .onPressed!;

    page = statusPage(
      sources: [
        {
          'type': 'account',
          'id': 7,
          'source_token': 'a' * 64,
          'name': 'Buyer account',
          'status': 'suspended',
          'reason': 'Review required.',
        },
        'unexpected row',
      ],
    );
    await tester.tap(find.byTooltip('Refresh account status'));
    await tester.pumpAndSettle();

    expect(find.text('Buyer account'), findsNothing);
    expect(find.text('Request a review'), findsNothing);
    expect(
      find.textContaining('Account status details could not be confirmed'),
      findsOneWidget,
    );
    staleSubmit();
    await tester.pumpAndSettle();
    expect(session.posts, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invalid review source tokens never expose a submit action', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onPage = (_) async => statusPage(
      sources: [
        {
          'type': 'account',
          'id': 7,
          'source_token': 'A' * 64,
          'name': 'Buyer account',
          'status': 'suspended',
        },
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: AccountStatusPage(repository: BuyerRepository(session)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Buyer account'), findsNothing);
    expect(find.text('Request a review'), findsNothing);
    expect(
      find.textContaining('Account status details could not be confirmed'),
      findsOneWidget,
    );
    expect(session.posts, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('malformed email update metadata cannot claim delivery', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onPage = (_) async =>
        statusPage(emailUpdate: {'pending': 'true', 'attempts': 'a lot'});
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: AccountStatusPage(repository: BuyerRepository(session)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('email update was delivered'), findsNothing);
    expect(find.textContaining('awaiting delivery'), findsNothing);
    expect(find.text('Buyer account'), findsNothing);
    expect(
      find.textContaining('Account status details could not be confirmed'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'malformed review history does not leave restriction details active',
    (tester) async {
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

      page = statusPage(
        requests: [
          {
            'id': 21,
            'status': 'rejected',
            'created_at': '2026-10-01T10:00:00Z',
            'message': 'Please review the recorded restriction.',
          },
          false,
        ],
      );
      await tester.tap(find.byTooltip('Refresh account status'));
      await tester.pumpAndSettle();

      expect(find.text('Buyer account'), findsNothing);
      expect(find.text('Review request history'), findsNothing);
      expect(
        find.textContaining('Account status details could not be confirmed'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('fractional account owner cannot display restricted details', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onPage = (_) async => statusPage(owner: 7.5);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: AccountStatusPage(repository: BuyerRepository(session)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Buyer account'), findsNothing);
    expect(find.text('Request a review'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
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
