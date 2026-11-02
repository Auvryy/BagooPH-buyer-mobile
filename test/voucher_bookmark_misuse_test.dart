import 'dart:async';
import 'dart:io';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/core/buyer_account_scope.dart';
import 'package:bagoo_buyer_mobile/features/products/product_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/no_network.dart';
import 'support/voucher_fixtures.dart';
import 'support/widget_helpers.dart';

void main() {
  final overrides = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = NoNetworkHttpOverrides());
  tearDownAll(() => HttpOverrides.global = overrides);
  late VoucherReviewSession session;
  int reloads = 0;
  setUp(() {
    session = VoucherReviewSession();
    reloads = 0;
  });
  tearDown(() => session.close());

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

  Widget app({
    Map<String, dynamic>? offer,
    bool canSave = true,
    VoidCallback? onUse,
    VoucherReviewSession? using,
    Future<void> Function()? onSaved,
    BuyerAccountScope? account,
  }) => MaterialApp(
    theme: BagooTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: OfferTile(
          key: const ValueKey('displayed-voucher'),
          offer: offer ?? reviewOffer(),
          repository: voucherRepository(using ?? session),
          onUse: onUse,
          canSave: canSave,
          account: account,
          onSaved:
              onSaved ??
              () async {
                reloads++;
              },
        ),
      ),
    ),
  );
  Future<void> open(WidgetTester tester, {Map<String, dynamic>? offer}) async {
    await tester.pumpWidget(app(offer: offer));
    await tester.pumpAndSettle();
  }

  VoidCallback saveAction(
    WidgetTester tester, [
    String label = 'Save voucher',
  ]) => tester
      .widget<TextButton>(find.widgetWithText(TextButton, label))
      .onPressed!;

  for (final scenario in [
    (
      label: 'negative percentage',
      overrides: {'discount_type': 'percent', 'discount_value': -5},
      hidden: '-5% off',
    ),
    (
      label: 'negative fixed discount and cap',
      overrides: {
        'discount_type': 'fixed',
        'discount_value': -10,
        'max_discount': -20,
      },
      hidden: '₱-10.00 off',
    ),
    (
      label: 'negative minimum spend',
      overrides: {'min_spend': -1},
      hidden: '₱-1.00',
    ),
    (
      label: 'percentage over one hundred',
      overrides: {'discount_type': 'percent', 'discount_value': 150},
      hidden: '150% off',
    ),
    (
      label: 'malformed selected-product list',
      overrides: {
        'product_scope': 'selected',
        'eligible_products': 'not-a-list',
      },
      hidden: 'Eligible product',
    ),
    (
      label: 'selected-product list with a malformed row',
      overrides: {
        'product_scope': 'selected',
        'eligible_products': [
          {'name': 'Visible item', 'url': '/product/item'},
          'not-a-product',
        ],
      },
      hidden: 'Visible item',
    ),
    (
      label: 'selected-product row without its server ID',
      overrides: {
        'product_scope': 'selected',
        'eligible_products': [
          {'name': 'Product without ID', 'url': '/product/missing-id'},
        ],
      },
      hidden: 'Product without ID',
    ),
    (
      label: 'duplicate selected-product IDs',
      overrides: {
        'product_scope': 'selected',
        'eligible_products': [
          {'id': 44, 'name': 'First eligible product', 'url': '/product/first'},
          {
            'id': 44,
            'name': 'Second eligible product',
            'url': '/product/second',
          },
        ],
      },
      hidden: 'First eligible product',
    ),
    (
      label: 'selected-product URL on another origin',
      overrides: {
        'product_scope': 'selected',
        'eligible_products': [
          {
            'id': 44,
            'name': 'Foreign product',
            'url': 'https://outside.example/product/foreign',
          },
        ],
      },
      hidden: 'Foreign product',
    ),
    (
      label: 'unknown product scope',
      overrides: {
        'product_scope': 'future-scope',
        'eligible_products': <Map<String, dynamic>>[],
      },
      hidden: 'Future scope offer',
    ),
    (
      label: 'all-products scope with selected-product rows',
      overrides: {
        'product_scope': 'all',
        'eligible_products': [
          {'id': 44, 'name': 'Unexpected product', 'url': '/product/extra'},
        ],
      },
      hidden: 'Unexpected product',
    ),
  ]) {
    check('unconfirmed ${scenario.label} cannot be shown or used', (
      tester,
    ) async {
      var uses = 0;
      await tester.pumpWidget(
        app(
          offer: {...reviewOffer(), ...scenario.overrides},
          onUse: () => uses++,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Offer terms could not be confirmed.'), findsOneWidget);
      expect(find.text(scenario.hidden), findsNothing);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Use voucher'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Save voucher'))
            .onPressed,
        isNull,
      );
      expect(uses, 0);
      expect(tester.takeException(), isNull);
    });
  }

  check('complete selected-product terms keep the eligible product link', (
    tester,
  ) async {
    var uses = 0;
    await tester.pumpWidget(
      app(
        offer: {
          ...reviewOffer(),
          'product_scope': 'selected',
          'eligible_products': [
            {'id': 44, 'name': 'Eligible product', 'url': '/product/eligible'},
          ],
        },
        onUse: () => uses++,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Eligible product'), findsOneWidget);
    expect(find.text('Offer terms could not be confirmed.'), findsNothing);
    await tester.tap(find.text('Use voucher'));
    await tester.pumpAndSettle();
    expect(uses, 1);
    expect(tester.takeException(), isNull);
  });

  check('valid free-shipping terms remain readable', (tester) async {
    await open(
      tester,
      offer: {
        ...reviewOffer(),
        'discount_type': 'free_shipping',
        'discount_value': null,
        'max_discount': 75,
      },
    );

    expect(find.text('Shipping discount up to ₱75.00'), findsOneWidget);
    expect(find.text('Offer terms could not be confirmed.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  check('confirmed bookmark save and removal use the acknowledged ID', (
    tester,
  ) async {
    await open(tester);
    await press(tester, find.text('Save voucher'));
    expect(find.text('Remove voucher'), findsOneWidget);
    await press(tester, find.text('Remove voucher'));
    expect(session.writes, [
      ('/buyer/saved-vouchers/12', 'POST'),
      ('/buyer/saved-vouchers/21', 'DELETE'),
    ]);
    expect(find.text('Save voucher'), findsOneWidget);
    expect(reloads, 2);
  });

  check('repeated saves share one pending bookmark request', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    session.reply = (_, _) => pending.future;
    await open(tester);
    final callback = saveAction(tester);
    for (var n = 0; n < 8; n++) {
      callback();
    }
    await tester.pump();
    expect(session.writes, [('/buyer/saved-vouchers/12', 'POST')]);
    pending.complete({'saved_id': 21});
    await tester.pumpAndSettle();
    expect(reloads, 1);
  });

  check('an expired saved-voucher callback cannot mutate the next session', (
    tester,
  ) async {
    await open(tester, offer: reviewOffer(saved: 4));
    final remove = saveAction(tester, 'Remove voucher');
    session.clear();
    remove();
    await tester.pumpAndSettle();
    expect(session.writes, isEmpty);
    expect(find.text('Remove voucher'), findsNothing);
    expect(reloads, 0);
  });

  for (final fails in [false, true]) {
    check(
      'a late ${fails ? 'failed' : 'successful'} bookmark reply is private to its session',
      (tester) async {
        final pending = Completer<Map<String, dynamic>>();
        session.reply = (_, _) => pending.future;
        await open(tester);
        saveAction(tester)();
        await tester.pump();
        session.clear();
        if (fails) {
          pending.completeError(
            const BackendException('Private old bookmark failure'),
          );
        } else {
          pending.complete({'saved_id': 21});
        }
        await tester.pumpAndSettle();
        expect(find.text('Remove voucher'), findsNothing);
        expect(find.text('Private old bookmark failure'), findsNothing);
        expect(reloads, 0);
      },
    );
  }

  check('a disabled save permission is checked again by a retained callback', (
    tester,
  ) async {
    await open(tester);
    final callback = saveAction(tester);
    await tester.pumpWidget(app(canSave: false));
    await tester.pumpAndSettle();
    callback();
    await tester.pumpAndSettle();
    expect(session.writes, isEmpty);
    expect(reloads, 0);
  });

  check('a late acknowledgement cannot revive a revoked save permission', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    session.reply = (_, _) => pending.future;
    await open(tester);
    saveAction(tester)();
    await tester.pump();
    await tester.pumpWidget(app(canSave: false));
    await tester.pump();
    pending.complete({'saved_id': 21});
    await tester.pumpAndSettle();
    expect(find.text('Remove voucher'), findsNothing);
    expect(reloads, 0);
  });

  check('a replaced repository cannot inherit the old voucher action', (
    tester,
  ) async {
    await open(tester, offer: reviewOffer(saved: 4));
    final callback = saveAction(tester, 'Remove voucher');
    final replacement = VoucherReviewSession();
    addTearDown(replacement.close);
    await tester.pumpWidget(app(using: replacement));
    await tester.pumpAndSettle();
    callback();
    await tester.pumpAndSettle();
    expect(session.writes, isEmpty);
    expect(replacement.writes, isEmpty);
  });

  check('a different offer initializes its own bookmark state', (tester) async {
    await open(tester, offer: reviewOffer(saved: 4));
    await tester.pumpWidget(app(offer: reviewOffer(revision: 30)));
    await tester.pumpAndSettle();
    expect(find.text('Save voucher'), findsOneWidget);
    await press(tester, find.text('Save voucher'));
    expect(session.writes, [('/buyer/saved-vouchers/30', 'POST')]);
  });

  check('a refreshed saved ID is used for the next explicit removal', (
    tester,
  ) async {
    await open(tester, offer: reviewOffer(saved: 4));
    await tester.pumpWidget(app(offer: reviewOffer(saved: 5)));
    await tester.pumpAndSettle();
    await press(tester, find.text('Remove voucher'));
    expect(session.writes, [('/buyer/saved-vouchers/5', 'DELETE')]);
  });

  check('a retained callback cannot apply to a replacement revision', (
    tester,
  ) async {
    await open(tester);
    final callback = saveAction(tester);
    await tester.pumpWidget(app(offer: reviewOffer(revision: 30)));
    await tester.pumpAndSettle();
    callback();
    await tester.pumpAndSettle();
    expect(session.writes, isEmpty);
  });

  for (final removing in [false, true]) {
    check(
      'a late ${removing ? 'remove' : 'save'} reply cannot overwrite a new offer',
      (tester) async {
        final pending = Completer<Map<String, dynamic>>();
        session.reply = (_, _) => pending.future;
        await open(tester, offer: reviewOffer(saved: removing ? 4 : null));
        saveAction(tester, removing ? 'Remove voucher' : 'Save voucher')();
        await tester.pump();
        await tester.pumpWidget(
          app(offer: reviewOffer(revision: 30, saved: removing ? 41 : null)),
        );
        await tester.pump();
        pending.complete({'saved_id': removing ? null : 21});
        await tester.pumpAndSettle();
        expect(
          find.text(removing ? 'Remove voucher' : 'Save voucher'),
          findsOneWidget,
        );
        expect(reloads, 0);
      },
    );
  }

  for (final saved in [0, -1, 1.5, double.nan, double.infinity, '21', null]) {
    check('invalid saved acknowledgement $saved is not accepted', (
      tester,
    ) async {
      session.reply = (_, _) async => {'saved_id': saved};
      await open(tester);
      await press(tester, find.text('Save voucher'));
      expect(find.text('Remove voucher'), findsNothing);
      expect(
        find.text('The voucher change was not confirmed.'),
        findsOneWidget,
      );
      expect(reloads, 0);
      expect(session.writes, hasLength(1));
    });
  }

  for (final revision in [0, -1, 1.5, double.infinity, '../12', 2147483648]) {
    check('invalid displayed revision $revision cannot be used as a path', (
      tester,
    ) async {
      await open(tester, offer: reviewOffer(revision: revision));
      final save = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Save voucher'))
          .onPressed;
      save?.call();
      await tester.pumpAndSettle();
      expect(session.writes, isEmpty);
      expect(reloads, 0);
    });
  }

  for (final saved in [0, -1, 1.5, double.nan, '../4']) {
    check('invalid displayed bookmark $saved cannot be used as a path', (
      tester,
    ) async {
      await open(tester, offer: reviewOffer(saved: saved));
      final remove = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Remove voucher'))
          .onPressed;
      remove?.call();
      await tester.pumpAndSettle();
      expect(session.writes, isEmpty);
      expect(reloads, 0);
    });
  }

  check('a callback after disposal cannot send or call setState', (
    tester,
  ) async {
    await open(tester);
    final callback = saveAction(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    callback();
    await tester.pumpAndSettle();
    expect(session.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  check(
    'an uncertain removal needs an explicit retry with the same bookmark ID',
    (tester) async {
      var attempts = 0;
      session.reply = (_, _) async {
        attempts++;
        if (attempts == 1) {
          throw const BackendException('Change not confirmed', status: 503);
        }
        return {'saved_id': null};
      };
      await open(tester, offer: reviewOffer(saved: 4));
      await press(tester, find.text('Remove voucher'));
      expect(session.writes, [('/buyer/saved-vouchers/4', 'DELETE')]);
      expect(find.text('Change not confirmed'), findsOneWidget);
      await press(tester, find.text('Remove voucher'));
      expect(session.writes, [
        ('/buyer/saved-vouchers/4', 'DELETE'),
        ('/buyer/saved-vouchers/4', 'DELETE'),
      ]);
      expect(find.text('Save voucher'), findsOneWidget);
    },
  );

  check(
    'an expired post-save refresh cannot display the former account error',
    (tester) async {
      final pending = Completer<void>();
      await tester.pumpWidget(app(onSaved: () => pending.future));
      await tester.pumpAndSettle();
      saveAction(tester)();
      await tester.pump(const Duration(milliseconds: 100));
      session.clear();
      pending.completeError(
        const BackendException('Private old refresh failure'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private old refresh failure'), findsNothing);
      expect(find.text('Remove voucher'), findsNothing);
    },
  );

  for (final removing in [false, true]) {
    check(
      'a completed ${removing ? 'remove' : 'save'} callback cannot toggle the opposite intent',
      (tester) async {
        await open(tester, offer: reviewOffer(saved: removing ? 4 : null));
        final callback = saveAction(
          tester,
          removing ? 'Remove voucher' : 'Save voucher',
        );
        callback();
        await tester.pumpAndSettle();
        callback();
        await tester.pumpAndSettle();
        expect(session.writes, hasLength(1));
        expect(
          find.text(removing ? 'Save voucher' : 'Remove voucher'),
          findsOneWidget,
        );
        expect(reloads, 1);
      },
    );
  }

  check('an ordinary parent rebuild retains its acknowledged bookmark', (
    tester,
  ) async {
    await open(tester);
    await press(tester, find.text('Save voucher'));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Remove voucher'), findsOneWidget);
    await press(tester, find.text('Remove voucher'));
    expect(session.writes.last, ('/buyer/saved-vouchers/21', 'DELETE'));
  });

  check('an older offer reply cannot clear a newer pending save', (
    tester,
  ) async {
    final old = Completer<Map<String, dynamic>>();
    final next = Completer<Map<String, dynamic>>();
    session.reply = (path, _) =>
        path.endsWith('/12') ? old.future : next.future;
    await open(tester);
    saveAction(tester)();
    await tester.pump();
    await tester.pumpWidget(app(offer: reviewOffer(revision: 30)));
    await tester.pumpAndSettle();
    saveAction(tester)();
    await tester.pump();
    old.complete({'saved_id': 21});
    await tester.pumpAndSettle();
    expect(find.text('Saving…'), findsOneWidget);
    expect(reloads, 0);
    next.complete({'saved_id': 31});
    await tester.pumpAndSettle();
    expect(find.text('Remove voucher'), findsOneWidget);
    expect(reloads, 1);
    expect(session.writes, [
      ('/buyer/saved-vouchers/12', 'POST'),
      ('/buyer/saved-vouchers/30', 'POST'),
    ]);
  });

  check('denied removal discards private bookmark state', (tester) async {
    session.reply = (_, _) async =>
        throw const BackendException('Access denied', status: 403);
    await open(tester, offer: reviewOffer(saved: 4));
    await press(tester, find.text('Remove voucher'));
    expect(session.writes, hasLength(1));
    expect(find.text('Remove voucher'), findsNothing);
    expect(reloads, 0);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Save voucher'))
          .onPressed,
      isNull,
    );
  });

  check('guest save opens one native sign-in route without a bookmark write', (
    tester,
  ) async {
    int signins = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: OfferTile(
              offer: reviewOffer(),
              repository: voucherRepository(session),
              onSignIn: () {
                signins++;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const Scaffold(body: Text('Synthetic native sign-in')),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final callback = saveAction(tester);
    for (var n = 0; n < 8; n++) {
      callback();
    }
    await tester.pumpAndSettle();
    expect(signins, 1);
    expect(session.writes, isEmpty);
    expect(find.text('Synthetic native sign-in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  check('a parent checkout scope ends a cached bookmark action immediately', (
    tester,
  ) async {
    final account = BuyerAccountScope(session);
    await tester.pumpWidget(app(account: account));
    await tester.pumpAndSettle();
    final callback = saveAction(tester);
    account.invalidate();
    callback();
    await tester.pumpAndSettle();
    expect(session.writes, isEmpty);
    expect(find.text('Remove voucher'), findsNothing);
  });

  check(
    'a different parent scope cannot inherit the previous bookmark callback',
    (tester) async {
      final first = BuyerAccountScope(session),
          second = BuyerAccountScope(session);
      await tester.pumpWidget(app(account: first));
      await tester.pumpAndSettle();
      final callback = saveAction(tester);
      await tester.pumpWidget(app(account: second));
      await tester.pumpAndSettle();
      callback();
      await tester.pumpAndSettle();
      expect(session.writes, isEmpty);
      expect(first.isCurrent, isTrue);
      expect(second.isCurrent, isTrue);
    },
  );

  check('disposing a bookmark tile does not close its parent checkout scope', (
    tester,
  ) async {
    final account = BuyerAccountScope(session);
    await tester.pumpWidget(app(account: account));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(account.isCurrent, isTrue);
    expect(session.writes, isEmpty);
  });
}
