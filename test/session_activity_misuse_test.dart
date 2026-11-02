import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/profile/sessions_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'returns_misuse_test.dart' show returnPress;
import 'support/account_fixtures.dart';
import 'support/return_fixtures.dart';

void main() {
  late AccountFixtureRepository repository;
  setUp(() {
    repository = AccountFixtureRepository();
    repository.onJson = (_) async => {
      'reference': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'affected_count': 1,
      'message': 'Synthetic session ended.',
    };
    (repository.session as ReturnSession).onGet = (_) async =>
        accountSessions();
  });
  tearDown(() => repository.session.close());

  for (final (field, value) in [('current_page', 1.5), ('last_page', 0)]) {
    testWidgets('login activity rejects malformed $field=$value', (
      tester,
    ) async {
      final data = accountSessions();
      (data['sessions'] as Map)[field] = value;
      (repository.session as ReturnSession).onGet = (_) async => data;
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: Scaffold(
            body: SessionsSection(repository: repository, owner: 7),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Private other device'), findsNothing);
      expect(find.text('Sign out this session'), findsNothing);
      expect(
        find.text('Login activity could not be confirmed for your account.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  void check(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(body: SessionsSection(repository: repository, owner: 7)),
      ),
    );
    await tester.pumpAndSettle();
  }

  void rejectsMalformedResponse(
    String description,
    void Function(Map<String, dynamic> data) mutate,
  ) {
    testWidgets('login activity rejects $description', (tester) async {
      final data = accountSessions();
      mutate(data);
      (repository.session as ReturnSession).onGet = (_) async => data;

      await open(tester);

      expect(find.text('Private other device'), findsNothing);
      expect(find.text('Sign out this session'), findsNothing);
      expect(
        find.text('Login activity could not be confirmed for your account.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  rejectsMalformedResponse('non-text metadata keys without crashing', (data) {
    final page = data['sessions'] as Map<String, dynamic>;
    final entries = List<dynamic>.from(page['data'] as List);
    final row = entries.last as Map;
    entries[entries.length - 1] = <Object?, Object?>{
      for (final entry in row.entries) entry.key: entry.value,
      7: 'unexpected key',
    };
    page['data'] = entries;
  });

  rejectsMalformedResponse('duplicate sign-in session IDs', (data) {
    final entries = (data['signIns'] as Map)['data'] as List;
    final first = entries.first as Map;
    final last = entries.last as Map;
    last['id'] = first['id'];
    last['current'] = first['current'];
  });

  rejectsMalformedResponse('a contradictory active status', (data) {
    final entries = (data['sessions'] as Map)['data'] as List;
    (entries.last as Map)['active'] = false;
  });

  rejectsMalformedResponse('an invalid confirmation flag', (data) {
    data['canConfirmByEmail'] = 'true';
  });

  testWidgets('legacy active sessions may lack optional sign-in times', (
    tester,
  ) async {
    final data = accountSessions();
    final entries = (data['sessions'] as Map)['data'] as List;
    (entries.last as Map)
      ..['signed_in_at'] = null
      ..['last_seen_at'] = null;
    (repository.session as ReturnSession).onGet = (_) async => data;

    await open(tester);

    expect(find.text('Private other device'), findsNWidgets(2));
    expect(find.text('Sign out this session'), findsOneWidget);
    expect(
      find.text('Login activity could not be confirmed for your account.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('login activity rejects a current-session marker mismatch', (
    tester,
  ) async {
    final data = accountSessions();
    final sessions = (data['sessions'] as Map)['data'] as List;
    (sessions.first as Map)['current'] = false;
    (repository.session as ReturnSession).onGet = (_) async => data;

    await open(tester);

    expect(find.text('Sign out this session'), findsNothing);
    expect(
      find.text('Login activity could not be confirmed for your account.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('login activity rejects empty session IDs before actions', (
    tester,
  ) async {
    final data = accountSessions();
    final sessions = (data['sessions'] as Map)['data'] as List;
    (sessions.last as Map)['id'] = '';
    (repository.session as ReturnSession).onGet = (_) async => data;

    await open(tester);

    expect(find.text('Private other device'), findsNothing);
    expect(find.text('Sign out this session'), findsNothing);
    expect(
      find.text('Login activity could not be confirmed for your account.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('login activity rejects impossible session timestamps', (
    tester,
  ) async {
    final data = accountSessions();
    final sessions = (data['sessions'] as Map)['data'] as List;
    (sessions.last as Map)['signed_in_at'] = '2026-02-30T00:00:00Z';
    (repository.session as ReturnSession).onGet = (_) async => data;

    await open(tester);

    expect(find.text('Private other device'), findsNothing);
    expect(find.text('Sign out this session'), findsNothing);
    expect(
      find.text('Login activity could not be confirmed for your account.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  check('foreign login-activity responses discard previous private rows', (
    tester,
  ) async {
    await open(tester);
    (repository.session as ReturnSession).onGet = (_) async =>
        accountSessions(owner: 8);
    await returnPress(tester, find.text('Refresh login activity'));
    expect(find.text('Private other device'), findsNothing);
    expect(find.text('Sign out this session'), findsNothing);
  });

  check('changed account cannot revoke an old login session', (tester) async {
    await open(tester);
    repository.session.clear();
    await returnPress(tester, find.text('Sign out this session'));
    expect(find.text('Confirm sign out'), findsNothing);
    expect(find.text('Private other device'), findsNothing);
    expect(repository.calls, isEmpty);
  });

  check('open revoke confirmation cannot submit after account change', (
    tester,
  ) async {
    await open(tester);
    await returnPress(tester, find.text('Sign out this session'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current password'),
      'Synthetic!123',
    );
    repository.session.clear();
    await returnPress(tester, find.text('Confirm sign out'));
    expect(repository.calls, isEmpty);
  });

  Future<void> proof(WidgetTester tester) async {
    await open(tester);
    await returnPress(tester, find.text('Sign out this session'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current password'),
      'Synthetic!123',
    );
  }

  const saved = {
    'reference': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'affected_count': 1,
    'message': 'Synthetic session ended.',
  };

  Future<void> startPending(WidgetTester tester) async {
    final button = find.text('Confirm sign out');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(button), alignment: .5);
    await tester.pumpAndSettle();
    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(repository.calls, hasLength(1));
  }

  check('a malformed revoke reference cannot confirm sign-out', (tester) async {
    await proof(tester);
    repository.onJson = (_) async => {
      'reference': '------------------------------------',
      'affected_count': 1,
      'message': 'Unverified sign-out.',
    };

    await returnPress(tester, find.text('Confirm sign out'));

    expect(repository.calls, hasLength(1));
    expect(find.text('Unverified sign-out.'), findsNothing);
    expect(
      find.text(
        'Sign-out could not be confirmed. Refresh login activity before retrying.',
      ),
      findsOneWidget,
    );
  });

  check('repeated revoke taps send one bound request and show server refresh', (
    tester,
  ) async {
    await proof(tester);
    final pending = Completer<Map<String, dynamic>>();
    repository.onJson = (_) => pending.future;
    final button = find.text('Confirm sign out');
    await Scrollable.ensureVisible(tester.element(button), alignment: .5);
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      await tester.tap(button);
    }
    expect(repository.calls, hasLength(1));
    final request = repository.calls.single;
    expect(
      request.path,
      '/account/security/sessions/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/revoke',
    );
    expect(request.values.keys.toSet(), {
      'request_token',
      'confirmation_method',
      'current_password',
      'code',
    });
    final fresh = accountSessions();
    final sessionPage = fresh['sessions'] as Map;
    ((sessionPage['data'] as List)).removeWhere(
      (entry) => entry['id'] == 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    );
    sessionPage['total'] = 1;
    sessionPage['to'] = 1;
    (repository.session as ReturnSession).onGet = (_) async => fresh;
    pending.complete(saved);
    await tester.pumpAndSettle();
    expect(find.text('Synthetic session ended.'), findsOneWidget);
    expect(find.text('Sign out this session'), findsNothing);
  });

  check('uncertain revoke retries preserve the exact intent and proof', (
    tester,
  ) async {
    await proof(tester);
    repository.onJson = (_) async =>
        throw const BackendException('Uncertain response.', status: 503);
    await returnPress(tester, find.text('Confirm sign out'));
    final original = repository.calls.single;
    tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Current password'),
            )
            .controller!
            .text =
        'Changed!789';
    repository.onJson = (_) async => saved;
    await returnPress(tester, find.text('Retry same sign-out request'));
    expect(repository.calls, hasLength(2));
    expect(repository.calls.last.values, original.values);
  });

  check('rate-limited revoke waits and blocks a captured retry action', (
    tester,
  ) async {
    await proof(tester);
    repository.onJson = (_) async => throw BackendException(
      'Too many sign-out attempts.',
      status: 429,
      retryAt: DateTime.now().add(const Duration(seconds: 30)),
    );
    final submit = find.widgetWithText(FilledButton, 'Confirm sign out');
    final savedAction = tester.widget<FilledButton>(submit).onPressed!;
    await returnPress(tester, find.text('Confirm sign out'));
    savedAction();
    await tester.pumpAndSettle();

    final retry = find.ancestor(
      of: find.textContaining('Retry sign-out in '),
      matching: find.byType(FilledButton),
    );
    expect(retry, findsOneWidget);
    expect(tester.widget<FilledButton>(retry).onPressed, isNull);
    expect(repository.calls, hasLength(1));
    expect(repository.calls.single.path, endsWith('/revoke'));
    expect(tester.takeException(), isNull);
  });

  check('a late revoke acknowledgement cannot confirm another buyer session', (
    tester,
  ) async {
    await proof(tester);
    final pending = Completer<Map<String, dynamic>>();
    repository.onJson = (_) => pending.future;
    await startPending(tester);
    repository.session.clear();
    pending.complete(saved);
    await tester.pumpAndSettle();
    expect(find.text('Synthetic session ended.'), findsNothing);
    expect(find.text('Private other device'), findsNothing);
    expect(
      find.widgetWithText(TextFormField, 'Current password'),
      findsNothing,
    );
  });

  for (final status in [401, 403, 404, 419]) {
    check('login activity access failure $status clears private rows', (
      tester,
    ) async {
      await open(tester);
      (repository.session as ReturnSession).onGet = (_) async =>
          throw BackendException('Denied.', status: status);
      await returnPress(tester, find.text('Refresh login activity'));
      expect(find.text('Private other device'), findsNothing);
      expect(find.text('Sign out this session'), findsNothing);
    });
  }

  check('a throttled session code prevents immediate resend taps', (
    tester,
  ) async {
    await open(tester);
    await returnPress(tester, find.text('Sign out this session'));
    await returnPress(
      tester,
      find.widgetWithText(DropdownButtonFormField<String>, 'Confirm it is you'),
    );
    await returnPress(tester, find.text('Email code').last);
    repository.onJson = (_) async => throw const BackendException(
      'Wait before requesting another code.',
      status: 429,
      data: {'cooldown': 900},
    );
    await returnPress(tester, find.text('Send email code'));
    expect(repository.calls, hasLength(1));
    expect(find.text('Send email code'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Resend in 900s'),
          )
          .onPressed,
      isNull,
    );
  });
}
