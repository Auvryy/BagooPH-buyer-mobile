import 'dart:convert';
import 'dart:io';

import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:flutter_test/flutter_test.dart';

String markup(
  String component, {
  Map<String, dynamic> props = const {},
  String version = 'v1',
}) =>
    '<html><head><meta name="csrf-token" content="csrf-meta"></head><body>'
    '<div data-page="${const HtmlEscape().convert(jsonEncode({'component': component, 'props': props, 'version': version}))}"></div></body></html>';
void main() {
  late HttpServer server;
  late WebSession session;
  late BuyerRepository repository;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    session = WebSession(Uri.parse('http://localhost:${server.port}'));
    repository = BuyerRepository(session);
  });
  tearDown(() async {
    session.close();
    await server.close(force: true);
  });

  test(
    'bootstraps CSRF, sends cookies, and follows a rotated login session',
    () async {
      final seen = <String>[];
      server.listen((request) async {
        seen.add('${request.method} ${request.uri.path}');
        if (request.method == 'GET' && request.uri.path == '/login') {
          request.response.cookies.add(
            Cookie('XSRF-TOKEN', 'csrf-cookie')..path = '/',
          );
          request.response.cookies.add(Cookie('session', 'guest')..path = '/');
          request.response.write(markup('Auth/Login'));
        } else if (request.method == 'POST') {
          expect(request.headers.value('X-XSRF-TOKEN'), 'csrf-cookie');
          expect(
            request.cookies.any(
              (c) => c.name == 'session' && c.value == 'guest',
            ),
            isTrue,
          );
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect(body['role'], 'buyer');
          expect(body['remember'], isFalse);
          request.response.cookies.add(Cookie('session', 'buyer')..path = '/');
          request.response.statusCode = 302;
          request.response.headers.set('Location', '/');
        } else {
          expect(
            request.cookies.any(
              (c) => c.name == 'session' && c.value == 'buyer',
            ),
            isTrue,
          );
          request.response.write(
            markup(
              'Buyer/Home',
              props: {
                'auth': {
                  'user': {'id': 1, 'role': 'buyer'},
                },
              },
            ),
          );
        }
        await request.response.close();
      });
      final page = await repository.login(
        'BUYER@example.test ',
        'test-password',
      );
      expect(page.user?['id'], 1);
      expect(seen, ['GET /login', 'POST /login', 'GET /']);
    },
  );

  test('returns server field errors without accepting a session', () async {
    server.listen((request) async {
      if (request.method == 'GET') {
        request.response.write(markup('Auth/Login'));
      } else {
        request.response.statusCode = 422;
        request.response.write(
          jsonEncode({
            'message': 'Invalid input',
            'errors': {
              'email': ['Buyer credentials rejected.'],
            },
          }),
        );
      }
      await request.response.close();
    });
    await expectLater(
      repository.login('buyer@example.test', 'wrong'),
      throwsA(
        isA<BackendException>().having(
          (e) => e.fields['email'],
          'email feedback',
          'Buyer credentials rejected.',
        ),
      ),
    );
  });

  test('rejects cross-origin credential redirects', () async {
    server.listen((request) async {
      if (request.method == 'GET') {
        request.response.write(markup('Auth/Login'));
      } else {
        request.response.statusCode = 302;
        request.response.headers.set('Location', 'https://unrelated.test/');
      }
      await request.response.close();
    });
    await expectLater(
      repository.login('buyer@example.test', 'test-password'),
      throwsA(
        isA<BackendException>().having(
          (e) => e.message,
          'redirect',
          contains('unsupported redirect'),
        ),
      ),
    );
  });

  test(
    'does not accept a redirect to login as successful authentication',
    () async {
      server.listen((request) async {
        if (request.method == 'POST') {
          request.response.statusCode = 302;
          request.response.headers.set('Location', '/login');
        } else {
          request.response.write(markup('Auth/Login'));
        }
        await request.response.close();
      });
      await expectLater(
        repository.login('buyer@example.test', 'test-password'),
        throwsA(isA<BackendException>()),
      );
    },
  );

  test(
    'refreshes the Inertia version after a deployment without mutation',
    () async {
      int requests = 0;
      server.listen((request) async {
        requests++;
        if (requests == 1) {
          request.response.write(markup('Auth/Login'));
        } else if (requests == 2) {
          expect(request.headers.value('X-Inertia-Version'), 'v1');
          request.response.statusCode = 409;
          request.response.headers.set('X-Inertia-Location', '/');
        } else if (requests == 3) {
          expect(request.headers.value('X-Inertia'), isNull);
          request.response.write(markup('Buyer/Home', version: 'v2'));
        } else {
          expect(request.headers.value('X-Inertia-Version'), 'v2');
          request.response.write(
            jsonEncode({
              'component': 'Buyer/Home',
              'props': {},
              'version': 'v2',
            }),
          );
        }
        await request.response.close();
      });
      await session.page('/login');
      expect((await session.page('/')).component, 'Buyer/Home');
      await session.page('/');
      expect(requests, 4);
    },
  );

  test('does not replay a mutation after CSRF expiration', () async {
    int posts = 0;
    server.listen((request) async {
      if (request.method == 'GET') {
        request.response.write(markup('Auth/Login'));
      } else {
        posts++;
        request.response.statusCode = 419;
      }
      await request.response.close();
    });
    await expectLater(
      repository.login('buyer@example.test', 'password'),
      throwsA(
        isA<BackendException>().having((e) => e.status, 'HTTP status', 419),
      ),
    );
    expect(posts, 1);
  });

  test('encodes search and filter values in the backend query', () async {
    server.listen((request) async {
      expect(request.uri.queryParameters['search'], 'tea & coffee');
      expect(request.uri.queryParameters['category'], 'food');
      expect(request.uri.queryParameters['sort'], 'price_asc');
      expect(request.uri.queryParameters['page'], '2');
      request.response.write(markup('Buyer/Home'));
      await request.response.close();
    });
    await repository.home(
      search: 'tea & coffee',
      category: 'food',
      sort: 'price_asc',
      page: 2,
    );
  });

  test(
    'rejects unsuccessful OTP responses instead of returning a token',
    () async {
      server.listen((request) async {
        if (request.method == 'GET') {
          request.response.write(markup('Auth/Login'));
        } else {
          request.response.write(
            jsonEncode({'success': false, 'message': 'Code expired.'}),
          );
        }
        await request.response.close();
      });
      await expectLater(
        repository.verifyCode('buyer@example.test', 'registration', '123456'),
        throwsA(
          isA<BackendException>().having(
            (e) => e.message,
            'server message',
            'Code expired.',
          ),
        ),
      );
    },
  );
}
