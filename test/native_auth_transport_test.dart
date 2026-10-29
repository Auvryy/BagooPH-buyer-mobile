import 'dart:convert';
import 'dart:io';

import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'web_session_test.dart' show markup;

void main() {
  late HttpServer server;
  late WebSession session;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    session = WebSession(Uri.parse('http://localhost:${server.port}'));
  });
  tearDown(() async {
    session.close();
    await server.close(force: true);
  });

  test('native mutations bootstrap CSRF and use rotated session/XSRF on the next write', () async {
    final paths = <String>[];
    server.listen((request) async {
      paths.add('${request.method} ${request.uri.path}');
      if (request.method == 'GET') {
        request.response.cookies.add(
          Cookie('XSRF-TOKEN', 'csrf-before')..path = '/',
        );
        request.response.cookies.add(Cookie('session', 'guest')..path = '/');
        request.response.write(markup('Auth/Login'));
      } else {
        await request.drain<void>();
        expect(
          request.headers.value('X-XSRF-TOKEN'),
          request.uri.path == '/auth/google/native'
              ? 'csrf-before'
              : 'csrf-after',
        );
        if (request.uri.path == '/auth/google/native') {
          request.response.cookies.add(
            Cookie('XSRF-TOKEN', 'csrf-after')..path = '/',
          );
          request.response.cookies.add(Cookie('session', 'buyer')..path = '/');
        } else {
          expect(
            request.cookies.any(
              (c) => c.name == 'session' && c.value == 'buyer',
            ),
            isTrue,
          );
        }
        request.response.write('{"authenticated":true}');
      }
      await request.response.close();
    });
    expect(
      await session.jsonPostDirect('/auth/google/native', {
        'id_token': 'synthetic',
      }),
      {'authenticated': true},
    );
    await session.jsonPostDirect('/next', {});
    expect(paths, ['GET /login', 'POST /auth/google/native', 'POST /next']);
  });

  test('native JSON writes reject redirected acknowledgements without replay or cookie adoption', () async {
    final paths = <String>[];
    server.listen((request) async {
      paths.add('${request.method} ${request.uri.path}');
      if (request.method == 'GET') {
        request.response.write(markup('Auth/Login'));
      } else {
        await request.drain<void>();
        request.response.statusCode = 303;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          '/website-auth',
        );
        request.response.cookies.add(
          Cookie('session', 'redirected')..path = '/',
        );
        request.response.write('{"authenticated":true}');
      }
      await request.response.close();
    });
    await expectLater(
      session.jsonPostDirect('/auth/google/native', {'id_token': 'synthetic'}),
      throwsA(isA<BackendException>().having((e) => e.status, 'redirect', 303)),
    );
    expect(paths, ['GET /login', 'POST /auth/google/native']);
    expect(session.imageHeaders('/'), isEmpty);
  });

  test(
    'rate limits retain safe retry metadata with no automatic POST retry',
    () async {
      var posts = 0;
      server.listen((request) async {
        if (request.method == 'GET') {
          request.response.write(markup('Auth/Login'));
        } else {
          posts++;
          await request.drain<void>();
          request.response.statusCode = 429;
          request.response.headers.set(HttpHeaders.retryAfterHeader, '45');
          request.response.write(
            jsonEncode({'message': 'Wait before trying again'}),
          );
        }
        await request.response.close();
      });
      final before = DateTime.now().toUtc();
      await expectLater(
        session.jsonPostDirect('/auth/google/native', {
          'id_token': 'synthetic',
        }),
        throwsA(
          isA<BackendException>().having(
            (e) => e.retryAt?.isAfter(before.add(const Duration(seconds: 44))),
            'retry deadline',
            true,
          ),
        ),
      );
      expect(posts, 1);
    },
  );

  test(
    'empty validation arrays keep the remaining field feedback readable',
    () async {
      server.listen((request) async {
        if (request.method == 'GET') {
          request.response.write(markup('Auth/Login'));
        } else {
          await request.drain<void>();
          request.response.statusCode = 422;
          request.response.write(
            jsonEncode({
              'message': 'Review your details.',
              'errors': {
                'empty': <String>[],
                'birthday': ['You must be 18 or older.'],
              },
            }),
          );
        }
        await request.response.close();
      });
      await expectLater(
        session.jsonPostDirect('/auth/google/native/register', {}),
        throwsA(
          isA<BackendException>().having((e) => e.fields, 'field errors', {
            'birthday': 'You must be 18 or older.',
          }),
        ),
      );
    },
  );

  test(
    'Retry-After accepts seconds or HTTP dates and rejects malformed metadata',
    () {
      final now = DateTime.utc(2026, 10, 29, 8);
      expect(
        retryDeadline('30', now: now),
        now.add(const Duration(seconds: 30)),
      );
      expect(
        retryDeadline(
          HttpDate.format(now.add(const Duration(seconds: 45))),
          now: now,
        ),
        now.add(const Duration(seconds: 45)),
      );
      for (final value in [
        null,
        '-1',
        'not-a-date',
        '999999999999999999999999999999',
      ]) {
        expect(retryDeadline(value, now: now), isNull);
      }
    },
  );
}
