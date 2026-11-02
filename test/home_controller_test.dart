import 'dart:async';

import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/home/home_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';

void main() {
  test(
    'home search rejects an overlong query before requesting the server',
    () async {
      final repository = FakeBuyerRepository();
      final controller = HomeController(repository);
      controller.search = List.filled(101, 'x').join();

      await controller.load();

      expect(repository.homeRequests, isEmpty);
      expect(
        controller.error,
        'Use no more than 100 characters for your search.',
      );
      controller.dispose();
      repository.session.close();
    },
  );

  test(
    'home rejects fractional product IDs before exposing save targets',
    () async {
      final repository = FakeBuyerRepository();
      repository.homeHandler = (_, _) async => homePage(
        products: [
          {...product(1), 'id': 1.5},
        ],
      );
      final controller = HomeController(repository);
      await controller.load();
      expect(controller.products, isEmpty);
      expect(
        controller.error,
        contains('Product results could not be confirmed'),
      );
      controller.dispose();
      repository.session.close();
    },
  );

  test('home rejects product rows without a confirmed detail route', () async {
    final repository = FakeBuyerRepository();
    final malformedProduct = product(1)..remove('slug');
    repository.homeHandler = (_, _) async =>
        homePage(products: [malformedProduct]);
    final controller = HomeController(repository);

    await controller.load();

    expect(controller.products, isEmpty);
    expect(
      controller.error,
      contains('Product results could not be confirmed'),
    );
    controller.dispose();
    repository.session.close();
  });

  test(
    'home rejects a fractional buyer ID before retaining account state',
    () async {
      final repository = FakeBuyerRepository();
      repository.homeHandler = (_, _) async {
        final page = homePage(signedIn: true);
        return WebPage('Buyer/Home', {
          ...page.props,
          'auth': {
            'user': {...buyer, 'id': 7.5},
          },
        });
      };
      final controller = HomeController(repository);

      await controller.load();

      expect(controller.user, isNull);
      expect(
        controller.error,
        contains('Your buyer account could not be confirmed'),
      );
      controller.dispose();
      repository.session.close();
    },
  );

  test('home does not expose partial category or campaign lists', () {
    final repository = FakeBuyerRepository();
    final page = homePage();
    page.props['categories'] = [
      {'id': 2, 'name': 'Electronics', 'slug': 'electronics'},
      'malformed category row',
    ];
    page.props['banners'] = [
      {
        'id': 7,
        'title': 'Valid campaign',
        'image': '/campaign.webp',
        'href': '/promotions/summer',
      },
      'malformed campaign row',
    ];
    final controller = HomeController(repository, initial: page);

    expect(controller.categories, isEmpty);
    expect(controller.banners, isEmpty);

    controller.dispose();
    repository.session.close();
  });

  test('home hides a partial related-product list', () {
    final repository = FakeBuyerRepository();
    final page = homePage();
    page.props['relatedProducts'] = [product(3), 'malformed related row'];
    final controller = HomeController(repository, initial: page);

    expect(controller.relatedProducts, isEmpty);

    controller.dispose();
    repository.session.close();
  });

  test('home hides categories with duplicate IDs', () {
    final repository = FakeBuyerRepository();
    final page = homePage();
    page.props['categories'] = [
      {'id': 2, 'name': 'Electronics', 'slug': 'electronics'},
      {'id': 2, 'name': 'Gadgets', 'slug': 'gadgets'},
    ];
    final controller = HomeController(repository, initial: page);

    expect(controller.categories, isEmpty);

    controller.dispose();
    repository.session.close();
  });

  test('home hides categories with duplicate slugs', () {
    final repository = FakeBuyerRepository();
    final page = homePage();
    page.props['categories'] = [
      {'id': 2, 'name': 'Electronics', 'slug': 'electronics'},
      {'id': 3, 'name': 'Gadgets', 'slug': 'electronics'},
    ];
    final controller = HomeController(repository, initial: page);

    expect(controller.categories, isEmpty);

    controller.dispose();
    repository.session.close();
  });

  test('home hides campaigns with duplicate IDs', () {
    final repository = FakeBuyerRepository();
    final page = homePage();
    page.props['banners'] = [
      {'id': 7, 'image': '/campaign-a.webp', 'href': '/promotions/a'},
      {'id': 7, 'image': '/campaign-b.webp', 'href': '/promotions/b'},
    ];
    final controller = HomeController(repository, initial: page);

    expect(controller.banners, isEmpty);

    controller.dispose();
    repository.session.close();
  });

  test('home ignores campaigns with malformed measurement metadata', () {
    final repository = FakeBuyerRepository();
    final page = homePage();
    page.props['banners'] = [
      {
        'id': 7,
        'image': '/campaign.webp',
        'href': '/promotions/a',
        'measurement': {
          'revision_id': 2.5,
          'token': 'opaque-token',
          'endpoint': '/advertisements/events',
        },
      },
    ];
    final controller = HomeController(repository, initial: page);

    expect(controller.banners, isEmpty);

    controller.dispose();
    repository.session.close();
  });

  for (final (field, value) in [
    ('current_page', 1.5),
    ('current_page', 2),
    ('last_page', 0),
    ('last_page', 99),
    ('total', -1),
    ('total', 9223372036854775807),
    ('per_page', 24),
    ('from', '1'),
    ('to', 2),
  ]) {
    test('home rejects malformed paginator $field=$value', () async {
      final repository = FakeBuyerRepository();
      repository.homeHandler = (_, _) async {
        final page = homePage(products: [product(1)]);
        final props = Map<String, dynamic>.from(page.props);
        final feed = Map<String, dynamic>.from(props['feedProducts'] as Map)
          ..[field] = value;
        props['feedProducts'] = feed;
        return WebPage('Buyer/Home', props);
      };
      final controller = HomeController(repository);

      await controller.load();

      expect(controller.products, isEmpty);
      expect(controller.data, isNull);
      expect(controller.error, contains('pagination'));
      controller.dispose();
      repository.session.close();
    });
  }

  test('home rejects invalid page requests before networking', () async {
    final repository = FakeBuyerRepository();
    final controller = HomeController(repository);

    await controller.load(pageNumber: 0);
    expect(repository.homeRequests, isEmpty);
    expect(controller.error, 'Choose a valid product page.');
    await controller.load(pageNumber: 1000001);
    expect(repository.homeRequests, isEmpty);

    controller.dispose();
    repository.session.close();
  });

  test('home accepts the backend correction to a reduced last page', () async {
    final repository = FakeBuyerRepository();
    repository.homeHandler = (_, page) async =>
        homePage(page: page, lastPage: 2, total: 19, products: [product(19)]);
    final controller = HomeController(repository);

    await controller.load(pageNumber: 100);

    expect(repository.homeRequests.single['page'], 100);
    expect(controller.currentPage, 2);
    expect(controller.lastPage, 2);
    expect(controller.products.single['id'], 19);
    controller.dispose();
    repository.session.close();
  });

  test('home rejects more rows than the backend page size', () async {
    final repository = FakeBuyerRepository();
    repository.homeHandler = (_, _) async => homePage(
      products: [for (var id = 1; id <= 19; id++) product(id)],
      total: 19,
    );
    final controller = HomeController(repository);

    await controller.load();

    expect(controller.products, isEmpty);
    expect(controller.error, contains('pagination'));
    controller.dispose();
    repository.session.close();
  });

  test('ignores stale catalogue results after a newer search', () async {
    final repository = FakeBuyerRepository();
    final first = Completer<WebPage>();
    repository.homeHandler = (query, page) => query == 'old'
        ? first.future
        : Future.value(homePage(products: [product(99)]));
    final controller = HomeController(repository);
    final pending = controller.filter(query: 'old');
    await controller.filter(query: 'new');
    first.complete(homePage(products: [product(1)]));
    await pending;
    expect(controller.products.single['id'], 99);
    expect(controller.search, 'new');
    controller.dispose();
    repository.session.close();
  });
  test(
    'pagination appends once and retains results on retryable failure',
    () async {
      final repository = FakeBuyerRepository();
      bool fail = true;
      repository.homeHandler = (_, page) async {
        if (page == 2 && fail) {
          throw const BackendException('Offline');
        }
        return homePage(
          page: page,
          lastPage: 2,
          total: 19,
          products: page == 1
              ? [for (var id = 1; id <= 18; id++) product(id)]
              : [product(19)],
        );
      };
      final controller = HomeController(repository);
      await controller.load();
      await controller.load(more: true);
      expect(controller.products.length, 18);
      expect(controller.moreError, 'Offline');
      fail = false;
      await controller.load(more: true);
      expect(controller.products, hasLength(19));
      expect(controller.products.last['id'], 19);
      expect(controller.hasMore, isFalse);
      controller.dispose();
      repository.session.close();
    },
  );
}
