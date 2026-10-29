import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:bagoo_buyer_mobile/features/profile/returns_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/return_fixtures.dart';

const privateDetails = 'Private return details for the original buyer.';

Future<void> returnPress(WidgetTester tester, Finder target) async {
  if (target.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(target.first);
    await tester.pumpAndSettle();
  }
  expect(target.hitTestable(), findsWidgets);
  await tester.tap(target.hitTestable().first);
  await tester.pumpAndSettle();
}

void main() {
  late ReturnSession session;
  late ProfileRepository repository;
  setUp(() {
    session = ReturnSession();
    repository = ProfileRepository(BuyerRepository(session));
    session.onPage = (_) async => returnDetail();
  });
  tearDown(() => session.close());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ReturnsPage(repository: repository, caseId: 4),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final status in [401, 403, 404, 419]) {
    testWidgets(
      'return access failure $status clears private details and actions',
      (tester) async {
        await open(tester);
        expect(find.textContaining(privateDetails), findsOneWidget);
        session.onPage = (_) async =>
            throw BackendException('Access denied.', status: status);
        await tester.tap(find.byTooltip('Refresh returns'));
        await tester.pumpAndSettle();
        expect(find.textContaining(privateDetails), findsNothing);
        expect(find.text('Withdraw request'), findsNothing);
      },
    );
  }

  testWidgets(
    'a different buyer response cannot replace or retain private details',
    (tester) async {
      await open(tester);
      session.onPage = (_) async =>
          returnDetail(owner: 8, description: 'Foreign buyer details');
      await tester.tap(find.byTooltip('Refresh returns'));
      await tester.pumpAndSettle();
      expect(find.textContaining(privateDetails), findsNothing);
      expect(find.textContaining('Foreign buyer details'), findsNothing);
    },
  );

  testWidgets('changed identity blocks opening a return mutation', (
    tester,
  ) async {
    await open(tester);
    session.clear();
    await returnPress(tester, find.text('Withdraw request'));
    expect(
      find.widgetWithText(TextFormField, 'Reason or receipt details'),
      findsNothing,
    );
    expect(find.textContaining(privateDetails), findsNothing);
    expect(session.submissions, isEmpty);
  });

  testWidgets(
    'a pending return read cannot reveal details after identity changes',
    (tester) async {
      final pending = Completer<WebPage>();
      session.onPage = (_) => pending.future;
      await tester.pumpWidget(
        MaterialApp(home: ReturnsPage(repository: repository, caseId: 4)),
      );
      await tester.pump();
      session.clear();
      pending.complete(returnDetail());
      await tester.pumpAndSettle();
      expect(find.textContaining(privateDetails), findsNothing);
    },
  );

  testWidgets('a return response needs a valid numeric buyer identity', (
    tester,
  ) async {
    final page = returnDetail();
    (page.props['auth'] as Map)['user'] = {'role': 'buyer'};
    session.onPage = (_) async => page;
    await open(tester);
    expect(find.textContaining(privateDetails), findsNothing);
  });

  testWidgets(
    'temporary return failure retains confirmed details for explicit retry',
    (tester) async {
      await open(tester);
      session.onPage = (_) async =>
          throw const BackendException('Offline.', status: 503);
      await tester.tap(find.byTooltip('Refresh returns'));
      await tester.pumpAndSettle();
      expect(find.textContaining(privateDetails), findsOneWidget);
      expect(find.textContaining('Offline.'), findsWidgets);
    },
  );

  testWidgets('a mismatched return ID is rejected before display', (
    tester,
  ) async {
    session.onPage = (_) async => returnDetail(id: 99);
    await open(tester);
    expect(find.textContaining(privateDetails), findsNothing);
    expect(find.text('Withdraw request'), findsNothing);
  });
}
