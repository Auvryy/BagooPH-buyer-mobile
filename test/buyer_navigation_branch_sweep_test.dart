import 'dart:async';
import 'dart:io';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/collections/followed_shops_page.dart';
import 'package:bagoo_buyer_mobile/features/collections/saved_products_page.dart';
import 'package:bagoo_buyer_mobile/features/engagement/buyer_destination_router.dart';
import 'package:bagoo_buyer_mobile/features/home/search_controller.dart';
import 'package:bagoo_buyer_mobile/features/notifications/notifications_page.dart';
import 'package:bagoo_buyer_mobile/features/products/shop_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/account_status_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/returns_page.dart';
import 'package:bagoo_buyer_mobile/features/tracking/parcel_tracking_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';
import 'support/no_network.dart';
import 'support/return_fixtures.dart';
import 'support/tracking_fixtures.dart';

const _noticeId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

WebPage _destination(
  String component,
  Map<String, dynamic> props, {
  String? url,
}) => WebPage(component, {
  'auth': {'user': buyer},
  'errors': <String, dynamic>{},
  ...props,
}, url: url);

Map<String, dynamic> _emptyPage(int pageSize) => {
  'data': <Map<String, dynamic>>[],
  'current_page': 1,
  'last_page': 1,
  'per_page': pageSize,
  'total': 0,
  'from': null,
  'to': null,
};

class _NavigationRepository extends FakeBuyerRepository {
  final documents = <String>[];
  final shops = <({String slug, String category})>[];
  Future<WebPage?> Function()? onSession;
  Future<WebPage> Function(String)? onDocument;
  int sessionChecks = 0;

  @override
  Future<WebPage?> currentSession() async {
    sessionChecks++;
    return onSession == null ? homePage(signedIn: true) : onSession!();
  }

  @override
  Future<WebPage> document(String path) async {
    documents.add(path);
    if (onDocument == null) {
      throw StateError('Unexpected isolated navigation read: $path');
    }
    return onDocument!(path);
  }

  @override
  Future<WebPage> shop(
    String slug, {
    int page = 1,
    String search = '',
    String category = '',
    String storeCategory = 'all',
    String sort = 'relevance',
  }) async {
    shops.add((slug: slug, category: storeCategory));
    return _destination('Marketplace/ShopDetail', {
      'shop': {'id': 8, 'name': 'Navigation test store', 'slug': slug},
      'products': _emptyPage(18),
      'categories': <Map<String, dynamic>>[],
      'storeCategories': <Map<String, dynamic>>[],
      'isFollowing': false,
      'savedProductIds': <int>[],
      'followerCount': 0,
      'shopStats': <String, dynamic>{},
    });
  }
}

Future<void> _mount(
  WidgetTester tester,
  Future<void> Function(BuildContext) open,
  List<BackendException> errors, {
  bool nested = false,
}) async {
  Widget source() => Builder(
    builder: (context) => Scaffold(
      appBar: AppBar(title: const Text('Source route')),
      body: FilledButton(
        onPressed: () async {
          try {
            await open(context);
          } on BackendException catch (error) {
            errors.add(error);
          }
        },
        child: const Text('Open destination'),
      ),
    ),
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: BagooTheme.light,
      home: nested
          ? Builder(
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('Navigation root')),
                body: FilledButton(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => source())),
                  child: const Text('Open source'),
                ),
              ),
            )
          : source(),
    ),
  );
  if (nested) {
    await tester.tap(find.text('Open source'));
    await tester.pumpAndSettle();
  }
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Open destination'));
  await tester.pumpAndSettle();
}

