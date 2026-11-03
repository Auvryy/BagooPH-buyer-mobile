import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/engagement/engagement_repository.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:bagoo_buyer_mobile/features/support/support_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// These tests exercise the real Dart HTTP/session adapters against an isolated
// loopback server. The synthetic server does not execute Laravel or a database.
String _page(String component, Map<String, dynamic> props) =>
    '<meta name="csrf-token" content="sweep-csrf"><div data-page="${const HtmlEscape().convert(jsonEncode({'component': component, 'props': props, 'version': 'sweep-v1'}))}"></div>';

Map<String, dynamic> _profile({int id = 7, int authenticatedId = 7}) => {
  'auth': {
    'user': {'id': authenticatedId, 'role': 'buyer'},
  },
  'user': {'id': id},
  'flash': {'success': 'Saved by the synthetic server.'},
};

const _noticeId = '123e4567-e89b-42d3-a456-426614174000';
const _snapshotId = '123e4567-e89b-42d3-a456-426614174001';

Map<String, dynamic> _notice() => {
  'id': _noticeId,
  'type': 'order-update',
  'data': {'title': 'Order update', 'body': 'Ready for pickup.'},
  'created_at': '2026-11-01T00:00:00Z',
  'read_at': null,
  'href': '/buyer/orders/42',
};

