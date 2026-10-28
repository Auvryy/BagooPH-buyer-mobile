import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/catalogue_cache.dart';
import 'package:bagoo_buyer_mobile/core/session_vault.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/home/home_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart';

class CatalogueVault implements SessionVault {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String key) async {
    if (fail) throw StateError('Unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('Unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (fail) throw StateError('Unavailable');
    values.remove(key);
  }
}

class DelayedCatalogueVault extends CatalogueVault {
  final started = Completer<void>();
  final finish = Completer<void>();
  @override
  Future<void> write(String key, String value) async {
    if (!started.isCompleted) started.complete();
    await finish.future;
    await super.write(key, value);
  }
}

const offline = BackendException('No connection.', connectionFailure: true);

void main() {
  test(
    'only public catalogue projections survive persistence and restart',
    () async {
      final origin = Uri.parse('https://catalogue.test');
      final vault = CatalogueVault();
      final cache = CatalogueCache(origin: origin, vault: vault);
      final page = productPage(signedIn: true);
      page.props.addAll({
        'checkoutToken': 'secret-checkout',
        'pickupClaim': {'code': 'secret-pickup'},
        'order': {'recipient_name': 'secret-recipient'},
        'messages': [
          {'message': 'secret-chat'},
        ],
      });
      final publicProduct = mapOf(page.props['product']);
      publicProduct.addAll(<String, dynamic>{
        'reviews': [
          {'review': 'secret-review', 'user': buyer},
        ],
        'metadata': {'token': 'secret-token'},
      });
      publicProduct['shop']['user_id'] = 42;
      page.props['product'] = publicProduct;
      await cache.save('product:everyday-bag-1', page);
      final persisted = vault.values.values.single;
      expect(persisted, isNot(contains('secret-')));
      for (final private in [
        'auth',
        'cartQuantities',
        'savedProductIds',
        'user_id',
        'reviews',
        'checkoutToken',
      ]) {
        expect(persisted, isNot(contains('"$private"')));
      }
      final restored = await CatalogueCache(
        origin: origin,
        vault: vault,
      ).read('product:everyday-bag-1');
      expect(restored!.isCached, isTrue);
      expect(restored.user, isNull);
      expect(mapOf(restored.props['product'])['name'], 'Everyday bag 1');
      expect(
        await CatalogueCache(
          origin: Uri.parse('https://other.test'),
          vault: vault,
        ).read('product:everyday-bag-1'),
        isNull,
      );
    },
  );

  test(
    'restored entries are sanitized again before any subsequent write',
    () async {
      final origin = Uri.parse('https://catalogue.test');
      final vault = CatalogueVault();
      final cache = CatalogueCache(origin: origin, vault: vault);
      await cache.save('home:', homePage());
      final key = vault.values.keys.single;
      final raw = jsonDecode(vault.values[key]!) as Map;
      raw['entries']['home:']['props']['auth'] = {
        'user': {'email': 'secret-restored-email'},
      };
      vault.values[key] = jsonEncode(raw);
      final restarted = CatalogueCache(origin: origin, vault: vault);
      await restarted.save('product:everyday-bag-1', productPage());
      expect(vault.values[key], isNot(contains('secret-restored-email')));
      expect((await restarted.read('home:'))!.user, isNull);
    },
  );

  test('entries expire, obey storage bounds, tolerate corruption, and can be cleared', () async {
    var now = DateTime.utc(2026, 10, 28);
    final vault = CatalogueVault();
    final origin = Uri.parse('https://catalogue.test');
    final cache = CatalogueCache(
      origin: origin,
      vault: vault,
      maxEntries: 2,
      maxBytes: 5000,
      clock: () => now,
    );
    await cache.save('home:1', homePage());
    await cache.save('home:2', homePage());
    await cache.save('home:3', homePage());
    expect(await cache.read('home:1'), isNull);
    expect(await cache.read('home:3'), isNotNull);
    expect(
      utf8.encode(vault.values.values.single).length,
      lessThanOrEqualTo(5000),
    );
    now = now.add(const Duration(days: 8));
    expect(await cache.read('home:3'), isNull);
    expect(vault.values, isEmpty);
    await cache.save('home:', homePage());
    await cache.clear();
    expect(vault.values, isEmpty);
    expect(await cache.read('home:'), isNull);
    vault.values['bagoo-buyer-catalogue-v1:${origin.origin}'] = 'invalid JSON';
    expect(
      await CatalogueCache(origin: origin, vault: vault).read('home:'),
      isNull,
    );
  });

  test(
    'unavailable native storage leaves online reads and memory fallback usable',
    () async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      final cache = CatalogueCache(
        origin: session.origin,
        vault: CatalogueVault()..fail = true,
      );
      final repo = BuyerRepository(session, catalogueCache: cache);
      session.onPage = (_) async => homePage();
      expect((await repo.home()).isCached, isFalse);
      session.onPage = (_) async => throw offline;
      expect((await repo.home()).isCached, isTrue);
    },
  );

  test('real HTTP catalogue survives a refused connection without persisting account props', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final session = WebSession(Uri.parse('http://localhost:${server.port}'));
    addTearDown(session.close);
    final vault = CatalogueVault();
    final repo = BuyerRepository(
      session,
      catalogueCache: CatalogueCache(origin: session.origin, vault: vault),
    );
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'component': 'Buyer/Home',
          'props': homePage(signedIn: true).props,
          'version': 'test-v1',
        }),
      );
      await request.response.close();
    });
    final online = await repo.home();
    expect(online.user?['id'], 7);
    await server.close(force: true);
    final cached = await repo.home();
    expect(cached.isCached, isTrue);
    expect(cached.user, isNull);
    expect(mapsOf(mapOf(cached.props['feedProducts'])['data']), hasLength(2));
    expect(vault.values.values.single, isNot(contains('buyer@example.test')));
  });

  test('network-first fallback matches query and page; later success replaces cached prices', () async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final repo = BuyerRepository(session);
    session.onPage = (_) async => productPage();
    expect((await repo.product('everyday-bag-1')).isCached, isFalse);
    session.onPage = (_) async => throw offline;
    expect((await repo.product('everyday-bag-1')).isCached, isTrue);
    await expectLater(
      repo.product('other-product'),
      throwsA(isA<BackendException>()),
    );
    session.onPage = (_) async => productPage(override: {'price': '1500.00'});
    final current = await repo.product('everyday-bag-1');
    expect(current.isCached, isFalse);
    expect(current.props['product']['price'], '1500.00');
    session.onPage = (_) async =>
        WebPage('Buyer/Search', {'products': homePage().props['feedProducts']});
    await repo.search({'search': 'bags', 'sort': 'latest'}, page: 2);
    session.onPage = (_) async => throw offline;
    expect(
      (await repo.search({
        'sort': 'latest',
        'search': 'bags',
      }, page: 2)).isCached,
      isTrue,
    );
    await expectLater(
      repo.search({'search': 'bags', 'sort': 'latest'}),
      throwsA(isA<BackendException>()),
    );
  });

  for (final status in [401, 403, 404, 410, 419, 422]) {
    test('HTTP $status cannot resurrect a cached product', () async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      final repo = BuyerRepository(session);
      session.onPage = (_) async => productPage();
      await repo.product('everyday-bag-1');
      session.onPage = (_) async =>
          throw BackendException('Unavailable.', status: status);
      await expectLater(
        repo.product('everyday-bag-1'),
        throwsA(isA<BackendException>()),
      );
      session.onPage = (_) async => throw offline;
      await expectLater(
        repo.product('everyday-bag-1'),
        throwsA(isA<BackendException>()),
      );
    });
  }

  test(
    'a changed identity cannot accept or cache a pending catalogue response',
    () async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      final pending = Completer<WebPage>();
      session.onPage = (_) => pending.future;
      final repo = BuyerRepository(session);
      final request = repo.product('everyday-bag-1');
      session.clear();
      pending.complete(productPage(signedIn: true));
      await expectLater(
        request,
        throwsA(isA<BackendException>().having((e) => e.status, 'status', 401)),
      );
      expect(await repo.catalogueCache.read('product:everyday-bag-1'), isNull);
    },
  );

  test('online catalogue returns before a slow cache write and persists no account data', () async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    final vault = DelayedCatalogueVault();
    session.onPage = (_) async => productPage(signedIn: true);
    final repo = BuyerRepository(
      session,
      catalogueCache: CatalogueCache(origin: session.origin, vault: vault),
    );
    var delivered = false;
    final request = repo.product('everyday-bag-1').then((page) {
      delivered = true;
      return page;
    });
    await vault.started.future;
    expect(delivered, isTrue);
    expect((await request).user?['id'], 7);
    session.clear();
    vault.finish.complete();
    expect((await repo.cachedProduct('everyday-bag-1'))!.user, isNull);
  });

  test(
    'clearing browsing data prevents an older network read from restoring it',
    () async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      final pending = Completer<WebPage>();
      session.onPage = (_) => pending.future;
      final repo = BuyerRepository(session);
      final request = repo.home();
      await repo.catalogueCache.clear();
      pending.complete(homePage());
      expect((await request).isCached, isFalse);
      expect(await repo.catalogueCache.read('home:'), isNull);
    },
  );

  test(
    'failed device deletion is reported while the in-process cache is cleared',
    () async {
      final origin = Uri.parse('https://catalogue.test');
      final vault = CatalogueVault();
      final cache = CatalogueCache(origin: origin, vault: vault);
      await cache.save('home:', homePage());
      vault.fail = true;
      expect(await cache.clear(), isFalse);
      expect(await cache.read('home:'), isNull);
      expect(vault.values, isNotEmpty);
      vault.fail = false;
      expect(await cache.clear(), isTrue);
      expect(vault.values, isEmpty);
    },
  );

  test(
    'public fallback does not replace a known in-memory buyer with a guest',
    () async {
      final repo = FakeBuyerRepository();
      addTearDown(repo.session.close);
      final controller = HomeController(
        repo,
        initial: homePage(signedIn: true),
      );
      final cached = homePage();
      repo.homeHandler = (_, _) async => WebPage(
        cached.component,
        cached.props,
        cachedAt: DateTime.utc(2026, 10, 28),
      );
      await controller.load();
      expect(controller.user?['id'], 7);
      expect(controller.data!.user, isNull);
      expect(controller.hasMore, isFalse);
      repo.session.clear();
      expect(controller.user, isNull);
      controller.dispose();
    },
  );
}