void main() {
  final priorHttpOverrides = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = NoNetworkHttpOverrides());
  tearDownAll(() => HttpOverrides.global = priorHttpOverrides);

  void check(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }

  for (final destination in {
    '/account/security': 'sessions',
    '/account/settings': 'personal',
    '/buyer/addresses': 'addresses',
    '/pending-approval': 'identity',
    '/verify-email': 'emails',
    '/buyer/orders': 'orders',
    '/wallet/payments': 'wallet',
    '/buyer/profile#account-password': 'password',
    '/buyer/profile#account-verification': 'identity',
    '/buyer/profile#identity-correction': 'identity',
    '/buyer/profile#account-emails': 'emails',
    '/buyer/profile#login-activity': 'sessions',
    '/buyer/profile#security': 'sessions',
    '/buyer/profile#vouchers': 'vouchers',
    '/buyer/profile?tab=wallet': 'wallet',
    '/buyer/profile?tab=wallet#account-password': 'password',
    '/buyer/profile#unsupported-section': 'overview',
    '/buyer/profile': 'overview',
  }.entries) {
    check('profile destination ${destination.key} selects its native section', (
      tester,
    ) async {
      final repository = _NavigationRepository();
      addTearDown(repository.session.close);
      final errors = <BackendException>[];
      final sections = <String>[];
      await _mount(
        tester,
        (context) => BuyerDestinationRouter.openHref(
          context,
          repository,
          destination.key,
          onSearch: null,
          onProfileSection: sections.add,
        ),
        errors,
      );
      await _open(tester);

      expect(sections, [destination.value]);
      expect(errors, isEmpty);
      expect(repository.documents, isEmpty);
      expect(repository.sessionChecks, 0);
      expect(repository.orderCalls, 0);
      expect(find.text('Source route'), findsOneWidget);
    });
  }

  for (final href in <String?>[null, '', ' \t\n']) {
    check('an unavailable destination $href leaves its source usable', (
      tester,
    ) async {
      final repository = _NavigationRepository();
      addTearDown(repository.session.close);
      final errors = <BackendException>[];
      await _mount(
        tester,
        (context) => BuyerDestinationRouter.openHref(
          context,
          repository,
          href,
          onSearch: (_) => fail('A missing destination cannot select Search.'),
          onProfileSection: (_) =>
              fail('A missing destination cannot select Profile.'),
          closeForTabDestination: true,
        ),
        errors,
        nested: true,
      );
      await _open(tester);

      expect(
        errors.single.message,
        'This update has no available destination.',
      );
      expect(find.text('Source route'), findsOneWidget);
      expect(repository.documents, isEmpty);
    });
  }

  for (final destination in [
    (href: '/buyer/search', name: 'Search'),
    (href: '/buyer/profile#orders', name: 'Profile'),
  ]) {
    check('missing ${destination.name} callback preserves the source route', (
      tester,
    ) async {
      final repository = _NavigationRepository();
      addTearDown(repository.session.close);
      final errors = <BackendException>[];
      await _mount(
        tester,
        (context) => BuyerDestinationRouter.openHref(
          context,
          repository,
          destination.href,
          onSearch: null,
          onProfileSection: null,
          closeForTabDestination: true,
        ),
        errors,
        nested: true,
      );
      await _open(tester);

      expect(
        errors.single.message,
        startsWith('${destination.name} is unavailable'),
      );
      expect(find.text('Source route'), findsOneWidget);
      expect(repository.documents, isEmpty);
    });
  }

  check('a valid search destination closes its source and preserves filters', (
    tester,
  ) async {
    final repository = _NavigationRepository();
    addTearDown(repository.session.close);
    final errors = <BackendException>[];
    final selections = <SearchFilters>[];
    await _mount(
      tester,
      (context) => BuyerDestinationRouter.openHref(
        context,
        repository,
        '/?search=weekend&category=bags&location=Laguna&min_price=12.50&max_price=99.99&rating=4.5&in_stock=true&sort=price_asc',
        onSearch: selections.add,
        onProfileSection: null,
        closeForTabDestination: true,
      ),
      errors,
      nested: true,
    );
    await _open(tester);

    final filters = selections.single;
    expect(filters.query, 'weekend');
    expect(filters.category, 'bags');
    expect(filters.location, 'Laguna');
    expect(filters.minimum, '12.50');
    expect(filters.maximum, '99.99');
    expect(filters.rating, '4.5');
    expect(filters.inStock, isTrue);
    expect(filters.sort, 'price_asc');
    expect(find.text('Source route'), findsNothing);
    expect(find.text('Navigation root'), findsOneWidget);
    expect(errors, isEmpty);
    expect(repository.documents, isEmpty);
  });

  check('an invalid linked search preserves its source route and selection', (
    tester,
  ) async {
    final repository = _NavigationRepository();
    addTearDown(repository.session.close);
    final errors = <BackendException>[];
    final selections = <SearchFilters>[];
    await _mount(
      tester,
      (context) => BuyerDestinationRouter.openHref(
        context,
        repository,
        '/buyer/search?min_price=unconfirmed',
        onSearch: selections.add,
        onProfileSection: null,
        closeForTabDestination: true,
      ),
      errors,
      nested: true,
    );
    await _open(tester);

    expect(
      errors.single.message,
      'This search link has an invalid price filter.',
    );
    expect(selections, isEmpty);
    expect(find.text('Source route'), findsOneWidget);
    expect(repository.documents, isEmpty);
  });

  for (final path in [
    '/buyer/saved-products',
    '/buyer/followed-shops',
    '/notifications',
  ]) {
    for (final id in <Object?>[null, 0, 7.5]) {
      check('private route $path rejects an unconfirmed buyer ID $id', (
        tester,
      ) async {
        final repository = _NavigationRepository()
          ..onSession = () async => _destination('Buyer/Home', {
            'auth': {
              'user': {...buyer, 'id': id},
            },
          });
        addTearDown(repository.session.close);
        final errors = <BackendException>[];
        await _mount(
          tester,
          (context) => BuyerDestinationRouter.openHref(
            context,
            repository,
            path,
            onSearch: null,
            onProfileSection: null,
          ),
          errors,
        );
        await _open(tester);

        expect(errors.single.status, 401);
        expect(
          errors.single.message,
          'Sign in to your buyer account to open this screen.',
        );
        expect(repository.sessionChecks, 1);
        expect(repository.documents, isEmpty);
        expect(find.text('Source route'), findsOneWidget);
      });
    }
  }

  for (final route in [
    (
      path: '/buyer/saved-products',
      component: 'Buyer/SavedProducts',
      empty: 'No saved products yet',
    ),
    (
      path: '/buyer/followed-shops',
      component: 'Buyer/FollowedShops',
      empty: 'No followed shops yet',
    ),
    (
      path: '/notifications',
      component: 'Notifications/Index',
      empty: 'No notifications yet',
    ),
  ]) {
    check('confirmed session opens the native ${route.path} destination', (
      tester,
    ) async {
      final repository = _NavigationRepository()
        ..onDocument = (_) async => _destination(route.component, {
          if (route.path != '/notifications') 'entries': _emptyPage(24),
          if (route.path == '/notifications') ...{
            'portal': 'buyer',
            'available': true,
            'filter': 'all',
            'notices': _emptyPage(20),
            'notificationSummary': {'available': true, 'unread': 0},
          },
        });
      addTearDown(repository.session.close);
      final errors = <BackendException>[];
      await _mount(
        tester,
        (context) => BuyerDestinationRouter.openHref(
          context,
          repository,
          route.path,
          onSearch: null,
          onProfileSection: null,
        ),
        errors,
      );
      await _open(tester);

      expect(find.text(route.empty), findsOneWidget);
      expect(repository.sessionChecks, 1);
      expect(repository.documents.single, startsWith('${route.path}?'));
      expect(errors, isEmpty);
      expect(repository.orderCalls, 0);
      final owner = switch (route.path) {
        '/buyer/saved-products' =>
          tester
              .widget<SavedProductsPage>(find.byType(SavedProductsPage))
              .ownerId,
        '/buyer/followed-shops' =>
          tester
              .widget<FollowedShopsPage>(find.byType(FollowedShopsPage))
              .ownerId,
        _ =>
          tester
              .widget<NotificationsPage>(find.byType(NotificationsPage))
              .ownerId,
      };
      expect(owner, 7);
    });
  }

  check('a disposed source ignores a delayed private-session confirmation', (
    tester,
  ) async {
    final pending = Completer<WebPage?>();
    final repository = _NavigationRepository()
      ..onSession = () => pending.future;
    addTearDown(repository.session.close);
    final errors = <BackendException>[];
    Future<void>? opening;
    await _mount(
      tester,
      (context) => opening = BuyerDestinationRouter.openHref(
        context,
        repository,
        '/buyer/saved-products',
        onSearch: null,
        onProfileSection: null,
      ),
      errors,
    );
    await tester.tap(find.text('Open destination'));
    await tester.pump();
    expect(repository.sessionChecks, 1);
    await tester.pumpWidget(
      const MaterialApp(home: Text('Replacement screen')),
    );
    pending.complete(homePage(signedIn: true));
    await opening;
    await tester.pumpAndSettle();

    expect(find.text('Replacement screen'), findsOneWidget);
    expect(find.byType(SavedProductsPage), findsNothing);
    expect(repository.documents, isEmpty);
    expect(errors, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final route in [
    (path: '/shop/navigation-store', category: 'all'),
    (path: '/shop/navigation-store/categories/12', category: '12'),
  ]) {
    check('native shop route ${route.path} retains its store category', (
      tester,
    ) async {
      final repository = _NavigationRepository();
      addTearDown(repository.session.close);
      final errors = <BackendException>[];
      await _mount(
        tester,
        (context) => BuyerDestinationRouter.openHref(
          context,
          repository,
          route.path,
          onSearch: null,
          onProfileSection: null,
        ),
        errors,
      );
      await _open(tester);

      expect(find.byType(ShopPage), findsOneWidget);
      expect(find.text('Navigation test store'), findsWidgets);
      expect(repository.shops, [
        (slug: 'navigation-store', category: route.category),
      ]);
      expect(errors, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final malformed in [
    (
      component: 'Public/Tracking',
      props: <String, dynamic>{'searchedNumber': null},
      message: 'This tracking destination is unavailable.',
    ),
    (
      component: 'Buyer/Promotion',
      props: <String, dynamic>{'promotion': null},
      message: 'This promotion is unavailable.',
    ),
    (
      component: 'Buyer/ProductDetail',
      props: <String, dynamic>{'product': <String, dynamic>{}},
      message: 'This product is unavailable.',
    ),
    (
      component: 'Marketplace/ShopDetail',
      props: <String, dynamic>{'shop': <String, dynamic>{}},
      message: 'This shop is unavailable.',
    ),
    (
      component: 'Buyer/OrderDetail',
      props: <String, dynamic>{
        'order': <String, dynamic>{'id': 0},
      },
      message: 'This order is unavailable.',
    ),
    (
      component: 'Returns/Show',
      props: <String, dynamic>{
        'returnCase': <String, dynamic>{'id': null},
      },
      message: 'This return is unavailable.',
    ),
    (
      component: 'Seller/Home',
      props: <String, dynamic>{},
      message: 'This destination is not available in the buyer app yet.',
    ),
  ]) {
    check(
      'server-selected ${malformed.component} rejects incomplete routing data',
      (tester) async {
        final repository = _NavigationRepository()
          ..onDocument = (_) async =>
              _destination(malformed.component, malformed.props);
        addTearDown(repository.session.close);
        final errors = <BackendException>[];
        final searches = <SearchFilters>[];
        final sections = <String>[];
        await _mount(
          tester,
          (context) => BuyerDestinationRouter.openHref(
            context,
            repository,
            '/advertisement/navigation-campaign',
            onSearch: searches.add,
            onProfileSection: sections.add,
          ),
          errors,
        );
        await _open(tester);

        expect(errors.single.message, malformed.message);
        expect(repository.documents, hasLength(1));
        expect(find.text('Source route'), findsOneWidget);
        expect(searches, isEmpty);
        expect(sections, isEmpty);
        expect(repository.productCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  check(
    'a server destination for a different account role cannot select a tab',
    (tester) async {
      final repository = _NavigationRepository()
        ..onDocument = (_) async => _destination('Buyer/Profile', {
          'auth': {
            'user': {...buyer, 'role': 'seller'},
          },
        });
      addTearDown(repository.session.close);
      final errors = <BackendException>[];
      final sections = <String>[];
      await _mount(
        tester,
        (context) => BuyerDestinationRouter.openHref(
          context,
          repository,
          '/promotions/navigation-campaign',
          onSearch: null,
          onProfileSection: sections.add,
        ),
        errors,
      );
      await _open(tester);

      expect(
        errors.single.message,
        'This destination is not available to your buyer account.',
      );
      expect(sections, isEmpty);
      expect(find.text('Source route'), findsOneWidget);
    },
  );

  check(
    'server-selected tracking opens its public native result without mutations',
    (tester) async {
      final repository = _NavigationRepository()
        ..onDocument = (path) async => Uri.parse(path).path.startsWith('/track')
            ? publicTrackingPage(number: 'NAV-123')
            : _destination('Public/Tracking', {'searchedNumber': 'NAV-123'});
      addTearDown(repository.session.close);
      final errors = <BackendException>[];
      await _mount(
        tester,
        (context) => BuyerDestinationRouter.openHref(
          context,
          repository,
          '/promotions/navigation-campaign',
          onSearch: null,
          onProfileSection: null,
        ),
        errors,
      );
      await _open(tester);

      expect(find.byType(ParcelTrackingPage), findsOneWidget);
      expect(find.text('NAV-123'), findsWidgets);
      expect(repository.documents.last, '/track?number=NAV-123');
      expect(repository.orderCalls, 0);
      expect(errors, isEmpty);
      expect(find.text('HIDDEN PRIVATE NOTE'), findsNothing);
    },
  );

  for (final stale in ['changed owner', 'disposed source']) {
    check('a notification reply from a $stale cannot select a destination', (
      tester,
    ) async {
      final session = ReturnSession();
      addTearDown(session.close);
      final pending = Completer<WebPage>();
      session.onSubmit = (_) => pending.future;
      final sections = <String>[];
      final errors = <BackendException>[];
      var current = true;
      Future<void>? opening;
      await _mount(
        tester,
        (context) => opening = BuyerDestinationRouter.openNotification(
          context,
          BuyerRepository(session),
          _noticeId,
          7,
          onSearch: null,
          onProfileSection: sections.add,
          isCurrent: () => current,
        ),
        errors,
      );
      await tester.tap(find.text('Open destination'));
      await tester.pump();
      expect(session.submissions, hasLength(1));
      current = stale != 'changed owner';
      if (stale == 'disposed source') {
        await tester.pumpWidget(
          const MaterialApp(home: Text('Replacement screen')),
        );
      }
      pending.complete(
        _destination('Buyer/Profile', {}, url: '/buyer/profile#orders'),
      );
      await opening;
      await tester.pumpAndSettle();

      expect(sections, isEmpty);
      expect(errors, isEmpty);
      expect(session.pageRequests, isEmpty);
      expect(session.submissions.single.method, 'PATCH');
      expect(session.submissions.single.values, {'open': true});
      expect(tester.takeException(), isNull);
    });
  }

  check(
    'a current notification uses its confirmed profile URL and closes the source',
    (tester) async {
      final session = ReturnSession();
      addTearDown(session.close);
      session.onSubmit = (_) async => _destination(
        'Buyer/Profile',
        {},
        url: '/buyer/profile?tab=wallet#account-emails',
      );
      final errors = <BackendException>[];
      final sections = <String>[];
      await _mount(
        tester,
        (context) => BuyerDestinationRouter.openNotification(
          context,
          BuyerRepository(session),
          _noticeId,
          7,
          onSearch: null,
          onProfileSection: sections.add,
          closeForTabDestination: true,
        ),
        errors,
        nested: true,
      );
      await _open(tester);

      expect(sections, ['emails']);
      expect(find.text('Source route'), findsNothing);
      expect(find.text('Navigation root'), findsOneWidget);
      expect(session.pageRequests, isEmpty);
      expect(session.submissions.single.path, '/notifications/$_noticeId/read');
      expect(errors, isEmpty);
    },
  );

  for (final route in [
    (path: '/buyer-returns/4', caseId: 4, orderId: null),
    (path: '/buyer-returns/orders/11/create', caseId: null, orderId: 11),
  ]) {
    check('return destination ${route.path} keeps its exact resource context', (
      tester,
    ) async {
      final session = ReturnSession();
      addTearDown(session.close);
      session.onPage = (_) async =>
          route.caseId == null ? returnForm() : returnDetail();
      final errors = <BackendException>[];
      await _mount(
        tester,
        (context) => BuyerDestinationRouter.openHref(
          context,
          BuyerRepository(session),
          route.path,
          onSearch: null,
          onProfileSection: null,
        ),
        errors,
      );
      await _open(tester);

      final page = tester.widget<ReturnsPage>(find.byType(ReturnsPage));
      expect(page.caseId, route.caseId);
      expect(page.orderId, route.orderId);
      expect(session.pageRequests.single, startsWith(route.path));
      expect(session.submissions, isEmpty);
      expect(errors, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final closeSource in [false, true]) {
    check(
      'account-status identity action respects source closure $closeSource',
      (tester) async {
        final repository = _NavigationRepository()
          ..onDocument = (_) async => _destination('Auth/AccountStatus', {
            'status': {
              'account': buyer,
              'sources': <Map<String, dynamic>>[],
              'requests': <Map<String, dynamic>>[],
              'can_correct_identity': true,
            },
          });
        addTearDown(repository.session.close);
        final errors = <BackendException>[];
        final sections = <String>[];
        await _mount(
          tester,
          (context) => BuyerDestinationRouter.openHref(
            context,
            repository,
            '/account/status',
            onSearch: null,
            onProfileSection: sections.add,
            closeForTabDestination: closeSource,
          ),
          errors,
          nested: true,
        );
        await _open(tester);
        expect(find.byType(AccountStatusPage), findsOneWidget);
        await tester.tap(find.text('Review identity or application'));
        await tester.pumpAndSettle();

        expect(sections, ['identity']);
        expect(find.byType(AccountStatusPage), findsNothing);
        expect(
          find.text('Source route'),
          closeSource ? findsNothing : findsOneWidget,
        );
        expect(repository.documents, ['/account/status']);
        expect(errors, isEmpty);
        expect(repository.orderCalls, 0);
      },
    );
  }
}
