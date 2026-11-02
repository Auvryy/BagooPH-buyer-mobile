import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:bagoo_buyer_mobile/features/profile/returns_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/return_fixtures.dart';
import 'support/fake_buyer_repository.dart' show buyer;

const privateDetails = 'Private return details for the original buyer.';

Future<void> returnPress(WidgetTester tester, Finder target) async {
  if (target.hitTestable().evaluate().isEmpty) {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(target.first), alignment: .5);
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

  testWidgets('a fractional return ID invalidates the return history page', (
    tester,
  ) async {
    session.onPage = (path) async => path.startsWith('/buyer-returns?page=')
        ? WebPage('Returns/Index', {
            'auth': {'user': buyer},
            'cases': {
              'data': [
                {
                  'id': 4.5,
                  'reference': 'RETURN-FRACTIONAL',
                  'order_number': 'TEST-11',
                  'status': 'requested',
                  'created_at': '2026-11-01T00:00:00Z',
                },
              ],
              'current_page': 1,
              'last_page': 1,
              'per_page': 12,
              'total': 1,
              'from': 1,
              'to': 1,
            },
          })
        : returnDetail();

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ReturnsPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('RETURN-FRACTIONAL'), findsNothing);
    expect(
      find.textContaining('Return history pagination could not be confirmed'),
      findsOneWidget,
    );
    expect(session.pageRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final entry in <({String label, List<dynamic> rows})>[
    (
      label: 'mixed malformed row',
      rows: [
        {
          'id': 4,
          'reference': 'PRIVATE-RETURN-4',
          'order_number': 'TEST-11',
          'status': 'requested',
          'created_at': '2026-11-01T00:00:00Z',
        },
        'malformed return row',
      ],
    ),
    (
      label: 'duplicate case IDs',
      rows: [
        {
          'id': 4,
          'reference': 'PRIVATE-RETURN-4',
          'order_number': 'TEST-11',
          'status': 'requested',
          'created_at': '2026-11-01T00:00:00Z',
        },
        {
          'id': 4,
          'reference': 'PRIVATE-RETURN-4B',
          'order_number': 'TEST-11',
          'status': 'approved',
          'created_at': '2026-11-02T00:00:00Z',
        },
      ],
    ),
  ]) {
    testWidgets('return history rejects ${entry.label}', (tester) async {
      session.onPage = (_) async => WebPage('Returns/Index', {
        'auth': {'user': buyer},
        'cases': {'current_page': 1, 'last_page': 1, 'data': entry.rows},
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: ReturnsPage(repository: repository),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PRIVATE-RETURN-4'), findsNothing);
      expect(find.text('PRIVATE-RETURN-4B'), findsNothing);
      expect(
        find.textContaining('Return history pagination could not be confirmed'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final (field, value) in [
    ('current_page', 1.5),
    ('last_page', 0),
    ('last_page', 99),
    ('per_page', 10),
    ('total', '1'),
    ('from', 2),
    ('to', 2),
    ('data', 'not-a-list'),
  ]) {
    testWidgets('return history rejects malformed paginator $field=$value', (
      tester,
    ) async {
      session.onPage = (_) async {
        final cases = <String, dynamic>{
          'current_page': 1,
          'last_page': 1,
          'per_page': 12,
          'total': 1,
          'from': 1,
          'to': 1,
          'data': [
            {
              'id': 4,
              'reference': 'PRIVATE-RETURN-4',
              'order_number': 'TEST-11',
              'status': 'requested',
              'created_at': '2026-11-01T00:00:00Z',
            },
          ],
        };
        cases[field] = value;
        return WebPage('Returns/Index', {
          'auth': {'user': buyer},
          'cases': cases,
        });
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: ReturnsPage(repository: repository),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PRIVATE-RETURN-4'), findsNothing);
      expect(
        find.textContaining('Return history pagination could not be confirmed'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('return history rereads the last valid page when stale', (
    tester,
  ) async {
    final requested = <String>[];
    session.onPage = (path) async {
      requested.add(path);
      final page = requested.length == 1 ? 3 : 2;
      final rows = requested.length == 1
          ? <Map<String, dynamic>>[]
          : [
              {
                'id': 4,
                'reference': 'PRIVATE-RETURN-4',
                'order_number': 'TEST-11',
                'status': 'requested',
                'created_at': '2026-11-01T00:00:00Z',
              },
            ];
      return WebPage('Returns/Index', {
        'auth': {'user': buyer},
        'cases': {
          'current_page': page,
          'last_page': 2,
          'per_page': 12,
          'total': 13,
          'from': rows.isEmpty ? null : 13,
          'to': rows.isEmpty ? null : 13,
          'data': rows,
        },
      });
    };

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ReturnsPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(requested, ['/buyer-returns?page=1', '/buyer-returns?page=2']);
    expect(find.text('PRIVATE-RETURN-4'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('return form rejects fractional purchased item IDs', (
    tester,
  ) async {
    final form = returnForm();
    ((form.props['items'] as List).first as Map)['id'] = 101.5;
    session.onPage = (_) async => form;

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ReturnsPage(repository: repository, orderId: 11),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test purchase'), findsNothing);
    expect(find.text('Request a return'), findsNothing);
    expect(
      find.text(
        'These purchased items could not be confirmed. Reload the purchase and try again.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('return form rejects duplicate purchased item IDs', (
    tester,
  ) async {
    final form = returnForm();
    (form.props['items'] as List).add(<String, Object>{
      ...Map<String, dynamic>.from((form.props['items'] as List).first as Map),
      'name': 'Conflicting duplicate purchase',
    });
    session.onPage = (_) async => form;

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ReturnsPage(repository: repository, orderId: 11),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test purchase'), findsNothing);
    expect(find.text('Conflicting duplicate purchase'), findsNothing);
    expect(find.text('Request a return'), findsNothing);
    expect(
      find.text(
        'These purchased items could not be confirmed. Reload the purchase and try again.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('malformed decision actions are hidden without crashing', (
    tester,
  ) async {
    final page = returnDetail();
    final details = page.props['returnCase'] as Map<String, dynamic>;
    details['actions'] = ['withdraw', 7];
    session.onPage = (_) async => page;

    await open(tester);

    expect(find.text('Withdraw request'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('malformed repayment actions are hidden without crashing', (
    tester,
  ) async {
    final page = returnDetail();
    final details = page.props['returnCase'] as Map<String, dynamic>;
    (details['money'] as Map<String, dynamic>)['actions'] = 'confirm-receipt';
    session.onPage = (_) async => page;

    await open(tester);

    expect(find.text('Confirm repayment received'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final deadline in [
    null,
    '2026-02-30T10:00:00Z',
    '2020-01-01T10:00:00Z',
  ]) {
    testWidgets(
      'drop-off authority requires a valid future deadline: $deadline',
      (tester) async {
        final page = returnDetail();
        final details = page.props['returnCase'] as Map<String, dynamic>;
        if (deadline != null) details['dropoff_until'] = deadline;
        details['custody'] = {
          'status': 'ready',
          'custody': {'kind': 'buyer'},
          'can_dropoff': true,
          'hubs': [],
          'actions': [],
          'position': 0,
        };
        session.onPage = (_) async => page;

        await open(tester);

        expect(
          find.textContaining('Bring the approved items to the original'),
          findsNothing,
        );
        expect(
          find.textContaining('No current drop-off authority is available'),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('malformed return history is not displayed as a partial audit', (
    tester,
  ) async {
    final page = returnDetail();
    final details = page.props['returnCase'] as Map<String, dynamic>;
    details['history'] = [
      {
        'event_type': 'seller-approved',
        'created_at': '2026-11-01T10:00:00Z',
        'actor_role': 'seller',
        'target_status': 'approved',
        'reason': 'Recorded seller decision.',
      },
      'malformed history row',
    ];
    session.onPage = (_) async => page;

    await open(tester);

    expect(find.textContaining('seller approved'), findsNothing);
    expect(find.textContaining(privateDetails), findsNothing);
  });

  testWidgets('return history rejects an impossible event timestamp', (
    tester,
  ) async {
    final page = returnDetail();
    final details = page.props['returnCase'] as Map<String, dynamic>;
    details['history'] = [
      {
        'reference': 'BRE-TEST-1',
        'event_type': 'requested',
        'actor_role': 'buyer',
        'reason': 'Return request was recorded.',
        'source_status': null,
        'target_status': 'requested',
        'created_at': '2026-02-30T10:00:00Z',
      },
    ];
    session.onPage = (_) async => page;

    await open(tester);

    expect(find.textContaining('requested · Date unavailable'), findsNothing);
    expect(find.textContaining(privateDetails), findsNothing);
  });

  testWidgets('return evidence must belong to the displayed case', (
    tester,
  ) async {
    final page = returnDetail();
    final details = page.props['returnCase'] as Map<String, dynamic>;
    details['evidence'] = [
      {
        'id': 12,
        'url': '/buyer-returns/99/evidence/12',
        'mime': 'image/jpeg',
        'bytes': 1024,
        'purpose': 'request',
      },
    ];
    session.onPage = (_) async => page;

    await open(tester);

    expect(find.text('View return request photo'), findsNothing);
    expect(find.textContaining(privateDetails), findsNothing);
  });

  testWidgets('return line details require a complete purchase snapshot', (
    tester,
  ) async {
    final page = returnDetail();
    final details = page.props['returnCase'] as Map<String, dynamic>;
    details['items'] = [
      {
        'id': 101,
        'quantity': null,
        'purchase': {'name': null},
      },
    ];
    session.onPage = (_) async => page;

    await open(tester);

    expect(find.textContaining('Purchased item × null'), findsNothing);
    expect(find.textContaining(privateDetails), findsNothing);
  });

  testWidgets('return parcel route requires complete hub details', (
    tester,
  ) async {
    final page = returnDetail();
    final details = page.props['returnCase'] as Map<String, dynamic>;
    details['custody'] = {
      'status': 'awaiting_dropoff',
      'position': 0,
      'custody': {'kind': 'buyer'},
      'hubs': [
        {'id': 12},
      ],
      'actions': [],
    };
    session.onPage = (_) async => page;

    await open(tester);

    expect(find.textContaining('null · null'), findsNothing);
    expect(find.textContaining(privateDetails), findsNothing);
  });

  testWidgets('return label action requires its buyer facing label', (
    tester,
  ) async {
    final page = returnDetail();
    final details = page.props['returnCase'] as Map<String, dynamic>;
    details['custody'] = {
      'status': 'label_needed',
      'position': 0,
      'custody': {'kind': 'buyer'},
      'hubs': [],
      'actions': [
        {'action': 'prepare-label', 'hub_id': null, 'label': 42},
      ],
    };
    session.onPage = (_) async => page;

    await open(tester);

    expect(find.text('42'), findsNothing);
    expect(find.textContaining(privateDetails), findsNothing);
  });

  for (final weight in [double.nan, -1000, '500']) {
    testWidgets('invalid parcel weight is not displayed as fact: $weight', (
      tester,
    ) async {
      final page = returnDetail();
      final details = page.props['returnCase'] as Map<String, dynamic>;
      details['custody'] = {
        'status': 'awaiting_dropoff',
        'custody': {'kind': 'buyer'},
        'weight_grams': weight,
        'position': 0,
        'hubs': [],
        'actions': [],
      };
      session.onPage = (_) async => page;

      await open(tester);

      expect(find.textContaining(' kg'), findsNothing);
      expect(find.text('Packed weight has not been recorded.'), findsOneWidget);
    });
  }

  testWidgets('duplicate return actions render only one control per action', (
    tester,
  ) async {
    final page = returnDetail();
    final details = page.props['returnCase'] as Map<String, dynamic>;
    details['actions'] = ['withdraw', 'withdraw'];
    (details['money'] as Map<String, dynamic>)
      ..['actions'] = ['confirm-receipt', 'confirm-receipt']
      ..['history'] = [
        {
          'id': 88,
          'event_type': 'record-repayment',
          'amount_cents': 9500,
          'reason': 'Recorded transfer.',
          'created_at': '2026-11-01T10:00:00Z',
        },
      ];
    session.onPage = (_) async => page;

    await open(tester);

    expect(
      find.widgetWithText(OutlinedButton, 'Withdraw request'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Confirm repayment received'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
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

  testWidgets('return details require a confirmed purchase reference', (
    tester,
  ) async {
    final page = returnDetail();
    final details = page.props['returnCase'] as Map<String, dynamic>;
    details['order'] = {'id': 11, 'order_number': 42};
    session.onPage = (_) async => page;

    await open(tester);

    expect(find.textContaining('Purchase 42'), findsNothing);
    expect(find.textContaining(privateDetails), findsNothing);
  });

  testWidgets(
    'resuming a return after account change clears loaded private data',
    (tester) async {
      await open(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      session.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining(privateDetails), findsNothing);
      expect(session.pageRequests, hasLength(1));
    },
  );

  for (final beforeNavigation in [true, false]) {
    testWidgets(
      'private return evidence keeps the opening account across navigation: $beforeNavigation',
      (tester) async {
        final page = returnDetail();
        (page.props['returnCase'] as Map)['evidence'] = [
          {
            'id': 1,
            'url': '/buyer-returns/4/evidence/1',
            'mime': 'image/png',
            'bytes': 64,
            'purpose': 'request',
          },
        ];
        session.onPage = (_) async => page;
        session.onDocument = (_) async =>
            RemoteDocument(returnPhotoBytes(), 'image/png');
        await open(tester);
        final view = find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data?.startsWith('View ') ?? false) &&
              (widget.data?.endsWith(' photo') ?? false),
        );
        await tester.ensureVisible(view);
        await tester.pumpAndSettle();
        if (beforeNavigation) session.clear();
        await tester.tap(view);
        if (!beforeNavigation) session.clear();
        await tester.pumpAndSettle();
        expect(session.documentRequests, isEmpty);
        expect(find.byType(Image), findsNothing);
      },
    );
  }
}
