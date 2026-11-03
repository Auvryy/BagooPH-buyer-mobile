import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/auth/email_verification_link_page.dart';
import 'package:bagoo_buyer_mobile/features/checkout/bag_page.dart';
import 'package:bagoo_buyer_mobile/features/auth/login_page.dart';
import 'package:bagoo_buyer_mobile/features/auth/password_link_page.dart';
import 'package:bagoo_buyer_mobile/features/engagement/buyer_link.dart';
import 'package:bagoo_buyer_mobile/features/engagement/buyer_destination_router.dart';
import 'package:bagoo_buyer_mobile/features/home/home_page.dart';
import 'package:bagoo_buyer_mobile/features/home/search_controller.dart';
import 'package:bagoo_buyer_mobile/features/products/product_page.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_page.dart';
import 'package:bagoo_buyer_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';
import 'support/widget_helpers.dart';

class LinkRepository extends FakeBuyerRepository {
  final documents = <String>[];
  @override
  Future<WebPage?> currentSession() async =>
      signedIn ? homePage(signedIn: true) : null;
  @override
  Future<WebPage> document(String path) async {
    documents.add(path);
    return WebPage('Buyer/Home', {
      ...homePage(signedIn: true).props,
      'auth': {
        'user': {...buyer, 'email_verified_at': '2026-10-28T00:00:00Z'},
      },
    });
  }
}

class PendingVerificationRepository extends LinkRepository {
  final verification = Completer<WebPage>();
  @override
  Future<WebPage> document(String path) async {
    documents.add(path);
    return verification.future;
  }
}

class MalformedVerificationRepository extends LinkRepository {
  MalformedVerificationRepository(this.verifiedAt);

  final Object? verifiedAt;

  @override
  Future<WebPage> document(String path) async {
    documents.add(path);
    return WebPage('Buyer/Home', {
      ...homePage(signedIn: true).props,
      'auth': {
        'user': {...buyer, 'email_verified_at': verifiedAt},
      },
    });
  }
}

class RateLimitedVerificationRepository extends LinkRepository {
  @override
  Future<WebPage> document(String path) async {
    documents.add(path);
    throw BackendException(
      'Wait before using this verification link again.',
      status: 429,
      data: const {'cooldown': 10},
      retryAt: DateTime.now().toUtc().add(const Duration(seconds: 45)),
    );
  }
}

class PendingGuestCheckRepository extends FakeBuyerRepository {
  final guestCheck = Completer<WebPage?>();
  int logoutCalls = 0;

  @override
  Future<WebPage?> currentSession() => guestCheck.future;

  @override
  Future<void> logout() async {
    logoutCalls++;
    signedIn = false;
  }
}

class SwitchableGuestRepository extends FakeBuyerRepository {
  int owner = 7;
  int logoutCalls = 0;

  @override
  Future<WebPage?> currentSession() async {
    if (!signedIn) return null;
    final user = {
      ...buyer,
      'id': owner,
      'email': owner == 7 ? 'buyer@example.test' : 'other@example.test',
    };
    final page = homePage(signedIn: true);
    page.props['auth'] = {'user': user};
    return page;
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    signedIn = false;
    session.clear();
  }
}

Uri verification(int owner) => Uri.parse(
  'http://backend.test/verify-email/$owner/${List.filled(40, 'a').join()}?expires=1999999999&signature=${List.filled(64, 'b').join()}',
);

