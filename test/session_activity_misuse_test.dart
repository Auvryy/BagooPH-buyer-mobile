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
    expect(request.path, '/account/security/sessions/other-id/revoke');
    expect(request.values.keys.toSet(), {
      'request_token',
      'confirmation_method',
      'current_password',
      'code',
    });
    final fresh = accountSessions();
    ((fresh['sessions'] as Map)['data'] as List).removeWhere(
      (entry) => entry['id'] == 'other-id',
    );
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
