import 'dart:convert';
import 'dart:io';

import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';

void main() {
  test(
    'restores buyer states from the executed backend session fixtures',
    () async {
      final fixture = jsonDecode(
        File('test/fixtures/buyer-session-states.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      for (final entry in mapsOf(fixture['cases'])) {
        final user = mapOf(entry['setup']);
        final session = ControlledWebSession();
        addTearDown(session.close);
        final status = mapOf(mapOf(entry['response'])['body']);
        session.onGet = (path) async {
          expect(path, '/auth/session');
          return status;
        };
        session.onPage = (path) async => WebPage(
          Uri.parse(path).path == '/buyer'
              ? 'Buyer/Home'
              : 'Auth/AccountStatus',
          {
            'auth': {'user': user},
          },
        );
        final buyer = BuyerRepository(session);
        if (user['role'] != 'buyer') {
          await expectLater(
            buyer.currentSession(),
            throwsA(isA<BackendException>()),
          );
          expect(session.pageRequests, isEmpty);
        } else {
          final page = await buyer.currentSession();
          expect(page?.user?['id'], user['id']);
          expect(page?.user?['role'], 'buyer');
          expect(page?.user?['status'], user['status']);
          expect(
            session.pageRequests.single,
            session.origin.resolve(status['redirect']).toString(),
          );
        }
      }
    },
  );

  test(
    'the buyer Home alias still requires a fetched buyer and numeric owner',
    () async {
      for (final user in <Map<String, Object?>?>[
        {'id': 101, 'role': 'seller'},
        {'id': 101, 'role': 'courier'},
        {'id': '101', 'role': 'buyer'},
        {'role': 'buyer'},
        null,
      ]) {
        final session = ControlledWebSession();
        addTearDown(session.close);
        session.onGet = (_) async => {
          'authenticated': true,
          'redirect': '/buyer',
        };
        session.onPage = (_) async => WebPage('Buyer/Home', {
          'auth': {'user': user},
        });
        await expectLater(
          BuyerRepository(session).currentSession(),
          throwsA(
            isA<BackendException>().having(
              (e) => e.status,
              'invalid buyer status',
              401,
            ),
          ),
        );
        expect(session.pageRequests, ['http://localhost/buyer']);
      }
    },
  );

  test(
    'unsupported and foreign session paths remain denied without fetching them',
    () async {
      for (final path in [
        '/buyer/anything',
        '/buyer/',
        '/seller/dashboard',
        '/courier/deliveries',
        '/staff/activate',
        'https://foreign.example.test/buyer',
      ]) {
        final session = ControlledWebSession();
        addTearDown(session.close);
        session.onGet = (_) async => {'authenticated': true, 'redirect': path};
        await expectLater(
          BuyerRepository(session).currentSession(),
          throwsA(isA<BackendException>()),
        );
        expect(session.pageRequests, isEmpty);
      }
    },
  );
}
