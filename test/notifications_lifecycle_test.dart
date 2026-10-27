import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/notifications/notifications_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart' show buyer;

const _noticeId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _snapshotId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

WebPage _inbox(String path, {int owner = 7, String title = 'Order update'}) {
  final query = Uri.parse(path).queryParameters;
  return WebPage('Notifications/Index', {
    'auth': {
      'user': {...buyer, 'id': owner},
    },
    'errors': <String, dynamic>{},
    'portal': 'buyer',
    'available': true,
    'filter': query['filter'] ?? 'all',
    'notices': {
      'data': [
        {
          'id': _noticeId,
          'type': 'order-event',
          'created_at': '2026-10-26T08:00:00Z',
          'read_at': null,
          'href': null,
          'data': {'title': title, 'body': 'Check the current order details.'},
        },
      ],
      'current_page': int.parse(query['page'] ?? '1'),
      'last_page': 2,
    },
    'readSnapshot': {'id': _snapshotId, 'count': 1},
    'notificationSummary': {'available': true, 'unread': 1},
  });
}

Widget _app(
  BuyerRepository repository, {
  int owner = 7,
  ValueChanged<int>? onSummaryChanged,
}) => MaterialApp(
  theme: BagooTheme.light,
  home: NotificationsPage(
    key: const ValueKey('notifications'),
    repository: repository,
    ownerId: owner,
    onSummaryChanged: onSummaryChanged,
  ),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pump();
}

void main() {
  late ControlledWebSession session;
  late BuyerRepository repository;

  setUp(() {
    session = ControlledWebSession();
    repository = BuyerRepository(session);
    session.onPage = (path) async => _inbox(path);
    session.onGet = (_) async => {
      'notices': <dynamic>[],
      'summary': {'available': true, 'unread': 0},
    };
  });
  tearDown(() => session.close());

  testWidgets(
    'resuming refreshes the current filter and page without marking read',
    (tester) async {
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Unread'));
      await tester.pumpAndSettle();
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Next'));
      await tester.pumpAndSettle();
      final readsBeforeResume = session.pageRequests.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(session.pageRequests.length, readsBeforeResume + 1);
      expect(session.pageRequests.last, '/notifications?filter=unread&page=2');
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(session.posts, isEmpty);
    },
  );

  testWidgets(
    'a confirmed read finishing after disposal starts no new requests',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      session.onPost = (_) => pending.future;
      final summaries = <int>[];
      await tester.pumpWidget(
        _app(repository, onSummaryChanged: summaries.add),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Mark read'));
      expect(session.posts.single.path, '/notifications/$_noticeId/read');
      expect(session.posts.single.method, 'PATCH');
      final reads = session.pageRequests.length;
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete({'read_at': '2026-10-27T00:00:00Z'});
      await tester.pumpAndSettle();
      expect(session.pageRequests.length, reads);
      expect(session.getRequests, isEmpty);
      expect(summaries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a rejected snapshot finishing after disposal does not reload', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    session.onPost = (_) => pending.future;
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Mark all as read (1)'));
    expect(session.posts.single.values, {'snapshot': _snapshotId});
    final reads = session.pageRequests.length;
    await tester.pumpWidget(const SizedBox.shrink());
    pending.completeError(
      const BackendException(
        'Refresh this list.',
        status: 422,
        fields: {'snapshot': 'This list expired.'},
      ),
    );
    await tester.pumpAndSettle();
    expect(session.pageRequests.length, reads);
    expect(session.getRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an old buyer read cannot refresh a new buyer or update its badge',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      var owner = 7;
      session.onPage = (path) async => _inbox(
        path,
        owner: owner,
        title: owner == 7 ? 'Old buyer update' : 'New buyer update',
      );
      session.onPost = (_) => pending.future;
      final summaries = <int>[];
      await tester.pumpWidget(
        _app(repository, onSummaryChanged: summaries.add),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Mark read'));
      owner = 8;
      await tester.pumpWidget(
        _app(repository, owner: owner, onSummaryChanged: summaries.add),
      );
      await tester.pumpAndSettle();
      final reads = session.pageRequests.length;
      pending.complete({'read_at': '2026-10-27T00:00:00Z'});
      await tester.pumpAndSettle();
      expect(find.text('Old buyer update'), findsNothing);
      expect(find.text('New buyer update'), findsOneWidget);
      expect(session.pageRequests.length, reads);
      expect(session.getRequests, isEmpty);
      expect(summaries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an in-flight badge response is ignored after the buyer changes',
    (tester) async {
      final pendingSummary = Completer<Map<String, dynamic>>();
      var owner = 7;
      session.onPage = (path) async => _inbox(path, owner: owner);
      session.onPost = (_) async => {'read_at': '2026-10-27T00:00:00Z'};
      session.onGet = (_) => pendingSummary.future;
      final summaries = <int>[];
      await tester.pumpWidget(
        _app(repository, onSummaryChanged: summaries.add),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Mark read'));
      await tester.pump();
      expect(session.getRequests, ['/notifications/preview']);
      owner = 8;
      await tester.pumpWidget(
        _app(repository, owner: owner, onSummaryChanged: summaries.add),
      );
      await tester.pumpAndSettle();
      pendingSummary.complete({
        'notices': <dynamic>[],
        'summary': {'available': true, 'unread': 99},
      });
      await tester.pumpAndSettle();
      expect(summaries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a read cannot open an old destination after the session changes',
    (tester) async {
      var reads = 0;
      session.onPage = (path) async {
        final page = _inbox(path, owner: reads++ == 0 ? 7 : 8);
        final notices = page.props['notices'] as Map<String, dynamic>;
        (notices['data'] as List).first['href'] = '/buyer/orders/10';
        return page;
      };
      session.onPost = (_) async => {'read_at': '2026-10-27T00:00:00Z'};
      final summaries = <int>[];
      await tester.pumpWidget(
        _app(repository, onSummaryChanged: summaries.add),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('View update'));
      await tester.pumpAndSettle();
      expect(session.pageRequests, [
        '/notifications?filter=all&page=1',
        '/notifications?filter=all&page=1',
      ]);
      expect(session.getRequests, isEmpty);
      expect(summaries, isEmpty);
      expect(
        find.text('Your account changed. Sign in again to view notifications.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a refresh from another account clears the previous inbox', (
    tester,
  ) async {
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    expect(find.text('Order update'), findsOneWidget);
    session.onPage = (path) async => _inbox(path, owner: 8);
    await _tap(tester, find.byTooltip('Refresh notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Order update'), findsNothing);
    expect(
      find.text('Your account changed. Sign in again to view notifications.'),
      findsOneWidget,
    );
    expect(session.posts, isEmpty);
  });
}
