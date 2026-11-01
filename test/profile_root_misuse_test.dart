import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/buyer_account_scope.dart';
import 'package:bagoo_buyer_mobile/features/checkout/bag_page.dart';
import 'package:bagoo_buyer_mobile/features/products/product_widgets.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/account_fixtures.dart';
import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart' show buyer;
import 'support/voucher_fixtures.dart';

WebPage privateProfile({
  int owner = 7,
  String name = 'Private original voucher',
  int page = 1,
  int last = 1,
}) => WebPage('Buyer/Profile', {
  ...accountPage(owner: owner).props,
  'canUsePortal': true,
  'voucherCollection': {
    'tab': 'saved',
    'counts': {'saved': 1},
    'offers': {
      'current_page': page,
      'last_page': last,
      'data': [
        {...reviewOffer(), 'name': name},
      ],
    },
  },
});

void main() {
  late ControlledWebSession session;
  late BuyerRepository repository;
  final changed = <Map<String, dynamic>>[];
  setUp(() {
    session = ControlledWebSession();
    repository = BuyerRepository(session);
    session.onPage = (_) async => privateProfile();
    changed.clear();
  });
  tearDown(() => session.close());

  Widget app({int owner = 7}) => MaterialApp(
    theme: BagooTheme.light,
    home: Scaffold(
      body: ProfilePage(
        repository: repository,
        user: {...buyer, 'id': owner},
        initialSection: 'vouchers',
        onLogin: () {},
        onLogout: () async {},
        onUserChanged: changed.add,
      ),
    ),
  );

  testWidgets('resuming an expired profile removes its private voucher rows', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Private original voucher'), findsOneWidget);
    session.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Private original voucher'), findsNothing);
    expect(find.text('Test Buyer'), findsNothing);
  });

  testWidgets('a late same-owner profile response cannot outlive its session', (
    tester,
  ) async {
    final pending = Completer<WebPage>();
    session.onPage = (_) => pending.future;
    await tester.pumpWidget(app());
    await tester.pump();
    session.clear();
    pending.complete(privateProfile());
    await tester.pumpAndSettle();
    expect(find.text('Private original voucher'), findsNothing);
    expect(changed, isEmpty);
  });

  for (final status in [403, 404]) {
    testWidgets('profile denial $status clears retained voucher rows', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      session.onPage = (_) async =>
          throw BackendException('Access ended', status: status);
      final refresh = tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Refresh profile details',
            ),
          )
          .onPressed!;
      refresh();
      await tester.pumpAndSettle();
      expect(find.text('Private original voucher'), findsNothing);
    });
  }

  testWidgets('an obsolete profile cannot start a corrected pagination read', (
    tester,
  ) async {
    final pending = Completer<WebPage>();
    session.onPage = (_) => pending.future;
    await tester.pumpWidget(app());
    await tester.pump();
    session.clear();
    pending.complete(privateProfile(page: 3, last: 1));
    await tester.pumpAndSettle();
    expect(session.pageRequests, hasLength(1));
    expect(changed, isEmpty);
  });

  testWidgets(
    'changing buyer reloads the profile without the previous private rows',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final pending = Completer<WebPage>();
      session.onPage = (_) => pending.future;
      await tester.pumpWidget(app(owner: 8));
      await tester.pump();
      expect(find.text('Private original voucher'), findsNothing);
      pending.complete(privateProfile(owner: 8, name: 'Current buyer voucher'));
      await tester.pumpAndSettle();
      expect(find.text('Current buyer voucher'), findsOneWidget);
    },
  );
  testWidgets('expired private voucher callbacks cannot open a new guest Bag', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final action = tester.widget<OfferTile>(find.byType(OfferTile)).onUse!;
    session.clear();
    action();
    await tester.pumpAndSettle();
    expect(find.byType(BagPage), findsNothing);
    expect(session.pageRequests, hasLength(1));
  });

  testWidgets('an expired inherited account prevents even the first Bag read', (
    tester,
  ) async {
    final account = BuyerAccountScope(session);
    account.invalidate();
    await tester.pumpWidget(
      MaterialApp(
        home: BagPage(repository: repository, account: account),
      ),
    );
    await tester.pumpAndSettle();
    expect(session.pageRequests, isEmpty);
  });

  testWidgets('repeated private voucher use opens one Bag route', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    session.onPage = (_) async => const WebPage('Cart/Index', {
      'auth': {'user': buyer},
      'items': [],
    });
    final action = tester.widget<OfferTile>(find.byType(OfferTile)).onUse!;
    action();
    action();
    action();
    await tester.pumpAndSettle();
    expect(find.byType(BagPage), findsOneWidget);
    expect(session.pageRequests, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
