import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/home/catalogue_loading.dart';
import 'package:bagoo_buyer_mobile/features/home/browse_controls.dart';
import 'package:bagoo_buyer_mobile/features/home/home_page.dart';
import 'package:bagoo_buyer_mobile/features/home/product_card.dart';
import 'package:bagoo_buyer_mobile/features/home/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';

class RefreshingSearch extends FakeBuyerRepository {
  Future<WebPage> Function()? handler;
  @override
  Future<WebPage> search(Map<String, String> filters, {int page = 1}) async =>
      handler == null
      ? WebPage('Buyer/Search', {
          'auth': {'user': buyer},
          'products': homePage().props['feedProducts'],
          'categories': [],
          'locations': [],
        })
      : handler!();
}

Future<void> showFirstProduct(WidgetTester tester) async {
  for (var i = 0; i < 10 && find.byType(ProductCard).evaluate().isEmpty; i++) {
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -200),
    );
    await tester.pump();
  }
  await tester.ensureVisible(find.byType(ProductCard).first);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Plus Jakarta Sans',
    )..addFont(rootBundle.load('assets/fonts/PlusJakartaSans.ttf'))).load();
  });

  testWidgets(
    'Home keeps the search draft through compact and inline headers',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 812);
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
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
      final search = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Search products',
      );
      await tester.enterText(search, 'canvas tote');
      for (final scene in [
        (const Size(900, 768), 1.4),
        (const Size(1024, 768), 1.0),
        (const Size(375, 812), 1.0),
      ]) {
        tester.platformDispatcher.textScaleFactorTestValue = scene.$2;
        tester.view.physicalSize = scene.$1;
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(search).controller!.text,
          'canvas tote',
        );
        expect(tester.takeException(), isNull);
      }
      expect(repo.homeRequests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final size in [const Size(375, 812), const Size(700, 375)]) {
    testWidgets(
      'all sort choices remain reachable at $size with enlarged text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        String? selected;
        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            builder: (_, child) => MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    selected = await showBuyerSort(context, 'relevance');
                  },
                  child: const Text('Choose sort'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Choose sort'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Price: high to low'),
          100,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Price: high to low'));
        await tester.pumpAndSettle();
        expect(selected, 'price_desc');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('Home keeps products and their position during refresh', (
    tester,
  ) async {
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
    await showFirstProduct(tester);
    final position = tester.getTopLeft(find.byType(ProductCard).first);
    final gate = Completer<WebPage>();
    repo.homeHandler = (_, _) => gate.future;
    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator).first)
        .onRefresh();
    await tester.pump();
    expect(find.byType(ProductCard), findsWidgets);
    expect(tester.getTopLeft(find.byType(ProductCard).first), position);
    expect(
      tester.widget<ProductCard>(find.byType(ProductCard).first).onSave,
      isNull,
    );
    gate.complete(homePage());
    await refresh;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Search retains readable results during refresh and retryable failure',
    (tester) async {
      final repo = RefreshingSearch();
      addTearDown(repo.session.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: Scaffold(body: SearchPage(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      await showFirstProduct(tester);
      final gate = Completer<WebPage>();
      repo.handler = () => gate.future;
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator).first)
          .onRefresh();
      await tester.pump();
      expect(find.byType(ProductCard), findsWidgets);
      expect(
        tester.widget<ProductCard>(find.byType(ProductCard).first).onSave,
        isNull,
      );
      gate.completeError(
        const BackendException(
          'Connection unavailable.',
          connectionFailure: true,
        ),
      );
      await refresh;
      await tester.pumpAndSettle();
      expect(find.byType(ProductCard), findsWidgets);
      expect(find.text('Connection unavailable.'), findsOneWidget);
      expect(
        tester.widget<ProductCard>(find.byType(ProductCard).first).onSave,
        isNull,
      );
      expect(repo.saveCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('initial catalogue loading has stable native placeholders', (
    tester,
  ) async {
    final repo = FakeBuyerRepository();
    addTearDown(repo.session.close);
    final gate = Completer<WebPage>();
    repo.homeHandler = (_, _) => gate.future;
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: HomePage(repository: repo, onLogin: () {}, onLogout: () async {}),
      ),
    );
    await tester.pump();
    expect(find.byType(CatalogueLoadingGrid), findsOneWidget);
    expect(find.byType(ProductCard), findsNothing);
    gate.complete(homePage());
    await tester.pumpAndSettle();
    expect(find.byType(CatalogueLoadingGrid), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'native sort preserves the search draft and sends the selected server sort',
    (tester) async {
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
      await tester.enterText(find.byType(TextField).first, 'canvas');
      await tester.tap(find.widgetWithText(TextButton, 'Sort'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Price: low to high'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Price: low to high'));
      await tester.pumpAndSettle();
      expect(repo.homeRequests.last['sort'], 'price_asc');
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'canvas',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
