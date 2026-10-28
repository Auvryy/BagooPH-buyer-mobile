import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/home/home_controller.dart';
import 'package:bagoo_buyer_mobile/features/home/home_page.dart';
import 'package:bagoo_buyer_mobile/features/home/search_controller.dart';
import 'package:bagoo_buyer_mobile/features/products/product_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart';

class GatedCatalogue extends FakeBuyerRepository {
  final searchGate = Completer<WebPage>();
  final productGate = Completer<WebPage>();
  @override
  Future<WebPage> search(Map<String, String> filters, {int page = 1}) =>
      searchGate.future;
  @override
  Future<WebPage> product(String slug) => productGate.future;
}

class DelayedHomePreview extends FakeBuyerRepository {
  final preview = Completer<WebPage?>();
  @override
  Future<WebPage?> cachedHome({
    String search = '',
    String category = '',
    String sort = 'relevance',
    int page = 1,
  }) => preview.future;
}

WebPage searchResult(int id) => WebPage('Buyer/Search', {
  'products': {
    'data': [product(id)],
    'current_page': 1,
    'last_page': 1,
    'total': 1,
  },
});

void main() {
  test('a late saved preview never replaces fresh Home results', () async {
    final repo = DelayedHomePreview();
    addTearDown(repo.session.close);
    repo.homeHandler = (_, _) async => homePage(products: [product(99)]);
    final controller = HomeController(repo);
    await controller.load();
    repo.preview.complete(
      WebPage(
        'Buyer/Home',
        homePage().props,
        cachedAt: DateTime.utc(2026, 10, 28),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.products.single['id'], 99);
    expect(controller.data!.isCached, isFalse);
    controller.dispose();
  });

  test(
    'clearing saved browsing data invalidates a pending Home preview',
    () async {
      final repo = DelayedHomePreview();
      addTearDown(repo.session.close);
      final fresh = Completer<WebPage>();
      repo.homeHandler = (_, _) => fresh.future;
      final controller = HomeController(repo);
      final pending = controller.load();
      await repo.catalogueCache.clear();
      repo.preview.complete(
        WebPage(
          'Buyer/Home',
          homePage().props,
          cachedAt: DateTime.utc(2026, 10, 28),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.data, isNull);
      fresh.complete(homePage());
      await pending;
      expect(controller.data!.isCached, isFalse);
      controller.dispose();
    },
  );

  test(
    'an account change clears Home even if a repository returns an old page',
    () async {
      final repo = FakeBuyerRepository();
      addTearDown(repo.session.close);
      final fresh = Completer<WebPage>();
      repo.homeHandler = (_, _) => fresh.future;
      final controller = HomeController(
        repo,
        initial: homePage(signedIn: true),
      );
      final pending = controller.load();
      repo.session.clear();
      fresh.complete(homePage(signedIn: true));
      await pending;
      expect(controller.user, isNull);
      expect(controller.products, isEmpty);
      expect(controller.error, contains('account changed'));
      controller.dispose();
    },
  );

  test(
    'initial authenticated Home is ready without another repository read',
    () {
      final repo = FakeBuyerRepository();
      addTearDown(repo.session.close);
      final controller = HomeController(
        repo,
        initial: homePage(signedIn: true),
      );
      expect(controller.products, hasLength(2));
      expect(controller.total, 4);
      expect(controller.user?['id'], 7);
      expect(repo.homeRequests, isEmpty);
      controller.dispose();
    },
  );

  testWidgets('Home reuses its already fetched initial page', (tester) async {
    final repo = FakeBuyerRepository();
    addTearDown(repo.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: HomePage(
          repository: repo,
          initial: homePage(),
          onLogin: () {},
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.homeRequests, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'Home renders a public snapshot while its server read is still pending',
    () async {
      final repo = FakeBuyerRepository();
      addTearDown(repo.session.close);
      await repo.catalogueCache.save('home:', homePage());
      final gate = Completer<WebPage>();
      repo.homeHandler = (_, _) => gate.future;
      final controller = HomeController(repo);
      final pending = controller.load();
      await Future<void>.delayed(Duration.zero);
      expect(controller.loading, isTrue);
      expect(controller.data!.isCached, isTrue);
      expect(controller.products, hasLength(2));
      expect(controller.user, isNull);
      gate.complete(homePage(products: [product(99)]));
      await pending;
      expect(controller.products.single['id'], 99);
      expect(controller.data!.isCached, isFalse);
      controller.dispose();
    },
  );

  test(
    'Search uses the exact saved query then replaces it with fresh results',
    () async {
      final repo = GatedCatalogue();
      addTearDown(repo.session.close);
      await repo.catalogueCache.save('search:search=bags', searchResult(1));
      final controller = CatalogueSearchController(repo);
      final pending = controller.apply(const SearchFilters(query: 'bags'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.loading, isTrue);
      expect(controller.data!.isCached, isTrue);
      expect(controller.products.single['id'], 1);
      repo.searchGate.complete(searchResult(2));
      await pending;
      expect(controller.data!.isCached, isFalse);
      expect(controller.products.single['id'], 2);
      controller.dispose();
    },
  );

  test('denied access clears a displayed Search preview', () async {
    final repo = GatedCatalogue();
    addTearDown(repo.session.close);
    await repo.catalogueCache.save('search:', searchResult(1));
    final controller = CatalogueSearchController(repo);
    final pending = controller.load();
    await Future<void>.delayed(Duration.zero);
    expect(controller.products, isNotEmpty);
    repo.searchGate.completeError(
      const BackendException('Access denied.', status: 403),
    );
    await pending;
    expect(controller.data, isNull);
    expect(controller.products, isEmpty);
    controller.dispose();
  });

  testWidgets('Product shows a read-only snapshot before the network result', (
    tester,
  ) async {
    final repo = GatedCatalogue();
    addTearDown(repo.session.close);
    await repo.catalogueCache.save('product:everyday-bag-1', productPage());
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Buy Now');
    expect(button, findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    repo.productGate.complete(productPage(signedIn: true));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(repo.orderCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'identical public reads share one request, but different scopes do not',
    () async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      final gate = Completer<WebPage>();
      session.onPage = (_) => gate.future;
      final repo = BuyerRepository(session);
      final first = repo.home();
      final second = repo.home();
      final different = repo.home(search: 'other');
      expect(session.pageRequests, hasLength(2));
      gate.complete(homePage());
      await Future.wait([first, second, different]);
      await repo.home();
      expect(session.pageRequests, hasLength(3));
    },
  );

  test(
    'an account switch cannot share or deliver an earlier pending read',
    () async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      final old = Completer<WebPage>();
      session.onPage = (_) => old.future;
      final repo = BuyerRepository(session);
      final pending = repo.home();
      final denied = expectLater(
        pending,
        throwsA(isA<BackendException>().having((e) => e.status, 'status', 401)),
      );
      session.clear();
      session.onPage = (_) async => homePage();
      await repo.home();
      expect(session.pageRequests, hasLength(2));
      old.complete(homePage(signedIn: true));
      await denied;
    },
  );
}
