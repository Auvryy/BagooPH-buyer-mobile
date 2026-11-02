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

  check('malformed verification time never claims email is verified', (
    tester,
  ) async {
    page.props['user'] = {
      ...(page.props['user'] as Map),
      'email_verified_at': '2026-02-30T10:00:00Z',
    };

    await open(tester, 'personal');

    expect(find.text('Your sign-in email is verified.'), findsNothing);
    expect(find.text('Resend verification email'), findsOneWidget);
  });

  check('impossible birthday is not shown as a recorded personal fact', (
    tester,
  ) async {
    page.props['user'] = {
      ...(page.props['user'] as Map),
      'birthday': '2026-02-30T00:00:00.000000Z',
    };

    await open(tester, 'personal');

    expect(find.text('2026-02-30'), findsNothing);
    expect(find.text('Not recorded'), findsWidgets);
  });

  check('non-text personal fields are not printed as account facts', (
    tester,
  ) async {
    page.props['user'] = {
      ...(page.props['user'] as Map),
      'email': 42,
      'first_name': {'private_payload': 'unconfirmed'},
    };

    await open(tester, 'personal');

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            (widget.data?.contains('private_payload') ?? false),
      ),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == '42',
      ),
      findsNothing,
    );
  });

  check('malformed original email metadata cannot enable removal', (
    tester,
  ) async {
    final settings = Map<String, dynamic>.from(
      page.props['emailSettings'] as Map,
    );
    final addresses = List<Map<String, dynamic>>.from(
      settings['addresses'] as List,
    );
    addresses[0] = {...addresses[0], 'is_original': 'true'};
    settings['addresses'] = addresses;
    page.props['emailSettings'] = settings;
    await open(tester, 'emails');

    expect(find.text('Remove email'), findsNothing);
    expect(
      find.textContaining('Saved email addresses could not be confirmed'),
      findsOneWidget,
    );
    expect(repository.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  check('confirmed removal rechecks that the same email still exists', (
    tester,
  ) async {
    await emailDraft(tester);
    await returnPress(tester, find.widgetWithText(TextButton, 'Remove email'));
    expect(find.byType(AlertDialog), findsOneWidget);

    final settings = Map<String, dynamic>.from(
      page.props['emailSettings'] as Map,
    );
    settings['addresses'] = [
      Map<String, dynamic>.from((settings['addresses'] as List).first as Map),
    ];
    page.props['emailSettings'] = settings;
    await open(tester, 'emails');
    expect(find.byType(AlertDialog), findsOneWidget);
    await returnPress(
      tester,
      find.widgetWithText(FilledButton, 'Remove email'),
    );

    expect(repository.calls, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
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

  check('malformed required-document metadata blocks identity correction', (
    tester,
  ) async {
    final identity = page.props['identityCorrection'] as Map;
    (identity['subject'] as Map)['required_documents'] = 'not-a-list';
    await open(tester, 'identity');

    expect(
      find.textContaining('Required identity documents could not be confirmed'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Submit correction request'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  check('partial identity correction history is not shown as complete', (
    tester,
  ) async {
    final subject =
        ((page.props['identityCorrection'] as Map)['subject'] as Map);
    subject['requests'] = [
      {
        'id': 91,
        'version': 1,
        'current': true,
        'reason': 'Correct the recorded first name.',
        'requested_at': '2026-10-29T00:00:00Z',
        'before': {'first_name': 'Synthetik'},
        'proposed': {'first_name': 'Synthetic'},
        'documents': {},
        'decision': null,
      },
      'malformed correction request',
    ];
    await open(tester, 'identity');

    expect(find.textContaining('Request #91'), findsNothing);
    expect(
      find.textContaining('request history could not be confirmed'),
      findsOneWidget,
    );
    expect(
      find.text('No correction requests have been recorded.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  check('valid identity correction history remains visible', (tester) async {
    final subject =
        ((page.props['identityCorrection'] as Map)['subject'] as Map);
    subject['requests'] = [
      {
        'id': 91,
        'version': 1,
        'current': true,
        'reason': 'Correct the recorded first name.',
        'requested_at': '2026-10-29T00:00:00Z',
        'before': {'first_name': 'Synthetik'},
        'proposed': {'first_name': 'Synthetic'},
        'documents': {},
        'decision': null,
      },
    ];
    await open(tester, 'identity');

    expect(find.textContaining('Request #91'), findsOneWidget);
    expect(
      find.textContaining('request history could not be confirmed'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  check('malformed application select options are rejected safely', (
    tester,
  ) async {
    page = applicationPage();
    final application = page.props['buyerApplication'] as Map;
    final form = application['application'] as Map;
    final sex = (form['fields'] as List).firstWhere(
      (field) => field['key'] == 'sex',
    ) as Map;
    sex['options'] = 'not-a-list';
    (form['values'] as Map)['sex'] = 'Male';
    await open(tester, 'identity');
    await returnPress(tester, find.text('Update application details'));

    expect(
      find.textContaining('Choices for Sex could not be confirmed'),
      findsOneWidget,
    );
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  check('buyer application does not offer a partial malformed field list', (
    tester,
  ) async {
    page = applicationPage();
    final application = page.props['buyerApplication'] as Map;
    final form = application['application'] as Map;
    form['fields'] = [
      ...(form['fields'] as List),
      'malformed application field row',
    ];
    await open(tester, 'identity');
    await returnPress(tester, find.text('Update application details'));

    expect(
      find.textContaining('Application fields could not be confirmed'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'First name'), findsNothing);
    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Submit application for review'),
    );
    expect(submit.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  check('buyer application rejects a missing field definition', (tester) async {
    page = applicationPage();
    final application = page.props['buyerApplication'] as Map;
    final form = application['application'] as Map;
    form['fields'] = (form['fields'] as List)
        .where((field) => field['key'] != 'phone')
        .toList();
    await open(tester, 'identity');
    await returnPress(tester, find.text('Update application details'));

    expect(
      find.textContaining('Application fields could not be confirmed'),
      findsOneWidget,
    );
    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Submit application for review'),
    );
    expect(submit.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  check('buyer application rejects duplicate field definitions', (
    tester,
  ) async {
    page = applicationPage();
    final application = page.props['buyerApplication'] as Map;
    final form = application['application'] as Map;
    final fields = form['fields'] as List;
    form['fields'] = [
      ...fields,
      Map<String, dynamic>.from(fields.first as Map),
    ];
    await open(tester, 'identity');
    await returnPress(tester, find.text('Update application details'));

    expect(
      find.textContaining('Application fields could not be confirmed'),
      findsOneWidget,
    );
    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Submit application for review'),
    );
    expect(submit.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  check('duplicate application select options do not crash the editor', (
    tester,
  ) async {
    page = applicationPage();
    final application = page.props['buyerApplication'] as Map;
    final form = application['application'] as Map;
    final sex = (form['fields'] as List).firstWhere(
      (field) => field['key'] == 'sex',
    ) as Map;
    sex['options'] = ['Male', 'Male'];
    (form['values'] as Map)['sex'] = 'Male';
    await open(tester, 'identity');
    await returnPress(tester, find.text('Update application details'));

    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  check('duplicate identity correction choices do not crash the form', (
    tester,
  ) async {
    final identity = page.props['identityCorrection'] as Map;
    final subject = identity['subject'] as Map;
    final fields = subject['fields'] as List;
    final sex = fields.firstWhere((field) => field['key'] == 'sex') as Map;
    sex['options'] = ['Male', 'Male'];

    await open(tester, 'identity');
    await returnPress(
      tester,
      find.widgetWithText(DropdownButtonFormField<String>, 'Detail to correct'),
    );
    await returnPress(tester, find.text('Sex').last);

    expect(
      find.widgetWithText(DropdownButtonFormField<String>, 'Corrected Sex'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  check('malformed identity correction options do not become free text', (
    tester,
  ) async {
    final identity = page.props['identityCorrection'] as Map;
    final subject = identity['subject'] as Map;
    final fields = subject['fields'] as List;
    final sex = fields.firstWhere((field) => field['key'] == 'sex') as Map;
    sex['options'] = 'not-a-list';

    await open(tester, 'identity');
    await returnPress(
      tester,
      find.widgetWithText(DropdownButtonFormField<String>, 'Detail to correct'),
    );
    await returnPress(tester, find.text('Sex').last);

    expect(
      find.textContaining('Choices for Sex could not be confirmed'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'Corrected Sex'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Submit correction request'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  check('duplicate identity field keys disable ambiguous corrections', (
    tester,
  ) async {
    final identity = page.props['identityCorrection'] as Map;
    final subject = identity['subject'] as Map;
    final fields = subject['fields'] as List;
    fields.add({
      'key': 'first_name',
      'label': 'Alternate first name',
      'type': 'text',
    });

    await open(tester, 'identity');
    expect(
      find.textContaining('Identity correction fields could not be confirmed'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Submit correction request'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  for (final invalid in ['Revised2', '<script>', 'Жанна', 'Hidden\u200bName']) {
    check('identity correction rejects invalid name text: $invalid', (
      tester,
    ) async {
      await correction(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Corrected First name'),
        invalid,
      );
      await returnPress(tester, find.text('Submit correction request'));
      expect(repository.calls, isEmpty);
    });
  }

  for (final invalid in [
    '<script>change</script>',
    'javascript:change()',
    'Reason\twith tab',
    'Hidden\u034ftext',
  ]) {
    check('identity correction rejects unsafe reason text: $invalid', (
      tester,
    ) async {
      await correction(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Reason'),
        invalid,
      );
      await returnPress(tester, find.text('Submit correction request'));
      expect(repository.calls, isEmpty);
    });
  }

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

  check('email verification respects its own rate-limit cooldown', (
    tester,
  ) async {
    await emailDraft(tester);
    repository.onJson = (request) async {
      if (request.path.endsWith('/confirm')) {
        throw BackendException(
          'Too many verification attempts.',
          status: 429,
          retryAt: DateTime.now().add(const Duration(seconds: 30)),
        );
      }
      return {'success': true, 'cooldown': 60};
    };
    await returnPress(tester, find.text('Send verification code'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Verification code'),
      '123456',
    );
    final savedVerifyAction = tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Verify and add email'),
        )
        .onPressed!;
    await returnPress(tester, find.text('Verify and add email'));
    savedVerifyAction();
    await tester.pumpAndSettle();

    final verify = find.ancestor(
      of: find.textContaining('Verify in '),
      matching: find.byType(FilledButton),
    );
    expect(verify, findsOneWidget);
    expect(tester.widget<FilledButton>(verify).onPressed, isNull);
    final resend = find.ancestor(
      of: find.textContaining('Resend in '),
      matching: find.byType(TextButton),
    );
    expect(resend, findsOneWidget);
    expect(tester.widget<TextButton>(resend).onPressed, isNull);
    expect(repository.calls.map((call) => call.path), [
      '/account/emails/send',
      '/account/emails/confirm',
    ]);
    expect(tester.takeException(), isNull);
  });

  check('changing the contact email waits after its own rate limit', (
    tester,
  ) async {
    await emailDraft(tester);
    repository.onJson = (_) async => throw BackendException(
      'Too many email changes.',
      status: 429,
      retryAt: DateTime.now().add(const Duration(seconds: 30)),
    );
    final finder = find.widgetWithText(TextButton, 'Use for contact');
    final savedPreferAction = tester.widget<TextButton>(finder).onPressed!;
    await returnPress(tester, finder);
    await returnPress(
      tester,
      find.widgetWithText(FilledButton, 'Use for contact'),
    );
    savedPreferAction();
    await tester.pumpAndSettle();

    final retry = find.ancestor(
      of: find.textContaining('Try again in '),
      matching: find.byType(TextButton),
    );
    expect(retry, findsOneWidget);
    expect(tester.widget<TextButton>(retry).onPressed, isNull);
    expect(repository.calls.map((call) => call.path), [
      '/account/emails/2/preferred',
    ]);
    expect(tester.takeException(), isNull);
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

  check('wallet credit retries wait after a server rate limit', (tester) async {
    await open(tester, 'wallet');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (PHP)'),
      '25.50',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason'),
      'Approved test wallet credit.',
    );
    repository.onJson = (_) async => throw BackendException(
      'Too many credit requests.',
      status: 429,
      retryAt: DateTime.now().add(const Duration(seconds: 30)),
    );
    final submit = find.widgetWithText(FilledButton, 'Request credits');
    final savedAction = tester.widget<FilledButton>(submit).onPressed!;
    await returnPress(tester, find.text('Request credits'));
    savedAction();
    await tester.pumpAndSettle();

    final retry = find.ancestor(
      of: find.textContaining('Retry same request in '),
      matching: find.byType(FilledButton),
    );
    expect(retry, findsOneWidget);
    expect(tester.widget<FilledButton>(retry).onPressed, isNull);
    expect(repository.calls, hasLength(1));
    expect(repository.calls.single.path, '/wallet/credits');
    expect(tester.takeException(), isNull);
  });

  check('identity correction fails closed on fractional field limits', (
    tester,
  ) async {
    final fields =
        (((page.props['identityCorrection'] as Map)['subject'] as Map)['fields']
            as List);
    (fields[1] as Map)['max_length'] = 50.5;
    await open(tester, 'identity');
    await returnPress(
      tester,
      find.widgetWithText(DropdownButtonFormField<String>, 'Detail to correct'),
    );
    await returnPress(tester, find.text('First name').last);

    final input = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Corrected First name'),
    );
    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Submit correction request'),
    );
    expect(input.enabled, isFalse);
    expect(submit.onPressed, isNull);
    expect(
      find.textContaining('Field length requirements could not be confirmed'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expect(repository.calls, isEmpty);
  });

  check('identity correction rejects inconsistent field length limits', (
    tester,
  ) async {
    final fields =
        (((page.props['identityCorrection'] as Map)['subject'] as Map)['fields']
            as List);
    (fields[1] as Map)
      ..['min_length'] = 51
      ..['max_length'] = 50;
    await open(tester, 'identity');
    await returnPress(
      tester,
      find.widgetWithText(DropdownButtonFormField<String>, 'Detail to correct'),
    );
    await returnPress(tester, find.text('First name').last);

    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Corrected First name'),
          )
          .enabled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
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

  check('buyer application rejects a name the server would refuse', (
    tester,
  ) async {
    page = applicationPage();
    await open(tester, 'identity');
    await returnPress(tester, find.text('Update application details'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'First name'),
      'Revised2',
    );
    await returnPress(tester, find.text('Submit application for review'));
    expect(repository.calls, isEmpty);
  });

  for (final invalidLimit in [50.5, '50']) {
    check('buyer application handles malformed max length: $invalidLimit', (
      tester,
    ) async {
      page = applicationPage();
      final application = page.props['buyerApplication'] as Map;
      final fields = (application['application'] as Map)['fields'] as List;
      (fields.first as Map)['max_length'] = invalidLimit;
      await open(tester, 'identity');
      await returnPress(tester, find.text('Update application details'));

      final input = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'First name'),
      );
      expect(input.enabled, isFalse);
      expect(
        find.textContaining(
          'One or more field length requirements could not be confirmed',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await returnPress(tester, find.text('Submit application for review'));
      expect(repository.calls, isEmpty);
    });
  }

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
