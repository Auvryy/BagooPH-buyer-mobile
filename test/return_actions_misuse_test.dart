import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:bagoo_buyer_mobile/features/profile/returns_page.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'returns_misuse_test.dart' show returnPress, privateDetails;
import 'support/return_fixtures.dart';

class ReturnNavigationObserver extends NavigatorObserver {
  int opened = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) opened++;
  }
}

void main() {
  late ReturnSession session;
  late ProfileRepository repository;
  late FixtureFileSelector picker;
  late FileSelectorPlatform originalPicker;
  setUp(() {
    session = ReturnSession();
    repository = ProfileRepository(BuyerRepository(session));
    originalPicker = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = picker = FixtureFileSelector();
    picker.next = returnPhoto();
    session.onPage = (path) async =>
        path.endsWith('/create') ? returnForm() : returnDetail();
    session.onSubmit = (_) async => returnDetail(success: 'Saved.');
  });
  tearDown(() {
    FileSelectorPlatform.instance = originalPicker;
    session.close();
  });

  Future<void> open(
    WidgetTester tester, {
    bool create = false,
    NavigatorObserver? observer,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        navigatorObservers: [?observer],
        home: ReturnsPage(
          repository: repository,
          caseId: create ? null : 4,
          orderId: create ? 11 : null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> command(WidgetTester tester) async {
    await open(tester);
    await returnPress(
      tester,
      find.widgetWithText(OutlinedButton, 'Withdraw request'),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason or receipt details'),
      'I no longer need this return.',
    );
  }

  Future<void> form(WidgetTester tester, {bool photo = true}) async {
    await open(tester, create: true);
    await returnPress(
      tester,
      find.widgetWithText(CheckboxListTile, 'Test purchase'),
    );
    await returnPress(tester, find.byType(DropdownButtonFormField<String>));
    await returnPress(tester, find.text('Item damaged').last);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'What happened?'),
      'The stitching is damaged on arrival.',
    );
    if (photo) await returnPress(tester, find.text('Add photo of the problem'));
  }

  testWidgets(
    'a return command requires a complete reason without submitting',
    (tester) async {
      await command(tester);
      final reason = find.widgetWithText(
        TextFormField,
        'Reason or receipt details',
      );
      for (final value in ['', ' ', 'short', 'x' * 1001]) {
        tester.widget<TextFormField>(reason).controller!.text = value;
        await returnPress(
          tester,
          find.widgetWithText(FilledButton, 'Withdraw request'),
        );
        expect(
          session.submissions,
          isEmpty,
          reason: 'Reason length: ${value.length}',
        );
      }
    },
  );

  testWidgets('eight command taps send one versioned update', (tester) async {
    await command(tester);
    final pending = Completer<WebPage>();
    session.onSubmit = (_) => pending.future;
    final submit = find.widgetWithText(FilledButton, 'Withdraw request');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      await tester.tap(submit);
    }
    expect(session.submissions, hasLength(1));
    expect(session.submissions.single.values['expected_version'], 1);
    expect(session.submissions.single.path, '/buyer-returns/4/actions');
    pending.complete(
      returnDetail(
        status: 'withdrawn',
        version: 2,
        actions: [],
        success: 'Updated.',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('withdrawn'), findsWidgets);
  });

  testWidgets(
    'return reason minimum counts Unicode characters like the server',
    (tester) async {
      await command(tester);
      tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Reason or receipt details'),
              )
              .controller!
              .text =
          String.fromCharCode(0x10428) * 5;
      await returnPress(
        tester,
        find.widgetWithText(FilledButton, 'Withdraw request'),
      );
      expect(session.submissions, isEmpty);
    },
  );

  testWidgets('return actions reject unsafe notes before submitting', (
    tester,
  ) async {
    await command(tester);
    final reason = find.widgetWithText(
      TextFormField,
      'Reason or receipt details',
    );
    for (final value in [
      'Reason with <script>payload</script>',
      'javascript:report()',
      'Call\tme today',
      'Hidden\u200btext is here',
    ]) {
      tester.widget<TextFormField>(reason).controller!.text = value;
      await returnPress(
        tester,
        find.widgetWithText(FilledButton, 'Withdraw request'),
      );
      expect(session.submissions, isEmpty, reason: value);
    }
  });

  testWidgets(
    'uncertain command retry preserves its exact token, version and reason',
    (tester) async {
      await command(tester);
      session.onSubmit = (_) async =>
          throw const BackendException('Uncertain result.', status: 503);
      await returnPress(
        tester,
        find.widgetWithText(FilledButton, 'Withdraw request'),
      );
      final original = session.submissions.single;
      session.onSubmit = (_) async =>
          returnDetail(status: 'withdrawn', version: 2, success: 'Updated.');
      await returnPress(
        tester,
        find.widgetWithText(FilledButton, 'Retry same update'),
      );
      expect(session.submissions, hasLength(2));
      expect(session.submissions.last.values, original.values);
    },
  );

  for (final failure in [false, true]) {
    testWidgets(
      'changed account discards a late command ${failure ? 'failure' : 'success'}',
      (tester) async {
        await command(tester);
        final pending = Completer<WebPage>();
        session.onSubmit = (_) => pending.future;
        final submit = find.widgetWithText(FilledButton, 'Withdraw request');
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        await tester.tap(submit);
        await tester.pump();
        session.clear();
        failure
            ? pending.completeError(
                const BackendException('Offline.', status: 503),
              )
            : pending.complete(returnDetail(success: 'Updated.'));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(TextFormField, 'Reason or receipt details'),
          findsNothing,
        );
        expect(find.textContaining('RETURN-TEST-4'), findsNothing);
        tester.state<NavigatorState>(find.byType(Navigator).last).pop();
        await tester.pumpAndSettle();
        expect(find.textContaining(privateDetails), findsNothing);
        expect(session.submissions, hasLength(1));
      },
    );
  }

  for (final confirmation in ['', null, 42]) {
    testWidgets(
      'command acknowledgement must contain a nonempty message: $confirmation',
      (tester) async {
        await command(tester);
        final result = returnDetail(status: 'withdrawn', version: 2);
        result.props['flash'] = {'success': confirmation};
        session.onSubmit = (_) async => result;
        await returnPress(
          tester,
          find.widgetWithText(FilledButton, 'Withdraw request'),
        );
        expect(find.text('Retry same update'), findsOneWidget);
        expect(session.submissions, hasLength(1));
      },
    );
  }

  testWidgets('return quantities reject malformed or unavailable units', (
    tester,
  ) async {
    await form(tester);
    final quantity = find.widgetWithText(TextFormField, 'Quantity to return');
    for (final value in ['0', '-1', '1.5', 'abc', '3', '100', '１２']) {
      tester.widget<TextFormField>(quantity).controller!.text = value;
      await returnPress(
        tester,
        find.widgetWithText(FilledButton, 'Request a return'),
      );
      expect(session.submissions, isEmpty, reason: value);
    }
  });

  testWidgets(
    'return description must contain ten to one thousand characters',
    (tester) async {
      await form(tester);
      final description = find.widgetWithText(TextFormField, 'What happened?');
      for (final value in [' ', 'too short', 'x' * 1001]) {
        tester.widget<TextFormField>(description).controller!.text = value;
        await returnPress(
          tester,
          find.widgetWithText(FilledButton, 'Request a return'),
        );
        expect(session.submissions, isEmpty);
      }
    },
  );

  testWidgets('return description rejects unsafe notes before submitting', (
    tester,
  ) async {
    await form(tester);
    final description = find.widgetWithText(TextFormField, 'What happened?');
    for (final value in [
      'The damage is <script>shown</script>.',
      'javascript:send-private-data()',
      'The label has a\ttab in it.',
      'The seam is hidden\u200bfrom view.',
    ]) {
      tester.widget<TextFormField>(description).controller!.text = value;
      await returnPress(
        tester,
        find.widgetWithText(FilledButton, 'Request a return'),
      );
      expect(session.submissions, isEmpty, reason: value);
    }
  });

  testWidgets('a return needs selected items and at least one photo', (
    tester,
  ) async {
    await form(tester, photo: false);
    await returnPress(
      tester,
      find.widgetWithText(FilledButton, 'Request a return'),
    );
    expect(session.submissions, isEmpty);
    await returnPress(tester, find.text('Add photo of the problem'));
    await returnPress(
      tester,
      find.widgetWithText(CheckboxListTile, 'Test purchase'),
    );
    await returnPress(
      tester,
      find.widgetWithText(FilledButton, 'Request a return'),
    );
    expect(session.submissions, isEmpty);
  });

  testWidgets('a return cannot select more than five evidence photos', (
    tester,
  ) async {
    await form(tester);
    for (var i = 1; i < 5; i++) {
      await returnPress(tester, find.text('Add photo of the problem'));
    }
    expect(picker.calls, 5);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Add photo of the problem'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'repeated return submission creates one request with allowed fields',
    (tester) async {
      await form(tester);
      final pending = Completer<WebPage>();
      session.onSubmit = (_) => pending.future;
      final submit = find.widgetWithText(FilledButton, 'Request a return');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        await tester.tap(submit);
      }
      expect(session.submissions, hasLength(1));
      expect(session.submissions.single.values.keys.toSet(), {
        'request_token',
        'reason',
        'description',
        'items',
      });
      expect(session.submissions.single.files.single.field, 'photos[0]');
      pending.complete(returnDetail(success: 'Saved.'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Your return request was saved.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('uncertain creation retry retains the same payload and photos', (
    tester,
  ) async {
    await form(tester);
    session.onSubmit = (_) async =>
        throw const BackendException('Uncertain result.', status: 503);
    await returnPress(
      tester,
      find.widgetWithText(FilledButton, 'Request a return'),
    );
    final original = session.submissions.single;
    session.onSubmit = (_) async => returnDetail(success: 'Saved.');
    await returnPress(
      tester,
      find.widgetWithText(FilledButton, 'Retry same return request'),
    );
    expect(session.submissions, hasLength(2));
    expect(session.submissions.last.values, original.values);
    expect(
      session.submissions.last.files.single.bytes,
      original.files.single.bytes,
    );
  });

  testWidgets('server photo rejection retains an editable creation draft', (
    tester,
  ) async {
    await form(tester);
    session.onSubmit = (_) async => throw const BackendException(
      'Choose a real photo.',
      status: 422,
      fields: {'photos.0': 'Choose a real JPG, PNG or WebP photo up to 5 MB.'},
    );
    await returnPress(
      tester,
      find.widgetWithText(FilledButton, 'Request a return'),
    );
    expect(find.textContaining('Choose a real JPG'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'What happened?'),
          )
          .enabled,
      isTrue,
    );
    expect(find.text('Request a return'), findsWidgets);
  });

  testWidgets(
    'a missing server request token blocks creation before submission',
    (tester) async {
      final page = returnForm();
      page.props['requestToken'] = '';
      session.onPage = (_) async => page;
      await form(tester);
      await returnPress(
        tester,
        find.widgetWithText(FilledButton, 'Request a return'),
      );
      expect(session.submissions, isEmpty);
    },
  );

  testWidgets('a refresh failure keeps details but disables stale decisions', (
    tester,
  ) async {
    await open(tester);
    session.onPage = (_) async =>
        throw const BackendException('Offline.', status: 503);
    await tester.tap(find.byTooltip('Refresh returns'));
    await tester.pumpAndSettle();
    expect(find.textContaining(privateDetails), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Withdraw request'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('repeated decision taps open only one native update page', (
    tester,
  ) async {
    final observer = ReturnNavigationObserver();
    await open(tester, observer: observer);
    final action = find.widgetWithText(OutlinedButton, 'Withdraw request');
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      // Later taps deliberately arrive while the first route is opening.
      await tester.tap(action, warnIfMissed: false);
    }
    await tester.pumpAndSettle();
    expect(observer.opened, 1);
  });

  testWidgets(
    'refreshed return items cannot leave removed purchases in the request',
    (tester) async {
      await form(tester);
      final fresh = returnForm();
      fresh.props['items'] = [];
      session.onPage = (_) async => fresh;
      await tester.tap(find.byTooltip('Refresh returns'));
      await tester.pumpAndSettle();
      await returnPress(
        tester,
        find.widgetWithText(FilledButton, 'Request a return'),
      );
      expect(session.submissions, isEmpty);
    },
  );

  testWidgets(
    'newly unavailable return units are deselected and remain editable',
    (tester) async {
      await form(tester);
      final fresh = returnForm();
      ((fresh.props['items'] as List).first as Map)['available_quantity'] = 0;
      session.onPage = (_) async => fresh;
      await tester.tap(find.byTooltip('Refresh returns'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Test purchase'),
            )
            .value,
        isFalse,
      );
      expect(
        find.widgetWithText(TextFormField, 'Quantity to return'),
        findsNothing,
      );
      expect(session.submissions, isEmpty);
    },
  );

  testWidgets(
    'changed return reasons reset an obsolete choice without crashing',
    (tester) async {
      await form(tester);
      final fresh = returnForm();
      fresh.props['reasons'] = {'wrong_item': 'Wrong item'};
      session.onPage = (_) async => fresh;
      await tester.tap(find.byTooltip('Refresh returns'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .state<FormFieldState<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .value,
        isNull,
      );
      expect(session.submissions, isEmpty);
    },
  );
}