void main() {
  final origin = Uri.parse('https://buyer.example.test');
  test('buyer links enforce their URL and reset-token size boundaries', () {
    final prefix = '${origin.origin}/buyer/search?x=';
    final maximumLink = Uri.parse('$prefix${'a' * (4096 - prefix.length)}');
    expect(maximumLink.toString().length, 4096);
    expect(
      BuyerLink.parse(maximumLink, origin).kind,
      BuyerLinkKind.destination,
    );
    expect(
      () => BuyerLink.parse(Uri.parse('${maximumLink}a'), origin),
      throwsA(isA<BackendException>()),
    );

    for (final length in [10, 512]) {
      final link = BuyerLink.parse(
        origin.resolve('/reset-password/${'a' * length}?role=buyer'),
        origin,
      );
      expect(link.kind, BuyerLinkKind.passwordReset);
    }
    for (final length in [9, 513]) {
      expect(
        () => BuyerLink.parse(
          origin.resolve('/reset-password/${'a' * length}?role=buyer'),
          origin,
        ),
        throwsA(isA<BackendException>()),
      );
    }
  });

  for (final value in [
    'https://foreign.example.test/product/bag',
    'https://user:password@buyer.example.test/product/bag',
    'javascript:alert(1)',
    'https://buyer.example.test/admin',
    'https://buyer.example.test/buyer/orders/1/confirm',
    'https://buyer.example.test/wallet/payments/2/pay',
    'https://buyer.example.test/buyer/orders/99999999999999999999999999',
    'https://buyer.example.test/buyer/orders/0',
    'https://buyer.example.test/product/%2Fadmin',
    'https://buyer.example.test/reset-password/token123456?role=admin',
    'https://buyer.example.test/reset-password/token123456?role=buyer&role=admin',
    'https://buyer.example.test/reset-password/token123456?role=buyer&role=buyer',
    'https://buyer.example.test/verify-email/7/${List.filled(40, 'a').join()}?expires=1999999999&expires=1&signature=${List.filled(64, 'b').join()}',
    'https://buyer.example.test/verify-email/7/${List.filled(40, 'a').join()}?expires=1999999999&signature=${List.filled(64, 'b').join()}&signature=${List.filled(64, 'c').join()}',
  ]) {
    test('rejects unsafe or non-buyer incoming destination $value', () {
      expect(
        () => BuyerLink.parse(Uri.parse(value), origin),
        throwsA(isA<BackendException>()),
      );
    });
  }
  for (final entry in {
    '/buyer/cart': ('/cart', false),
    '/buyer/checkout': ('/checkout', true),
    '/buyer/disputes': ('/buyer-returns', true),
    '/buyer/catalog': ('/buyer/search', false),
  }.entries) {
    test(
      'website alias ${entry.key} retains native destination and context',
      () {
        final link = BuyerLink.parse(
          origin.resolve('${entry.key}?page=2&voucher=DEMO#details'),
          origin,
        );
        expect(link.uri.path, entry.value.$1);
        expect(link.requiresLogin, entry.value.$2);
        expect(link.uri.queryParameters, {'page': '2', 'voucher': 'DEMO'});
        expect(link.uri.fragment, 'details');
      },
    );
  }

  for (final query in [
    'min_price=15oops',
    'max_price=-1',
    'min_price=100000000',
  ]) {
    testWidgets('incoming search links reject invalid price $query', (
      tester,
    ) async {
      final repo = LinkRepository();
      addTearDown(repo.session.close);
      BackendException? rejection;
      Object? selectedFilters;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  try {
                    await BuyerDestinationRouter.openHref(
                      context,
                      repo,
                      'http://backend.test/buyer/search?$query',
                      onSearch: (filters) => selectedFilters = filters,
                      onProfileSection: (_) {},
                    );
                  } on BackendException catch (error) {
                    rejection = error;
                  }
                },
                child: const Text('Open search link'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open search link'));
      await tester.pumpAndSettle();

      expect(
        rejection?.message,
        'This search link has an invalid price filter.',
      );
      expect(selectedFilters, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('incoming search links normalize unknown optional filters', (
    tester,
  ) async {
    final repo = LinkRepository();
    addTearDown(repo.session.close);
    SearchFilters? selectedFilters;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => BuyerDestinationRouter.openHref(
                context,
                repo,
                'http://backend.test/buyer/search?rating=6&sort=unknown&in_stock=yes',
                onSearch: (filters) => selectedFilters = filters,
                onProfileSection: (_) {},
              ),
              child: const Text('Open search link'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open search link'));
    await tester.pumpAndSettle();

    expect(selectedFilters?.rating, '');
    expect(selectedFilters?.sort, 'relevance');
    expect(selectedFilters?.inStock, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('incoming search price filters trim control whitespace', (
    tester,
  ) async {
    final repo = LinkRepository();
    addTearDown(repo.session.close);
    SearchFilters? selectedFilters;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => BuyerDestinationRouter.openHref(
                context,
                repo,
                'http://backend.test/buyer/search?min_price=%0A1%0A&max_price=%092.50%09',
                onSearch: (filters) => selectedFilters = filters,
                onProfileSection: (_) {},
              ),
              child: const Text('Open padded search link'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open padded search link'));
    await tester.pumpAndSettle();

    expect(selectedFilters?.minimum, '1');
    expect(selectedFilters?.maximum, '2.50');
    expect(tester.takeException(), isNull);
  });

  testWidgets('incoming search links reject overlong search text', (
    tester,
  ) async {
    final repo = LinkRepository();
    addTearDown(repo.session.close);
    BackendException? rejection;
    Object? selectedFilters;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                try {
                  await BuyerDestinationRouter.openHref(
                    context,
                    repo,
                    'http://backend.test/buyer/search?search=${'a' * 101}',
                    onSearch: (filters) => selectedFilters = filters,
                    onProfileSection: (_) {},
                  );
                } on BackendException catch (error) {
                  rejection = error;
                }
              },
              child: const Text('Open search link'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open search link'));
    await tester.pumpAndSettle();

    expect(
      rejection?.message,
      'Use no more than 100 characters for your search.',
    );
    expect(selectedFilters, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final value in [
    'boots%0Awater',
    'boots%00water',
    'boots%E2%80%A8water',
  ]) {
    testWidgets('incoming search links reject line controls: $value', (
      tester,
    ) async {
      final repo = LinkRepository();
      addTearDown(repo.session.close);
      BackendException? rejection;
      Object? selectedFilters;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  try {
                    await BuyerDestinationRouter.openHref(
                      context,
                      repo,
                      'http://backend.test/buyer/search?search=$value',
                      onSearch: (filters) => selectedFilters = filters,
                      onProfileSection: (_) {},
                    );
                  } on BackendException catch (error) {
                    rejection = error;
                  }
                },
                child: const Text('Open search link'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open search link'));
      await tester.pumpAndSettle();

      expect(rejection?.message, 'This search link has an invalid query.');
      expect(selectedFilters, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('incoming search links accept 100 Unicode characters', (
    tester,
  ) async {
    final repo = LinkRepository();
    addTearDown(repo.session.close);
    final query = '\u{1f600}' * 100;
    String? selectedQuery;
    Object? rejection;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                try {
                  await BuyerDestinationRouter.openHref(
                    context,
                    repo,
                    'http://backend.test/buyer/search?search=${Uri.encodeQueryComponent(query)}',
                    onSearch: (filters) => selectedQuery = filters.query,
                    onProfileSection: (_) {},
                  );
                } on BackendException catch (error) {
                  rejection = error;
                }
              },
              child: const Text('Open search link'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open search link'));
    await tester.pumpAndSettle();

    expect(rejection, isNull);
    expect(selectedQuery, query);
    expect(selectedQuery!.runes.length, 100);
    expect(tester.takeException(), isNull);
  });

  testWidgets('incoming website Bag alias opens the guest native Bag', (
    tester,
  ) async {
    final repo = LinkRepository();
    addTearDown(repo.session.close);
    final links = StreamController<Uri>();
    addTearDown(links.close);
    await tester.pumpWidget(
      MainApp(repository: repo, incomingLinks: links.stream),
    );
    await tester.pumpAndSettle();
    links.add(Uri.parse('http://backend.test/buyer/cart'));
    await tester.pumpAndSettle();
    expect(find.byType(BagPage), findsOneWidget);
    expect(repo.bagCalls, 1);
    expect(repo.loginCalls, 0);
    expect(repo.orderCalls, 0);
  });

  test(
    'supports public shop categories and retains private account fragments',
    () {
      expect(
        BuyerLink.parse(
          origin.resolve('/shop/test/categories/12'),
          origin,
        ).requiresLogin,
        isFalse,
      );
      final profile = BuyerLink.parse(
        origin.resolve('/buyer/profile?tab=account#account-password'),
        origin,
      );
      expect(profile.requiresLogin, isTrue);
      expect(profile.uri.fragment, 'account-password');
    },
  );

  testWidgets(
    'a public incoming link opens a native product without signing in',
    (tester) async {
      final repo = LinkRepository();
      addTearDown(repo.session.close);
      final links = StreamController<Uri>();
      addTearDown(links.close);
      await tester.pumpWidget(
        MainApp(repository: repo, incomingLinks: links.stream),
      );
      await tester.pumpAndSettle();
      links.add(Uri.parse('http://backend.test/product/everyday-bag-1'));
      await tester.pumpAndSettle();
      expect(find.byType(ProductPage), findsOneWidget);
      expect(repo.productCalls, 1);
      expect(repo.loginCalls, 0);
      expect(repo.orderCalls, 0);
    },
  );

  testWidgets(
    'a private link waits for sign-in and restores the native profile section',
    (tester) async {
      final repo = LinkRepository();
      addTearDown(repo.session.close);
      final links = StreamController<Uri>();
      addTearDown(links.close);
      await tester.pumpWidget(
        MainApp(repository: repo, incomingLinks: links.stream),
      );
      await tester.pumpAndSettle();
      links.add(
        Uri.parse(
          'http://backend.test/buyer/profile?tab=account#account-personal',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'buyer@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'Password!123',
      );
      await press(tester, find.widgetWithText(FilledButton, 'Log In'));
      expect(repo.loginCalls, 1);
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.text('Personal info'), findsWidgets);
      expect(repo.orderCalls, 0);
    },
  );

  testWidgets(
    'signed email verification makes no request until explicit confirmation',
    (tester) async {
      final repo = LinkRepository()..signedIn = true;
      addTearDown(repo.session.close);
      final uri = verification(7);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: EmailVerificationLinkPage(repository: repo, link: uri),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.documents, isEmpty);
      await tester.tap(find.text('Verify my email'));
      await tester.pumpAndSettle();
      expect(repo.documents, [uri.toString()]);
      expect(find.text('Your email is verified.'), findsOneWidget);
    },
  );

  testWidgets(
    'email verification honors Retry-After after buyer eligibility is checked again',
    (tester) async {
      final repo = RateLimitedVerificationRepository()..signedIn = true;
      addTearDown(repo.session.close);
      final uri = verification(7);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: EmailVerificationLinkPage(repository: repo, link: uri),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Verify my email'));
      await tester.pumpAndSettle();
      expect(repo.documents, [uri.toString()]);
      expect(find.textContaining('Try again in '), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      await tester.tap(find.text('Check signed-in buyer'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Try again in '), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(repo.documents, [uri.toString()]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an email verification link for another buyer cannot be confirmed',
    (tester) async {
      final repo = LinkRepository()..signedIn = true;
      addTearDown(repo.session.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: EmailVerificationLinkPage(
            repository: repo,
            link: verification(8),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Verify my email'),
            )
            .onPressed,
        isNull,
      );
      expect(repo.documents, isEmpty);
    },
  );

  testWidgets(
    'a signed-out session cannot use a previously confirmed verification link',
    (tester) async {
      final repo = LinkRepository()..signedIn = true;
      addTearDown(repo.session.close);
      final uri = verification(7);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: EmailVerificationLinkPage(repository: repo, link: uri),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Verify my email'),
            )
            .onPressed,
        isNotNull,
      );

      repo.signedIn = false;
      repo.session.clear();
      await tester.tap(find.text('Verify my email'));
      await tester.pumpAndSettle();

      expect(repo.documents, isEmpty);
      expect(find.text('Your email is verified.'), findsNothing);
      expect(
        find.text(
          'Sign in to the buyer account named by this verification link.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a verification acknowledgement is discarded after the account changes',
    (tester) async {
      final repo = PendingVerificationRepository()..signedIn = true;
      addTearDown(repo.session.close);
      final uri = verification(7);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: EmailVerificationLinkPage(repository: repo, link: uri),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verify my email'));
      await tester.pump();
      expect(repo.documents, [uri.toString()]);

      repo.signedIn = false;
      repo.session.clear();
      repo.verification.complete(
        WebPage('Buyer/Home', {
          ...homePage(signedIn: true).props,
          'auth': {
            'user': {...buyer, 'email_verified_at': '2026-10-28T00:00:00Z'},
          },
        }),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your email is verified.'), findsNothing);
      expect(find.textContaining('account changed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final malformed in [
    42,
    false,
    '',
    'not-a-timestamp',
    '2026-02-30T10:00:00Z',
  ]) {
    testWidgets('malformed verification timestamp $malformed is not accepted', (
      tester,
    ) async {
      final repo = MalformedVerificationRepository(malformed)..signedIn = true;
      addTearDown(repo.session.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: EmailVerificationLinkPage(
            repository: repo,
            link: verification(7),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verify my email'));
      await tester.pumpAndSettle();

      expect(find.text('Your email is verified.'), findsNothing);
      expect(
        find.textContaining('Email verification was not confirmed.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'incoming recovery requires explicit logout and clears the previous account',
    (tester) async {
      final repo = LinkRepository()..signedIn = true;
      addTearDown(repo.session.close);
      final links = StreamController<Uri>();
      addTearDown(links.close);
      await tester.pumpWidget(
        MainApp(repository: repo, incomingLinks: links.stream),
      );
      await tester.pumpAndSettle();
      links.add(
        Uri.parse(
          'http://backend.test/reset-password/reset-token-123456?email=buyer%40example.test&role=buyer',
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.signedIn, isTrue);
      expect(find.widgetWithText(TextFormField, 'New password'), findsNothing);
      await press(tester, find.text('Sign out and continue'));
      expect(repo.signedIn, isFalse);
      expect(
        find.widgetWithText(TextFormField, 'New password'),
        findsOneWidget,
      );
      Navigator.of(tester.element(find.byType(PasswordLinkPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(HomePage), findsNothing);
    },
  );

  testWidgets('pasted recovery rejects duplicate email or role parameters', (
    tester,
  ) async {
    final repo = LinkRepository();
    addTearDown(repo.session.close);
    final links = [
      Uri.parse(
        'http://backend.test/reset-password/reset-token-123456?email=buyer%40example.test&role=admin&role=buyer',
      ),
      Uri.parse(
        'http://backend.test/reset-password/reset-token-123456?email=other%40example.test&email=buyer%40example.test&role=buyer',
      ),
    ];

    for (var index = 0; index < links.length; index++) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(index),
          theme: BagooTheme.light,
          home: PasswordLinkPage(
            repository: repo,
            initialLink: links[index],
            onComplete: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Use the complete buyer password reset link'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, 'New password'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a late recovery session check cannot display the prior account after sign-out',
    (tester) async {
      final repo = PendingGuestCheckRepository()..signedIn = true;
      addTearDown(repo.session.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: PasswordLinkPage(
            repository: repo,
            initialLink: Uri.parse(
              'http://backend.test/reset-password/reset-token-123456?email=buyer%40example.test&role=buyer',
            ),
            checkGuest: true,
            onComplete: () {},
          ),
        ),
      );
      await tester.pump();

      repo.signedIn = false;
      repo.session.clear();
      repo.guestCheck.complete(homePage(signedIn: true));
      await tester.pumpAndSettle();

      expect(find.textContaining('buyer@example.test'), findsNothing);
      expect(find.text('Sign out and continue'), findsNothing);
      expect(find.textContaining('account changed'), findsOneWidget);
      expect(repo.logoutCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sign-out confirmation rechecks instead of logging out a changed buyer',
    (tester) async {
      final repo = SwitchableGuestRepository()..signedIn = true;
      addTearDown(repo.session.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: PasswordLinkPage(
            repository: repo,
            initialLink: Uri.parse(
              'http://backend.test/reset-password/reset-token-123456?email=buyer%40example.test&role=buyer',
            ),
            checkGuest: true,
            onComplete: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('buyer@example.test'), findsOneWidget);

      repo.owner = 8;
      repo.session.clear();
      await tester.tap(find.text('Sign out and continue'));
      await tester.pumpAndSettle();

      expect(repo.logoutCalls, 0);
      expect(find.textContaining('other@example.test'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'New password'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'incoming navigation waits while the current route blocks leaving',
    (tester) async {
      final repo = LinkRepository()..signedIn = true;
      addTearDown(repo.session.close);
      final links = StreamController<Uri>();
      addTearDown(links.close);
      await tester.pumpWidget(
        MainApp(repository: repo, incomingLinks: links.stream),
      );
      await tester.pumpAndSettle();
      final navigator = Navigator.of(tester.element(find.byType(HomePage)));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (context) => const PopScope(
            canPop: false,
            child: Scaffold(body: Text('Current confirmed action')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      links.add(Uri.parse('http://backend.test/product/everyday-bag-1'));
      await tester.pumpAndSettle();
      expect(repo.productCalls, 0);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(ProductPage), findsOneWidget);
      expect(repo.productCalls, 1);
    },
  );
}
