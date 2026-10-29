import 'dart:convert';
import 'dart:io';

import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test(
    'direct JSON reads use the existing session without CSRF bootstrap',
    () async {
      final seen = <String>[];
      server.listen((request) async {
        seen.add('${request.method} ${request.uri.path}');
        expect(
          request.headers.value(HttpHeaders.acceptHeader),
          'application/json',
        );
        expect(request.headers.value('X-CSRF-TOKEN'), isNull);
        if (request.uri.path == '/first') {
          request.response.cookies.add(Cookie('session', 'guest')..path = '/');
        } else {
          expect(request.cookies.single.value, 'guest');
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"ok":true}');
        await request.response.close();
      });
      expect(await session.jsonGetDirect('/first'), {'ok': true});
      expect(await session.jsonGetDirect('/next'), {'ok': true});
      expect(seen, ['GET /first', 'GET /next']);
    },
  );

  test(
    'redirect bodies and targets cannot grant capabilities or replace cookies',
    () async {
      final seen = <String>[];
      server.listen((request) async {
        seen.add(request.uri.path);
        if (request.uri.path == '/bootstrap') {
          request.response.cookies.add(Cookie('session', 'buyer')..path = '/');
        } else if (request.uri.path == '/capabilities') {
          request.response.statusCode = int.parse(
            request.uri.queryParameters['status']!,
          );
          request.response.headers.set(HttpHeaders.locationHeader, '/enabled');
          request.response.cookies.add(
            Cookie('session', 'redirected')..path = '/',
          );
        } else {
          expect(request.uri.path, '/proof');
          expect(request.cookies.single.value, 'buyer');
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'contract_version': 1,
            'features': {'native_google_sign_in': true, 'device_push': true},
          }),
        );
        await request.response.close();
      });
      await session.jsonGetDirect('/bootstrap');
      for (final status in [301, 302, 303, 307, 308, 409]) {
        await expectLater(
          session.jsonGetDirect('/capabilities?status=$status'),
          throwsA(
            isA<BackendException>().having(
              (e) => e.status,
              'redirect status',
              status,
            ),
          ),
        );
      }
      await session.jsonGetDirect('/proof');
      expect(seen, [
        '/bootstrap',
        ...List.filled(6, '/capabilities'),
        '/proof',
      ]);
      expect(seen, isNot(contains('/enabled')));
    },
  );

  test(
    'a redirect without a destination cannot be read as valid JSON',
    () async {
      server.listen((request) async {
        request.response.statusCode = 302;
        request.response.write(
          '{"contract_version":1,"features":{"native_google_sign_in":true,"device_push":false}}',
        );
        await request.response.close();
      });
      await expectLater(
        session.jsonGetDirect('/capabilities'),
        throwsA(
          isA<BackendException>().having(
            (e) => e.status,
            'redirect status',
            302,
          ),
        ),
      );
    },
  );

  test(
    'ordinary JSON redirects still follow their same-origin destination',
    () async {
      final seen = <String>[];
      server.listen((request) async {
        seen.add(request.uri.path);
        if (request.uri.path == '/start') {
          request.response.statusCode = 302;
          request.response.headers.set(HttpHeaders.locationHeader, '/result');
        } else {
          request.response.write('{"ok":true}');
        }
        await request.response.close();
      });
      expect(await session.jsonGet('/start'), {'ok': true});
      expect(seen, ['/start', '/result']);
    },
  );

  test(
    'direct reads preserve structured HTTP errors without retrying',
    () async {
      var reads = 0;
      server.listen((request) async {
        reads++;
        request.response.statusCode = 429;
        request.response.write(
          '{"message":"Try later","errors":{"request":["Rate limited"]}}',
        );
        await request.response.close();
      });
      await expectLater(
        session.jsonGetDirect('/capabilities'),
        throwsA(
          isA<BackendException>()
              .having((e) => e.status, 'HTTP status', 429)
              .having(
                (e) => e.fields['request'],
                'field feedback',
                'Rate limited',
              ),
        ),
      );
      expect(reads, 1);
    },
  );
}
