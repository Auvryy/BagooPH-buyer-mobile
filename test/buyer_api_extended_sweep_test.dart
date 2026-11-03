import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bagoo_buyer_mobile/core/buyer_account_scope.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// Real loopback HTTP, without Laravel or SQL. Routes implemented inline in UI
// use their actual WebSession adapter and BuyerAccountScope here. Those tests
// cover transport/account boundaries, not execution of the widget validators.
String _markup(String component, Map<String, dynamic> props) =>
    '<meta name="csrf-token" content="extended-csrf"><div data-page="${const HtmlEscape().convert(jsonEncode({'component': component, 'props': props, 'version': 'extended-v1'}))}"></div>';

Map<String, dynamic> _owned({int owner = 7}) => {
  'auth': {
    'user': {'id': owner, 'role': 'buyer'},
  },
  'user': {'id': owner},
};

Map<String, dynamic> _chat({int id = 21}) => {
  'id': id,
  'sender_id': 7,
  'receiver_id': 3,
  'message': 'Question about this purchase',
  'created_at': '2026-11-03T01:02:03Z',
  'attachment_url': null,
  'product': {'id': 41, 'slug': 'test-product'},
};

final _photo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGN4wOv0HwAFLwIvfpkhFAAAAABJRU5ErkJggg==',
);

const _intent = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _sessionId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _returnIntent =
    'v1.aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _ReadRoute {
  const _ReadRoute(this.path, this.component, this.props);
  final String path;
  final String component;
  final Map<String, dynamic> props;
}

class _PageMutation {
  const _PageMutation({
    required this.path,
    required this.values,
    required this.referer,
    required this.component,
    required this.props,
    this.method = 'POST',
    this.photoField,
    this.destination,
    this.multipartFields = const {},
  });
  final String path, referer, component, method;
  final Map<String, dynamic> values, props;
  final String? photoField;
  final String? destination;
  String get redirectTarget => destination ?? referer;
  final Map<String, String> multipartFields;
}

