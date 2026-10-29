import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/profile/email_section.dart';
import 'package:bagoo_buyer_mobile/features/profile/identity_section.dart';
import 'package:bagoo_buyer_mobile/features/profile/personal_section.dart';
import 'package:bagoo_buyer_mobile/features/profile/wallet_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'returns_misuse_test.dart' show returnPress;
import 'support/account_fixtures.dart';

void main() {
  late AccountFixtureRepository repository;
  late WebPage page;
  int reloads = 0;
  setUp(() {
    repository = AccountFixtureRepository();
    page = accountPage();
    reloads = 0;
    repository.onJson = (_) async => {
      'success': true,
      'message': 'Saved.',
      'cooldown': 60,
      'id': 1,
    };
    repository.onMutation = (_) async => page;
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

  Future<void> open(WidgetTester tester, String section) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(
          body: switch (section) {
            'identity' => IdentitySection(
              repository: repository,
              page: page,
              onChanged: (_) {},
              reload: () async => reloads++,
            ),
            'personal' => PersonalSection(
              repository: repository,
              page: page,
              onChanged: (_) {},
              onIdentity: () {},
            ),
            'password' => PasswordSection(
              repository: repository,
              page: page,
              onChanged: (_) {},
            ),
            'wallet' => WalletSection(
              repository: repository,
              page: page,
              reload: () async => reloads++,
              onPage: (_) {},
              onOrder: (_) {},
            ),
            _ => EmailSection(
              repository: repository,
              page: page,
              reload: () async => reloads++,
            ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> emailDraft(WidgetTester tester) async {
    await open(tester, 'emails');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current password'),
      'Synthetic!123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Additional email'),
      'new@example.test',
    );
  }

  Future<void> startPending(WidgetTester tester, Finder button) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(button), alignment: .5);
    await tester.pumpAndSettle();
    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(repository.calls, hasLength(1));
  }

  Future<void> correction(WidgetTester tester) async {
    await open(tester, 'identity');
    await returnPress(
      tester,
      find.widgetWithText(DropdownButtonFormField<String>, 'Detail to correct'),
    );
    await returnPress(tester, find.text('First name').last);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Corrected First name'),
      'Revised',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason'),
      'Correct the recorded first name.',
    );
  }

  check('original sign-in email cannot be removed from email settings', (
    tester,
  ) async {
    await open(tester, 'emails');
    expect(find.widgetWithText(TextButton, 'Remove email'), findsOneWidget);
    expect(find.text('primary@example.test'), findsOneWidget);
    expect(repository.calls, isEmpty);
  });

  check('verified email confirmation preserves the original sign-in email', (
    tester,
  ) async {
    await emailDraft(tester);
    await returnPress(tester, find.text('Send verification code'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Verification code'),
      '123456',
    );
    await returnPress(tester, find.text('Verify and add email'));
    expect(repository.calls, hasLength(2));
    expect(repository.calls.last.path, '/account/emails/confirm');
    expect(repository.calls.last.values, {
      'current_password': 'Synthetic!123',
      'email': 'new@example.test',
      'code': '123456',
    });
    expect(find.text('primary@example.test'), findsOneWidget);
    expect(reloads, 1);
  });

  check('confirmed correction remains a proposal pending server review', (
    tester,
  ) async {
    await correction(tester);
    await returnPress(tester, find.text('Submit correction request'));
    expect(repository.calls, hasLength(1));
    expect(repository.calls.single.values, {
      'source_token': 'a' * 64,
      'shop_id': null,
      'changes': {'first_name': 'Revised'},
      'reason': 'Correct the recorded first name.',
    });
    expect(reloads, 1);
    expect(find.textContaining('Correction requested.'), findsOneWidget);
    expect(find.text('Currently recorded: Synthetic'), findsOneWidget);
  });

  check('email resend respects the server fifteen-minute cooldown', (
    tester,
  ) async {
    await emailDraft(tester);
    repository.onJson = (_) async => throw const BackendException(
      'Wait fifteen minutes.',
      status: 429,
      data: {'cooldown': 900},
    );
    await returnPress(tester, find.text('Send verification code'));
    expect(repository.calls, hasLength(1));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Send code in 900s'),
          )
          .onPressed,
      isNull,
    );
  });

  check('account change blocks an email send and hides old private addresses', (
    tester,
  ) async {
    await emailDraft(tester);
    repository.session.clear();
    await returnPress(tester, find.text('Send verification code'));
    expect(repository.calls, isEmpty);
    expect(find.text('primary@example.test'), findsNothing);
    expect(find.text('contact@example.test'), findsNothing);
  });

  check('a late email response cannot open code entry for another account', (
    tester,
  ) async {
    await emailDraft(tester);
    final pending = Completer<Map<String, dynamic>>();
    repository.onJson = (_) => pending.future;
    await startPending(tester, find.text('Send verification code'));
    repository.session.clear();
    pending.complete({'success': true, 'cooldown': 60});
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextFormField, 'Verification code'),
      findsNothing,
    );
    expect(find.text('primary@example.test'), findsNothing);
    expect(reloads, 0);
  });

  check('changed email destination cannot reuse a previously sent code', (
    tester,
  ) async {
    await emailDraft(tester);
    await returnPress(tester, find.text('Send verification code'));
    tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Additional email'),
            )
            .controller!
            .text =
        'changed@example.test';
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Verification code'),
      '123456',
    );
    await returnPress(tester, find.text('Verify and add email'));
    expect(
      repository.calls.where((call) => call.path.endsWith('/confirm')),
      isEmpty,
    );
    expect(reloads, 0);
  });

  check('email removal confirmation retains the opening buyer account', (
    tester,
  ) async {
    await emailDraft(tester);
    await returnPress(tester, find.widgetWithText(TextButton, 'Remove email'));
    repository.session.clear();
    await returnPress(
      tester,
      find.widgetWithText(FilledButton, 'Remove email'),
    );
    expect(repository.calls, isEmpty);
    expect(find.text('contact@example.test'), findsNothing);
  });

  check('denied email action discards old addresses and proof fields', (
    tester,
  ) async {
    await emailDraft(tester);
    repository.onJson = (_) async =>
        throw const BackendException('Denied.', status: 403);
    await returnPress(tester, find.text('Send verification code'));
    expect(find.text('primary@example.test'), findsNothing);
    expect(
      find.widgetWithText(TextFormField, 'Current password'),
      findsNothing,
    );
  });

  check('identity correction blocks a changed session before submission', (
    tester,
  ) async {
    await correction(tester);
    repository.session.clear();
    await returnPress(tester, find.text('Submit correction request'));
    expect(repository.calls, isEmpty);
    expect(find.textContaining('Currently recorded:'), findsNothing);
  });

  check('late identity correction cannot reload or confirm a changed account', (
    tester,
  ) async {
    await correction(tester);
    final pending = Completer<Map<String, dynamic>>();
    repository.onJson = (_) => pending.future;
    await startPending(tester, find.text('Submit correction request'));
    repository.session.clear();
    pending.complete({'id': 1});
    await tester.pumpAndSettle();
    expect(reloads, 0);
    expect(find.textContaining('Correction requested.'), findsNothing);
  });

  check('unchanged identity details are not sent as a correction', (
    tester,
  ) async {
    await open(tester, 'identity');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason'),
      'Correct my recorded birth date.',
    );
    await returnPress(tester, find.text('Submit correction request'));
    expect(repository.calls, isEmpty);
  });

  check('identity correction requires a valid source version', (tester) async {
    page = accountPage(token: 'invalid');
    await correction(tester);
    await returnPress(tester, find.text('Submit correction request'));
    expect(repository.calls, isEmpty);
  });

  check('unsuccessful identity refresh cannot unlock a source conflict', (
    tester,
  ) async {
    await correction(tester);
    repository.onJson = (_) async =>
        throw const BackendException('Details changed.', status: 409);
    await returnPress(tester, find.text('Submit correction request'));
    await returnPress(tester, find.text('Reload current identity details'));
    expect(reloads, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Submit correction request'),
          )
          .onPressed,
      isNull,
    );
  });

  check('personal details cannot save after the buyer changes', (tester) async {
    await open(tester, 'personal');
    repository.session.clear();
    await returnPress(tester, find.text('Save Profile Changes'));
    expect(repository.calls, isEmpty);
    expect(find.text('primary@example.test'), findsNothing);
  });

  check('verification-link acknowledgement must belong to the opening buyer', (
    tester,
  ) async {
    await open(tester, 'personal');
    repository.onMutation = (_) async => accountPage(owner: 8);
    await returnPress(tester, find.text('Resend verification email'));
    expect(repository.calls, hasLength(1));
    expect(find.textContaining('Verification link requested.'), findsNothing);
    expect(find.text('primary@example.test'), findsNothing);
  });

  check('password proof cannot be sent after the buyer changes', (
    tester,
  ) async {
    await open(tester, 'password');
    for (final entry in {
      'Current password': 'Synthetic!123',
      'New password': 'Replacement!456',
      'Confirm new password': 'Replacement!456',
    }.entries) {
      await tester.enterText(
        find.widgetWithText(TextFormField, entry.key),
        entry.value,
      );
    }
    repository.session.clear();
    await returnPress(tester, find.text('Update password'));
    expect(repository.calls, isEmpty);
    expect(
      find.widgetWithText(TextFormField, 'Current password'),
      findsNothing,
    );
  });

  check('wallet credit drafts cannot cross a buyer account change', (
    tester,
  ) async {
    await open(tester, 'wallet');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (PHP)'),
      '25.50',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason'),
      'Synthetic credit request',
    );
    repository.session.clear();
    await returnPress(tester, find.text('Request credits'));
    expect(repository.calls, isEmpty);
    expect(find.widgetWithText(TextFormField, 'Amount (PHP)'), findsNothing);
  });

  for (final id in [0, -1, 1.5]) {
    check('correction acknowledgement requires a positive integer ID: $id', (
      tester,
    ) async {
      await correction(tester);
      repository.onJson = (_) async => {'id': id};
      await returnPress(tester, find.text('Submit correction request'));
      expect(repository.calls, hasLength(1));
      expect(reloads, 0);
      expect(find.textContaining('Correction requested.'), findsNothing);
    });
  }

  check('changed identity choices reset a removed selected field', (
    tester,
  ) async {
    await correction(tester);
    page = accountPage(token: 'b' * 64);
    ((page.props['identityCorrection'] as Map)['subject'] as Map)['fields'] = [
      {'key': 'birthday', 'label': 'Birth date', 'type': 'date'},
    ];
    await open(tester, 'identity');
    expect(tester.takeException(), isNull);
    expect(
      find.widgetWithText(TextFormField, 'Corrected First name'),
      findsNothing,
    );
  });

  check('a correction birth date must precede today', (tester) async {
    final now = DateTime.now();
    final initial = DateTime(
      now.year,
      now.month,
      1,
    ).toIso8601String().split('T').first;
    (((page.props['identityCorrection'] as Map)['subject'] as Map)['values']
            as Map)['birthday'] =
        initial;
    await open(tester, 'identity');
    await returnPress(tester, find.text('Corrected birth date: $initial'));
    await returnPress(tester, find.text('${now.day}').last);
    await returnPress(tester, find.text('OK'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason'),
      'Correct the recorded birth date.',
    );
    await returnPress(tester, find.text('Submit correction request'));
    expect(repository.calls, isEmpty);
  });

  check('application editor cannot submit an old buyer draft', (tester) async {
    page = applicationPage();
    await open(tester, 'identity');
    await returnPress(tester, find.text('Update application details'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'First name'),
      'Revised',
    );
    repository.session.clear();
    await returnPress(tester, find.text('Submit application for review'));
    expect(repository.calls, isEmpty);
    expect(find.widgetWithText(TextFormField, 'First name'), findsNothing);
  });

  for (final beforeNavigation in [true, false]) {
    check(
      'application navigation retains the opening buyer: $beforeNavigation',
      (tester) async {
        page = applicationPage();
        await open(tester, 'identity');
        final edit = find.text('Update application details');
        await tester.ensureVisible(edit);
        await tester.pumpAndSettle();
        if (beforeNavigation) repository.session.clear();
        await tester.tap(edit);
        if (!beforeNavigation) repository.session.clear();
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextFormField, 'First name'), findsNothing);
        expect(repository.calls, isEmpty);
      },
    );
  }
}
