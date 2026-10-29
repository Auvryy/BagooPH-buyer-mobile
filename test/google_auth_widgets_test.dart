import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/buyer_capabilities.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/auth/auth_shell.dart';
import 'package:bagoo_buyer_mobile/features/auth/google_auth_page.dart';
import 'package:bagoo_buyer_mobile/features/auth/google_auth_repository.dart';
import 'package:bagoo_buyer_mobile/features/auth/login_page.dart';
import 'package:bagoo_buyer_mobile/features/products/product_page.dart';
import 'package:bagoo_buyer_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'google_auth_repository_test.dart' show registrationData;
import 'support/controlled_web_session.dart';
import 'support/fake_google_identity.dart';
import 'support/fake_buyer_repository.dart';

class GoogleLifecycleRepository extends FakeBuyerRepository {
  int sessionChecks = 0;
  @override
  Future<WebPage?> currentSession() async {
    sessionChecks++;
    return null;
  }

  @override
  Future<BuyerCapabilities> discoverCapabilities() async =>
      BuyerCapabilities.parse({
        'contract_version': 1,
        'features': {'native_google_sign_in': true, 'device_push': false},
      });
}

Future<void> press(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  expect(finder.first.hitTestable(), findsOneWidget);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Finder editable(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(EditableText),
);

void main() {
  late ControlledWebSession session;
  late GoogleAuthRepository auth;
  late FakeGoogleIdentity provider;
  late DateTime clock;
  setUp(() {
    session = ControlledWebSession();
    clock = DateTime.utc(2026, 10, 29, 8);
    auth = GoogleAuthRepository(BuyerRepository(session), now: () => clock);
    provider = FakeGoogleIdentity();
    session.onGet = (path) async => switch (path) {
      '/buyer/mobile-capabilities' => {
        'contract_version': 1,
        'features': {'native_google_sign_in': true, 'device_push': false},
      },
      '/auth/session' => {'authenticated': false},
      _ => registrationData(),
    };
    session.onPost = (_) async => {'registration_required': true};
  });
  tearDown(() => session.close());

  Future<void> open(WidgetTester tester, {MediaQueryData? media}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        builder: media == null
            ? null
            : (_, child) => MediaQuery(data: media, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GoogleAuthPage(
                    repository: auth,
                    provider: provider,
                    remember: false,
                  ),
                ),
              ),
              child: const Text('Open Google'),
            ),
          ),
        ),
      ),
    );
    await press(tester, find.text('Open Google'));
  }

  Future<void> fillRegistration(WidgetTester tester) async {
    await tester.enterText(editable('google-first_name'), 'Native');
    await tester.enterText(editable('google-last_name'), 'Buyer');
    await press(tester, find.byKey(const ValueKey('google-sex')));
    await press(tester, find.text('Other').last);
    await press(tester, find.byKey(const ValueKey('google-birthday')));
    await press(tester, find.text('OK'));
    await press(tester, find.byKey(const ValueKey('google-policies')));
  }

  testWidgets(
    'explicit password proof keeps rejected input and returns to email',
    (tester) async {
      session.onPost = (_) async => throw BackendException(
        session.posts.length == 1
            ? 'Confirm your existing password.'
            : 'Check your password.',
        status: session.posts.length == 1 ? 409 : 422,
        data: const {'code': 'GOOGLE_ACCOUNT_LINK_REQUIRED'},
        fields: session.posts.length == 1
            ? const {}
            : const {'account_password': 'Incorrect Bagoo password.'},
      );
      await open(tester);
      expect(session.posts.length, 1);
      await tester.enterText(
        editable('google-account-password'),
        ' password with spaces ',
      );
      await press(tester, find.text('Confirm and connect account'));
      expect(find.text('Incorrect Bagoo password.'), findsOneWidget);
      expect(find.text(' password with spaces '), findsOneWidget);
      expect(
        session.posts.last.values['account_password'],
        ' password with spaces ',
      );
      await press(tester, find.text('Back to log in'));
      expect(find.text('Open Google'), findsOneWidget);
      expect(session.posts.length, 2);
    },
  );

  testWidgets(
    'native registration retains draft and only reads after an uncertain submission',
    (tester) async {
      await open(tester);
      expect(find.text('native-buyer@bagoo.test'), findsOneWidget);
      expect(find.text('Google-verified email'), findsOneWidget);
      await fillRegistration(tester);
      session.onPost = (_) async => throw const BackendException(
        'Connection interrupted.',
        connectionFailure: true,
      );
      await press(tester, find.text('Create buyer account'));
      expect(session.posts.length, 2);
      expect(session.posts.last.values['birthday'], '2008-10-29');
      expect(session.posts.last.values.containsKey('email'), isFalse);
      expect(find.text('Native'), findsOneWidget);
      await press(tester, find.text('Check sign-in status'));
      expect(session.posts.length, 2);
      expect(session.getRequests, contains('/auth/session'));
      expect(find.text('Native'), findsOneWidget);
      expect(find.text('Buyer'), findsOneWidget);
    },
  );

  testWidgets(
    'expired registration disables creation and offers explicit recovery',
    (tester) async {
      final challenge = registrationData();
      challenge['expiresAt'] =
          clock.add(const Duration(seconds: 2)).millisecondsSinceEpoch ~/ 1000;
      final previous = session.onGet!;
      session.onGet = (path) => path == '/auth/google/native/registration'
          ? Future.value(challenge)
          : previous(path);
      await open(tester);
      clock = clock.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(
        find.textContaining('This registration session has expired'),
        findsOneWidget,
      );
      final create = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Create buyer account'),
      );
      expect(create.onPressed, isNull);
      expect(find.text('Check sign-in status'), findsOneWidget);
      expect(session.posts.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(740, 360),
    const Size(1024, 768),
  ]) {
    testWidgets('Google registration fits $size with large text and keyboard', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(
        tester,
        media: MediaQueryData(
          size: size,
          textScaler: const TextScaler.linear(2),
          viewInsets: const EdgeInsets.only(bottom: 150),
          disableAnimations: true,
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('google-first_name')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(editable('google-first_name'), 'Native');
      await tester.ensureVisible(find.text('Create buyer account'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Native'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'Google cancellation preserves the email draft and releases the provider flow',
    (tester) async {
      provider.onAuthenticate = () async => null;
      final active = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: LoginPage(
            repository: auth.buyer,
            googleProvider: provider,
            onProviderFlowChanged: active.add,
            onAuthenticated: (_) =>
                fail('Canceled provider must not authenticate'),
            onRegister: () {},
            onForgot: () {},
            onBrowse: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final email = find.byWidgetPredicate(
        (w) => w is AuthField && w.label == 'Email address',
      );
      await tester.enterText(
        find.descendant(of: email, matching: find.byType(EditableText)),
        'draft@bagoo.test',
      );
      await press(tester, find.text('Continue with Google'));
      expect(find.text('draft@bagoo.test'), findsOneWidget);
      expect(active, [true, false]);
      expect(session.posts, isEmpty);
    },
  );

  testWidgets(
    'changed policy versions require fresh consent without erasing the draft',
    (tester) async {
      await open(tester);
      await tester.enterText(editable('google-first_name'), 'Retained');
      await press(tester, find.byKey(const ValueKey('google-policies')));
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('google-policies')),
            )
            .value,
        isTrue,
      );
      final updated = registrationData();
      updated['policies'] = {
        ...mapOf(updated['policies']),
        'terms_version': 'updated-terms',
      };
      final previous = session.onGet!;
      session.onGet = (path) => path == '/auth/google/native/registration'
          ? Future.value(updated)
          : previous(path);
      await press(tester, find.text('Refresh registration details'));
      expect(find.text('Retained'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('google-policies')),
            )
            .value,
        isFalse,
      );
      expect(
        find.text('Review and accept the current Terms and Privacy Notice.'),
        findsOneWidget,
      );
      expect(session.posts.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'provider selection pauses lifecycle probes and queues incoming buyer links',
    (tester) async {
      final repository = GoogleLifecycleRepository();
      addTearDown(repository.session.close);
      final links = StreamController<Uri>();
      addTearDown(links.close);
      final selection = Completer<String?>();
      provider.onAuthenticate = () => selection.future;
      await tester.pumpWidget(
        MainApp(
          repository: repository,
          googleProvider: provider,
          incomingLinks: links.stream,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue with Google'));
      await tester.tap(find.text('Continue with Google'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(provider.calls, 1);
      final checks = repository.sessionChecks;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      links.add(Uri.parse('http://backend.test/product/everyday-bag-1'));
      await tester.pump();
      expect(repository.sessionChecks, checks);
      expect(repository.productCalls, 0);
      selection.complete(null);
      await tester.pumpAndSettle();
      expect(repository.productCalls, 1);
      expect(find.byType(ProductPage), findsOneWidget);
    },
  );
}
