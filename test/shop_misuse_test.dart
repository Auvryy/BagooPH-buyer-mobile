import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/home/product_card.dart';
import 'package:bagoo_buyer_mobile/features/products/shop_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart';

class _ShopMisuseRepository extends BuyerRepository {
  _ShopMisuseRepository(this.controlled) : super(controlled);

  final ControlledWebSession controlled;
  bool signedIn = true;
  int shopCalls = 0;
  int saveCalls = 0;
  dynamic productId = 1;
  dynamic productSlug = 'everyday-bag-1';
  dynamic productRows;
  dynamic currentPage;
  dynamic lastPage;
  dynamic perPage;
  dynamic total;
  dynamic from;
  dynamic to;
  dynamic storeCategories = <Map<String, dynamic>>[];
  dynamic productCount;
  dynamic followerCount = 3;
  dynamic reviewCount;
  dynamic savedProductIds = <int>[];
  Completer<bool>? pendingSave;
  Completer<WebPage>? pendingFirstShop;

  @override
  Future<WebPage> shop(
    String slug, {
    int page = 1,
    String search = '',
    String category = '',
    String storeCategory = 'all',
    String sort = 'relevance',
  }) async {
    shopCalls++;
    if (shopCalls == 1 && pendingFirstShop != null) {
      return pendingFirstShop!.future;
    }
    return pageFixture(signedIn: signedIn, page: page);
  }

  WebPage pageFixture({required bool signedIn, int page = 1}) {
    final shopProduct = {...product(1), 'id': productId};
    if (productSlug == null) {
      shopProduct.remove('slug');
    } else {
      shopProduct['slug'] = productSlug;
    }
    return WebPage('Marketplace/ShopDetail', {
      'auth': {'user': signedIn ? buyer : null},
      'shop': {
        'id': 8,
        'name': 'Test shop',
        if (productCount != null) 'products_count': productCount,
      },
      'products': {
        'data': productRows ?? [shopProduct],
        'current_page': currentPage ?? page,
        'last_page': lastPage ?? 1,
        'per_page': perPage ?? 18,
        'total': total ?? 1,
        'from': from ?? 1,
        'to': to ?? 1,
      },
      'categories': <Map<String, dynamic>>[],
      'storeCategories': storeCategories,
      'isFollowing': false,
      'savedProductIds': savedProductIds,
      'followerCount': followerCount,
      'shopStats': {if (reviewCount != null) 'review_count': reviewCount},
    });
  }

  @override
  Future<bool> saveProduct(int id, bool saved) {
    saveCalls++;
    return pendingSave?.future ?? Future<bool>.value(saved);
  }
}

