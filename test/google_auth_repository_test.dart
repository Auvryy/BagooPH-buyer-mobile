import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/auth/google_auth_contract.dart';
import 'package:bagoo_buyer_mobile/features/auth/google_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';

Map<String, dynamic> googleFixture(String name) => mapOf(
  mapOf(
    jsonDecode(
      File('test/fixtures/native-google/$name.json').readAsStringSync(),
    ),
  )['response'],
);

Map<String, dynamic> registrationData() {
  final data = mapOf(googleFixture('registration')['body']);
  data['registrationNonce'] = List.filled(40, 'n').join();
  data['expiresAt'] = DateTime.utc(2030, 10, 29).millisecondsSinceEpoch ~/ 1000;
  data['birthDateLimits'] = {
    'today': '2026-10-29',
    'past_maximum': '2026-10-28',
    'adult_maximum': '2008-10-29',
  };
  return data;
}

WebPage signedIn({
  String role = 'buyer',
  String email = 'original@bagoo.test',
}) => WebPage('Buyer/Home', {
  'auth': {
    'user': {'id': 7, 'role': role, 'email': email},
  },
});

void main() {
  late ControlledWebSession session;
  late GoogleAuthRepository auth;
  setUp(() {
    session = ControlledWebSession();
    auth = GoogleAuthRepository(BuyerRepository(session));
  });
  tearDown(() {
    auth.abandon();
    session.close();
  });

  test('decodes the shared registration fixture with concrete dynamic placeholders', () {
    final contract = GoogleRegistrationContract.parse(
      registrationData(),
      session,
    );
    expect(contract.email, 'native-buyer@bagoo.test');
    expect(contract.nonce.length, 40);
    expect(contract.adultMaximum, DateTime(2008, 10, 29));
    expect(contract.policies['required'], isTrue);
    expect(contract.expired(DateTime.utc(2031)), isTrue);
  });

  test('rejects invalid challenge identity, nonce, expiry, dates and foreign policy links', () {
    for (final change in <Map<String, dynamic>>[
      {
        'identity': {'name': 'Buyer', 'email': 'not-an-email'},
      },
      {'registrationNonce': '<SESSION_BOUND_NONCE>'},
      {'expiresAt': '1898467200'},
      {'expiresAt': -1},
      {
        'birthDateLimits': {
          'today': '2026-10-29',
          'past_maximum': '2026-10-28',
          'adult_maximum': '2008-02-31',
        },
      },
      {
        'policies': {
          ...mapOf(registrationData()['policies']),
          'terms_url': 'https://foreign.example.test/terms',
        },
      },
    ]) {
      expect(
        () => GoogleRegistrationContract.parse({
          ...registrationData(),
          ...change,
        }, session),
        throwsA(isA<BackendException>()),
      );
    }
  });

  test('confirms the backend buyer and remembers its original email after exchange', () async {
    session.onPost = (_) async => mapOf(googleFixture('authenticated')['body']);
    session.onGet = (_) async => {'authenticated': true, 'redirect': '/buyer'};
    session.onPage = (_) async => signedIn();
    await auth.begin(remember: true);
    final outcome = await auth.exchange('synthetic-id-token');
    expect(outcome.page?.user?['id'], 7);
    expect(session.remembersLogin, isTrue);
    expect(session.rememberedEmail, 'original@bagoo.test');
    expect(session.directPosts.single.values, {
      'id_token': 'synthetic-id-token',
      'remember': true,
    });
    expect(session.pageRequests, ['http://localhost/buyer']);
  });

  test('an acknowledgement cannot sign in a wrong-role page', () async {
    session.onPost = (_) async => {'authenticated': true};
    session.onGet = (_) async => {'authenticated': true, 'redirect': '/buyer'};
    session.onPage = (_) async => signedIn(role: 'seller');
    await auth.begin(remember: true);
    await expectLater(
      auth.exchange('synthetic-id-token'),
      throwsA(isA<GoogleAuthUncertain>()),
    );
    expect(session.remembersLogin, isFalse);
  });

  test(
    'ambiguous or missing success fields require recovery without extra writes',
    () async {
      await auth.begin(remember: false);
      for (final body in [
        <String, dynamic>{},
        {'authenticated': false},
        {'authenticated': true, 'registration_required': true},
        {'authenticated': 'true'},
      ]) {
        session.onPost = (_) async => body;
        await expectLater(
          auth.exchange('synthetic-id-token'),
          throwsA(isA<GoogleAuthUncertain>()),
        );
      }
      expect(session.posts.length, 4);
      expect(session.getRequests, isEmpty);
    },
  );

  test(
    'existing-account proof stays explicit and preserves password spaces',
    () async {
      var calls = 0;
      session.onPost = (request) async {
        if (++calls == 1) {
          final response = googleFixture('link-required');
          throw BackendException(
            'Enter your Bagoo password.',
            status: 409,
            data: mapOf(response['body']),
          );
        }
        expect(request.values['account_password'], ' existing password ');
        return {'authenticated': true};
      };
      session.onGet = (_) async => {
        'authenticated': true,
        'redirect': '/buyer',
      };
      session.onPage = (_) async => signedIn();
      await auth.begin(remember: false);
      await expectLater(
        auth.exchange('synthetic-id-token'),
        throwsA(
          isA<BackendException>().having(
            (e) => e.data['code'],
            'link challenge',
            'GOOGLE_ACCOUNT_LINK_REQUIRED',
          ),
        ),
      );
      expect(calls, 1);
      await auth.exchange(
        'synthetic-id-token',
        accountPassword: ' existing password ',
      );
      expect(calls, 2);
      expect(session.remembersLogin, isFalse);
    },
  );

  test(
    'new identities fetch a same-session challenge without creating an account',
    () async {
      session.onPost = (_) async =>
          mapOf(googleFixture('registration-required')['body']);
      session.onGet = (path) async {
        expect(path, '/auth/google/native/registration');
        return registrationData();
      };
      await auth.begin(remember: false);
      final outcome = await auth.exchange('synthetic-id-token');
      expect(outcome.registration?.email, 'native-buyer@bagoo.test');
      expect(session.directPosts.single.path, '/auth/google/native');
      expect(session.directGetRequests, ['/auth/google/native/registration']);
      expect(session.remembersLogin, isFalse);
    },
  );

  test('completion sends only accepted buyer fields and current challenge policies', () async {
    final contract = GoogleRegistrationContract.parse(
      registrationData(),
      session,
    );
    session.onPost = (request) async {
      expect(request.path, '/auth/google/native/register');
      expect(request.values['registration_nonce'], contract.nonce);
      expect(
        request.values['terms_version'],
        contract.policies['terms_version'],
      );
      for (final key in [
        'email',
        'role',
        'google_id',
        'kyc_status',
        'remember',
        'id_token',
      ]) {
        expect(request.values.containsKey(key), isFalse);
      }
      return {'authenticated': true};
    };
    session.onGet = (_) async => {'authenticated': true, 'redirect': '/buyer'};
    session.onPage = (_) async => signedIn(email: contract.email);
    await auth.begin(remember: true);
    final result = await auth.complete(contract, {
      'first_name': 'Native',
      'last_name': 'Buyer',
      'birthday': '1995-04-02',
      'sex': 'Other',
      'policy_accepted': true,
      'terms_version': 'stale',
      'email': 'changed@bagoo.test',
      'role': 'admin',
      'google_id': 'untrusted',
      'kyc_status': 'approved',
    });
    expect(result.page?.user?['email'], contract.email);
    expect(session.rememberedEmail, contract.email);
    expect(session.posts.length, 1);
  });

  test(
    'field rejection preserves its safe feedback without retrying registration',
    () async {
      session.onPost = (_) async => throw const BackendException(
        'Check your birth date.',
        status: 422,
        fields: {'birthday': 'You must be 18 or older.'},
      );
      await auth.begin(remember: false);
      await expectLater(
        auth.complete(
          GoogleRegistrationContract.parse(registrationData(), session),
          {},
        ),
        throwsA(
          isA<BackendException>().having(
            (e) => e.fields['birthday'],
            'field error',
            'You must be 18 or older.',
          ),
        ),
      );
      expect(session.posts.length, 1);
    },
  );

  test(
    'uncertain writes do not retry; explicit recovery performs only reads',
    () async {
      session.onPost = (_) async => throw const BackendException(
        'Connection interrupted',
        connectionFailure: true,
      );
      session.onGet = (path) async => path == '/auth/session'
          ? {'authenticated': false}
          : registrationData();
      await auth.begin(remember: false);
      await expectLater(
        auth.exchange('synthetic-id-token'),
        throwsA(isA<GoogleAuthUncertain>()),
      );
      expect(session.posts.length, 1);
      expect(session.getRequests, isEmpty);
      final recovered = await auth.recover();
      expect(recovered.registration, isNotNull);
      expect(session.posts.length, 1);
      expect(session.getRequests, [
        '/auth/session',
        '/auth/google/native/registration',
      ]);
    },
  );

  test(
    'registration confirmation cannot adopt a different buyer email',
    () async {
      session.onPost = (_) async => {'authenticated': true};
      session.onGet = (_) async => {
        'authenticated': true,
        'redirect': '/buyer',
      };
      session.onPage = (_) async => signedIn(email: 'different@bagoo.test');
      await auth.begin(remember: true);
      await expectLater(
        auth.complete(
          GoogleRegistrationContract.parse(registrationData(), session),
          {},
        ),
        throwsA(isA<GoogleAuthUncertain>()),
      );
      expect(session.remembersLogin, isFalse);
    },
  );

  test('late exchange results cannot adopt a cleared session', () async {
    final reply = Completer<Map<String, dynamic>>();
    session.onPost = (_) => reply.future;
    await auth.begin(remember: true);
    final pending = auth.exchange('synthetic-id-token');
    final rejection = expectLater(
      pending,
      throwsA(
        isA<BackendException>().having((e) => e.status, 'session change', 401),
      ),
    );
    session.clear();
    reply.complete({'authenticated': true});
    await rejection;
    expect(session.getRequests, isEmpty);
    expect(session.remembersLogin, isFalse);
  });
}
