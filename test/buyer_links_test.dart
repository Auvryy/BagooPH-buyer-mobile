import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/auth/email_verification_link_page.dart';
import 'package:bagoo_buyer_mobile/features/auth/login_page.dart';
import 'package:bagoo_buyer_mobile/features/auth/password_link_page.dart';
import 'package:bagoo_buyer_mobile/features/engagement/buyer_link.dart';
import 'package:bagoo_buyer_mobile/features/home/home_page.dart';
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

Uri verification(int owner) => Uri.parse(
  'http://backend.test/verify-email/$owner/${List.filled(40, 'a').join()}?expires=1999999999&signature=${List.filled(64, 'b').join()}',
);

void main() {
  final origin = Uri.parse('https://buyer.example.test');
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
  ]) {
    test('rejects unsafe or non-buyer incoming destination $value', () {
      expect(
        () => BuyerLink.parse(Uri.parse(value), origin),
        throwsA(isA<BackendException>()),
      );
    });
  }
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
