import 'dart:async';

import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/bag_page.dart';
import 'package:bagoo_buyer_mobile/features/checkout/order_result_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:bagoo_buyer_mobile/features/profile/purchases_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart' show buyer;

void main() {
  for (final payment in [true, false]) {
    testWidgets(
      'late ${payment ? 'wallet payment' : 'Buy again'} reply cannot open under a changed session',
      (tester) async {
        final session = ControlledWebSession();
        addTearDown(session.close);
        final repository = ProfileRepository(BuyerRepository(session));
        final read = Completer<WebPage>();
        final mutation = Completer<Map<String, dynamic>>();
        session.onPage = (_) => read.future;
        session.onPost = (_) => mutation.future;
        BackendException? failure;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    try {
                      if (payment) {
                        await openWalletPayment(context, repository, 41);
                      } else {
                        await buyAgain(
                          context,
                          repository,
                          11,
                          'synthetic-token',
                        );
                      }
                    } on BackendException catch (error) {
                      failure = error;
                    }
                  },
                  child: const Text('Open purchase'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open purchase'));
        await tester.pump();
        session.clear();
        if (payment) {
          read.complete(
            const WebPage('Buyer/WalletPayment', {
              'auth': {'user': buyer},
              'payment': {'id': 41, 'status': 'cancelled', 'amount_cents': 100},
            }),
          );
        } else {
          session.onPage = (_) async => const WebPage('Cart/Index', {
            'auth': {'user': buyer},
            'items': [],
          });
          mutation.complete({
            'result': {
              'order_id': 11,
              'items': [
                {'cart_item_id': 3},
              ],
            },
          });
        }
        await tester.pumpAndSettle();
        expect(find.byType(OrderResultPage), findsNothing);
        expect(find.byType(BagPage), findsNothing);
        expect(failure, isNotNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
  for (final payment in [true, false]) {
    testWidgets(
      'current ${payment ? 'wallet payment' : 'Buy again'} reply opens its native screen',
      (tester) async {
        final session = ControlledWebSession();
        addTearDown(session.close);
        final repository = ProfileRepository(BuyerRepository(session));
        session.onPage = (path) async => path.startsWith('/wallet/')
            ? const WebPage('Buyer/WalletPayment', {
                'auth': {'user': buyer},
                'payment': {
                  'id': 41,
                  'status': 'cancelled',
                  'amount_cents': 100,
                },
              })
            : const WebPage('Cart/Index', {
                'auth': {'user': buyer},
                'items': [],
              });
        session.onPost = (_) async => {
          'result': {
            'order_id': 11,
            'items': [
              {'cart_item_id': 3},
            ],
          },
        };
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    if (payment) {
                      await openWalletPayment(context, repository, 41);
                    } else {
                      await buyAgain(
                        context,
                        repository,
                        11,
                        'synthetic-token',
                      );
                    }
                  },
                  child: const Text('Open purchase'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open purchase'));
        await tester.pumpAndSettle();
        expect(
          payment ? find.byType(OrderResultPage) : find.byType(BagPage),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
  for (final id in [0, -1, 1.5, '3', null, false]) {
    testWidgets('Buy again rejects malformed selected Bag ID $id', (
      tester,
    ) async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      final repository = ProfileRepository(BuyerRepository(session));
      session.onPost = (_) async => {
        'result': {
          'order_id': 11,
          'items': [
            {'cart_item_id': id},
          ],
        },
      };
      BackendException? failure;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  try {
                    await buyAgain(context, repository, 11, 'synthetic-token');
                  } on BackendException catch (error) {
                    failure = error;
                  }
                },
                child: const Text('Open purchase'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open purchase'));
      await tester.pumpAndSettle();
      expect(find.byType(BagPage), findsNothing);
      expect(failure, isNotNull);
      expect(session.pageRequests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  for (final returnedItems in [
    <Object>[
      {'cart_item_id': 3},
      'malformed Bag row',
    ],
    <Object>[
      {'cart_item_id': 3},
      {'cart_item_id': 3},
    ],
  ]) {
    testWidgets('Buy again rejects incomplete or duplicate returned Bag rows', (
      tester,
    ) async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      final repository = ProfileRepository(BuyerRepository(session));
      session.onPost = (_) async => {
        'result': {'order_id': 11, 'items': returnedItems},
      };
      session.onPage = (_) async => const WebPage('Cart/Index', {
        'auth': {'user': buyer},
        'items': [],
      });
      BackendException? failure;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  try {
                    await buyAgain(context, repository, 11, 'synthetic-token');
                  } on BackendException catch (error) {
                    failure = error;
                  }
                },
                child: const Text('Buy again'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Buy again'));
      await tester.pumpAndSettle();
      expect(find.byType(BagPage), findsNothing);
      expect(failure, isNotNull);
      expect(session.pageRequests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
