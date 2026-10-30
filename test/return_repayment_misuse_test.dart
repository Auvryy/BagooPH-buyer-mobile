import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:bagoo_buyer_mobile/features/profile/returns_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'returns_misuse_test.dart' show returnPress, privateDetails;
import 'support/return_fixtures.dart';

WebPage repayment({
  String action = 'confirm-receipt',
  dynamic source = 102,
  dynamic version = 8,
}) {
  final page = returnDetail(
    status: action == 'confirm-receipt'
        ? 'repayment_disputed'
        : 'payment_recorded',
    version: 8,
    actions: [],
  );
  final item = Map<String, dynamic>.from(page.props['returnCase'] as Map);
  page.props['returnCase'] = item;
  item['version'] = version;
  item['money'] = {
    'mode': 'cod',
    'adjustment': {
      'gross_cents': 10000,
      'shop_discount_cents': 500,
      'platform_discount_cents': 0,
      'buyer_cents': 9500,
    },
    'actions': [action],
    'history': [
      {
        'id': 101,
        'event_type': 'record-repayment',
        'amount_cents': 9500,
        'reason': 'Earlier recorded transfer.',
      },
      {
        'id': source,
        'event_type': 'record-repayment',
        'amount_cents': 9500,
        'reason': 'Latest recorded transfer.',
      },
      if (action == 'confirm-receipt')
        {
          'id': 103,
          'event_type': 'report-nonreceipt',
          'amount_cents': 9500,
          'reason': 'Receipt needs investigation.',
        },
    ],
  };
  return page;
}

WebPage returnIndex() => WebPage('Returns/Index', {
  'auth': {
    'user': {'id': 7, 'role': 'buyer'},
  },
  'cases': {
    'current_page': 1,
    'last_page': 1,
    'data': [
      {
        'id': 4,
        'reference': 'PRIVATE-RETURN-4',
        'order_number': 'TEST-11',
        'status': 'requested',
      },
    ],
  },
});

void main() {
  late ReturnSession session;
  late ProfileRepository repository;
  setUp(() {
    session = ReturnSession();
    repository = ProfileRepository(BuyerRepository(session));
    session.onPage = (_) async => repayment();
    session.onSubmit = (_) async => returnDetail(
      status: 'repaid',
      version: 9,
      actions: [],
      success: 'Receipt confirmed.',
    );
  });
  tearDown(() => session.close());

  Future<void> open(WidgetTester tester, {bool index = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ReturnsPage(repository: repository, caseId: index ? null : 4),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> decision(WidgetTester tester, String action) async {
    await open(tester);
    await returnPress(
      tester,
      find.text(
        action == 'confirm-receipt'
            ? 'Confirm repayment received'
            : 'Report repayment not received',
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason or receipt details'),
      'These are my actual repayment receipt details.',
    );
    expect(session.submissions, isEmpty);
  }

  for (final action in ['confirm-receipt', 'report-nonreceipt']) {
    testWidgets(
      'repayment $action uses the latest transfer and confirmed case version',
      (tester) async {
        session.onPage = (_) async => repayment(action: action);
        await decision(tester, action);
        await returnPress(
          tester,
          find.widgetWithText(
            FilledButton,
            action == 'confirm-receipt'
                ? 'Confirm repayment received'
                : 'Report repayment not received',
          ),
        );
        final request = session.submissions.single;
        expect(request.path, '/buyer-returns/4/money');
        expect(request.values['source_event_id'], 102);
        expect(request.values['expected_version'], 8);
        expect(request.values['action'], action);
        expect(request.values.keys.toSet(), {
          'action',
          'expected_version',
          'request_token',
          'reason',
          'source_event_id',
        });
      },
    );
  }

  testWidgets(
    'repeated repayment presses send one request and uncertain retries keep its intent',
    (tester) async {
      await decision(tester, 'confirm-receipt');
      final pending = Completer<WebPage>();
      session.onSubmit = (_) => pending.future;
      final button = find.widgetWithText(
        FilledButton,
        'Confirm repayment received',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await Scrollable.ensureVisible(tester.element(button), alignment: .5);
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        await tester.tap(button);
      }
      expect(session.submissions, hasLength(1));
      final original = session.submissions.single;
      pending.completeError(
        const BackendException('Uncertain reply.', status: 503),
      );
      await tester.pumpAndSettle();
      session.onSubmit = (_) async => returnDetail(
        status: 'repaid',
        version: 9,
        actions: [],
        success: 'Receipt confirmed.',
      );
      await returnPress(tester, find.text('Retry same update'));
      expect(session.submissions, hasLength(2));
      expect(session.submissions.last.values, original.values);
    },
  );

  for (final source in [null, 0, -1, '102']) {
    testWidgets('repayment cannot submit an unconfirmed source: $source', (
      tester,
    ) async {
      session.onPage = (_) async => repayment(source: source);
      await decision(tester, 'confirm-receipt');
      await returnPress(
        tester,
        find.widgetWithText(FilledButton, 'Confirm repayment received'),
      );
      expect(session.submissions, isEmpty);
    });
  }

  for (final version in [null, 0, -1, 1.5, '8']) {
    testWidgets('repayment cannot submit an invalid case version: $version', (
      tester,
    ) async {
      session.onPage = (_) async => repayment(version: version);
      await decision(tester, 'confirm-receipt');
      await returnPress(
        tester,
        find.widgetWithText(FilledButton, 'Confirm repayment received'),
      );
      expect(session.submissions, isEmpty);
    });
  }

  for (final beforeNavigation in [true, false]) {
    testWidgets(
      'return-list navigation retains the opening account: $beforeNavigation',
      (tester) async {
        session.onPage = (path) async =>
            path.contains('?') ? returnIndex() : returnDetail();
        await open(tester, index: true);
        final row = find.text('PRIVATE-RETURN-4');
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        if (beforeNavigation) session.clear();
        await tester.tap(row);
        if (!beforeNavigation) session.clear();
        await tester.pumpAndSettle();
        expect(session.pageRequests, hasLength(1));
        expect(find.textContaining(privateDetails), findsNothing);
      },
    );
  }
}
