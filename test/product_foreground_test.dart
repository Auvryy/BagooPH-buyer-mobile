import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/products/product_page.dart';
import 'package:bagoo_buyer_mobile/features/products/sale_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';

class DelayedProductRepository extends FakeBuyerRepository {
  Completer<WebPage>? pending;
  @override
  Future<WebPage> product(String slug) {
    if (pending case final request?) {
      productCalls++;
      return request.future;
    }
    return super.product(slug);
  }
}

WebPage salePage({String name = 'Sale product'}) => productPage(
  signedIn: true,
  override: {
    'name': name,
    'sale_offer': {
      'server_now': '2026-10-28T00:00:00Z',
      'active': {'ends_at': '2030-01-01T00:00:00Z', 'title': 'Seasonal offer'},
    },
  },
);

void main() {
  testWidgets('sale reads pause behind routes and while backgrounded', (
    tester,
  ) async {
    final repo = FakeBuyerRepository()..productResponse = salePage();
    addTearDown(repo.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.productCalls, 1);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(repo.productCalls, 2);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covered')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 3));
    expect(repo.productCalls, 2);
    nav.pop();
    await tester.pumpAndSettle();
    expect(repo.productCalls, 3);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump(const Duration(minutes: 3));
    expect(repo.productCalls, 3);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(repo.productCalls, 4);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 3));
    expect(repo.productCalls, 4);
    expect(repo.orderCalls, 0);
  });

  testWidgets('a covered sale read cannot replace the visible product state', (
    tester,
  ) async {
    final repo = DelayedProductRepository()..productResponse = salePage();
    addTearDown(repo.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
      ),
    );
    await tester.pumpAndSettle();
    repo.pending = Completer<WebPage>();
    await tester.pump(const Duration(seconds: 30));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covered')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pending = repo.pending!;
    repo.pending = null;
    pending.complete(salePage(name: 'Old hidden response'));
    await tester.pumpAndSettle();
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.text('Sale product'), findsOneWidget);
    expect(find.text('Old hidden response'), findsNothing);
    expect(repo.productCalls, 3);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('countdown boundaries wait for their visible route', (
    tester,
  ) async {
    var boundaries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SaleClock(
            offer: const {
              'server_now': '2026-10-28T00:00:00Z',
              'active': {'ends_at': '2026-10-27T00:00:00Z'},
            },
            onBoundary: () => boundaries++,
          ),
        ),
      ),
    );
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covered')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 2));
    expect(boundaries, 0);
    nav.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(boundaries, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
