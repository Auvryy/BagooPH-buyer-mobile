import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/collections/followed_shops_page.dart';
import 'package:bagoo_buyer_mobile/features/collections/saved_products_page.dart';
import 'package:bagoo_buyer_mobile/features/engagement/engagement_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart' show buyer, product;

WebPage collection(
  bool shops, {
  int owner = 7,
  int currentPage = 1,
  int total = 1,
}) {
  final firstRow = (currentPage - 1) * 24;
  final remaining = total - firstRow;
  final rowCount = remaining <= 0
      ? 0
      : remaining < 24
      ? remaining
      : 24;
  final rows = [
    for (var index = 0; index < rowCount; index++)
      if (shops)
        {
          'shop_id': firstRow + index + 2,
          'shop': {
            'id': firstRow + index + 2,
            'name': index == 0 ? 'Private followed shop' : 'Followed shop',
            'slug': 'private-followed-shop-${firstRow + index + 2}',
            'logo': null,
            'description': null,
          },
        }
      else
        {
          'product_id': firstRow + index + 1,
          'product': null,
          'unavailable_reason': index == 0
              ? 'Private saved note'
              : 'Saved product unavailable',
        },
  ];
  final lastPage = total == 0 ? 1 : (total + 23) ~/ 24;
  final from = rowCount == 0 ? null : firstRow + 1;
  return WebPage(shops ? 'Buyer/FollowedShops' : 'Buyer/SavedProducts', {
    'auth': {
      'user': {...buyer, 'id': owner},
    },
    'entries': {
      'data': rows,
      'current_page': currentPage,
      'last_page': lastPage,
      'per_page': 24,
      'total': total,
      'from': from,
      'to': rowCount == 0 ? null : from! + rowCount - 1,
    },
  });
}

