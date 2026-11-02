import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/features/engagement/engagement_repository.dart';
import 'package:bagoo_buyer_mobile/features/engagement/buyer_destination_router.dart';
import 'package:bagoo_buyer_mobile/features/home/advertisement_exposure.dart';
import 'package:bagoo_buyer_mobile/features/notifications/notification_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart' show productPage;

class NoticeDestinationSession extends ControlledWebSession {
  WebPage? destination;
  @override
  Future<WebPage> submit(
    String path,
    Map<String, dynamic> values, {
    String method = 'POST',
    String? referer,
    List<UploadPart>? files,
  }) async {
    expect(path, '/notifications/${noticeId(1)}/read');
    expect(method, 'PATCH');
    expect(values, {'open': true});
    return destination ??
        productPage(signedIn: true, override: {'slug': 'current-product'});
  }
}

String noticeId(int index) =>
    'aaaaaaaa-aaaa-4aaa-8aaa-${index.toString().padLeft(12, '0')}';
Map<String, dynamic> preview() => {
  'notices': [
    for (var index = 1; index <= 6; index++)
      {
        'id': noticeId(index),
        'type': 'order-event',
        'href': null,
        'data': {
          'title': 'Private update $index',
          'body': List.filled(12, 'Recorded buyer information.').join('\n'),
        },
        'created_at': '2026-10-28T00:00:00Z',
        'read_at': null,
      },
  ],
  'summary': {'available': true, 'unread': 6},
};