void main() {
  late HttpServer server;
  late WebSession session;
  late BuyerRepository buyer;
  late ProfileRepository profile;
  late BuyerAccountScope account;
  late List<String> seen;
  late Future<void> Function(HttpRequest) respond;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    session = WebSession(Uri.parse('http://127.0.0.1:${server.port}'));
    buyer = BuyerRepository(session);
    profile = ProfileRepository(buyer);
    account = BuyerAccountScope(session)
      ..check(page: WebPage('Buyer/Profile', _owned()));
    seen = [];
    respond = (request) async {
      request.response.write('{}');
    };
    server.listen((request) async {
      seen.add('${request.method} ${request.uri.path}');
      try {
        if (request.method == 'GET' && request.uri.path == '/login') {
          request.response.cookies.add(
            Cookie('extended_session', 'synthetic-only')..path = '/',
          );
          request.response.write(_markup('Auth/Login', {}));
        } else {
          await respond(request);
        }
      } finally {
        await request.response.close();
      }
    });
  });

  tearDown(() async {
    session.close();
    await server.close(force: true);
  });

  Future<WebPage> readOwned(String path) async {
    final result = await buyer.document(path);
    buyer.requireNoErrors(result);
    account.check(page: result);
    return result;
  }

  group('private page adapters used by inline native flows', () {
    final routes = [
      const _ReadRoute('/buyer/messages', 'Buyer/Messages', {
        'conversations': [],
      }),
      const _ReadRoute('/buyer/orders?page=2', 'Buyer/Orders', {
        'orders': {'data': [], 'current_page': 2},
      }),
      const _ReadRoute('/wallet/payments/42', 'Buyer/WalletPayment', {
        'payment': {'id': 42, 'request_token': _intent},
      }),
      const _ReadRoute('/account/status', 'Auth/AccountStatus', {
        'status': {
          'account': {'id': 7},
          'sources': [],
          'requests': [],
        },
      }),
      const _ReadRoute('/buyer-returns?page=2', 'Returns/Index', {
        'cases': {'data': [], 'current_page': 2},
      }),
      const _ReadRoute('/buyer-returns/orders/42/create', 'Returns/Create', {
        'order': {'id': 42},
        'requestToken': _intent,
      }),
      const _ReadRoute('/buyer-returns/12', 'Returns/Show', {
        'returnCase': {
          'id': 12,
          'order': {'id': 42},
          'version': 3,
        },
      }),
    ];
    for (final route in routes) {
      test('GET ${route.path} retains route, query, page and buyer', () async {
        respond = (request) async {
          expect(request.method, 'GET');
          expect(request.uri, Uri.parse(route.path));
          expect(
            request.headers.value('accept'),
            'text/html, application/xhtml+xml',
          );
          request.response.write(
            _markup(route.component, {..._owned(), ...route.props}),
          );
        };
        final result = await readOwned(route.path);
        expect(result.component, route.component);
        expect(result.user?['id'], 7);
        for (final entry in route.props.entries) {
          expect(result.props[entry.key], entry.value);
        }
        expect(seen, ['GET ${Uri.parse(route.path).path}']);
      });

      test('GET ${route.path} cannot cross the opening buyer scope', () async {
        respond = (request) async {
          request.response.write(
            _markup(route.component, {..._owned(owner: 8), ...route.props}),
          );
        };
        await expectLater(
          readOwned(route.path),
          throwsA(
            isA<BackendException>().having(
              (e) => e.status,
              'changed owner',
              401,
            ),
          ),
        );
        expect(account.isCurrent, isFalse);
        expect(seen, hasLength(1));
      });

      for (final status in [401, 403]) {
        test(
          'GET ${route.path} preserves HTTP $status without retry',
          () async {
            respond = (request) async {
              request.response.statusCode = status;
              request.response.write(
                '{"message":"Private resource unavailable"}',
              );
            };
            await expectLater(
              readOwned(route.path),
              throwsA(
                isA<BackendException>().having(
                  (e) => e.status,
                  'HTTP status',
                  status,
                ),
              ),
            );
            expect(seen, hasLength(1));
          },
        );
      }
    }

    for (final body in [
      'null',
      '[]',
      '{}',
      '{"component":"Buyer/Messages"}',
      '{"component":7,"props":{}}',
      '{"component":"Buyer/Messages","props":[]}',
      '<html>Proxy error</html>',
    ]) {
      test('inbox page rejects malformed wire response $body', () async {
        respond = (request) async {
          request.response.write(body);
        };
        await expectLater(
          readOwned('/buyer/messages'),
          throwsA(isA<BackendException>()),
        );
        expect(seen, ['GET /buyer/messages']);
      });
    }

    test(
      'private page validation errors and flash errors remain failures',
      () async {
        var validation = true;
        respond = (request) async {
          request.response.write(
            _markup('Returns/Show', {
              ..._owned(),
              if (validation)
                'errors': {
                  'return_case': ['Return eligibility changed'],
                },
              if (!validation) 'flash': {'error': 'Return access ended'},
            }),
          );
        };
        await expectLater(
          readOwned('/buyer-returns/12'),
          throwsA(
            isA<BackendException>().having(
              (e) => e.fields['return_case'],
              'field error',
              'Return eligibility changed',
            ),
          ),
        );
        validation = false;
        await expectLater(
          readOwned('/buyer-returns/12'),
          throwsA(
            isA<BackendException>().having(
              (e) => e.message,
              'flash error',
              'Return access ended',
            ),
          ),
        );
        expect(seen, ['GET /buyer-returns/12', 'GET /buyer-returns/12']);
      },
    );
  });

  group('JSON security and geographic reads', () {
    test(
      'security history preserves both independent page parameters',
      () async {
        respond = (request) async {
          expect(request.method, 'GET');
          expect(request.uri.path, '/account/security');
          expect(request.uri.queryParameters, {
            'sessions_page': '2',
            'history_page': '3',
          });
          expect(request.headers.value('accept'), 'application/json');
          request.response.write(
            jsonEncode({
              'sessionOwnerId': 7,
              'currentSessionId': _sessionId,
              'sessions': {'data': []},
              'history': {'data': []},
            }),
          );
        };
        final result = await session.jsonGet(
          '/account/security?sessions_page=2&history_page=3',
        );
        expect(result['sessionOwnerId'], 7);
        expect(result['currentSessionId'], _sessionId);
        expect(seen, ['GET /account/security']);
      },
    );

    test('location hierarchy query preserves spaces and ampersands', () async {
      final query = {
        'region': 'Region IV-A',
        'province': 'Province & Islands',
        'city': 'Test City',
      };
      respond = (request) async {
        expect(request.method, 'GET');
        expect(request.uri.path, '/address-locations');
        expect(request.uri.queryParameters, query);
        request.response.write(
          jsonEncode({
            'regions': [],
            'provinces': [],
            'cities': [],
            'barangays': [],
            'resolved': query,
          }),
        );
      };
      expect(
        (await session.jsonGet(
          Uri(path: '/address-locations', queryParameters: query).toString(),
        ))['resolved'],
        query,
      );
      expect(seen, ['GET /address-locations']);
    });

    for (final path in [
      '/account/security?sessions_page=1&history_page=1',
      '/address-locations?region=Region',
    ]) {
      test('$path rejects JSON arrays and HTML login bodies', () async {
        var body = '[]';
        respond = (request) async {
          request.response.write(body);
        };
        await expectLater(
          session.jsonGet(path),
          throwsA(isA<BackendException>()),
        );
        body = '<html>Sign in again</html>';
        await expectLater(
          session.jsonGet(path),
          throwsA(isA<BackendException>()),
        );
        expect(seen, hasLength(2));
      });
    }
  });

  group('remaining repository commerce and chat contracts', () {
    final quote = <String, dynamic>{
      'item_ids': [4, 8],
      'item_quantities': {'4': 2, '8': 1},
      'delivery_type': 'doorstep',
      'pickup_hub_id': null,
      'shipping_city': 'Test City',
      'shipping_province': 'Test Province',
      'shipping_postal_code': '4000',
      'destination_barangay': 'Test Barangay',
      'logistics_company_id': 3,
      'code': 'SAVE',
      'platform_voucher_revision_id': 17,
      'shop_voucher_revision_ids': {'2': 18},
    };
    for (final route in ['choices', 'best']) {
      test(
        'voucher $route uses current quote fields and confirms its reply',
        () async {
          final values = {
            ...quote,
            if (route == 'choices') 'shop_id': 2,
            if (route == 'choices') 'voucher_page': 3,
          };
          respond = (request) async {
            expect(request.method, 'POST');
            expect(request.uri.path, '/buyer/vouchers/$route');
            expect(request.headers.value('X-CSRF-TOKEN'), 'extended-csrf');
            expect(jsonDecode(await utf8.decoder.bind(request).join()), values);
            request.response.write(
              route == 'choices'
                  ? '{"offers":{"data":[]}}'
                  : '{"selection":{},"quote":{}}',
            );
          };
          final result = route == 'choices'
              ? await buyer.voucherChoices(values)
              : await buyer.bestVouchers(values);
          expect(
            result.keys,
            contains(route == 'choices' ? 'offers' : 'selection'),
          );
          expect(seen, ['GET /login', 'POST /buyer/vouchers/$route']);
        },
      );

      for (final body in [
        '{}',
        '{"offers":{"data":null}}',
        '{"selection":[],"quote":null}',
      ]) {
        test(
          'voucher $route rejects incomplete acknowledgement $body',
          () async {
            respond = (request) async {
              await request.drain<void>();
              request.response.write(body);
            };
            final operation = route == 'choices'
                ? buyer.voucherChoices(quote)
                : buyer.bestVouchers(quote);
            await expectLater(operation, throwsA(isA<BackendException>()));
            expect(seen, ['GET /login', 'POST /buyer/vouchers/$route']);
          },
        );
      }
    }

    for (final subscribed in [true, false]) {
      test(
        'sale reminder ${subscribed ? 'POST' : 'DELETE'} follows product referer and state',
        () async {
          respond = (request) async {
            expect(request.method, subscribed ? 'POST' : 'DELETE');
            expect(request.uri.path, '/buyer/sale-reminders/13');
            expect(
              request.headers.value('referer'),
              '${session.origin}/buyer/product/test-product',
            );
            expect(
              jsonDecode(await utf8.decoder.bind(request).join()),
              isEmpty,
            );
            request.response.write(
              _markup('Buyer/ProductDetail', {
                'saleReminder': {'subscribed': subscribed},
              }),
            );
          };
          expect(
            (await buyer.reminder('test-product', 13, subscribed)).component,
            'Buyer/ProductDetail',
          );
          expect(seen, [
            'GET /login',
            '${subscribed ? 'POST' : 'DELETE'} /buyer/sale-reminders/13',
          ]);
        },
      );
    }

    test(
      'sale reminder refuses opposite acknowledgement and invalid local ID',
      () async {
        respond = (request) async {
          await request.drain<void>();
          request.response.write(
            _markup('Buyer/ProductDetail', {
              'saleReminder': {'subscribed': false},
            }),
          );
        };
        await expectLater(
          buyer.reminder('test-product', 0, true),
          throwsA(isA<BackendException>()),
        );
        expect(seen, isEmpty);
        await expectLater(
          buyer.reminder('test-product', 13, true),
          throwsA(isA<BackendException>()),
        );
        expect(seen, ['GET /login', 'POST /buyer/sale-reminders/13']);
      },
    );

    final chatValues = {
      'receiver_id': 3,
      'shop_id': 2,
      'product_id': 41,
      'order_id': 42,
      'message': 'Question about this purchase',
      'request_key': _intent,
    };
    test(
      'chat JSON sends the existing participant/context/idempotency fields',
      () async {
        respond = (request) async {
          expect(request.method, 'POST');
          expect(request.uri.path, '/chat/send');
          expect(
            jsonDecode(await utf8.decoder.bind(request).join()),
            chatValues,
          );
          request.response.write(
            jsonEncode({'success': true, 'message': _chat()}),
          );
        };
        expect(await buyer.sendMessage(chatValues), _chat());
        expect(seen, ['GET /login', 'POST /chat/send']);
      },
    );

    test(
      'chat attachment carries bytes and request key through multipart',
      () async {
        respond = (request) async {
          expect(request.method, 'POST');
          expect(request.uri.path, '/chat/send');
          expect(request.headers.contentType?.mimeType, 'multipart/form-data');
          final bytes = await request.fold<List<int>>(
            [],
            (all, chunk) => all..addAll(chunk),
          );
          final body = latin1.decode(bytes);
          expect(body, contains('name="request_key"\r\n\r\n$_intent\r\n'));
          expect(body, contains('name="receiver_id"\r\n\r\n3\r\n'));
          expect(body, contains('name="attachment"; filename="photo.png"'));
          expect(body, contains(latin1.decode(_photo)));
          request.response.write(
            jsonEncode({
              'success': true,
              'message': {..._chat(), 'attachment_url': '/chat/attachments/21'},
            }),
          );
        };
        final message = await buyer.sendMessage(
          chatValues,
          files: [UploadPart('attachment', 'photo.png', _photo, 'image/png')],
        );
        expect(message['attachment_url'], '/chat/attachments/21');
        expect(seen, ['GET /login', 'POST /chat/send']);
      },
    );

    for (final badMessage in <Map<String, dynamic>>[
      {..._chat(), 'id': 0},
      {..._chat(), 'sender_id': '7'},
      {..._chat(), 'receiver_id': null},
      {..._chat(), 'message': null},
      {..._chat(), 'created_at': '2026-02-30T00:00:00Z'},
      {..._chat(), 'attachment_url': 7},
      {..._chat(), 'product': []},
    ]) {
      test(
        'chat rejects incomplete message ${jsonEncode(badMessage)}',
        () async {
          respond = (request) async {
            await request.drain<void>();
            request.response.write(
              jsonEncode({'success': true, 'message': badMessage}),
            );
          };
          await expectLater(
            buyer.sendMessage(chatValues),
            throwsA(isA<BackendException>()),
          );
          expect(seen, ['GET /login', 'POST /chat/send']);
        },
      );
    }
  });

  group('inline JSON mutations use the production session transport', () {
    final routes =
        <(String, String, Map<String, dynamic>, Map<String, dynamic>)>[
          (
            'POST',
            '/buyer/followed-shops/2',
            {},
            {'following': true, 'followers': 3},
          ),
          (
            'DELETE',
            '/buyer/followed-shops/2',
            {},
            {'following': false, 'followers': 2},
          ),
          ('POST', '/buyer/saved-vouchers/17', {}, {'saved_id': 22}),
          ('DELETE', '/buyer/saved-vouchers/22', {}, {'saved_id': null}),
          (
            'POST',
            '/wallet/payments/42/pay',
            {'request_token': _intent, 'payment_confirmed': true},
            {'success': true},
          ),
          (
            'POST',
            '/wallet/payments/42/cancel',
            {'request_token': _intent, 'payment_confirmed': false},
            {'success': true},
          ),
          (
            'POST',
            '/account/review-requests',
            {
              'subject_type': 'account',
              'subject_id': 7,
              'source_token': List.filled(64, 'a').join(),
              'message': 'Please review my updated account evidence.',
            },
            {'id': 12, 'status': 'pending'},
          ),
        ];
    for (final route in routes) {
      test(
        '${route.$1} ${route.$2} serializes its actual native payload',
        () async {
          respond = (request) async {
            expect(request.method, route.$1);
            expect(request.uri.path, route.$2);
            expect(request.headers.value('X-CSRF-TOKEN'), 'extended-csrf');
            expect(request.cookies.single.value, 'synthetic-only');
            expect(
              jsonDecode(await utf8.decoder.bind(request).join()),
              route.$3,
            );
            request.response.write(jsonEncode(route.$4));
          };
          expect(
            await session.jsonPost(route.$2, route.$3, method: route.$1),
            route.$4,
          );
          account.check();
          expect(seen, ['GET /login', '${route.$1} ${route.$2}']);
        },
      );

      test(
        '${route.$1} ${route.$2} preserves denied status and never replays',
        () async {
          respond = (request) async {
            await request.drain<void>();
            request.response.statusCode = 403;
            request.response.write('{"message":"Buyer is not permitted"}');
          };
          await expectLater(
            session.jsonPost(route.$2, route.$3, method: route.$1),
            throwsA(
              isA<BackendException>().having((e) => e.status, 'denied', 403),
            ),
          );
          expect(seen, ['GET /login', '${route.$1} ${route.$2}']);
        },
      );
    }

    test(
      'wallet explicit retry keeps the original token and payment proof',
      () async {
        final values = {'request_token': _intent, 'payment_confirmed': true};
        var attempts = 0;
        respond = (request) async {
          attempts++;
          expect(jsonDecode(await utf8.decoder.bind(request).join()), values);
          request.response.statusCode = attempts == 1 ? 503 : 200;
          request.response.write(
            attempts == 1
                ? '{"message":"Uncertain payment"}'
                : '{"success":true}',
          );
        };
        await expectLater(
          session.jsonPost('/wallet/payments/42/pay', values),
          throwsA(
            isA<BackendException>().having(
              (e) => e.status,
              'uncertain status',
              503,
            ),
          ),
        );
        expect(attempts, 1);
        expect(await session.jsonPost('/wallet/payments/42/pay', values), {
          'success': true,
        });
        expect(attempts, 2);
      },
    );

    for (final method in ['password', 'email']) {
      test(
        'session revoke keeps $method confirmation and nullable alternatives',
        () async {
          final values = {
            'request_token': _intent,
            'confirmation_method': method,
            'current_password': method == 'password'
                ? 'synthetic-password'
                : null,
            'code': method == 'email' ? '001234' : null,
          };
          respond = (request) async {
            expect(
              request.uri.path,
              '/account/security/sessions/$_sessionId/revoke',
            );
            expect(jsonDecode(await utf8.decoder.bind(request).join()), values);
            request.response.write(
              jsonEncode({
                'reference': _intent,
                'affected_count': 1,
                'message': 'Revoked',
              }),
            );
          };
          expect(
            (await profile.json(
              '/account/security/sessions/$_sessionId/revoke',
              values,
            ))['affected_count'],
            1,
          );
          expect(seen, [
            'GET /login',
            'POST /account/security/sessions/$_sessionId/revoke',
          ]);
        },
      );
    }
  });

  group('review, cancellation and return page mutations', () {
    final routes = [
      const _PageMutation(
        path: '/buyer/orders/42/cancel',
        values: {
          'reason': 'Other reason',
          'notes': 'The delivery schedule no longer works.',
        },
        referer: '/buyer/orders/42',
        component: 'Buyer/OrderDetail',
        props: {
          'order': {'id': 42, 'status': 'cancelled'},
        },
      ),
      const _PageMutation(
        path: '/buyer/reviews',
        values: {
          'rating': 5,
          'comment': 'The item matched its description.',
          'order_item_id': 101,
        },
        referer: '/buyer/orders/42',
        component: 'Buyer/OrderDetail',
        props: {
          'order': {'id': 42},
        },
        photoField: 'images[0]',
        multipartFields: {
          'rating': '5',
          'order_item_id': '101',
          'comment': 'The item matched its description.',
        },
      ),
      const _PageMutation(
        path: '/buyer/reviews/22',
        method: 'PATCH',
        values: {'rating': 4, 'comment': 'Updated after using the item.'},
        referer: '/buyer/orders/42',
        component: 'Buyer/OrderDetail',
        props: {
          'order': {'id': 42},
        },
        photoField: 'images[0]',
        multipartFields: {
          'rating': '4',
          'comment': 'Updated after using the item.',
        },
      ),
      const _PageMutation(
        path: '/buyer-returns/orders/42',
        destination: '/buyer-returns/12',
        values: {
          'request_token': _returnIntent,
          'reason': 'damaged',
          'description': 'The parcel contained a damaged item.',
          'items': [
            {'order_item_id': 101, 'quantity': 2},
          ],
        },
        referer: '/buyer-returns/orders/42/create',
        component: 'Returns/Show',
        props: {
          'returnCase': {
            'id': 12,
            'order': {'id': 42},
            'version': 1,
          },
        },
        photoField: 'photos[0]',
        multipartFields: {
          'request_token': _returnIntent,
          'reason': 'damaged',
          'items[0][order_item_id]': '101',
          'items[0][quantity]': '2',
        },
      ),
      const _PageMutation(
        path: '/buyer-returns/12/actions',
        values: {
          'action': 'withdraw',
          'expected_version': 3,
          'request_token': _intent,
          'reason': 'The concern has already been resolved.',
        },
        referer: '/buyer-returns/12',
        component: 'Returns/Show',
        props: {
          'returnCase': {'id': 12, 'version': 4},
        },
      ),
      const _PageMutation(
        path: '/buyer-returns/12/custody',
        values: {
          'action': 'prepare-label',
          'expected_version': 3,
          'request_token': _intent,
          'reason': 'Prepare the authorized return shipping label.',
        },
        referer: '/buyer-returns/12',
        component: 'Returns/Show',
        props: {
          'returnCase': {'id': 12, 'version': 4},
        },
      ),
      const _PageMutation(
        path: '/buyer-returns/12/money',
        values: {
          'action': 'confirm-receipt',
          'expected_version': 3,
          'request_token': _intent,
          'reason': 'The repayment was received in full.',
          'source_event_id': 9,
        },
        referer: '/buyer-returns/12',
        component: 'Returns/Show',
        props: {
          'returnCase': {'id': 12, 'version': 4},
        },
      ),
    ];
    for (final route in routes) {
      Future<WebPage> submit() async {
        final page = await session.submit(
          route.path,
          route.values,
          method: route.method,
          referer: route.referer,
          files: route.photoField == null
              ? null
              : [
                  UploadPart(
                    route.photoField!,
                    'evidence.png',
                    _photo,
                    'image/png',
                  ),
                ],
        );
        buyer.requireNoErrors(page);
        account.check(page: page);
        return page;
      }

      test(
        '${route.method} ${route.path} preserves payload and native redirect',
        () async {
          respond = (request) async {
            if (request.method == 'GET') {
              expect(request.uri.path, route.redirectTarget);
              request.response.write(
                _markup(route.component, {
                  ..._owned(),
                  ...route.props,
                  'flash': {'success': 'Recorded'},
                }),
              );
            } else {
              expect(request.uri.path, route.path);
              expect(request.method, route.method);
              expect(
                request.headers.value('referer'),
                '${session.origin}${route.referer}',
              );
              expect(request.headers.value('X-CSRF-TOKEN'), 'extended-csrf');
              if (route.photoField == null) {
                expect(
                  jsonDecode(await utf8.decoder.bind(request).join()),
                  route.values,
                );
              } else {
                expect(
                  request.headers.contentType?.mimeType,
                  'multipart/form-data',
                );
                final body = latin1.decode(
                  await request.fold<List<int>>(
                    [],
                    (all, chunk) => all..addAll(chunk),
                  ),
                );
                for (final field in route.multipartFields.entries) {
                  expect(
                    body,
                    contains('name="${field.key}"\r\n\r\n${field.value}\r\n'),
                  );
                }
                expect(
                  body,
                  contains(
                    'name="${route.photoField}"; filename="evidence.png"',
                  ),
                );
                expect(body, contains(latin1.decode(_photo)));
              }
              request.response.statusCode = 303;
              request.response.headers.set('location', route.redirectTarget);
            }
          };
          final result = await submit();
          expect(result.component, route.component);
          expect(seen, [
            'GET /login',
            '${route.method} ${route.path}',
            'GET ${route.redirectTarget}',
          ]);
        },
      );

      for (final status in [403, 409, 422]) {
        test(
          '${route.method} ${route.path} keeps HTTP $status and does not replay',
          () async {
            respond = (request) async {
              await request.drain<void>();
              request.response.statusCode = status;
              request.response.write(
                '{"message":"Current eligibility changed","errors":{"request":["Refresh the saved result"]}}',
              );
            };
            await expectLater(
              submit(),
              throwsA(
                isA<BackendException>()
                    .having((e) => e.status, 'status', status)
                    .having(
                      (e) => e.fields['request'],
                      'repair field',
                      'Refresh the saved result',
                    ),
              ),
            );
            expect(seen, ['GET /login', '${route.method} ${route.path}']);
          },
        );
      }
    }
  });

  group('KYC and avatar multipart through ProfileRepository', () {
    for (final route in [
      '/buyer/kyc/upload',
      '/kyc/resubmit',
      '/buyer/profile',
    ]) {
      test(
        '$route sends the selected document and confirms the same profile',
        () async {
          final avatar = route == '/buyer/profile';
          final field = avatar ? 'avatar' : 'id_document';
          final values = avatar
              ? {
                  'name': 'Buyer Test',
                  'phone': '09171234567',
                  'remove_avatar': false,
                }
              : <String, dynamic>{};
          respond = (request) async {
            expect(request.method, 'POST');
            expect(request.uri.path, route);
            expect(
              request.headers.value('referer'),
              '${session.origin}/buyer/profile?tab=account',
            );
            expect(
              request.headers.contentType?.mimeType,
              'multipart/form-data',
            );
            final body = latin1.decode(
              await request.fold<List<int>>(
                [],
                (all, chunk) => all..addAll(chunk),
              ),
            );
            expect(body, contains('name="$field"; filename="evidence.png"'));
            expect(body, contains(latin1.decode(_photo)));
            if (avatar) {
              expect(body, contains('name="remove_avatar"\r\n\r\n0\r\n'));
            }
            request.response.write(
              _markup('Buyer/Profile', {
                ..._owned(),
                'flash': {'success': 'Submitted for review'},
              }),
            );
          };
          expect(
            (await profile.mutate(
              route,
              values,
              files: [UploadPart(field, 'evidence.png', _photo, 'image/png')],
            )).user?['id'],
            7,
          );
          expect(seen, ['GET /login', 'POST $route']);
        },
      );

      test(
        '$route preserves rejected document field feedback with no replay',
        () async {
          final field = route == '/buyer/profile' ? 'avatar' : 'id_document';
          respond = (request) async {
            await request.drain<void>();
            request.response.statusCode = 422;
            request.response.write(
              jsonEncode({
                'message': 'Unsupported document',
                'errors': {
                  field: ['Select an accepted file'],
                },
              }),
            );
          };
          await expectLater(
            profile.mutate(
              route,
              {},
              files: [UploadPart(field, 'evidence.png', _photo, 'image/png')],
            ),
            throwsA(
              isA<BackendException>().having(
                (e) => e.fields[field],
                'document feedback',
                'Select an accepted file',
              ),
            ),
          );
          expect(seen, ['GET /login', 'POST $route']);
        },
      );
    }
  });

  group('remaining private media and account-change boundaries', () {
    for (final path in [
      '/verification-documents/7/id.pdf',
      '/identity-correction-documents/12/id.pdf',
      '/buyer-returns/12/evidence/3',
      '/buyer-returns/12/money/9/proof',
    ]) {
      test(
        'private media $path sends only its own session and exact bytes',
        () async {
          await session.page('/login');
          final bytes = Uint8List.fromList(
            ascii.encode('%PDF-1.7 synthetic proof'),
          );
          respond = (request) async {
            expect(request.method, 'GET');
            expect(request.uri.path, path);
            expect(request.cookies.single.value, 'synthetic-only');
            request.response.headers.contentType = ContentType(
              'application',
              'pdf',
            );
            request.response.add(bytes);
          };
          expect((await session.documentBytes(path)).bytes, bytes);
          expect(seen, ['GET /login', 'GET $path']);
        },
      );

      test('private media $path preserves server ownership denial', () async {
        respond = (request) async {
          request.response.statusCode = 403;
          request.response.write(
            '{"message":"This proof belongs to another buyer"}',
          );
        };
        await expectLater(
          session.documentBytes(path),
          throwsA(
            isA<BackendException>().having((e) => e.status, 'forbidden', 403),
          ),
        );
        expect(seen, ['GET $path']);
      });
    }

    for (final path in [
      '/buyer/messages',
      '/wallet/payments/42',
      '/buyer-returns/12',
      '/account/security',
    ]) {
      test('late $path reply cannot enter a cleared session', () async {
        final arrived = Completer<void>();
        final release = Completer<void>();
        respond = (request) async {
          arrived.complete();
          await release.future;
          request.response.cookies.add(
            Cookie('extended_session', 'late-private-account')..path = '/',
          );
          request.response.write(_markup('Buyer/Profile', _owned()));
        };
        final operation = path == '/account/security'
            ? session.jsonGet(path)
            : buyer.document(path);
        final rejected = expectLater(
          operation,
          throwsA(
            isA<BackendException>().having(
              (e) => e.status,
              'cleared session',
              401,
            ),
          ),
        );
        await arrived.future;
        session.clear();
        release.complete();
        await rejected;
        expect(session.imageHeaders('/'), isEmpty);
        expect(account.isCurrent, isFalse);
        expect(seen, ['GET $path']);
      });
    }
  });
}
