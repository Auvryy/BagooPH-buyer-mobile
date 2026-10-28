import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/features/engagement/buyer_destination_router.dart';
import 'package:bagoo_buyer_mobile/features/home/advertisement_exposure.dart';
import 'package:bagoo_buyer_mobile/features/notifications/notification_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart' show productPage;

class NoticeDestinationSession extends ControlledWebSession {
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
    return productPage(signedIn: true, override: {'slug': 'current-product'});
  }
}

String noticeId(int index) =>
    'aaaaaaaa-aaaa-4aaa-8aaa-${index.toString().padLeft(12, '0')}';
Map<String, dynamic> preview() => {
  'notices': [
    for (var index = 1; index <= 6; index++)
      {
        'id': noticeId(index),
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
}
