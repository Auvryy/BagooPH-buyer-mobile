import 'dart:convert';
import 'dart:io';

import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:flutter_test/flutter_test.dart';

String page(String component, Map<String, dynamic> props) =>
    '<meta name="csrf-token" content="test-csrf"><div data-page="${const HtmlEscape().convert(jsonEncode({'component': component, 'props': props, 'version': 'v1'}))}"></div>';

void main() {
  late HttpServer server;
  late WebSession session;
  late BuyerRepository repo;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    session = WebSession(Uri.parse('http://localhost:${server.port}'));
    repo = BuyerRepository(session);
  });
  tearDown(() async {
    session.close();
    await server.close(force: true);
  });

  test('saved product mutations require the requested server state', () async {
    final methods = <String>[];
    server.listen((request) async {
      if (request.method == 'GET') {
        request.response.write(page('Auth/Login', {}));
      } else {
        methods.add(request.method);
        expect(request.headers.value('Accept'), 'application/json');
        expect(request.headers.value('X-CSRF-TOKEN'), 'test-csrf');
        request.response.write(
          jsonEncode({'product_id': 4, 'saved': request.method == 'POST'}),
        );
      }
      await request.response.close();
    });
    expect(await repo.saveProduct(4, true), isTrue);
    expect(await repo.saveProduct(4, false), isFalse);
    await expectLater(
      repo.saveProduct(5, true),
      throwsA(isA<BackendException>()),
    );
    expect(methods, ['POST', 'DELETE', 'POST']);
  });

  test(
    'search uses dedicated catalogue route and retains filter query values',
    () async {
      server.listen((request) async {
        expect(request.uri.path, '/buyer/search');
        expect(request.uri.queryParameters, {
          'search': 'shoe & bag',
          'location': 'test-area',
          'min_price': '10.50',
          'in_stock': '1',
          'sort': 'top_rated',
          'page': '2',
        });
        request.response.write(
          page('Buyer/Search', {
            'products': {'data': []},
          }),
        );
        await request.response.close();
      });
      final result = await repo.search({
        'search': 'shoe & bag',
        'location': 'test-area',
        'min_price': '10.50',
        'in_stock': '1',
        'sort': 'top_rated',
      }, page: 2);
      expect(result.component, 'Buyer/Search');
    },
  );

  test(
    'add to Bag follows its product referer and verifies the line quantity',
    () async {
      var confirmed = 3;
      var mutations = 0;
      server.listen((request) async {
        if (request.method == 'POST') {
          mutations++;
          expect(request.uri.path, '/cart');
          expect(
            request.headers.value('Referer'),
            '${session.origin}/buyer/product/test-bag',
          );
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect(body['color'], 'Red');
          expect(body['quantity'], 2);
          request.response.statusCode = 302;
          request.response.headers.set('Location', '/buyer/product/test-bag');
        } else if (request.uri.path == '/login') {
          request.response.write(page('Auth/Login', {}));
        } else {
          request.response.write(
            page('Buyer/ProductDetail', {
              'cartQuantities': [
                {'color': 'Red', 'size': null, 'quantity': confirmed},
              ],
            }),
          );
        }
        await request.response.close();
      });
      await repo.addToBag(
        {'id': 1, 'slug': 'test-bag'},
        2,
        color: 'Red',
        previousQuantity: 1,
      );
      confirmed = 1;
      await expectLater(
        repo.addToBag(
          {'id': 1, 'slug': 'test-bag'},
          2,
          color: 'Red',
          previousQuantity: 1,
        ),
        throwsA(isA<BackendException>()),
      );
      expect(mutations, 2);
    },
  );

  test('Bag PATCH and DELETE confirm the actual returned item state', () async {
    var deleted = false;
    server.listen((request) async {
      if (request.method == 'PATCH' || request.method == 'DELETE') {
        expect(request.headers.value('Referer'), '${session.origin}/cart');
        expect(request.headers.value('Accept'), 'application/json');
        deleted = request.method == 'DELETE';
        if (!deleted) {
          expect(jsonDecode(await utf8.decoder.bind(request).join()), {
            'quantity': 2,
          });
        }
        request.response.statusCode = 303;
        request.response.headers.set('Location', '/cart');
      } else {
        request.response.write(
          page(request.uri.path == '/login' ? 'Auth/Login' : 'Cart/Index', {
            'items': deleted
                ? []
                : [
                    {'id': 8, 'quantity': 2},
                  ],
          }),
        );
      }
      await request.response.close();
    });
    await repo.changeBagItem(8, 2);
    await repo.changeBagItem(8, null);
  });

  test(
    'checkout needs a nonempty server success and never replays a conflict',
    () async {
      var confirmed = false;
      var conflict = false;
      var posts = 0;
      server.listen((request) async {
        if (request.method == 'POST') {
          posts++;
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect(body['checkout_token'], 'same-token');
          if (conflict) {
            request.response.statusCode = 409;
            request.response.write(
              jsonEncode({
                'message': 'Check your existing order before retrying.',
              }),
            );
          } else {
            request.response.statusCode = 302;
            request.response.headers.set('Location', '/buyer/orders');
          }
        } else {
          request.response.write(
            page(
              request.uri.path == '/login' ? 'Auth/Login' : 'Buyer/Profile',
              {
                'flash': {'success': confirmed ? 'Order recorded.' : ''},
              },
            ),
          );
        }
        await request.response.close();
      });
      await expectLater(
        repo.placeOrder({'checkout_token': 'same-token'}),
        throwsA(isA<BackendException>()),
      );
      confirmed = true;
      expect(
        (await repo.placeOrder({'checkout_token': 'same-token'})).component,
        'Buyer/Profile',
      );
      conflict = true;
      await expectLater(
        repo.placeOrder({'checkout_token': 'same-token'}),
        throwsA(
          isA<BackendException>().having((e) => e.status, 'conflict', 409),
        ),
      );
      expect(posts, 3);
    },
  );

  test(
    'private media headers stay within the buyer origin and cookie path',
    () async {
      server.listen((request) async {
        request.response.cookies.add(
          Cookie('session', 'test-only')..path = '/chat',
        );
        request.response.write(page('Auth/Login', {}));
        await request.response.close();
      });
      await session.page('/login');
      expect(
        session.imageHeaders('/chat/attachments/1')['cookie'],
        'session=test-only',
      );
      expect(session.imageHeaders('/products/a.png'), isEmpty);
      expect(session.imageHeaders('/chatty/a.png'), isEmpty);
      expect(
        () => session.imageHeaders('https://other.example.test/a.png'),
        throwsA(isA<BackendException>()),
      );
    },
  );
}