void main() {
  for (final (label, rows) in [
    (
      'a malformed row',
      <Object?>[
        {'id': 10, 'name': 'Bags', 'parent_id': null},
        'malformed category',
      ],
    ),
    (
      'duplicate IDs',
      <Object?>[
        {'id': 10, 'name': 'Bags', 'parent_id': null},
        {'id': 10, 'name': 'Travel', 'parent_id': null},
      ],
    ),
    (
      'an orphan child',
      <Object?>[
        {'id': 10, 'name': 'Bags', 'parent_id': null},
        {'id': 11, 'name': 'Travel', 'parent_id': 99},
      ],
    ),
  ]) {
    testWidgets('shop hides store-category choices for $label', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = ControlledWebSession();
      final repository = _ShopMisuseRepository(session)..storeCategories = rows;
      addTearDown(session.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: ShopPage(repository: repository, slug: 'test-shop'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shop-filter-toggle')));
      await tester.pumpAndSettle();

      final storeFilter = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Store category',
      );
      await tester.tap(storeFilter);
      await tester.pumpAndSettle();

      expect(find.text('Bags'), findsNothing);
      expect(find.text('Travel'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('shop omits malformed product, follower, and review counts', (
    tester,
  ) async {
    final session = ControlledWebSession();
    final repository = _ShopMisuseRepository(session)
      ..productCount = 1.5
      ..followerCount = 2.5
      ..reviewCount = -1;
    addTearDown(session.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ShopPage(repository: repository, slug: 'test-shop'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rating No ratings yet · 1 products'), findsOneWidget);
    expect(find.text('2.5 followers · -1 reviews'), findsNothing);
    expect(find.text('— followers · — reviews'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
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
    testWidgets('shop rejects malformed paginator $field=$value', (
      tester,
    ) async {
      final session = ControlledWebSession();
      final repository = _ShopMisuseRepository(session);
      if (field == 'current_page') repository.currentPage = value;
      if (field == 'last_page') repository.lastPage = value;
      if (field == 'per_page') repository.perPage = value;
      if (field == 'total') repository.total = value;
      if (field == 'from') repository.from = value;
      if (field == 'to') repository.to = value;
      addTearDown(session.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: ShopPage(repository: repository, slug: 'test-shop'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProductCard), findsNothing);
      expect(
        find.text(
          'Shop pagination could not be confirmed. Refresh and try again.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('shop rejects more rows than the backend page size', (
    tester,
  ) async {
    final session = ControlledWebSession();
    final repository = _ShopMisuseRepository(session)
      ..productRows = [for (var id = 1; id <= 19; id++) product(id)]
      ..lastPage = 2
      ..total = 19
      ..from = 1
      ..to = 19;
    addTearDown(session.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ShopPage(repository: repository, slug: 'test-shop'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ProductCard), findsNothing);
    expect(
      find.text(
        'Shop pagination could not be confirmed. Refresh and try again.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'shop rejects malformed product IDs before showing save actions',
    (tester) async {
      final session = ControlledWebSession();
      final repository = _ShopMisuseRepository(session)..productId = 1.5;
      addTearDown(session.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: ShopPage(repository: repository, slug: 'test-shop'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProductCard), findsNothing);
      expect(
        find.text(
          'Shop products could not be confirmed. Refresh and try again.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shop rejects product rows without a confirmed detail route', (
    tester,
  ) async {
    final session = ControlledWebSession();
    final repository = _ShopMisuseRepository(session)..productSlug = null;
    addTearDown(session.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ShopPage(repository: repository, slug: 'test-shop'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ProductCard), findsNothing);
    expect(
      find.text('Shop products could not be confirmed. Refresh and try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('malformed saved-product IDs do not crash Shop cards', (
    tester,
  ) async {
    final session = ControlledWebSession();
    final repository = _ShopMisuseRepository(session)
      ..savedProductIds = 'not-a-list';
    addTearDown(session.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ShopPage(repository: repository, slug: 'test-shop'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Everyday bag 1'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );

    expect(find.byType(ProductCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an old shop load is discarded after an account change', (
    tester,
  ) async {
    final session = ControlledWebSession();
    final repository = _ShopMisuseRepository(session)
      ..pendingFirstShop = Completer<WebPage>();
    addTearDown(session.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ShopPage(repository: repository, slug: 'test-shop'),
      ),
    );
    await tester.pump();
    expect(repository.shopCalls, 1);

    session.clear();
    repository.signedIn = false;
    repository.pendingFirstShop!.complete(
      repository.pageFixture(signedIn: true),
    );
    await tester.pumpAndSettle();

    expect(repository.shopCalls, 2);
    expect(find.text('Follow shop'), findsOneWidget);
    expect(find.text('Unfollow shop'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late follow reply cannot restore the previous buyer state', (
    tester,
  ) async {
    final session = ControlledWebSession();
    final repository = _ShopMisuseRepository(session);
    addTearDown(session.close);
    final pending = Completer<Map<String, dynamic>>();
    session.onPost = (_) => pending.future;

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ShopPage(repository: repository, slug: 'test-shop'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Follow shop'), findsOneWidget);

    await tester.tap(find.text('Follow shop'));
    await tester.pump();
    expect(session.posts, hasLength(1));

    session.clear();
    repository.signedIn = false;
    pending.complete({'following': true, 'followers': 4});
    await tester.pumpAndSettle();

    expect(repository.shopCalls, 2);
    expect(find.text('Follow shop'), findsOneWidget);
    expect(find.text('Unfollow shop'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final malformedCount in [1.5, '1']) {
    testWidgets(
      'follow reply does not replace the count with malformed data: $malformedCount',
      (tester) async {
        final session = ControlledWebSession();
        final repository = _ShopMisuseRepository(session);
        addTearDown(session.close);
        session.onPost = (_) async => {
          'following': true,
          'followers': malformedCount,
        };

        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            home: ShopPage(repository: repository, slug: 'test-shop'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('3 followers'), findsOneWidget);

        await tester.tap(find.text('Follow shop'));
        await tester.pumpAndSettle();

        expect(find.text('Unfollow shop'), findsOneWidget);
        expect(find.textContaining('3 followers'), findsOneWidget);
        expect(find.textContaining('$malformedCount followers'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('rapid retained save taps submit only once', (tester) async {
    final session = ControlledWebSession();
    final repository = _ShopMisuseRepository(session)
      ..pendingSave = Completer<bool>();
    addTearDown(session.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ShopPage(repository: repository, slug: 'test-shop'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('Save product'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final onSave = tester.widget<ProductCard>(find.byType(ProductCard)).onSave!;

    onSave();
    onSave();
    await tester.pump();
    expect(repository.saveCalls, 1);

    repository.pendingSave!.complete(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late save reply cannot retain the previous buyer state', (
    tester,
  ) async {
    final session = ControlledWebSession();
    final repository = _ShopMisuseRepository(session)
      ..pendingSave = Completer<bool>();
    addTearDown(session.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ShopPage(repository: repository, slug: 'test-shop'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('Save product'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    tester.widget<ProductCard>(find.byType(ProductCard)).onSave!();
    await tester.pump();
    expect(repository.saveCalls, 1);

    session.clear();
    repository.signedIn = false;
    repository.pendingSave!.complete(true);
    await tester.pumpAndSettle();

    expect(repository.shopCalls, 2);
    expect(find.byTooltip('Sign in to save'), findsOneWidget);
    expect(find.byTooltip('Remove from saved'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
