import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/collections/followed_shops_page.dart';
import 'package:bagoo_buyer_mobile/features/collections/saved_products_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart' show buyer;

WebPage collection(bool shops, {int owner = 7}) =>
    WebPage(shops ? 'Buyer/FollowedShops' : 'Buyer/SavedProducts', {
      'auth': {
        'user': {...buyer, 'id': owner},
      },
      'entries': {
        'data': [
          if (shops)
            {
              'shop_id': 2,
              'shop': {'name': 'Private followed shop'},
            }
          else
            {
              'product_id': 1,
              'product': null,
              'unavailable_reason': 'Private saved note',
            },
        ],
        'current_page': 1,
        'last_page': 1,
      },
    });

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
          expect(getPrivate(), findsOneWidget);
          session.onPage = (_) async =>
              throw const BackendException('Access denied', status: 403);
          await tester.tap(refresh);
          await tester.pumpAndSettle();
          expect(getPrivate(), findsNothing);
          expect(getRemove(), findsNothing);
        },
      );
    });
  }
}
