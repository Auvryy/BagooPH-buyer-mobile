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
      'per_page': 12,
      'total': 1,
      'from': 1,
      'to': 1,
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

  Widget app({int owner = 7, String section = 'vouchers'}) => MaterialApp(
    theme: BagooTheme.light,
    home: Scaffold(
      body: ProfilePage(
        repository: repository,
        user: {...buyer, 'id': owner},
        initialSection: section,
        onLogin: () {},
        onLogout: () async {},
        onUserChanged: changed.add,
      ),
    ),
  );

  for (final (field, value) in [
    ('current_page', 1.5),
    ('last_page', 0),
    ('last_page', 99),
    ('total', '1'),
    ('per_page', 10),
    ('from', '1'),
    ('to', 2),
    ('data', 'not-a-list'),
  ]) {
    testWidgets('profile rejects malformed paginator $field=$value', (
      tester,
    ) async {
      session.onPage = (_) async {
        final page = privateProfile();
        final offers =
            (page.props['voucherCollection'] as Map)['offers'] as Map;
        offers[field] = value;
        return page;
      };
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.text('Private original voucher'), findsNothing);
      expect(
        find.text(
          'Profile pagination could not be confirmed. Refresh and try again.',
        ),
        findsOneWidget,
      );
      expect(session.pageRequests, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('profile rejects duplicate voucher revisions', (tester) async {
    session.onPage = (_) async {
      final page = privateProfile();
      final offers = (page.props['voucherCollection'] as Map)['offers'] as Map;
      final original = (offers['data'] as List).single as Map<String, dynamic>;
      offers['data'] = [
        {...original, 'name': 'Duplicate voucher one'},
        {...original, 'name': 'Duplicate voucher two'},
      ];
      return page;
    };

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Duplicate voucher one'), findsNothing);
    expect(find.text('Duplicate voucher two'), findsNothing);
    expect(
      find.text(
        'Profile pagination could not be confirmed. Refresh and try again.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile rejects paginator rows with non-text map keys', (
    tester,
  ) async {
    session.onPage = (_) async {
      final page = privateProfile();
      final wallet = page.props['wallet'] as Map;
      wallet['transactions'] = {
        'current_page': 1,
        'last_page': 1,
        'data': [
          <Object, Object>{1: 'malformed ledger row'},
        ],
      };
      return page;
    };

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Private original voucher'), findsNothing);
    expect(
      find.text(
        'Profile pagination could not be confirmed. Refresh and try again.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile does not show a partial voucher-use history', (
    tester,
  ) async {
    session.onPage = (_) async {
      final page = privateProfile();
      final offers = (page.props['voucherCollection'] as Map)['offers'] as Map;
      final rows = offers['data'] as List;
      final offer = rows.single as Map<String, dynamic>;
      offer['uses'] = [
        {
          'id': 91,
          'used_at': '2026-11-02T09:00:00+08:00',
          'saving': 10,
          'code': 'TEST-OFFER',
          'name': 'Test voucher',
        },
        'malformed voucher-use row',
      ];
      return page;
    };
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.textContaining('· Saved '), findsNothing);
    expect(
      find.text('Voucher use history could not be confirmed.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile keeps a complete voucher-use history', (tester) async {
    session.onPage = (_) async {
      final page = privateProfile();
      final offers = (page.props['voucherCollection'] as Map)['offers'] as Map;
      final offer = (offers['data'] as List).single as Map<String, dynamic>;
      offer['uses'] = [
        {
          'id': 91,
          'used_at': '2026-11-02T09:00:00+08:00',
          'saving': 10,
          'code': 'TEST-OFFER',
          'name': 'Test voucher',
        },
      ];
      return page;
    };
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.textContaining('· Saved ₱10.00'), findsOneWidget);
    expect(
      find.text('Voucher use history could not be confirmed.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile hides malformed menu summary counts', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    session.onPage = (_) async {
      final page = privateProfile();
      page.props['ordersCount'] = 1.5;
      page.props['availableVoucherCount'] = -2;
      return page;
    };
    await tester.pumpWidget(app(section: 'overview'));
    await tester.pumpAndSettle();

    expect(find.text('My Purchases & Orders'), findsOneWidget);
    expect(find.text('Vouchers & Promos'), findsOneWidget);
    expect(find.text('1.5'), findsNothing);
    expect(find.text('-2'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile address count hides a partial address list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    session.onPage = (_) async {
      final page = privateProfile();
      page.props['addresses'] = [
        {
          'id': 1,
          'recipient_name': 'Test Buyer',
          'phone': '09171234567',
          'street': '123 Test Street',
          'province': 'Laguna',
          'city': 'San Pablo City',
          'barangay': 'San Rafael',
          'postal_code': '4000',
          'region': '0400000000',
          'is_default': true,
        },
        'malformed address row',
      ];
      return page;
    };
    await tester.pumpWidget(app(section: 'overview'));
    await tester.pumpAndSettle();

    final addressRow = find
        .ancestor(
          of: find.text('Delivery Address Book'),
          matching: find.byType(Row),
        )
        .first;
    expect(
      find.descendant(of: addressRow, matching: find.text('1')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile shows the count for a complete address list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    session.onPage = (_) async {
      final page = privateProfile();
      page.props['addresses'] = [
        {
          'id': 1,
          'recipient_name': 'Test Buyer',
          'phone': '09171234567',
          'street': '123 Test Street',
          'province': 'Laguna',
          'city': 'San Pablo City',
          'barangay': 'San Rafael',
          'postal_code': '4000',
          'region': '0400000000',
          'is_default': true,
        },
      ];
      return page;
    };
    await tester.pumpWidget(app(section: 'overview'));
    await tester.pumpAndSettle();

    final addressRow = find
        .ancestor(
          of: find.text('Delivery Address Book'),
          matching: find.byType(Row),
        )
        .first;
    expect(
      find.descendant(of: addressRow, matching: find.text('1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('voucher tabs hide fractional and negative counts', (
    tester,
  ) async {
    session.onPage = (_) async {
      final page = privateProfile();
      (page.props['voucherCollection'] as Map)['counts'] = {
        'saved': 1.5,
        'available': -2,
      };
      return page;
    };
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Saved (—)'), findsOneWidget);
    expect(find.text('Available (—)'), findsOneWidget);
    expect(find.text('Saved (1.5)'), findsNothing);
    expect(find.text('Available (-2)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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
  testWidgets(
    'a Bag cannot read through a different repository session than its parent',
    (tester) async {
      final other = ControlledWebSession();
      addTearDown(other.close);
      final account = BuyerAccountScope(other);
      session.onPage = (_) async => const WebPage('Cart/Index', {
        'auth': {'user': buyer},
        'items': [],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: BagPage(repository: repository, account: account),
        ),
      );
      await tester.pumpAndSettle();
      expect(session.pageRequests, isEmpty);
    },
  );
}
