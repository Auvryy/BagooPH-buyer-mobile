import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/profile/purchases_section.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/account_fixtures.dart';
import 'support/fake_buyer_repository.dart' show buyer;
import 'support/return_fixtures.dart';

void main() {
  for (final resume in [true, false]) {
    testWidgets(
      resume
          ? 'resuming expired purchases removes private order rows'
          : 'a cached Buy again action cannot start after account expiry',
      (tester) async {
        final repository = AccountFixtureRepository();
        addTearDown(repository.session.close);
        final session = repository.session as ReturnSession;
        session.onPage = (_) async => const WebPage('Cart/Index', {
          'auth': {'user': buyer},
          'items': [],
        });
        repository.onJson = (_) async => {
          'result': {
            'order_id': 11,
            'items': [
              {'cart_item_id': 3},
            ],
          },
        };
        final page = WebPage('Buyer/Profile', {
          ...accountPage().props,
          'orders': {
            'current_page': 1,
            'last_page': 1,
            'data': [
              {
                'id': 11,
                'order_number': 'PRIVATE-11',
                'items': [],
                'can_buy_again': true,
                'buy_again_token': 'synthetic-token',
              },
            ],
          },
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            home: Scaffold(
              body: PurchasesSection(
                repository: repository,
                page: page,
                onQuery: (_, _) {},
                reload: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final action = tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Buy again'))
            .onPressed!;
        session.clear();
        if (resume) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        } else {
          action();
        }
        await tester.pumpAndSettle();
        expect(repository.calls, isEmpty);
        expect(find.text('Order #PRIVATE-11'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
  for (final accept in [true, false]) {
    testWidgets(
      'queued confirmation decision $accept consumes only its dialog',
      (tester) async {
        final errors = <Object>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => confirmAction(
                    context,
                    'Confirm receipt?',
                    'Synthetic decision only.',
                    'Confirm Received',
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final callback = accept
            ? tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Confirm Received'),
                  )
                  .onPressed!
            : tester
                  .widget<TextButton>(
                    find.widgetWithText(TextButton, 'Go back'),
                  )
                  .onPressed!;
        for (var n = 0; n < 3; n++) {
          try {
            callback();
          } catch (e) {
            errors.add(e);
          }
        }
        await tester.pumpAndSettle();
        expect(errors, isEmpty);
        expect(tester.takeException(), isNull);
        expect(find.text('Open'), findsOneWidget);
      },
    );
  }
  testWidgets('queued receipt actions open one confirmation dialog', (
    tester,
  ) async {
    final repository = AccountFixtureRepository();
    addTearDown(repository.session.close);
    final page = WebPage('Buyer/Profile', {
      ...accountPage().props,
      'orders': {
        'data': [
          {
            'id': 11,
            'order_number': 'PRIVATE-11',
            'items': [],
            'can_confirm_receipt': true,
          },
        ],
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PurchasesSection(
            repository: repository,
            page: page,
            onQuery: (_, _) {},
            reload: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final action = tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Confirm Received'),
        )
        .onPressed!;
    action();
    action();
    action();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
    expect(repository.calls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  for (final expire in [false, true]) {
    testWidgets(
      'receipt decision after session expiry $expire respects current ownership',
      (tester) async {
        final repository = AccountFixtureRepository();
        addTearDown(repository.session.close);
        final page = WebPage('Buyer/Profile', {
          ...accountPage().props,
          'orders': {
            'data': [
              {
                'id': 11,
                'order_number': 'PRIVATE-11',
                'items': [],
                'can_confirm_receipt': true,
              },
            ],
          },
        });
        repository.onMutation = (_) async => page;
        var reloads = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PurchasesSection(
                repository: repository,
                page: page,
                onQuery: (_, _) {},
                reload: () async {
                  reloads++;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Confirm Received'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Confirm Received'));
        await tester.pumpAndSettle();
        if (expire) repository.session.clear();
        final confirm = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        );
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(repository.calls, hasLength(expire ? 0 : 1));
        expect(reloads, expire ? 0 : 1);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