void main() {
  test('notifications reject an excessive page before networking', () async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final repository = BuyerEngagementRepository(BuyerRepository(session));

    await expectLater(
      repository.notifications(page: 1000001),
      throwsA(isA<BackendException>()),
    );

    expect(session.pageRequests, isEmpty);
  });

  test('mark displayed rejects a fractional unread count', () async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onPost = (_) async => {
      'summary': {'available': true, 'unread': 2.5},
    };
    final repository = BuyerEngagementRepository(BuyerRepository(session));

    await expectLater(
      repository.markDisplayedNotifications([noticeId(1)]),
      throwsA(isA<BackendException>()),
    );

    expect(session.posts.single.path, '/notifications/read-displayed');
  });

  test('mark all read rejects a fractional unread count', () async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onPost = (_) async => {
      'updated': 1,
      'summary': {'available': true, 'unread': 2.5},
    };
    final repository = BuyerEngagementRepository(BuyerRepository(session));

    await expectLater(
      repository.markNotificationSnapshotRead(noticeId(1)),
      throwsA(isA<BackendException>()),
    );

    expect(session.posts.single.path, '/notifications/read-all');
  });

  testWidgets('preview rejects a fractional unread count', (tester) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final data = preview();
    (data['summary'] as Map)['unread'] = 1.5;
    session.onGet = (_) async => data;
    final summaries = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Scaffold(
          body: NotificationPreview(
            repository: BuyerRepository(session),
            ownerId: 7,
            isCurrentOwner: () => true,
            onSummaryChanged: summaries.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(summaries, isEmpty);
    expect(
      find.textContaining('Notifications are temporarily unavailable'),
      findsOneWidget,
    );
    expect(find.text('Private update 1'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'preview rejects a malformed notice row instead of showing a partial list',
    (tester) async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      final data = preview();
      final notices = List<Object?>.of(data['notices'] as List);
      notices[2] = 'not-a-notice';
      data['notices'] = notices;
      session.onGet = (_) async => data;
      final summaries = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: Scaffold(
            body: NotificationPreview(
              repository: BuyerRepository(session),
              ownerId: 7,
              isCurrentOwner: () => true,
              onSummaryChanged: summaries.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(summaries, isEmpty);
      expect(
        find.textContaining('Notifications are temporarily unavailable'),
        findsOneWidget,
      );
      expect(find.text('Private update 1'), findsNothing);
      expect(find.text('Mark displayed as read (0)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('notification preview rejects duplicate notice identifiers', () async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final data = preview();
    final notices = data['notices'] as List;
    (notices[1] as Map)['id'] = (notices[0] as Map)['id'];
    session.onGet = (_) async => data;

    await expectLater(
      BuyerEngagementRepository(BuyerRepository(session)).notificationPreview(),
      throwsA(isA<BackendException>()),
    );
  });

  test('notification preview rejects more than six notices', () async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final data = preview();
    final notices = data['notices'] as List;
    notices.add({
      ...(notices.first as Map<String, dynamic>),
      'id': noticeId(7),
    });
    session.onGet = (_) async => data;

    await expectLater(
      BuyerEngagementRepository(BuyerRepository(session)).notificationPreview(),
      throwsA(isA<BackendException>()),
    );
  });

  test(
    'notification read requires a valid timezone-qualified acknowledgement',
    () async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      final repository = BuyerEngagementRepository(BuyerRepository(session));
      for (final readAt in [
        'not-a-date',
        '2026-02-30T00:00:00Z',
        '2026-10-29',
      ]) {
        session.onPost = (_) async => {'read_at': readAt};
        await expectLater(
          repository.markNotificationRead(noticeId(1)),
          throwsA(isA<BackendException>()),
        );
      }
      session.onPost = (_) async => {'read_at': '2026-10-29T08:00:00+08:00'};
      await repository.markNotificationRead(noticeId(1));
    },
  );

  for (final malformed in [
    (
      name: 'an impossible creation timestamp',
      change: (Map<String, dynamic> notice) =>
          notice['created_at'] = '2026-02-30T00:00:00Z',
    ),
    (
      name: 'a malformed read timestamp',
      change: (Map<String, dynamic> notice) => notice['read_at'] = 42,
    ),
    (
      name: 'a non-text title',
      change: (Map<String, dynamic> notice) =>
          notice['data'] = {...notice['data'] as Map, 'title': 42},
    ),
  ]) {
    testWidgets('preview rejects ${malformed.name}', (tester) async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      final data = preview();
      malformed.change((data['notices'] as List).first as Map<String, dynamic>);
      session.onGet = (_) async => data;

      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: Scaffold(
            body: NotificationPreview(
              repository: BuyerRepository(session),
              ownerId: 7,
              isCurrentOwner: () => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Private update 1'), findsNothing);
      expect(
        find.textContaining('Notifications are temporarily unavailable'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'opening an update follows the current owned server destination',
    (tester) async {
      final session = NoticeDestinationSession();
      addTearDown(session.close);
      session.onPage = (_) async =>
          productPage(signedIn: true, override: {'slug': 'current-product'});
      final repository = BuyerRepository(session);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => BuyerDestinationRouter.openNotification(
                  context,
                  repository,
                  noticeId(1),
                  7,
                  onSearch: null,
                  onProfileSection: null,
                ),
                child: const Text('Open update'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open update'));
      await tester.pumpAndSettle();
      expect(session.pageRequests, ['/buyer/product/current-product']);
    },
  );
  for (final malformed in [
    (
      'order',
      WebPage('Buyer/OrderDetail', {
        'auth': {
          'user': {'id': 7, 'role': 'buyer'},
        },
        'order': {'id': 11.5},
      }),
    ),
    (
      'return',
      WebPage('Returns/Show', {
        'auth': {
          'user': {'id': 7, 'role': 'buyer'},
        },
        'returnCase': {'id': 4.5},
      }),
    ),
  ]) {
    testWidgets('notification cannot route to a different ${malformed.$1}', (
      tester,
    ) async {
      final session = NoticeDestinationSession()..destination = malformed.$2;
      addTearDown(session.close);
      final errors = <BackendException>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  try {
                    await BuyerDestinationRouter.openNotification(
                      context,
                      BuyerRepository(session),
                      noticeId(1),
                      7,
                      onSearch: null,
                      onProfileSection: null,
                    );
                  } on BackendException catch (error) {
                    errors.add(error);
                  }
                },
                child: const Text('Open malformed update'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open malformed update'));
      await tester.pumpAndSettle();

      expect(errors, hasLength(1));
      expect(session.pageRequests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'preview reads are explicit and include only records actually displayed',
    (tester) async {
      tester.view.physicalSize = const Size(375, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = ControlledWebSession();
      addTearDown(session.close);
      session.onGet = (_) async => preview();
      session.onPost = (_) async => {
        'summary': {'available': true, 'unread': 5},
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: Scaffold(
            body: NotificationPreview(
              repository: BuyerRepository(session),
              ownerId: 7,
              isCurrentOwner: () => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(session.posts, isEmpty);
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed!();
      await tester.pumpAndSettle();
      expect(session.posts.single.path, '/notifications/read-displayed');
      final ids = session.posts.single.values['ids'] as List;
      expect(ids, contains(noticeId(1)));
      expect(ids, isNot(contains(noticeId(6))));
      expect(ids.length, lessThan(6));
    },
  );

  testWidgets(
    'preview discards a read acknowledgement after its account changes',
    (tester) async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      session.onGet = (_) async => preview();
      final pending = Completer<Map<String, dynamic>>();
      session.onPost = (_) => pending.future;
      var current = true;
      final summaries = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: Scaffold(
            body: NotificationPreview(
              repository: BuyerRepository(session),
              ownerId: 7,
              isCurrentOwner: () => current,
              onSummaryChanged: summaries.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed!();
      await tester.pump();
      current = false;
      pending.complete({
        'summary': {'available': true, 'unread': 0},
      });
      await tester.pumpAndSettle();
      expect(find.text('Private update 1'), findsNothing);
      expect(summaries, [6]);
      expect(session.getRequests, ['/notifications/preview']);
    },
  );

  testWidgets(
    'impression requires a loaded image visible for an uninterrupted second',
    (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var active = true, impressions = 0;
      late StateSetter update;
      late ValueChanged<bool> imageReady;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) {
                update = set;
                return SingleChildScrollView(
                  controller: scroll,
                  child: Column(
                    children: [
                      const SizedBox(height: 800),
                      AdvertisementExposure(
                        active: active,
                        onImpression: () => impressions++,
                        builder: (_, ready) {
                          imageReady = ready;
                          return const SizedBox(width: 400, height: 200);
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      imageReady(true);
      await tester.pump(const Duration(seconds: 2));
      expect(impressions, 0);
      scroll.jumpTo(400);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      update(() => active = false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(impressions, 0);
      update(() => active = true);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(impressions, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(impressions, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'measurement failures never block shopping or repeat a revision event',
    () async {
      final sent = <String>[];
      final measurements = BuyerAdvertisementSession((data, type) async {
        sent.add('$type:${data['revision_id']}');
        throw StateError('Unavailable');
      });
      measurements.record({'revision_id': 2}, 'click');
      measurements.record({'revision_id': 2}, 'click');
      measurements.record({'revision_id': 2}, 'impression');
      await Future<void>.delayed(Duration.zero);
      expect(sent, ['click:2', 'impression:2']);
    },
  );

  test('ad measurements ignore malformed revision IDs', () async {
    final sent = <String>[];
    final measurements = BuyerAdvertisementSession((data, type) async {
      sent.add('$type:${data['revision_id']}');
    });

    for (final revision in [0, -1, 1.5, double.nan, double.infinity, '2']) {
      measurements.record({'revision_id': revision}, 'click');
    }
    await Future<void>.delayed(Duration.zero);

    expect(sent, isEmpty);
  });
}
