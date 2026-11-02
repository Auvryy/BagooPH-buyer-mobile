import 'dart:async';
import 'dart:io';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/checkout_page.dart';
import 'package:bagoo_buyer_mobile/features/checkout/voucher_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/checkout_fixtures.dart';
import 'support/no_network.dart';
import 'support/voucher_fixtures.dart';
import 'support/widget_helpers.dart';

class _Observer extends NavigatorObserver {
  int pops = 0;
  VoidCallback? onNextPush;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) return;
    final callback = onNextPush;
    onNextPush = null;
    callback?.call();
  }
}

void main() {
  final overrides = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = NoNetworkHttpOverrides());
  tearDownAll(() => HttpOverrides.global = overrides);
  late VoucherReviewSession session;
  late VoucherPickerReviewRepository repository;
  late _Observer observer;
  Map<String, dynamic>? selected;
  setUp(() {
    session = VoucherReviewSession();
    repository = VoucherPickerReviewRepository(session);
    observer = _Observer();
    selected = null;
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

  Future<void> open(
    WidgetTester tester, {
    int? selectedRevision,
    Map<String, dynamic>? values,
    bool expectDefaultOffer = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await Navigator.of(context)
                    .push<Map<String, dynamic>>(
                      MaterialPageRoute(
                        builder: (_) => VoucherPickerPage(
                          repository: repository,
                          values:
                              values ??
                              {
                                'item_ids': [1],
                                'delivery_type': 'doorstep',
                              },
                          title: 'Test voucher choices',
                          selectedRevision: selectedRevision,
                        ),
                      ),
                    );
              },
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await press(tester, find.text('Open picker'));
    if (expectDefaultOffer) {
      expect(find.text('Private voucher choice 1'), findsOneWidget);
    }
  }

  VoidCallback textAction(WidgetTester tester, String label) => tester
      .widget<TextButton>(find.widgetWithText(TextButton, label))
      .onPressed!;

  check('repeated paging shares one request and stays within the page range', (
    tester,
  ) async {
    await open(tester);
    final pending = Completer<Map<String, dynamic>>();
    repository.choices = (_) => pending.future;
    await tester.scrollUntilVisible(
      find.text('Next'),
      160,
      scrollable: verticalScroll(),
    );
    await tester.pumpAndSettle();
    final next = tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Next'))
        .onPressed!;
    for (var n = 0; n < 8; n++) {
      next();
    }
    await tester.pump();
    pending.complete(reviewChoices(2));
    await tester.pumpAndSettle();
    expect(repository.choiceRequests.map((v) => v['voucher_page']), [1, 2]);
    await tester.scrollUntilVisible(
      find.text('Page 2 of 3'),
      160,
      scrollable: verticalScroll(),
    );
    expect(find.text('Page 2 of 3'), findsOneWidget);
    expect(selected, isNull);
  });

  check('an out-of-range voucher revision cannot be selected', (tester) async {
    final page = reviewChoices(1, last: 1);
    ((page['offers'] as Map<String, dynamic>)['data'] as List)
            .single['revision_id'] =
        2147483648;
    repository.choices = (_) async => page;
    await open(tester);
    expect(find.text('Use voucher'), findsNothing);
    expect(selected, isNull);
    expect(find.byType(VoucherPickerPage), findsOneWidget);
  });

  check('voucher pagination rejects totals that contradict last page', (
    tester,
  ) async {
    final page = reviewChoices(1, last: 1);
    (page['offers'] as Map<String, dynamic>)['last_page'] = 100000;
    repository.choices = (_) async => page;

    await open(tester, expectDefaultOffer: false);

    expect(
      find.text('These voucher choices could not be confirmed. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Private voucher choice 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  check('voucher pagination rejects rows larger than the server page size', (
    tester,
  ) async {
    final page = reviewChoices(1, last: 1);
    final offers = List<dynamic>.from(
      (page['offers'] as Map<String, dynamic>)['data'] as List,
    );
    offers.addAll([
      for (var i = 0; i < 12; i++) reviewOffer(revision: i + 100),
    ]);
    (page['offers'] as Map<String, dynamic>)['data'] = offers;
    repository.choices = (_) async => page;

    await open(tester, expectDefaultOffer: false);

    expect(
      find.text('These voucher choices could not be confirmed. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Private voucher choice 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  check('a malformed voucher row cannot make a partial page look complete', (
    tester,
  ) async {
    final validOffers =
        (reviewChoices(1)['offers'] as Map<String, dynamic>)['data'] as List;
    final offerPage =
        reviewChoices(1, last: 1)['offers'] as Map<String, dynamic>;
    offerPage
      ..['total'] = 12
      ..['to'] = 12
      ..['data'] = [...validOffers.take(11), 'not-a-voucher'];
    repository.choices = (_) async => {'offers': offerPage};

    await open(tester, expectDefaultOffer: false);

    expect(
      find.text('These voucher choices could not be confirmed. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Private voucher choice 1'), findsNothing);
    expect(
      find.text('No vouchers are available for this selection.'),
      findsNothing,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  check('duplicate voucher revisions cannot create ambiguous choices', (
    tester,
  ) async {
    final offerPage =
        reviewChoices(1, last: 1)['offers'] as Map<String, dynamic>;
    final offers = List<dynamic>.from(offerPage['data'] as List);
    offers.add(Map<String, dynamic>.from(offers.single));
    offerPage
      ..['total'] = 2
      ..['to'] = 2
      ..['data'] = offers;
    repository.choices = (_) async => {'offers': offerPage};

    await open(tester, expectDefaultOffer: false);

    expect(
      find.text('These voucher choices could not be confirmed. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Private voucher choice 1'), findsNothing);
    expect(
      find.text('No vouchers are available for this selection.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  for (final action in ['Use voucher', 'Remove current voucher']) {
    check('queued $action decisions pop only the picker route', (tester) async {
      await open(tester, selectedRevision: 11);
      final callback = textAction(tester, action);
      final errors = <Object>[];
      for (var n = 0; n < 8; n++) {
        try {
          callback();
        } catch (error) {
          errors.add(error);
        }
      }
      await tester.pumpAndSettle();
      expect(errors, isEmpty);
      expect(tester.takeException(), isNull);
      expect(observer.pops, 1);
      expect(find.text('Open picker'), findsOneWidget);
      expect(
        selected?[action == 'Use voucher' ? 'revision_id' : 'remove'],
        action == 'Use voucher' ? 11 : true,
      );
      expect(session.writes, isEmpty);
    });
  }

  check('resuming an expired picker clears its private choices', (
    tester,
  ) async {
    await open(tester);
    session.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Private voucher choice 1'), findsNothing);
    expect(find.text('Use voucher'), findsNothing);
    expect(selected, isNull);
  });

  for (final action in ['Use voucher', 'Remove current voucher', 'Next']) {
    check('an expired cached $action cannot select or request choices', (
      tester,
    ) async {
      await open(tester, selectedRevision: 11);
      if (action == 'Next') {
        await tester.scrollUntilVisible(
          find.text('Next'),
          70,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
      }
      final callback = action == 'Next'
          ? tester
                .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, action),
                )
                .onPressed!
          : textAction(tester, action);
      session.clear();
      callback();
      await tester.pumpAndSettle();
      expect(repository.choiceRequests, hasLength(1));
      expect(selected, isNull);
      expect(find.text('Private voucher choice 1'), findsNothing);
      expect(observer.pops, 0);
    });
  }

  for (final fails in [false, true]) {
    check(
      'a late ${fails ? 'failed' : 'successful'} choice reply cannot restore an expired picker',
      (tester) async {
        await open(tester);
        final pending = Completer<Map<String, dynamic>>();
        repository.choices = (_) => pending.future;
        textAction(tester, 'Save voucher')();
        await tester.pump();
        // Successful bookmark refresh starts the next choice request.
        expect(repository.choiceRequests, hasLength(2));
        session.clear();
        if (fails) {
          pending.completeError(
            const BackendException('Private old choice failure'),
          );
        } else {
          pending.complete(reviewChoices(1));
        }
        await tester.pumpAndSettle();
        expect(find.text('Private voucher choice 1'), findsNothing);
        expect(find.text('Private old choice failure'), findsNothing);
        expect(selected, isNull);
      },
    );
  }

  check('a previous page callback cannot select a different displayed page', (
    tester,
  ) async {
    await open(tester);
    final old = textAction(tester, 'Use voucher');
    await press(tester, find.text('Next'));
    old();
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(repository.choiceRequests.map((v) => v['voucher_page']), [1, 2]);
    expect(observer.pops, 0);
  });

  check('paging keeps the opening nested checkout selection snapshot', (
    tester,
  ) async {
    final values = <String, dynamic>{
      'item_ids': [1],
      'item_quantities': {'1': 2},
      'delivery_type': 'doorstep',
    };
    await open(tester, values: values);
    (values['item_ids'] as List).add(2);
    (values['item_quantities'] as Map)['1'] = 99;
    values['delivery_type'] = 'hub_self_pickup';
    await press(tester, find.text('Next'));
    expect(repository.choiceRequests.last['item_ids'], [1]);
    expect(repository.choiceRequests.last['item_quantities'], {'1': 2});
    expect(repository.choiceRequests.last['delivery_type'], 'doorstep');
  });

  for (final status in [401, 403, 404, 419]) {
    check('choice access denial $status clears old choices', (tester) async {
      await open(tester);
      final old = textAction(tester, 'Use voucher');
      repository.choices = (_) async =>
          throw BackendException('Access ended', status: status);
      await press(tester, find.text('Next'));
      expect(find.text('Private voucher choice 1'), findsNothing);
      expect(find.text('Remove current voucher'), findsNothing);
      expect(find.text('Use voucher'), findsNothing);
      old();
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(observer.pops, 0);
    });
  }

  check(
    'temporary choice failure has an explicit read retry without a selection',
    (tester) async {
      await open(tester);
      repository.choices = (_) async =>
          throw const BackendException('Try later', status: 503);
      await press(tester, find.text('Next'));
      expect(repository.choiceRequests, hasLength(2));
      expect(find.text('Try later'), findsOneWidget);
      expect(selected, isNull);
      repository.choices = null;
      await press(tester, find.text('Try again'));
      expect(repository.choiceRequests.map((v) => v['voucher_page']), [
        1,
        2,
        2,
      ]);
      expect(find.text('Private voucher choice 2'), findsOneWidget);
    },
  );

  check('rate-limited voucher choices wait before a read retry', (
    tester,
  ) async {
    repository.choices = (_) async => throw BackendException(
      'Too many attempts. Please wait before trying again.',
      status: 429,
      retryAt: DateTime.now().add(const Duration(seconds: 30)),
    );
    await open(tester, expectDefaultOffer: false);

    final retryFinder = find.ancestor(
      of: find.textContaining('Try again in'),
      matching: find.byType(TextButton),
    );
    expect(retryFinder, findsOneWidget);
    expect(tester.widget<TextButton>(retryFinder).onPressed, isNull);
    expect(repository.choiceRequests, hasLength(1));
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
  });

  check(
    'an account change between checkout push and picker build sends no choice request',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          navigatorObservers: [observer],
          home: CheckoutPage(repository: repository, initial: ownedCheckout()),
        ),
      );
      await tester.pumpAndSettle();
      final tile = find.widgetWithText(ListTile, 'Bagoo voucher');
      await Scrollable.ensureVisible(tester.element(tile), alignment: .5);
      await tester.pumpAndSettle();
      observer.onNextPush = session.clear;
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(repository.choiceRequests, isEmpty);
      expect(find.text('Private voucher choice 1'), findsNothing);
    },
  );

  check(
    'cached bookmark actions cannot save rows while their page is changing',
    (tester) async {
      await open(tester);
      final save = textAction(tester, 'Save voucher');
      final pending = Completer<Map<String, dynamic>>();
      repository.choices = (_) => pending.future;
      await tester.scrollUntilVisible(
        find.text('Next'),
        160,
        scrollable: verticalScroll(),
      );
      await tester.pumpAndSettle();
      final next = tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Next'))
          .onPressed!;
      next();
      save();
      await tester.pump();
      pending.complete(reviewChoices(2));
      await tester.pumpAndSettle();
      expect(session.writes, isEmpty);
      expect(repository.choiceRequests.map((v) => v['voucher_page']), [1, 2]);
    },
  );

  check('checkout repeated voucher entries open one picker', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: CheckoutPage(repository: repository, initial: ownedCheckout()),
      ),
    );
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(ListTile, 'Bagoo voucher');
    await Scrollable.ensureVisible(tester.element(tile), alignment: .5);
    await tester.pumpAndSettle();
    final callback = tester.widget<ListTile>(tile).onTap!;
    for (var n = 0; n < 8; n++) {
      callback();
    }
    await tester.pumpAndSettle();
    expect(find.byType(VoucherPickerPage, skipOffstage: false), findsOneWidget);
    expect(repository.choiceRequests, hasLength(1));
    expect(session.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  check('a removed final page is corrected with one bounded read', (
    tester,
  ) async {
    await open(tester);
    repository.choices = (values) async => values['voucher_page'] == 2
        ? {
            'offers': {
              'current_page': 2,
              'last_page': 1,
              'per_page': 12,
              'total': 1,
              'from': null,
              'to': null,
              'data': [],
            },
          }
        : reviewChoices(1, last: 1);
    await press(tester, find.text('Next'));
    expect(repository.choiceRequests.map((v) => v['voucher_page']), [1, 2, 1]);
    expect(find.text('Private voucher choice 1'), findsOneWidget);
    expect(selected, isNull);
  });
  for (final action in ['Review order', 'Use best vouchers']) {
    check('cached $action waits for the open picker to close', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: CheckoutPage(repository: repository, initial: ownedCheckout()),
        ),
      );
      await tester.pumpAndSettle();
      final tile = find.widgetWithText(ListTile, 'Bagoo voucher');
      await Scrollable.ensureVisible(tester.element(tile), alignment: .5);
      await tester.pumpAndSettle();
      final callback = action == 'Review order'
          ? tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, action).hitTestable().first,
                )
                .onPressed!
          : tester
                .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, action),
                )
                .onPressed!;
      await tester.tap(tile);
      await tester.pumpAndSettle();
      callback();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(VoucherPickerPage), findsOneWidget);
      expect(session.writes, isEmpty);
      expect(repository.choiceRequests, hasLength(1));
    });
  }
  check('denied voucher access also clears checkout when the picker closes', (
    tester,
  ) async {
    repository.choices = (_) async =>
        throw const BackendException('Access denied', status: 403);
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: CheckoutPage(repository: repository, initial: ownedCheckout()),
      ),
    );
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(ListTile, 'Bagoo voucher');
    await Scrollable.ensureVisible(tester.element(tile), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('Private voucher choice 1'), findsNothing);
    await press(tester, find.text('Close'));
    expect(find.widgetWithText(TextFormField, 'Recipient name'), findsNothing);
    expect(find.text('Review order'), findsNothing);
    expect(session.writes, isEmpty);
  });
}