void main() {
  for (final shops in [false, true]) {
    group(shops ? 'Followed shops' : 'Saved products', () {
      late ControlledWebSession session;
      late BuyerRepository repository;
      setUp(() {
        session = ControlledWebSession();
        repository = BuyerRepository(session);
        session.onPage = (_) async => collection(shops);
      });
      tearDown(() => session.close());
      Finder getRemove() => shops
          ? find.byTooltip('Unfollow shop')
          : find.widgetWithText(OutlinedButton, 'Remove');
      Finder getPrivate() =>
          find.text(shops ? 'Private followed shop' : 'Private saved note');
      Future<void> open(WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            home: shops
                ? FollowedShopsPage(repository: repository, ownerId: 7)
                : SavedProductsPage(repository: repository, ownerId: 7),
          ),
        );
        await tester.pumpAndSettle();
        expect(getPrivate(), findsOneWidget);
      }

      for (final (field, value) in [
        ('current_page', 1.5),
        ('last_page', 0),
        ('total', '1'),
        ('current_page', 2),
        ('last_page', 10),
        ('per_page', 12),
        ('total', 25),
        ('from', 2),
      ]) {
        testWidgets(
          'malformed collection pagination $field=$value is rejected',
          (tester) async {
            session.onPage = (_) async {
              final page = collection(shops);
              (page.props['entries'] as Map)[field] = value;
              return page;
            };
            await tester.pumpWidget(
              MaterialApp(
                theme: BagooTheme.light,
                home: shops
                    ? FollowedShopsPage(repository: repository, ownerId: 7)
                    : SavedProductsPage(repository: repository, ownerId: 7),
              ),
            );
            await tester.pumpAndSettle();

            expect(getPrivate(), findsNothing);
            expect(getRemove(), findsNothing);
            expect(
              find.text(
                'This saved list is unavailable for your buyer account.',
              ),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }

      test(
        'oversized collection pages are rejected before row display',
        () async {
          session.onPage = (_) async {
            final page = collection(shops, total: 25);
            final entries = page.props['entries'] as Map;
            final rows = entries['data'] as List;
            rows.add(
              shops
                  ? {
                      'shop_id': 26,
                      'shop': {
                        'id': 26,
                        'name': 'Overflow shop',
                        'slug': 'overflow-shop',
                        'logo': null,
                        'description': null,
                      },
                    }
                  : {
                      'product_id': 25,
                      'product': null,
                      'unavailable_reason': 'Overflow product',
                    },
            );
            entries['to'] = 25;
            return page;
          };
          final engagement = BuyerEngagementRepository(repository);

          await expectLater(
            shops ? engagement.followedShops() : engagement.savedProducts(),
            throwsA(isA<BackendException>()),
          );
        },
      );

      test(
        'invalid collection page numbers are rejected before networking',
        () async {
          final engagement = BuyerEngagementRepository(repository);
          for (final page in [0, 1000001]) {
            await expectLater(
              shops
                  ? engagement.followedShops(page: page)
                  : engagement.savedProducts(page: page),
              throwsA(isA<BackendException>()),
            );
          }
          expect(session.pageRequests, isEmpty);
        },
      );

      test(
        'an out-of-range request accepts the backend-corrected last page',
        () async {
          session.onPage = (_) async =>
              collection(shops, currentPage: 2, total: 25);
          final engagement = BuyerEngagementRepository(repository);
          final result = shops
              ? await engagement.followedShops(page: 1000000)
              : await engagement.savedProducts(page: 1000000);

          expect(mapOf(result.props['entries'])['current_page'], 2);
          expect(session.pageRequests.single, endsWith('?page=1000000'));
        },
      );

      testWidgets('a fractional collection ID is rejected before display', (
        tester,
      ) async {
        session.onPage = (_) async {
          final page = collection(shops);
          final rows = (page.props['entries'] as Map)['data'] as List;
          final row = rows.single as Map;
          row[shops ? 'shop_id' : 'product_id'] = 1.5;
          return page;
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            home: shops
                ? FollowedShopsPage(repository: repository, ownerId: 7)
                : SavedProductsPage(repository: repository, ownerId: 7),
          ),
        );
        await tester.pumpAndSettle();

        expect(getPrivate(), findsNothing);
        expect(getRemove(), findsNothing);
        expect(session.posts, isEmpty);
        expect(tester.takeException(), isNull);
      });

      if (shops) {
        testWidgets('a mismatched shop relation cannot open another shop', (
          tester,
        ) async {
          session.onPage = (_) async {
            final page = collection(true);
            final entry =
                (page.props['entries'] as Map)['data'] as List<dynamic>;
            (entry.single as Map)['shop'] = {
              'id': 99,
              'name': 'Foreign shop',
              'slug': 'foreign-shop',
              'logo': null,
              'description': 'Wrong related shop',
            };
            return page;
          };
          await tester.pumpWidget(
            MaterialApp(
              theme: BagooTheme.light,
              home: FollowedShopsPage(repository: repository, ownerId: 7),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Foreign shop'), findsNothing);
          expect(find.text('Visit shop'), findsNothing);
          expect(find.text('Shop unavailable'), findsNWidgets(2));
          expect(getRemove(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }

      Future<void> remove(WidgetTester tester) async {
        final target = getRemove();
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
        await tester.tap(target);
        await tester.pump();
      }

      testWidgets(
        'late removal after leaving starts no new read or state update',
        (tester) async {
          final pending = Completer<Map<String, dynamic>>();
          session.onPost = (_) => pending.future;
          await open(tester);
          final target = getRemove();
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          for (var i = 0; i < 8; i++) {
            await tester.tap(target);
          }
          await tester.pump();
          expect(session.posts, hasLength(1));
          await tester.pumpWidget(
            const MaterialApp(home: Text('Collection closed')),
          );
          pending.complete(
            shops
                ? {'shop_id': 2, 'following': false}
                : {'product_id': 1, 'saved': false},
          );
          await tester.pumpAndSettle();
          expect(session.pageRequests, hasLength(1));
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('foreign-owner refresh clears previous private rows', (
        tester,
      ) async {
        await open(tester);
        session.onPage = (_) async => collection(shops, owner: 8);
        await tester.tap(
          find.byTooltip(
            shops ? 'Refresh followed shops' : 'Refresh saved products',
          ),
        );
        await tester.pumpAndSettle();
        expect(getPrivate(), findsNothing);
        expect(getRemove(), findsNothing);
      });

      testWidgets('changed session blocks removal before any request', (
        tester,
      ) async {
        session.onPost = (_) async => shops
            ? {'shop_id': 2, 'following': false}
            : {'product_id': 1, 'saved': false};
        await open(tester);
        session.clear();
        await remove(tester);
        await tester.pumpAndSettle();
        expect(session.posts, isEmpty);
        expect(getPrivate(), findsNothing);
      });

      testWidgets('session change while removing discards late confirmation', (
        tester,
      ) async {
        final pending = Completer<Map<String, dynamic>>();
        session.onPost = (_) => pending.future;
        await open(tester);
        await remove(tester);
        session.clear();
        pending.complete(
          shops
              ? {'shop_id': 2, 'following': false}
              : {'product_id': 1, 'saved': false},
        );
        await tester.pumpAndSettle();
        expect(getPrivate(), findsNothing);
        expect(session.pageRequests, hasLength(1));
        expect(find.textContaining('removed from'), findsNothing);
      });

      testWidgets(
        'temporary read failure retains rows but access denial clears them',
        (tester) async {
          await open(tester);
          final refresh = find.byTooltip(
            shops ? 'Refresh followed shops' : 'Refresh saved products',
          );
          session.onPage = (_) async =>
              throw const BackendException('Offline', status: 503);
          await tester.tap(refresh);
          await tester.pumpAndSettle();
          if (getPrivate().evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              getPrivate(),
              180,
              scrollable: find
                  .descendant(
                    of: find.byType(ListView).first,
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.pumpAndSettle();
          }
          expect(getPrivate(), findsOneWidget);
          session.onPage = (_) async =>
              throw const BackendException('Access denied', status: 403);
          await tester.tap(refresh);
          await tester.pumpAndSettle();
          expect(getPrivate(), findsNothing);
          expect(getRemove(), findsNothing);
        },
      );

      testWidgets('failed removal after a session change clears private rows', (
        tester,
      ) async {
        final pending = Completer<Map<String, dynamic>>();
        session.onPost = (_) => pending.future;
        await open(tester);
        await remove(tester);
        session.clear();
        pending.completeError(const BackendException('Offline', status: 503));
        await tester.pumpAndSettle();
        expect(getPrivate(), findsNothing);
        expect(getRemove(), findsNothing);
        expect(session.pageRequests, hasLength(1));
      });
    });
  }

  for (final invalidProduct in [
    product(1)..remove('slug'),
    {...product(1), 'slug': '   '},
    {...product(1), 'id': 2},
  ]) {
    testWidgets(
      'saved product with unusable detail metadata is shown as removable unavailable row',
      (tester) async {
        final session = ControlledWebSession();
        addTearDown(session.close);
        final repository = BuyerRepository(session);
        session.onPage = (_) async {
          final page = collection(false);
          final entries = (page.props['entries'] as Map)['data'] as List;
          final row = entries.single as Map;
          row['product'] = invalidProduct;
          row.remove('unavailable_reason');
          return page;
        };

        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            home: SavedProductsPage(repository: repository, ownerId: 7),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Saved product unavailable'), findsOneWidget);
        expect(
          find.text(
            'Product details could not be confirmed. You can remove this saved item.',
          ),
          findsOneWidget,
        );
        expect(find.text('Everyday bag 1'), findsNothing);
        expect(find.widgetWithText(OutlinedButton, 'Remove'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
