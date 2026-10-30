import 'dart:io';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/checkout/bag_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bag_fixtures.dart';
import 'support/no_network.dart';
import 'support/widget_helpers.dart';

class _PopObserver extends NavigatorObserver {
  int pops = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

void main() {
  final overrides = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = NoNetworkHttpOverrides());
  tearDownAll(() => HttpOverrides.global = overrides);
  late ReviewBagRepository repository;
  setUp(() => repository = ReviewBagRepository());
  tearDown(() => repository.session.close());

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

  Widget app({ReviewBagRepository? using, bool active = true}) => MaterialApp(
    theme: BagooTheme.light,
    home: BagPage(repository: using ?? repository, active: active),
  );
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }

  Finder quantityField() => find.widgetWithText(TextFormField, 'Quantity');
  Finder searchField() => find.widgetWithText(TextField, 'Search your Bag');
  void noPrivateBag(WidgetTester tester) {
    expect(find.text('Private Bag product'), findsNothing);
    expect(quantityField(), findsNothing);
    expect(searchField(), findsNothing);
    expect(repository.changes, isEmpty);
    expect(tester.takeException(), isNull);
  }

  check('resume discards Bag search and the open quantity draft after expiry', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(searchField(), 'Private');
    await press(tester, find.text('Quantity 1'));
    await tester.enterText(quantityField(), '2');
    repository.session.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    noPrivateBag(tester);
  });

  check('resume masks an expired removal confirmation', (tester) async {
    await open(tester);
    await press(tester, find.text('Remove'));
    repository.session.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    noPrivateBag(tester);
    expect(find.text('Remove from your Bag?'), findsNothing);
    expect(find.text('Bag changed'), findsOneWidget);
  });

  for (final status in ['guest', 'pending_approval', 'inactive', 'suspended']) {
    check('$status Bag shows only its permitted native controls', (
      tester,
    ) async {
      repository.owner = status == 'guest'
          ? null
          : {...repository.owner!, 'status': status};
      await open(tester);
      await Scrollable.ensureVisible(
        tester.element(find.text('Quantity 1')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Quantity 1'),
      );
      if (['guest', 'pending_approval'].contains(status)) {
        expect(button.onPressed, isNotNull);
        await press(tester, find.text('Quantity 1'));
        await tester.enterText(quantityField(), '2');
        await press(tester, find.text('Update'));
        expect(repository.changes, [(1, 2)]);
        expect(find.text('Bag quantity updated.'), findsOneWidget);
      } else {
        expect(button.onPressed, isNull);
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Remove'))
              .onPressed,
          isNull,
        );
        expect(repository.changes, isEmpty);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final status in [403, 503]) {
    check('removal failure $status displays the correct recovery state', (
      tester,
    ) async {
      repository.change = (_, _) async =>
          throw BackendException('Synthetic removal failed', status: status);
      await open(tester);
      await press(tester, find.text('Remove'));
      await press(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Remove'),
        ),
      );
      expect(repository.changes, [(1, null)]);
      expect(find.text('Item removed from your Bag.'), findsNothing);
      if (status == 403) {
        expect(find.text('Reopen Bag'), findsOneWidget);
        expect(find.text('Private Bag product'), findsNothing);
        expect(searchField(), findsNothing);
      } else {
        expect(find.text('Private Bag product'), findsOneWidget);
        expect(find.text('Synthetic removal failed'), findsOneWidget);
        expect(find.text('Reload Bag to check this item'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final layout in [(375.0, 812.0, 2.0, 280.0), (812.0, 375.0, 1.0, 0.0)]) {
    check('Bag dialogs remain usable at $layout with reduced motion', (
      tester,
    ) async {
      final size = Size(layout.$1, layout.$2);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(layout.$3),
              disableAnimations: true,
              viewInsets: EdgeInsets.only(bottom: layout.$4),
              padding: const EdgeInsets.only(top: 24, bottom: 24),
            ),
            child: BagPage(repository: repository),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Quantity 1'),
        70,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 80,
      );
      await tester.pumpAndSettle();
      await press(tester, find.text('Quantity 1'));
      tester.widget<TextFormField>(quantityField()).controller!.text = '0';
      await press(tester, find.text('Update'));
      expect(find.text('Choose 1 to 3 units.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      repository.session.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await press(tester, find.text('Close'));
      expect(find.text('Reopen Bag').hitTestable(), findsOneWidget);
      noPrivateBag(tester);
    });
  }

  for (final action in ['Cancel', 'Keep item']) {
    check('cancelling $action still clears an expired Bag', (tester) async {
      await open(tester);
      await tester.enterText(searchField(), 'Private');
      await press(
        tester,
        find.text(action == 'Cancel' ? 'Quantity 1' : 'Remove'),
      );
      repository.session.clear();
      await press(tester, find.text(action));
      noPrivateBag(tester);
    });
  }

  for (final action in ['Quantity 1', 'Remove']) {
    check('an expired cached $action action cannot open private details', (
      tester,
    ) async {
      await open(tester);
      final target = find.text(action);
      await Scrollable.ensureVisible(tester.element(target), alignment: .5);
      await tester.pumpAndSettle();
      final callback = action == 'Remove'
          ? tester
                .widget<TextButton>(find.widgetWithText(TextButton, action))
                .onPressed!
          : tester
                .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, action),
                )
                .onPressed!;
      repository.session.clear();
      callback();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      noPrivateBag(tester);
    });

    check('repeated $action opens one Bag dialog', (tester) async {
      await open(tester);
      final target = find.text(action);
      await Scrollable.ensureVisible(tester.element(target), alignment: .5);
      await tester.pumpAndSettle();
      final callback = action == 'Remove'
          ? tester
                .widget<TextButton>(find.widgetWithText(TextButton, action))
                .onPressed!
          : tester
                .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, action),
                )
                .onPressed!;
      for (var index = 0; index < 8; index++) {
        callback();
      }
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
      expect(repository.changes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final action in ['Update', 'Cancel', 'Remove', 'Keep item']) {
    check(
      'queued $action decisions consume one dialog and keep the Bag route',
      (tester) async {
        final observer = _PopObserver();
        await tester.pumpWidget(
          MaterialApp(
            theme: BagooTheme.light,
            navigatorObservers: [observer],
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BagPage(repository: repository),
                    ),
                  ),
                  child: const Text('Open Bag'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await press(tester, find.text('Open Bag'));
        final quantity = ['Update', 'Cancel'].contains(action);
        await press(tester, find.text(quantity ? 'Quantity 1' : 'Remove'));
        if (quantity) await tester.enterText(quantityField(), '2');
        final dialog = find.byType(AlertDialog);
        final callback = ['Update', 'Remove'].contains(action)
            ? tester
                  .widget<FilledButton>(
                    find.descendant(
                      of: dialog,
                      matching: find.widgetWithText(FilledButton, action),
                    ),
                  )
                  .onPressed!
            : tester
                  .widget<TextButton>(
                    find.descendant(
                      of: dialog,
                      matching: find.widgetWithText(TextButton, action),
                    ),
                  )
                  .onPressed!;
        final errors = <Object>[];
        for (var index = 0; index < 8; index++) {
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
        expect(find.byType(BagPage), findsOneWidget);
        expect(
          repository.changes,
          action == 'Update'
              ? [(1, 2)]
              : action == 'Remove'
              ? [(1, null)]
              : isEmpty,
        );
      },
    );
  }

  check('a queued quantity step cannot change an item behind its open dialog', (
    tester,
  ) async {
    await open(tester);
    await Scrollable.ensureVisible(
      tester.element(find.text('Quantity 1')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    final increase = tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is IconButton &&
                widget.tooltip == 'Increase Bag quantity',
          ),
        )
        .onPressed!;
    await press(tester, find.text('Quantity 1'));
    increase();
    await tester.pumpAndSettle();
    expect(repository.changes, isEmpty);
    expect(find.text('Update quantity'), findsOneWidget);
  });

  for (final value in ['0', '-1', '1x', '4']) {
    check('quantity submission cannot bypass validation with $value', (
      tester,
    ) async {
      await open(tester);
      await press(tester, find.text('Quantity 1'));
      tester.widget<TextFormField>(quantityField()).controller!.text = value;
      await press(tester, find.text('Update'));
      expect(find.text('Choose 1 to 3 units.'), findsOneWidget);
      expect(find.text('Update quantity'), findsOneWidget);
      expect(repository.changes, isEmpty);
    });
  }

  check('an entire mixed edit keeps the previous valid quantity', (
    tester,
  ) async {
    await open(tester);
    await press(tester, find.text('Quantity 1'));
    await tester.enterText(quantityField(), '2x');
    expect(tester.widget<TextFormField>(quantityField()).controller!.text, '1');
    expect(repository.changes, isEmpty);
  });

  check(
    'an active-tab refresh updates quantity limits inside the open dialog',
    (tester) async {
      await open(tester);
      await press(tester, find.text('Quantity 1'));
      await tester.enterText(quantityField(), '2');
      final row = repository.rows.single;
      final product = Map<String, dynamic>.from(row['product'] as Map);
      product['stock'] = 1;
      repository.rows = [
        {...row, 'product': product},
      ];
      await tester.pumpWidget(app(active: false));
      await tester.pump();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await press(tester, find.text('Update'));
      expect(find.text('Choose 1 to 1 units.'), findsOneWidget);
      expect(repository.changes, isEmpty);
    },
  );

  check('repository changes mask an open private quantity dialog', (
    tester,
  ) async {
    await open(tester);
    await press(tester, find.text('Quantity 1'));
    final replacement = ReviewBagRepository();
    addTearDown(replacement.session.close);
    await tester.pumpWidget(app(using: replacement));
    await tester.pumpAndSettle();
    noPrivateBag(tester);
    expect(replacement.changes, isEmpty);
  });

  check('a rebuilt Bag masks an expired dialog without a lifecycle event', (
    tester,
  ) async {
    await open(tester);
    await press(tester, find.text('Quantity 1'));
    repository.session.clear();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    noPrivateBag(tester);
  });

  check('queued reopen actions create one fresh Bag and then expire', (
    tester,
  ) async {
    await open(tester);
    repository.session.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    final reopen = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Reopen Bag'))
        .onPressed!;
    for (var n = 0; n < 8; n++) {
      reopen();
    }
    await tester.pumpAndSettle();
    expect(repository.reads, 2);
    reopen();
    await tester.pumpAndSettle();
    expect(repository.reads, 2);
    expect(tester.takeException(), isNull);
  });

  check(
    'an expired Bag can be explicitly reopened without reviving old callbacks',
    (tester) async {
      await open(tester);
      await press(tester, find.text('Quantity 1'));
      final oldUpdate = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Update'))
          .onPressed!;
      repository.session.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await press(tester, find.text('Close'));
      repository.owner = {...repository.owner!, 'id': 8};
      final row = repository.rows.single;
      repository.rows = [
        {
          ...row,
          'product': {
            ...Map<String, dynamic>.from(row['product'] as Map),
            'name': 'New buyer product',
          },
        },
      ];
      await press(tester, find.text('Reopen Bag'));
      await press(tester, find.text('Quantity 1'));
      oldUpdate();
      await tester.pumpAndSettle();
      expect(find.text('New buyer product'), findsWidgets);
      expect(find.text('Private Bag product'), findsNothing);
      expect(find.text('Update quantity'), findsOneWidget);
      expect(repository.changes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
