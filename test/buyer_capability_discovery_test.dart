import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:flutter_test/flutter_test.dart';

String page(String component, {Map<String, dynamic> props = const {}}) =>
    '<html><head><meta name="csrf-token" content="test-csrf"></head>'
    '<body><div data-page="${const HtmlEscape().convert(jsonEncode({'component': component, 'props': props, 'version': 'v1'}))}"></div></body></html>';

Map<String, dynamic> fixture() => jsonDecode(
  File('test/fixtures/buyer-mobile-capabilities-disabled.json')
      .readAsStringSync(),
) as Map<String, dynamic>;

void main() {
  late HttpServer server;
  late WebSession session;
  late BuyerRepository buyer;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    session = WebSession(Uri.parse('http://localhost:${server.port}'));
    buyer = BuyerRepository(session);
  });
  tearDown(() async {
    session.close();
    await server.close(force: true);
  });

  test(
    'reads the agreed fixture on demand without a CSRF or login request',
    () async {
      final envelope = fixture();
      final seen = <String>[];
      server.listen((request) async {
        seen.add('${request.method} ${request.uri.path}');
        expect(
          request.headers.value(HttpHeaders.acceptHeader),
          'application/json',
        );
        request.response.statusCode = envelope['response']['status'] as int;
        for (final header in (envelope['response']['headers'] as Map).entries) {
          request.response.headers.set(header.key.toString(), header.value);
        }
        request.response.write(jsonEncode(envelope['response']['body']));
        await request.response.close();
      });
      expect(seen, isEmpty);
      final result = await buyer.discoverCapabilities();
      expect(result.isSupported, isTrue);
      expect(result.nativeGoogleSignIn, isFalse);
      expect(result.devicePush, isFalse);
      expect(seen, ['GET /buyer/mobile-capabilities']);
    },
  );

  test(
    'HTTP failures disable optional providers without automatic retries',
    () async {
      var status = 401, reads = 0;
      server.listen((request) async {
        reads++;
        expect(request.method, 'GET');
        request.response.statusCode = status;
        request.response.write('{"message":"Unavailable"}');
        await request.response.close();
      });
      for (final code in [401, 403, 404, 419, 422, 429, 500, 503]) {
        status = code;
        final result = await buyer.discoverCapabilities();
        expect(result.isSupported, isFalse);
        expect(result.nativeGoogleSignIn, isFalse);
        expect(result.devicePush, isFalse);
      }
      expect(reads, 8);
    },
  );

  test(
    'a redirect cannot enable a provider through its body or destination',
    () async {
      final paths = <String>[];
      server.listen((request) async {
        paths.add(request.uri.path);
        request.response.statusCode = 302;
        request.response.headers.set(HttpHeaders.locationHeader, '/enabled');
        request.response.write(
          '{"contract_version":1,"features":{"native_google_sign_in":true,"device_push":true}}',
        );
        await request.response.close();
      });
      final result = await buyer.discoverCapabilities();
      expect(result.isSupported, isFalse);
      expect(result.nativeGoogleSignIn, isFalse);
      expect(result.devicePush, isFalse);
      expect(paths, ['/buyer/mobile-capabilities']);
    },
  );

  test(
    'HTML, non-object JSON and malformed bodies leave capabilities unavailable',
    () async {
      var body = '';
      server.listen((request) async {
        request.response.write(body);
        await request.response.close();
      });
      for (final value in [
        '',
        '[]',
        'null',
        '{"features":',
        page('Auth/Login'),
      ]) {
        body = value;
        final result = await buyer.discoverCapabilities();
        expect(result.isSupported, isFalse);
        expect(result.nativeGoogleSignIn, isFalse);
        expect(result.devicePush, isFalse);
      }
    },
  );

  test(
    'discovery does not retain capability grants after the next failed read',
    () async {
      var available = true;
      server.listen((request) async {
        request.response.statusCode = available ? 200 : 503;
        request.response.write(
          available
              ? '{"contract_version":1,"features":{"native_google_sign_in":true,"device_push":false}}'
              : '{"message":"Unavailable"}',
        );
        await request.response.close();
      });
      expect((await buyer.discoverCapabilities()).nativeGoogleSignIn, isTrue);
      available = false;
      final result = await buyer.discoverCapabilities();
      expect(result.isSupported, isFalse);
      expect(result.nativeGoogleSignIn, isFalse);
    },
  );

  test(
    'an unavailable discovery request does not prevent ordinary email login',
    () async {
      final seen = <String>[];
      server.listen((request) async {
        seen.add('${request.method} ${request.uri.path}');
        switch (request.uri.path) {
          case '/buyer/mobile-capabilities':
            request.response.statusCode = 503;
            request.response.write(
              '{"message":"Optional service unavailable"}',
            );
          case '/login' when request.method == 'GET':
            request.response.write(page('Auth/Login'));
          case '/login':
            final values = jsonDecode(await utf8.decoder.bind(request).join());
            expect(values['role'], 'buyer');
            request.response.cookies.add(
              Cookie('session', 'buyer')..path = '/',
            );
            request.response.statusCode = 303;
            request.response.headers.set(HttpHeaders.locationHeader, '/');
          case '/':
            expect(request.cookies.single.value, 'buyer');
            request.response.write(
              page(
                'Buyer/Home',
                props: {
                  'auth': {
                    'user': {'id': 7, 'role': 'buyer'},
                  },
                },
              ),
            );
          default:
            fail('Unexpected discovery/login request');
        }
        await request.response.close();
      });
      expect((await buyer.discoverCapabilities()).isSupported, isFalse);
      final result = await buyer.login('buyer@example.test', 'test-password');
      expect(result.user?['id'], 7);
      expect(seen, [
        'GET /buyer/mobile-capabilities',
        'GET /login',
        'POST /login',
        'GET /',
      ]);
    },
  );

  test(
    'a late reply cannot advertise capabilities after the session changes',
    () async {
      final received = Completer<void>(), release = Completer<void>();
      server.listen((request) async {
        received.complete();
        await release.future;
        request.response.write(
          '{"contract_version":1,"features":{"native_google_sign_in":true,"device_push":true}}',
        );
        await request.response.close();
      });
      final pending = buyer.discoverCapabilities();
      await received.future;
      session.clear();
      release.complete();
      final result = await pending;
      expect(result.isSupported, isFalse);
      expect(result.nativeGoogleSignIn, isFalse);
      expect(result.devicePush, isFalse);
    },
  );

  test(
    'connection failure does not throw or imply an enabled provider',
    () async {
      await server.close(force: true);
      final result = await buyer.discoverCapabilities();
      expect(result.isSupported, isFalse);
      expect(result.nativeGoogleSignIn, isFalse);
      expect(result.devicePush, isFalse);
    },
  );
}
