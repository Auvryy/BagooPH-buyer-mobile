import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/engagement/buyer_destination_router.dart';
import 'package:bagoo_buyer_mobile/features/engagement/engagement_repository.dart';
import 'package:bagoo_buyer_mobile/features/promotions/promotion_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';
import 'support/controlled_web_session.dart';

void main() {
  test(
    'promotion repository rejects a partially malformed product list',
    () async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      session.onPage = (_) async => WebPage('Buyer/Promotion', {
        'auth': {'user': buyer},
        'promotion': {'available': true, 'title': 'Test offer'},
        'products': [product(1), 'malformed product row'],
      });

      await expectLater(
        BuyerEngagementRepository(BuyerRepository(session))
            .promotion('test-offer'),
        throwsA(isA<BackendException>()),
      );
    },
  );

  testWidgets('promotion link rejects a partially malformed product list', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onPage = (_) async => WebPage('Buyer/Promotion', {
      'auth': {'user': buyer},
      'promotion': {'available': true, 'title': 'Test offer', 'target': {}},
      'products': [product(1), 'malformed product row'],
    });
    final repository = BuyerRepository(session);
    BackendException? routeError;

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                try {
                  await BuyerDestinationRouter.openHref(
                    context,
                    repository,
                    '/promotions/test-offer',
                    onSearch: null,
                    onProfileSection: null,
                  );
                } on BackendException catch (error) {
                  routeError = error;
                }
              },
              child: const Text('Open offer'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open offer'));
    await tester.pumpAndSettle();

    expect(routeError, isNotNull);
    expect(find.byType(PromotionPage), findsNothing);
    expect(find.text('Everyday bag 1'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('promotion refuses products without a confirmed route slug', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final malformedProduct = product(1)..remove('slug');
    session.onPage = (_) async => WebPage('Buyer/Promotion', {
      'auth': {'user': buyer},
      'promotion': {'available': true, 'title': 'Test offer', 'target': {}},
      'products': [malformedProduct],
    });
    final repository = BuyerRepository(session);
    BackendException? routeError;

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                try {
                  await BuyerDestinationRouter.openHref(
                    context,
                    repository,
                    '/promotions/test-offer',
                    onSearch: null,
                    onProfileSection: null,
                  );
                } on BackendException catch (error) {
                  routeError = error;
                }
              },
              child: const Text('Open offer'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open offer'));
    await tester.pumpAndSettle();

    expect(routeError, isNotNull);
    expect(find.byType(PromotionPage), findsNothing);
    expect(find.text('Everyday bag 1'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final invalidLimit in [1.5, '2']) {
    testWidgets(
      'promotion does not round or accept malformed per-buyer limit: $invalidLimit',
      (tester) async {
        tester.view.physicalSize = const Size(360, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final repository = FakeBuyerRepository();
        addTearDown(repository.session.close);
        final page = WebPage('Buyer/Promotion', {
          'auth': {'user': null},
          'promotion': {
            'available': true,
            'title': 'Test offer',
            'offer': {
              'name': 'Test voucher',
              'discount_type': 'fixed',
              'value_cents': 500,
              'per_buyer_limit': invalidLimit,
            },
            'target': {},
          },
          'products': <Map<String, dynamic>>[],
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            home: PromotionPage(
              repository: repository,
              initial: page,
              onOpenDestination: (_) async {},
              onProfileSection: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Uses per buyer'), findsOneWidget);
        expect(find.textContaining('Could not be confirmed'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
