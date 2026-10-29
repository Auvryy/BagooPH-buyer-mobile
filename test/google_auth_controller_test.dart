import 'dart:async';

import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/auth/google_auth_controller.dart';
import 'package:bagoo_buyer_mobile/features/auth/google_auth_repository.dart';
import 'package:bagoo_buyer_mobile/features/auth/google_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import 'google_auth_repository_test.dart' show registrationData, signedIn;
import 'support/controlled_web_session.dart';
import 'support/fake_google_identity.dart';

void main() {
  late ControlledWebSession session;
  late GoogleAuthRepository repository;
  late FakeGoogleIdentity provider;
  late GoogleAuthController controller;
  late DateTime clock;
  setUp(() {
    clock = DateTime.utc(2026, 10, 29, 8);
    session = ControlledWebSession();
    repository = GoogleAuthRepository(
      BuyerRepository(session),
      now: () => clock,
    );
    provider = FakeGoogleIdentity();
    controller = GoogleAuthController(
      repository: repository,
      provider: provider,
    );
    session.onGet = (path) async => path == '/buyer/mobile-capabilities'
        ? {
            'contract_version': 1,
            'features': {'native_google_sign_in': true, 'device_push': false},
          }
        : path == '/auth/session'
        ? {'authenticated': true, 'redirect': '/buyer'}
        : registrationData();
    session.onPage = (_) async => signedIn();
    session.onPost = (_) async => {'authenticated': true};
  });
  tearDown(() {
    controller.dispose();
    session.close();
  });

  test('a disabled capability never invokes the identity SDK or mutates the session', () async {
    session.onGet = (_) async => {
      'contract_version': 1,
      'features': {'native_google_sign_in': false, 'device_push': false},
    };
    final epoch = session.identityEpoch;
    await controller.start(remember: true);
    expect(provider.calls, 0);
    expect(session.posts, isEmpty);
    expect(session.identityEpoch, epoch);
    expect(controller.stage, GoogleAuthStage.error);
  });

  test('user cancellation keeps guest persistence and performs no backend mutation', () async {
    provider.onAuthenticate = () async => null;
    final epoch = session.identityEpoch;
    await controller.start(remember: true);
    expect(controller.stage, GoogleAuthStage.canceled);
    expect(session.identityEpoch, epoch);
    expect(session.posts, isEmpty);
    expect(controller.busy, isFalse);
  });

  test(
    'a provider failure does not leak diagnostics or reach the backend writer',
    () async {
      provider.onAuthenticate = () async => throw const GoogleIdentityException(
        'Google is unavailable. Use email.',
      );
      await controller.start(remember: false);
      expect(controller.error, 'Google is unavailable. Use email.');
      expect(session.posts, isEmpty);
    },
  );

  test(
    'a confirmed buyer is the only successful result and uses original email',
    () async {
      await controller.start(remember: true);
      expect(controller.stage, GoogleAuthStage.authenticated);
      expect(controller.authenticatedPage?.user?['id'], 7);
      expect(session.rememberedEmail, 'original@bagoo.test');
      expect(session.posts.length, 1);
    },
  );

  test('link proof requires a separate action, retains field errors and cannot double-submit', () async {
    var calls = 0;
    final pending = Completer<Map<String, dynamic>>();
    session.onPost = (request) async {
      calls++;
      if (calls == 1) {
        throw const BackendException(
          'Confirm your existing password',
          status: 409,
          data: {'code': 'GOOGLE_ACCOUNT_LINK_REQUIRED'},
        );
      }
      if (calls == 2) {
        throw const BackendException(
          'Incorrect password',
          status: 422,
          fields: {'account_password': 'Check your Bagoo password.'},
        );
      }
      expect(request.values['account_password'], ' correct password ');
      return pending.future;
    };
    await controller.start(remember: false);
    expect(controller.stage, GoogleAuthStage.link);
    expect(calls, 1);
    await controller.link('wrong');
    expect(controller.stage, GoogleAuthStage.link);
    expect(controller.fields['account_password'], isNotNull);
    controller.clearField('account_password');
    expect(controller.fields, isEmpty);
    final submit = controller.link(' correct password ');
    await Future<void>.delayed(Duration.zero);
    await controller.link('duplicate');
    expect(calls, 3);
    pending.complete({'authenticated': true});
    await submit;
    expect(controller.stage, GoogleAuthStage.authenticated);
  });

  test(
    'registration keeps the same challenge and field feedback after validation',
    () async {
      session.onPost = (request) async {
        if (request.path == '/auth/google/native') {
          return {'registration_required': true};
        }
        throw const BackendException(
          'Check the form',
          status: 422,
          fields: {'birthday': 'You must be 18 or older.'},
        );
      };
      await controller.start(remember: false);
      final nonce = controller.registration!.nonce;
      await controller.complete({'birthday': '2020-01-01'});
      expect(controller.stage, GoogleAuthStage.registration);
      expect(controller.registration?.nonce, nonce);
      expect(controller.fields['birthday'], 'You must be 18 or older.');
      expect(session.posts.length, 2);
    },
  );

  test(
    'uncertain exchange only recovers through explicit read-only status checks',
    () async {
      session.onPost = (_) async =>
          throw const BackendException('Interrupted', connectionFailure: true);
      await controller.start(remember: false);
      expect(controller.stage, GoogleAuthStage.uncertain);
      expect(session.posts.length, 1);
      expect(session.getRequests, ['/buyer/mobile-capabilities']);
      await controller.recover();
      expect(controller.stage, GoogleAuthStage.authenticated);
      expect(session.posts.length, 1);
      expect(session.getRequests, [
        '/buyer/mobile-capabilities',
        '/auth/session',
      ]);
    },
  );

  test(
    'CSRF expiry clears the native challenge rather than replaying it',
    () async {
      session.onPost = (_) async =>
          throw const BackendException('Session expired', status: 419);
      await controller.start(remember: false);
      expect(controller.stage, GoogleAuthStage.error);
      expect(controller.registration, isNull);
      expect(session.posts.length, 1);
      expect(session.remembersLogin, isFalse);
    },
  );

  test(
    'a failed recovery read keeps the uncertain result open without replay',
    () async {
      session.onPost = (_) async =>
          throw const BackendException('Interrupted', connectionFailure: true);
      await controller.start(remember: false);
      session.onGet = (_) async => throw const BackendException(
        'Still offline',
        connectionFailure: true,
      );
      await controller.recover();
      expect(controller.stage, GoogleAuthStage.uncertain);
      expect(controller.error, 'Still offline');
      expect(session.posts.length, 1);
    },
  );

  test('Retry-After survives page abandonment and blocks writes until its deadline', () async {
    session.onPost = (_) async => throw BackendException(
      'Wait',
      status: 429,
      retryAt: clock.add(const Duration(seconds: 45)),
    );
    await controller.start(remember: false);
    expect(controller.coolingDown, isTrue);
    expect(controller.retrySeconds, 45);
    await controller.start(remember: false);
    expect(provider.calls, 1);
    expect(session.posts.length, 1);
    repository.abandon();
    final next = GoogleAuthController(
      repository: repository,
      provider: provider,
    );
    addTearDown(next.dispose);
    await next.start(remember: false);
    expect(provider.calls, 1);
    clock = clock.add(const Duration(seconds: 46));
    session.onPost = (_) async => {'authenticated': true};
    await next.start(remember: false);
    expect(next.stage, GoogleAuthStage.authenticated);
    expect(provider.calls, 2);
  });

  test('expired challenges cannot be submitted locally', () async {
    session.onPost = (_) async => {'registration_required': true};
    await controller.start(remember: false);
    clock = DateTime.utc(2031);
    controller.tick();
    expect(controller.challengeExpired, isTrue);
    expect(controller.canSubmit, isFalse);
    await controller.complete({});
    expect(session.posts.length, 1);
  });

  test('disposal or an account change during provider selection discards its result', () async {
    final choice = Completer<String?>();
    provider.onAuthenticate = () => choice.future;
    final pending = controller.start(remember: false);
    await Future<void>.delayed(Duration.zero);
    session.clear();
    choice.complete('synthetic-id-token');
    await pending;
    expect(controller.stage, GoogleAuthStage.error);
    expect(session.posts, isEmpty);
    final second = GoogleAuthController(
      repository: repository,
      provider: provider,
    );
    final nextChoice = Completer<String?>();
    provider.onAuthenticate = () => nextChoice.future;
    final next = second.start(remember: false);
    await Future<void>.delayed(Duration.zero);
    second.dispose();
    nextChoice.complete('synthetic-id-token');
    await next;
    expect(session.posts, isEmpty);
  });
}