void main() {
  late HttpServer server;
  late WebSession session;
  late BuyerRepository buyer;
  late ProfileRepository profile;
  late BuyerEngagementRepository engagement;
  late SupportAssistantRepository support;
  late Future<void> Function(HttpRequest) respond;
  late List<String> requests;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    session = WebSession(Uri.parse('http://127.0.0.1:${server.port}'));
    buyer = BuyerRepository(session);
    profile = ProfileRepository(buyer);
    engagement = BuyerEngagementRepository(buyer);
    support = SupportAssistantRepository(buyer);
    requests = [];
    respond = (request) async {
      request.response.write('{}');
    };
    server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      try {
        if (request.method == 'GET' && request.uri.path == '/login') {
          request.response.cookies.add(
            Cookie('sweep_session', 'synthetic-only')..path = '/',
          );
          request.response.write(_page('Auth/Login', {}));
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

  group('profile adapter over real HTTP', () {
    for (final route in <(String, String, String)>[
      ('POST', '/buyer/profile', 'personal'),
      ('PUT', '/password', 'account'),
      ('POST', '/email/verification-notification', 'account'),
      ('POST', '/buyer/addresses', 'addresses'),
      ('PATCH', '/buyer/addresses/12', 'addresses'),
      ('DELETE', '/buyer/addresses/12', 'addresses'),
      ('POST', '/buyer/addresses/12/default', 'addresses'),
      ('POST', '/buyer/orders/42/confirm', 'orders'),
    ]) {
      test('${route.$1} ${route.$2} preserves profile context', () async {
        respond = (request) async {
          if (request.method == 'GET') {
            expect(request.uri.path, '/buyer/profile');
            request.response.write(_page('Buyer/Profile', _profile()));
          } else {
            expect(request.method, route.$1);
            expect(request.uri.path, route.$2);
            expect(request.headers.value('X-CSRF-TOKEN'), 'sweep-csrf');
            final referer = Uri.parse(request.headers.value('referer')!);
            expect(referer.origin, session.origin.origin);
            expect(referer.queryParameters, {
              'tab': route.$3,
              'orders_page': '3',
              'search': 'A & B',
            });
            expect(jsonDecode(await utf8.decoder.bind(request).join()), {
              'request_token': 'stable-synthetic-token',
            });
            request.response.statusCode = HttpStatus.seeOther;
            request.response.headers.set('location', '/buyer/profile');
          }
        };
        await profile.load(query: {'orders_page': '3', 'search': 'A & B'});
        final result = await profile.mutate(
          route.$2,
          {'request_token': 'stable-synthetic-token'},
          method: route.$1,
          tab: route.$3,
        );
        expect(result.user?['id'], 7);
        expect(requests.where((value) => value.startsWith(route.$1)), [
          '${route.$1} ${route.$2}',
        ]);
      });
    }

    for (final route in <(String, String)>[
      ('POST', '/account/emails/send'),
      ('POST', '/account/emails/confirm'),
      ('PATCH', '/account/emails/12/preferred'),
      ('DELETE', '/account/emails/12'),
      ('POST', '/account/security/code'),
      ('POST', '/account/security/sessions/revoke-others'),
      ('POST', '/account/security/sessions/$_noticeId/revoke'),
      ('POST', '/account/identity-corrections'),
      ('POST', '/wallet/credits'),
      ('POST', '/buyer/orders/42/buy-again'),
      ('POST', '/buyer/orders/42/pickup-code'),
    ]) {
      test('${route.$1} ${route.$2} sends one JSON mutation', () async {
        respond = (request) async {
          expect(request.method, route.$1);
          expect(request.uri.path, route.$2);
          expect(request.headers.contentType?.mimeType, 'application/json');
          expect(request.headers.value('accept'), 'application/json');
          expect(request.headers.value('X-CSRF-TOKEN'), 'sweep-csrf');
          expect(
            request.headers.value('referer'),
            '${session.origin}/buyer/profile?tab=account',
          );
          expect(request.cookies.single.value, 'synthetic-only');
          expect(jsonDecode(await utf8.decoder.bind(request).join()), {
            'request_token': 'same-token',
            'code': '001234',
          });
          request.response.write('{"message":"Recorded"}');
        };
        expect(
          await profile.json(route.$2, {
            'request_token': 'same-token',
            'code': '001234',
          }, method: route.$1),
          {'message': 'Recorded'},
        );
        expect(requests, ['GET /login', '${route.$1} ${route.$2}']);
      });
    }

    test(
      'identity uploads preserve nested correction fields and raw bytes',
      () async {
        respond = (request) async {
          expect(request.method, 'POST');
          expect(request.uri.path, '/account/identity-corrections');
          expect(request.headers.contentType?.mimeType, 'multipart/form-data');
          expect(request.headers.value('X-CSRF-TOKEN'), 'sweep-csrf');
          final bytes = await request.fold<List<int>>(
            [],
            (all, part) => all..addAll(part),
          );
          final body = latin1.decode(bytes);
          expect(body, contains('name="changes[first_name]"\r\n\r\nBuyer'));
          expect(body, contains('name="source_token"\r\n\r\nsynthetic-source'));
          expect(body, contains('name="id_document"; filename="identity.pdf"'));
          expect(
            body,
            contains('Content-Type: application/pdf\r\n\r\n%PDF-1.7'),
          );
          request.response.write('{"id":12}');
        };
        expect(
          await profile.json(
            '/account/identity-corrections',
            {
              'changes': {'first_name': 'Buyer'},
              'source_token': 'synthetic-source',
            },
            files: [
              UploadPart(
                'id_document',
                'identity.pdf',
                Uint8List.fromList(ascii.encode('%PDF-1.7')),
                'application/pdf',
              ),
            ],
          ),
          {'id': 12},
        );
        expect(requests, ['GET /login', 'POST /account/identity-corrections']);
      },
    );

    test('profile mutations reject a different returned account', () async {
      respond = (request) async {
        await request.drain<void>();
        request.response.write(_page('Buyer/Profile', _profile(id: 8)));
      };
      await expectLater(
        profile.mutate('/buyer/profile', {}),
        throwsA(isA<BackendException>().having((e) => e.status, 'status', 401)),
      );
      expect(requests, ['GET /login', 'POST /buyer/profile']);
    });

    test('profile mutation requires explicit saved feedback', () async {
      respond = (request) async {
        await request.drain<void>();
        request.response.write(
          _page('Buyer/Profile', _profile()..remove('flash')),
        );
      };
      await expectLater(
        profile.mutate('/buyer/profile', {}),
        throwsA(isA<BackendException>()),
      );
      expect(requests.where((value) => value.startsWith('POST')), hasLength(1));
    });

    test(
      'profile JSON cannot accept an unrelated success-shaped body',
      () async {
        respond = (request) async {
          await request.drain<void>();
          request.response.write('{"unrelated":true}');
        };
        await expectLater(
          profile.json('/wallet/credits', {}),
          throwsA(isA<BackendException>()),
        );
      },
    );

    test('order details bind the response to the requested order', () async {
      var returnedId = 43;
      respond = (request) async {
        expect(request.method, 'GET');
        expect(request.uri.path, '/buyer/orders/42');
        request.response.write(
          _page('Buyer/OrderDetail', {
            ..._profile(),
            'order': {'id': returnedId},
          }),
        );
      };
      await expectLater(profile.order(42), throwsA(isA<BackendException>()));
      returnedId = 42;
      expect((await profile.order(42)).props['order'], {'id': 42});
    });
  });

  group('notification contracts over real HTTP', () {
    test(
      'full list requests the selected filter and validates its page',
      () async {
        respond = (request) async {
          expect(request.method, 'GET');
          expect(request.uri.path, '/notifications');
          expect(request.uri.queryParameters, {
            'filter': 'unread',
            'page': '1',
          });
          request.response.write(
            _page('Notifications/Index', {
              ..._profile(),
              'portal': 'buyer',
              'filter': 'unread',
              'available': true,
              'notices': {
                'data': [_notice()],
                'current_page': 1,
                'last_page': 1,
                'per_page': 20,
                'total': 1,
                'from': 1,
                'to': 1,
              },
            }),
          );
        };
        expect(
          (await engagement.notifications(filter: 'unread')).component,
          'Notifications/Index',
        );
        expect(requests, ['GET /notifications']);
      },
    );

    test('preview retains well-formed rows and unread summary', () async {
      respond = (request) async {
        expect(request.method, 'GET');
        expect(request.uri.path, '/notifications/preview');
        request.response.write(
          jsonEncode({
            'notices': [_notice()],
            'summary': {'available': true, 'unread': 1},
          }),
        );
      };
      expect((await engagement.notificationPreview())['notices'], [_notice()]);
      expect(requests, ['GET /notifications/preview']);
    });

    for (final invalid in <Object?>[null, '1', -1, 1.5, true]) {
      test('preview rejects malformed unread count $invalid', () async {
        respond = (request) async {
          request.response.write(
            jsonEncode({
              'notices': [_notice()],
              'summary': {'available': true, 'unread': invalid},
            }),
          );
        };
        await expectLater(
          engagement.notificationPreview(),
          throwsA(isA<BackendException>()),
        );
        expect(requests, ['GET /notifications/preview']);
      });
    }

    test('preview rejects duplicate UUIDs regardless of letter case', () async {
      respond = (request) async {
        request.response.write(
          jsonEncode({
            'notices': [_notice(), _notice()..['id'] = _noticeId.toUpperCase()],
            'summary': {'available': true, 'unread': 2},
          }),
        );
      };
      await expectLater(
        engagement.notificationPreview(),
        throwsA(isA<BackendException>()),
      );
    });

    test('single read uses PATCH and requires a timezone-qualified acknowledgement', () async {
      var timestamp = '2026-11-01T00:00:00';
      respond = (request) async {
        expect(request.method, 'PATCH');
        expect(request.uri.path, '/notifications/$_noticeId/read');
        expect(jsonDecode(await utf8.decoder.bind(request).join()), isEmpty);
        request.response.write(jsonEncode({'read_at': timestamp}));
      };
      await expectLater(
        engagement.markNotificationRead(_noticeId),
        throwsA(isA<BackendException>()),
      );
      timestamp = '2026-11-01T00:00:00+08:00';
      await engagement.markNotificationRead(_noticeId);
      expect(
        requests.where((value) => value.startsWith('PATCH')),
        hasLength(2),
      );
    });

    test(
      'displayed and snapshot reads keep server-owned scope in JSON',
      () async {
        respond = (request) async {
          expect(request.method, 'PATCH');
          final values = jsonDecode(await utf8.decoder.bind(request).join());
          if (request.uri.path == '/notifications/read-displayed') {
            expect(values, {
              'ids': [_noticeId],
            });
          } else {
            expect(request.uri.path, '/notifications/read-all');
            expect(values, {'snapshot': _snapshotId});
          }
          request.response.write(
            '{"updated":1,"summary":{"available":true,"unread":2}}',
          );
        };
        expect(await engagement.markDisplayedNotifications([_noticeId]), 2);
        expect(await engagement.markNotificationSnapshotRead(_snapshotId), 2);
        expect(requests, [
          'GET /login',
          'PATCH /notifications/read-displayed',
          'PATCH /notifications/read-all',
        ]);
      },
    );

    test(
      'invalid notification scopes fail before any network request',
      () async {
        for (final ids in <List<String>>[
          [],
          [_noticeId, _noticeId],
          ['bad'],
          List.generate(7, (index) => _noticeId),
        ]) {
          await expectLater(
            engagement.markDisplayedNotifications(ids),
            throwsA(isA<BackendException>()),
          );
        }
        await expectLater(
          engagement.markNotificationRead('not-a-uuid'),
          throwsA(isA<BackendException>()),
        );
        await expectLater(
          engagement.markNotificationSnapshotRead('not-a-uuid'),
          throwsA(isA<BackendException>()),
        );
        expect(requests, isEmpty);
      },
    );

    test('opening a notice follows a native page redirect and rejects another buyer', () async {
      respond = (request) async {
        if (request.method == 'PATCH') {
          expect(request.uri.path, '/notifications/$_noticeId/read');
          expect(jsonDecode(await utf8.decoder.bind(request).join()), {
            'open': true,
          });
          request.response.statusCode = 303;
          request.response.headers.set('location', '/buyer/orders/42');
        } else {
          expect(request.uri.path, '/buyer/orders/42');
          request.response.write(
            _page('Buyer/OrderDetail', _profile(id: 8, authenticatedId: 8)),
          );
        }
      };
      await expectLater(
        engagement.openNotification(_noticeId, 7),
        throwsA(isA<BackendException>().having((e) => e.status, 'status', 401)),
      );
      expect(requests, [
        'GET /login',
        'PATCH /notifications/$_noticeId/read',
        'GET /buyer/orders/42',
      ]);
    });

    test(
      'advertisement measurement accepts HTTP 204 without decoding JSON',
      () async {
        respond = (request) async {
          expect(request.method, 'POST');
          expect(request.uri.path, '/advertisement-events');
          expect(jsonDecode(await utf8.decoder.bind(request).join()), {
            'token': 'synthetic-measurement',
            'type': 'impression',
          });
          request.response.statusCode = HttpStatus.noContent;
        };
        await engagement.reportAdvertisement({
          'endpoint': '/advertisement-events',
          'token': 'synthetic-measurement',
        }, 'impression');
        expect(requests, ['GET /login', 'POST /advertisement-events']);
      },
    );

    test(
      'foreign advertisement measurements cannot send a token off origin',
      () async {
        await expectLater(
          engagement.reportAdvertisement({
            'endpoint': 'https://other.example.invalid/advertisement-events',
            'token': 'synthetic-measurement',
          }, 'click'),
          throwsA(isA<BackendException>()),
        );
        expect(requests.where((value) => value.startsWith('POST')), isEmpty);
      },
    );
  });

  group('collection and promotion page transport', () {
    for (final shops in [false, true]) {
      test(
        'saved ${shops ? 'shops' : 'products'} preserves the requested page',
        () async {
          respond = (request) async {
            expect(request.method, 'GET');
            expect(
              request.uri.path,
              shops ? '/buyer/followed-shops' : '/buyer/saved-products',
            );
            expect(request.uri.queryParameters, {'page': '2'});
            request.response.write(
              _page(shops ? 'Buyer/FollowedShops' : 'Buyer/SavedProducts', {
                ..._profile(),
                'entries': {
                  'data': [
                    {shops ? 'shop_id' : 'product_id': 42},
                  ],
                  'current_page': 2,
                  'last_page': 2,
                  'per_page': 24,
                  'total': 25,
                  'from': 25,
                  'to': 25,
                },
              }),
            );
          };
          final result = shops
              ? await engagement.followedShops(page: 2)
              : await engagement.savedProducts(page: 2);
          expect(mapOf(result.props['entries'])['current_page'], 2);
          expect(requests, hasLength(1));
        },
      );
    }

    test('promotion serializes its slug and publication query', () async {
      respond = (request) async {
        expect(request.method, 'GET');
        expect(request.uri.pathSegments, ['promotions', 'summer & sale']);
        expect(request.uri.queryParameters, {'publication': 'revision & 2'});
        request.response.write(
          _page('Buyer/Promotion', {
            'promotion': {'available': true},
            'products': <Object>[],
          }),
        );
      };
      expect(
        (await engagement.promotion(
          'summer & sale',
          publication: 'revision & 2',
        )).component,
        'Buyer/Promotion',
      );
      expect(requests, hasLength(1));
    });
  });

  group('private binary document transport', () {
    for (final mime in ['application/pdf', 'image/png', 'image/jpeg']) {
      test(
        'accepts nonempty $mime through the authenticated session',
        () async {
          await session.page('/login');
          final content = Uint8List.fromList([0, 1, 2, 127, 128, 255]);
          respond = (request) async {
            expect(request.method, 'GET');
            expect(request.uri.path, '/chat/attachments/42');
            expect(request.cookies.single.value, 'synthetic-only');
            request.response.headers.contentType = ContentType.parse(mime);
            request.response.add(content);
          };
          final document = await session.documentBytes('/chat/attachments/42');
          expect(document.mime, mime);
          expect(document.bytes, content);
        },
      );
    }

    for (final mime in [
      'text/html',
      'application/json',
      'application/octet-stream',
    ]) {
      test('rejects a non-document $mime reply', () async {
        respond = (request) async {
          request.response.headers.contentType = ContentType.parse(mime);
          request.response.write('Synthetic login or unexpected content');
        };
        await expectLater(
          session.documentBytes('/chat/attachments/42'),
          throwsA(
            isA<BackendException>().having(
              (e) => e.message,
              'unavailable document',
              contains('unavailable'),
            ),
          ),
        );
      });
    }

    test('empty PDF cannot be treated as a downloaded document', () async {
      respond = (request) async {
        request.response.headers.contentType = ContentType(
          'application',
          'pdf',
        );
      };
      await expectLater(
        session.documentBytes('/chat/attachments/42'),
        throwsA(
          isA<BackendException>().having(
            (e) => e.message,
            'empty document',
            contains('empty'),
          ),
        ),
      );
    });

    test(
      'private document redirect to login remains an unavailable document',
      () async {
        respond = (request) async {
          request.response.statusCode = 302;
          request.response.headers.set('location', '/login');
        };
        await expectLater(
          session.documentBytes('/chat/attachments/42'),
          throwsA(isA<BackendException>()),
        );
        expect(requests, ['GET /chat/attachments/42', 'GET /login']);
      },
    );

    test(
      'private document HTTP errors retain structured authorization failure',
      () async {
        respond = (request) async {
          request.response.statusCode = 403;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '{"message":"Document belongs to another buyer"}',
          );
        };
        await expectLater(
          session.documentBytes('/chat/attachments/42'),
          throwsA(
            isA<BackendException>().having(
              (e) => e.status,
              'denied document',
              403,
            ),
          ),
        );
        expect(requests, ['GET /chat/attachments/42']);
      },
    );
  });

  group('support contract over real HTTP', () {
    test('serializes trimmed inputs and bounds safe suggestions', () async {
      respond = (request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/buyer/support/assistant');
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'message': 'Where is my order?',
          'order_number': 'ORDER_42',
        });
        request.response.write(
          jsonEncode({
            'reply': '  Check your tracking.  ',
            'suggested_questions': [
              null,
              '',
              ' Track ',
              'Track',
              4,
              'Returns',
              'Payment',
              'Ignored fourth',
            ],
          }),
        );
      };
      final answer = await support.ask(
        '  Where is my order?  ',
        orderNumber: ' ORDER_42 ',
      );
      expect(answer.reply, 'Check your tracking.');
      expect(answer.suggestions, ['Track', 'Returns', 'Payment']);
      expect(() => answer.suggestions.add('Mutable'), throwsUnsupportedError);
      expect(requests, ['GET /login', 'POST /buyer/support/assistant']);
    });

    test(
      'Unicode question length uses characters and accepts the 1000 boundary',
      () async {
        final question = List.filled(1000, '\u{10400}').join();
        respond = (request) async {
          final values =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect((values['message'] as String).runes.length, 1000);
          expect(values.containsKey('order_number'), isFalse);
          request.response.write('{"reply":"Accepted"}');
        };
        expect((await support.ask(question)).reply, 'Accepted');
        await expectLater(
          support.ask('$question!'),
          throwsA(
            isA<BackendException>().having(
              (e) => e.fields.containsKey('message'),
              'message field',
              isTrue,
            ),
          ),
        );
        expect(
          requests.where((value) => value.startsWith('POST')),
          hasLength(1),
        );
      },
    );

    for (final reply in <Object?>[null, '', '   ', 1, false, [], {}]) {
      test('rejects unconfirmed support reply ${jsonEncode(reply)}', () async {
        respond = (request) async {
          await request.drain<void>();
          request.response.write(jsonEncode({'reply': reply}));
        };
        await expectLater(
          support.ask('Question'),
          throwsA(isA<BackendException>()),
        );
        expect(
          requests.where((value) => value.startsWith('POST')),
          hasLength(1),
        );
      });
    }
  });

  group('session recognition and adversarial transport', () {
    test('valid encoded XSRF cookies keep normal mutation behavior', () async {
      respond = (request) async {
        if (request.method == 'GET') {
          expect(request.uri.path, '/auth/session');
          request.response.cookies.add(
            Cookie('XSRF-TOKEN', 'safe%2Btoken%3D')..path = '/',
          );
          request.response.write('{"authenticated":false}');
        } else {
          expect(request.uri.path, '/buyer/support/assistant');
          expect(request.headers.value('X-XSRF-TOKEN'), 'safe+token=');
          await request.drain<void>();
          request.response.write('{"reply":"Confirmed"}');
        }
      };
      await session.jsonGetDirect('/auth/session');
      final epoch = session.identityEpoch;
      expect((await support.ask('Question')).reply, 'Confirmed');
      expect(session.identityEpoch, epoch);
      expect(requests, ['GET /auth/session', 'POST /buyer/support/assistant']);
    });

    for (final cookie in ['%', '%GG', '%FF', '%0D%0Ainjected', '%00']) {
      test(
        'malformed XSRF cookie $cookie fails safely before a mutation',
        () async {
          respond = (request) async {
            if (request.method == 'GET') {
              expect(request.uri.path, '/auth/session');
              request.response.cookies.add(
                Cookie('XSRF-TOKEN', cookie)..path = '/',
              );
              request.response.write('{"authenticated":false}');
            } else {
              expect(request.uri.path, '/buyer/support/assistant');
              await request.drain<void>();
              request.response.write('{"reply":"Recovered on explicit retry"}');
            }
          };
          await session.jsonGetDirect('/auth/session');
          final epoch = session.identityEpoch;
          await expectLater(
            support.ask('Question'),
            throwsA(
              isA<BackendException>().having(
                (e) => e.status,
                'expired session',
                419,
              ),
            ),
          );
          expect(requests, ['GET /auth/session']);
          expect(session.identityEpoch, epoch + 1);
          expect(session.imageHeaders('/'), isEmpty);
          final result = await support.ask('Question');
          expect(result.reply, 'Recovered on explicit retry');
          expect(requests, [
            'GET /auth/session',
            'GET /login',
            'POST /buyer/support/assistant',
          ]);
        },
      );
    }

    for (final path in [
      '/',
      '/buyer',
      '/account/status',
      '/buyer/orders',
      '/buyer/orders/42',
    ]) {
      test(
        'session recognition accepts the existing buyer destination $path',
        () async {
          respond = (request) async {
            if (request.uri.path == '/auth/session') {
              request.response.write(
                jsonEncode({'authenticated': true, 'redirect': path}),
              );
            } else {
              expect(request.uri.path, path);
              request.response.write(_page('Buyer/Profile', _profile()));
            }
          };
          expect((await buyer.currentSession())?.user?['id'], 7);
          expect(requests, ['GET /auth/session', 'GET $path']);
        },
      );
    }

    for (final path in [
      '/seller/dashboard',
      '/courier',
      '/buyer/orders/42/cancel',
      '//other.example.invalid/buyer',
      'https://other.example.invalid/buyer',
    ]) {
      test(
        'session recognition refuses unsupported destination $path',
        () async {
          respond = (request) async {
            request.response.write(
              jsonEncode({'authenticated': true, 'redirect': path}),
            );
          };
          await expectLater(
            buyer.currentSession(),
            throwsA(isA<BackendException>()),
          );
          expect(requests, ['GET /auth/session']);
        },
      );
    }

    for (final status in [
      400,
      401,
      403,
      404,
      408,
      409,
      419,
      422,
      429,
      500,
      502,
      503,
      504,
    ]) {
      test(
        'support HTTP $status preserves the failure and never replays the write',
        () async {
          respond = (request) async {
            await request.drain<void>();
            request.response.statusCode = status;
            request.response.headers.set('retry-after', '30');
            request.response.write(
              '{"message":"Rejected","errors":{"message":["Repair this question"]},"retry_after":30}',
            );
          };
          final epoch = session.identityEpoch;
          await expectLater(
            support.ask('Question'),
            throwsA(
              isA<BackendException>()
                  .having((e) => e.status, 'HTTP status', status)
                  .having(
                    (e) => e.fields['message'],
                    'field feedback',
                    'Repair this question',
                  )
                  .having((e) => e.data['retry_after'], 'repair metadata', 30)
                  .having((e) => e.retryAt, 'retry deadline', isNotNull),
            ),
          );
          expect(requests, ['GET /login', 'POST /buyer/support/assistant']);
          expect(session.identityEpoch, status == 419 ? epoch + 1 : epoch);
          if (status == 419) expect(session.imageHeaders('/'), isEmpty);
        },
      );
    }

    test(
      'a support reply in flight cannot restore a cleared account cookie',
      () async {
        final arrived = Completer<void>();
        final release = Completer<void>();
        respond = (request) async {
          await request.drain<void>();
          arrived.complete();
          await release.future;
          request.response.cookies.add(
            Cookie('sweep_session', 'late-account')..path = '/',
          );
          request.response.write('{"reply":"Late private answer"}');
        };
        final operation = support.ask('Question');
        final rejected = expectLater(
          operation,
          throwsA(
            isA<BackendException>().having(
              (e) => e.status,
              'changed session',
              401,
            ),
          ),
        );
        await arrived.future;
        session.clear();
        release.complete();
        await rejected;
        expect(session.imageHeaders('/'), isEmpty);
        expect(requests, ['GET /login', 'POST /buyer/support/assistant']);
      },
    );

    for (final body in [
      'null',
      '[]',
      'true',
      '"text"',
      '{invalid',
      '<html>Sign in</html>',
    ]) {
      test('support rejects a malformed wire body $body', () async {
        respond = (request) async {
          await request.drain<void>();
          request.response.write(body);
        };
        await expectLater(
          support.ask('Question'),
          throwsA(isA<BackendException>()),
        );
        expect(
          requests.where((value) => value.startsWith('POST')),
          hasLength(1),
        );
      });
    }
  });
}
