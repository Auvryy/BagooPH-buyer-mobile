import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/session_vault.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'web_session_test.dart' show markup;

class MemoryVault implements SessionVault {
  final values = <String, String>{};
  Completer<void>? writeGate;
  final writeStarted = Completer<void>();
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    await writeGate?.future;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  late HttpServer server;
  late Uri origin;
  late MemoryVault vault;
  bool valid = true;
  setUp(() async {
    vault = MemoryVault();
    valid = true;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin = Uri.parse('http://localhost:${server.port}');
    server.listen((request) async {
      final signedIn =
          valid &&
          request.cookies.any(
            (cookie) =>
                cookie.name == 'session' && cookie.value == 'signed-buyer',
          );
      if (request.uri.path == '/auth/session') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'authenticated': signedIn,
            if (signedIn) 'redirect': '/',
          }),
        );
      } else if (request.method == 'POST' && request.uri.path == '/login') {
        await request.drain<void>();
        request.response.cookies.add(
          Cookie('session', 'signed-buyer')
            ..path = '/'
            ..httpOnly = true
            ..maxAge = 3600,
        );
        request.response.statusCode = 302;
        request.response.headers.set('Location', '/');
      } else {
        if (!signedIn) {
          request.response.cookies.add(
            Cookie('session', 'guest-bag')
              ..path = '/'
              ..maxAge = 3600,
          );
        }
        request.response.write(
          markup(
            signedIn ? 'Buyer/Home' : 'Auth/Login',
            props: {
              'auth': {
                'user': signedIn ? {'id': 7, 'role': 'buyer'} : null,
              },
            },
          ),
        );
      }
      await request.response.close();
    });
  });
  tearDown(() async => server.close(force: true));

  test(
    'remembered session survives close and is rechecked with the server',
    () async {
      final first = WebSession(origin, vault: vault);
      await BuyerRepository(first).login(
        'buyer@example.test',
        'never-store-this-password',
        remember: true,
      );
      first.close();
      expect(
        vault.values.values.single,
        isNot(contains('never-store-this-password')),
      );
      final restored = WebSession(origin, vault: vault);
      addTearDown(restored.close);
      await restored.restoreSavedSession();
      expect(restored.rememberedEmail, 'buyer@example.test');
      expect(
        (await BuyerRepository(restored).currentSession())?.user?['id'],
        7,
      );
      valid = false;
      expect(await BuyerRepository(restored).currentSession(), isNull);
    },
  );

  test(
    'guest Bag cookies persist, while an unremembered login does not',
    () async {
      final guest = WebSession(origin, vault: vault);
      await guest.page('/cart');
      guest.close();
      final restored = WebSession(origin, vault: vault);
      await restored.restoreSavedSession();
      expect(
        restored.imageHeaders('/cart')[HttpHeaders.cookieHeader],
        contains('guest-bag'),
      );
      await BuyerRepository(restored)
          .login('buyer@example.test', 'password', remember: false);
      restored.close();
      final reopened = WebSession(origin, vault: vault);
      addTearDown(reopened.close);
      await reopened.restoreSavedSession();
      expect(reopened.imageHeaders('/cart'), isEmpty);
      expect(reopened.remembersLogin, isFalse);
    },
  );

  test(
    'a delayed secure write cannot resurrect cookies after session clear',
    () async {
      final session = WebSession(origin, vault: vault);
      addTearDown(session.close);
      final gate = Completer<void>();
      vault.writeGate = gate;
      final request = session.page('/cart');
      final rejected = expectLater(request, throwsA(isA<BackendException>()));
      await vault.writeStarted.future;
      final clear = session.clearSavedSession();
      gate.complete();
      await clear;
      await rejected;
      expect(vault.values, isEmpty);
    },
  );

  test('records from a different origin never restore cookies', () async {
    vault.values['bagoo-buyer-session-v1:${origin.origin}'] = jsonEncode({
      'origin': 'https://foreign.example.test',
      'remember': true,
      'cookies': [
        {'header': 'session=foreign; Path=/', 'expires': null},
      ],
    });
    final session = WebSession(origin, vault: vault);
    addTearDown(session.close);
    await session.restoreSavedSession();
    expect(session.imageHeaders('/'), isEmpty);
    expect(vault.values, isEmpty);
  });
}
