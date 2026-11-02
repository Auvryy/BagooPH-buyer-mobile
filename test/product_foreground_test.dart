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

class DelayedAddRepository extends FakeBuyerRepository {
  final pendingAdd = Completer<WebPage>();

  @override
  Future<WebPage> addToBag(
    Map<String, dynamic> product,
    int quantity, {
    String? color,
    String? size,
    bool buyNow = false,
    int previousQuantity = 0,
  }) => pendingAdd.future;
}

class DelayedSaveRepository extends FakeBuyerRepository {
  final pendingSave = Completer<bool>();

  @override
  Future<bool> saveProduct(int id, bool saved) => pendingSave.future;
}

class DelayedReminderRepository extends FakeBuyerRepository {
  final pendingReminder = Completer<WebPage>();

  @override
  Future<WebPage> reminder(String slug, int id, bool subscribed) =>
      pendingReminder.future;
}

class RateLimitedReminderRepository extends FakeBuyerRepository {
  int reminderCalls = 0;

  @override
  Future<WebPage> reminder(String slug, int id, bool subscribed) async {
    reminderCalls++;
    throw BackendException(
      'Too many attempts. Please wait before trying again.',
      status: 429,
      retryAt: DateTime.now().add(const Duration(seconds: 30)),
    );
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

WebPage reminderPage({required bool signedIn, bool subscribed = false}) {
  final page = productPage(
    signedIn: signedIn,
    override: {
      'sale_offer': {
        'server_now': '2026-10-28T00:00:00Z',
        'upcoming': {
          'id': 12,
          'name': 'Upcoming offer',
          'starts_at': '2030-01-01T00:00:00Z',
        },
      },
    },
  );
  page.props['saleReminder'] = {'subscribed': subscribed};
  return page;
}

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

  testWidgets('a late add-to-Bag reply cannot restore the prior buyer state', (
    tester,
  ) async {
    final repo = DelayedAddRepository()
      ..signedIn = true
      ..productResponse = productPage(signedIn: true);
    addTearDown(repo.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Add to Bag'));
    await tester.pump();

    repo
      ..signedIn = false
      ..productResponse = productPage(signedIn: false);
    repo.session.clear();
    repo.pendingAdd.complete(productPage(signedIn: true));
    await tester.pumpAndSettle();

    expect(find.text('1 added to your Shopping Bag.'), findsNothing);
    expect(repo.productCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a late save reply cannot restore prior buyer saved state', (
    tester,
  ) async {
    final repo = DelayedSaveRepository()
      ..signedIn = true
      ..productResponse = productPage(signedIn: true);
    addTearDown(repo.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save product'));
    await tester.pump();

    repo
      ..signedIn = false
      ..productResponse = productPage(signedIn: false);
    repo.session.clear();
    repo.pendingSave.complete(true);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Remove from saved'), findsNothing);
    expect(find.byTooltip('Sign in to save'), findsOneWidget);
    expect(repo.productCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a late reminder reply cannot restore prior buyer reminder state',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1000);
      addTearDown(tester.view.reset);
      final repo = DelayedReminderRepository()
        ..signedIn = true
        ..productResponse = reminderPage(signedIn: true);
      addTearDown(repo.session.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Remind me'));
      await tester.tap(find.text('Remind me'));
      await tester.pump();

      repo
        ..signedIn = false
        ..productResponse = reminderPage(signedIn: false);
      repo.session.clear();
      repo.pendingReminder.complete(
        reminderPage(signedIn: true, subscribed: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('Remove reminder'), findsNothing);
      expect(find.text('Remind me'), findsOneWidget);
      expect(repo.productCalls, greaterThan(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('sale reminder honors the server rate-limit deadline', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.reset);
    final repo = RateLimitedReminderRepository()
      ..signedIn = true
      ..productResponse = reminderPage(signedIn: true);
    addTearDown(repo.session.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Remind me'));
    await tester.tap(find.text('Remind me'));
    await tester.pumpAndSettle();

    final retryButtonFinder = find.ancestor(
      of: find.textContaining('Try again in'),
      matching: find.byType(TextButton),
    );
    expect(retryButtonFinder, findsOneWidget);
    final retryButton = tester.widget<TextButton>(retryButtonFinder);
    expect(retryButton.onPressed, isNull);
    expect(repo.reminderCalls, 1);
    expect(find.textContaining('Too many attempts'), findsWidgets);
    expect(tester.takeException(), isNull);
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
