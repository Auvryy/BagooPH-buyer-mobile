import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_actions.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/bag_page.dart';
import 'package:bagoo_buyer_mobile/features/products/product_page.dart';
import 'package:bagoo_buyer_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bag_fixtures.dart';
import 'support/fake_buyer_repository.dart';

final unverifiedBuyer = {...buyer, 'kyc_status': 'unverified'};

class UnverifiedProductRepository extends FakeBuyerRepository {
  int adds = 0;
  @override
  Future<WebPage> addToBag(
    Map<String, dynamic> product,
    int quantity, {
    String? color,
    String? size,
    bool buyNow = false,
    int previousQuantity = 0,
  }) async {
    adds++;
    return productPage(signedIn: true);
  }
}

class SignedInVerificationRepository extends UnverifiedProductRepository {
  @override
  Future<WebPage?> currentSession() async {
    final page = homePage(signedIn: true);
    page.props['auth'] = {'user': unverifiedBuyer};
    return page;
  }
}

void main() {
  for (final expire in [false, true]) {
    testWidgets(
      'unverified product prompts once and checks account before navigation (expired: $expire)',
      (tester) async {
        final page = productPage(signedIn: true);
        page.props['auth'] = {'user': unverifiedBuyer};
        final repo = UnverifiedProductRepository()..productResponse = page;
        addTearDown(repo.session.close);
        var opened = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            builder: (_, child) => BuyerActions(
              signIn: (_) {},
              openVerification: () => opened++,
              child: child!,
            ),
            home: ProductPage(repository: repo, slug: 'everyday-bag-1'),
          ),
        );
        await tester.pumpAndSettle();
        final action = tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Buy Now').first,
            )
            .onPressed!;
        action();
        action();
        await tester.pumpAndSettle();
        expect(find.text('Verification needed'), findsOneWidget);
        expect(repo.adds, 0);
        if (expire) repo.session.clear();
        await tester.tap(find.text('Review account'));
        await tester.pumpAndSettle();
        expect(opened, expire ? 0 : 1);
        expect(repo.adds, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('verification action opens the real identity submission screen', (
    tester,
  ) async {
    final page = productPage(signedIn: true);
    page.props['auth'] = {'user': unverifiedBuyer};
    final repo = SignedInVerificationRepository()..productResponse = page;
    final session = repo.session as FakeSession;
    session.profileResponse = WebPage('Buyer/Profile', {
      'auth': {'user': unverifiedBuyer},
      'user': unverifiedBuyer,
      'orders': {'data': []},
      'orderCounts': {},
    });
    addTearDown(session.close);
    await tester.pumpWidget(MainApp(repository: repo));
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ProductPage(repository: repo, slug: 'everyday-bag-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Buy Now').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review account'));
    await tester.pumpAndSettle();
    expect(find.text('Identity correction'), findsWidgets);
    expect(find.text('Choose government ID'), findsOneWidget);
    expect(repo.adds, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final expire in [false, true]) {
    testWidgets(
      'unverified Bag prompt checks the account before navigation (expired: $expire)',
      (tester) async {
        final repo = ReviewBagRepository()..owner = unverifiedBuyer;
        addTearDown(repo.session.close);
        var opened = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            builder: (_, child) => BuyerActions(
              signIn: (_) {},
              openVerification: () => opened++,
              child: child!,
            ),
            home: BagPage(repository: repo),
          ),
        );
        await tester.pumpAndSettle();
        final checkout = find.widgetWithText(FilledButton, 'Checkout (1)');
        await tester.ensureVisible(checkout.first);
        await tester.tap(checkout.first);
        await tester.pumpAndSettle();
        expect(find.text('Verification needed'), findsOneWidget);
        if (expire) repo.session.clear();
        await tester.tap(find.text('Review account'));
        await tester.pumpAndSettle();
        expect(opened, expire ? 0 : 1);
        expect(repo.orderCalls, 0);
        expect(repo.changes, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
