import 'dart:async';

import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/home/home_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';

void main() {
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
          products: page == 1 ? [product(1)] : [product(1), product(2)],
        );
      };
      final controller = HomeController(repository);
      await controller.load();
      await controller.load(more: true);
      expect(controller.products.length, 1);
      expect(controller.moreError, 'Offline');
      fail = false;
      await controller.load(more: true);
      expect(controller.products.map((p) => p['id']), [1, 2]);
      expect(controller.hasMore, isFalse);
      controller.dispose();
      repository.session.close();
    },
  );
}
