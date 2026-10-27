import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/engagement/buyer_destination_router.dart';
import 'package:bagoo_buyer_mobile/features/tracking/parcel_tracking_page.dart';
import 'package:bagoo_buyer_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart';
import 'support/tracking_fixtures.dart';

Finder _input() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.labelText == 'Tracking number',
);

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final custom = find.byType(CustomScrollView);
    final scrollable = custom.evaluate().isNotEmpty
        ? find
              .descendant(of: custom.first, matching: find.byType(Scrollable))
              .first
        : find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .first;
    await tester.scrollUntilVisible(finder, 220, scrollable: scrollable);
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder.first);
  await tester.pump();
}

Widget _app(
  BuyerRepository repository, {
  String? initialNumber,
  double scale = 1,
  double keyboard = 0,
}) => MaterialApp(
  theme: BagooTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      viewInsets: EdgeInsets.only(bottom: keyboard),
      disableAnimations: true,
    ),
    child: child!,
  ),
  home: ParcelTrackingPage(
    key: const ValueKey('tracking'),
    repository: repository,
    initialNumber: initialNumber,
  ),
);

void main() {
  late ControlledWebSession session;
  late BuyerRepository repository;
  setUp(() {
    session = ControlledWebSession();
    repository = BuyerRepository(session);
    session.onPage = (path) async =>
        publicTrackingPage(number: Uri.parse(path).queryParameters['number']!);
  });
  tearDown(() => session.close());

  testWidgets(
    'guest form validates before requests and displays public fields only',
    (tester) async {
      await tester.pumpWidget(_app(repository));
      expect(session.pageRequests, isEmpty);
      await tester.enterText(_input(), 'invalid/path');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(session.pageRequests, isEmpty);
      expect(
        tester.widget<TextField>(_input()).decoration!.errorText,
        isNotNull,
      );
      await tester.enterText(_input(), ' bagoo-1 ');
      await _tap(tester, find.widgetWithText(FilledButton, 'Track parcel'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_input()).controller!.text, 'BAGOO-1');
      await _reveal(
        tester,
        find.text('Delivered · awaiting buyer confirmation'),
      );
      expect(
        find.text('Delivered · awaiting buyer confirmation'),
        findsOneWidget,
      );
      await _reveal(tester, find.text('B*** T***'));
      expect(find.text('B*** T***'), findsOneWidget);
      await _reveal(tester, find.text('Doorstep handover recorded'));
      expect(find.text('Latest recorded update'), findsOneWidget);
      expect(find.text('HIDDEN PRIVATE NOTE'), findsNothing);
      expect(find.text('HIDDEN FULL ADDRESS'), findsNothing);
      expect(find.text('hidden@example.test'), findsNothing);
      expect(find.text('unrelated_action'), findsNothing);
      expect(find.text('Confirm receipt'), findsNothing);
      expect(session.posts, isEmpty);
    },
  );

  testWidgets(
    'new server milestone labels are shown without inventing completion',
    (tester) async {
      final page = publicTrackingPage(status: 'completed');
      (page.props['statusLabels'] as Map)['completed'] =
          'Order completed after delivery';
      (page.props['checkpointLabels'] as Map)['delivery_completed'] =
          'Completion recorded after delivery';
      final checkpoints = (page.props['parcel'] as Map)['checkpoints'] as List;
      checkpoints.last['checkpoint_type'] = 'delivery_completed';
      session.onPage = (_) async => page;
      await tester.pumpWidget(_app(repository, initialNumber: 'BAGOO-1'));
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('Order completed after delivery'));
      expect(find.text('Order completed after delivery'), findsOneWidget);
      await _reveal(tester, find.text('Completion recorded after delivery'));
      expect(find.text('Completion recorded after delivery'), findsOneWidget);
      expect(find.text('Buyer receipt is confirmed.'), findsNothing);
      expect(find.text('Confirm receipt'), findsNothing);
      expect(session.posts, isEmpty);
    },
  );

  testWidgets(
    'a not-found result keeps the searched number and useful guidance',
    (tester) async {
      session.onPage = (_) async => publicTrackingPage(notFound: true);
      await tester.pumpWidget(_app(repository, initialNumber: 'BAGOO-1'));
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('Parcel not found'));
      expect(find.text('Parcel not found'), findsOneWidget);
      await _reveal(tester, _input());
      expect(tester.widget<TextField>(_input()).controller!.text, 'BAGOO-1');
      expect(find.byTooltip('Copy tracking number'), findsNothing);
      expect(session.posts, isEmpty);
    },
  );

  testWidgets(
    'failed lookups retry and failed refreshes label retained results',
    (tester) async {
      var calls = 0;
      session.onPage = (_) async {
        calls++;
        if (calls == 1 || calls == 3) throw const BackendException('Offline');
        return publicTrackingPage(
          status: calls == 4 ? 'completed' : 'delivered',
          observedAt: calls == 4
              ? '2026-10-27T09:00:00Z'
              : '2026-10-27T08:30:00Z',
        );
      };
      await tester.pumpWidget(_app(repository, initialNumber: 'bagoo-1'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_input()).controller!.text, 'BAGOO-1');
      await _tap(tester, find.text('Try again'));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Refresh tracking'));
      await tester.pumpAndSettle();
      await _reveal(
        tester,
        find.text(
          'Showing the last confirmed lookup below. Its checked time has not changed.',
        ),
      );
      expect(
        find.text(
          'Showing the last confirmed lookup below. Its checked time has not changed.',
        ),
        findsOneWidget,
      );
      await _reveal(
        tester,
        find.text('Checked 27 Oct 2026, 4:30 PM · Philippine time'),
      );
      expect(
        find.text('Checked 27 Oct 2026, 4:30 PM · Philippine time'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Try again'));
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('Buyer confirmed receipt'));
      expect(find.text('Buyer confirmed receipt'), findsOneWidget);
      expect(session.pageRequests, hasLength(4));
      expect(session.posts, isEmpty);
    },
  );

  testWidgets(
    'editing while searching permits a new query and hides the old reply',
    (tester) async {
      final pending = Completer<WebPage>();
      session.onPage = (path) => path.contains('FIRST')
          ? pending.future
          : Future.value(publicTrackingPage(number: 'SECOND'));
      await tester.pumpWidget(_app(repository));
      await tester.enterText(_input(), 'FIRST');
      await _tap(tester, find.widgetWithText(FilledButton, 'Track parcel'));
      await tester.enterText(_input(), 'SECOND');
      await _tap(tester, find.widgetWithText(FilledButton, 'Track parcel'));
      await tester.pumpAndSettle();
      pending.complete(publicTrackingPage(number: 'FIRST'));
      await tester.pumpAndSettle();
      await _reveal(tester, find.byTooltip('Copy tracking number'));
      expect(find.text('FIRST'), findsNothing);
      expect(find.text('SECOND'), findsWidgets);
      expect(session.pageRequests, hasLength(2));
    },
  );

  testWidgets(
    'copy acknowledges the confirmed number through the native clipboard',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(_app(repository, initialNumber: 'BAGOO-1'));
      await tester.pumpAndSettle();
      await _tap(tester, find.byTooltip('Copy tracking number'));
      await tester.pumpAndSettle();
      expect(copied, 'BAGOO-1');
      expect(find.text('Tracking number copied.'), findsOneWidget);
      expect(session.posts, isEmpty);
    },
  );

  for (final href in ['/track/bagoo-1', '/track?tracking_number=bagoo-1']) {
    testWidgets('opens the existing tracking link natively: $href', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => unawaited(
                  BuyerDestinationRouter.openHref(
                    context,
                    repository,
                    href,
                    onSearch: null,
                    onProfileSection: null,
                  ),
                ),
                child: const Text('Open tracking'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open tracking'));
      await tester.pumpAndSettle();
      expect(find.byType(ParcelTrackingPage), findsOneWidget);
      expect(session.pageRequests, ['/track?number=BAGOO-1']);
    });
  }

  testWidgets(
    'external tracking links are rejected before navigation or requests',
    (tester) async {
      Object? rejection;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                BuyerDestinationRouter.openHref(
                  context,
                  repository,
                  'https://unrelated.test/track/BAGOO-1',
                  onSearch: null,
                  onProfileSection: null,
                ).catchError((Object error) {
                  rejection = error;
                }),
              ),
              child: const Text('Open external'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open external'));
      await tester.pumpAndSettle();
      expect(rejection, isA<BackendException>());
      expect(find.byType(ParcelTrackingPage), findsNothing);
      expect(session.pageRequests, isEmpty);
    },
  );

  testWidgets('a guest can open tracking from Home without logging in', (
    tester,
  ) async {
    final fake = FakeBuyerRepository();
    addTearDown(fake.session.close);
    await tester.pumpWidget(MainApp(repository: fake));
    await _tap(tester, find.text('Browse the marketplace'));
    await tester.pumpAndSettle();
    await _tap(tester, find.widgetWithText(TextButton, 'Track a parcel'));
    await tester.pumpAndSettle();
    expect(find.byType(ParcelTrackingPage), findsOneWidget);
    expect(fake.loginCalls, 0);
    expect(_input(), findsOneWidget);
  });

  testWidgets('a prefilled invalid number gives feedback without fetching', (
    tester,
  ) async {
    await tester.pumpWidget(_app(repository, initialNumber: 'invalid/path'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_input()).decoration!.errorText, isNotNull);
    expect(session.pageRequests, isEmpty);
    await _tap(tester, find.byTooltip('Clear tracking number'));
    expect(tester.widget<TextField>(_input()).controller!.text, isEmpty);
    expect(tester.widget<TextField>(_input()).decoration!.errorText, isNull);
  });

  testWidgets('signed-in Profile exposes the same native tracker', (
    tester,
  ) async {
    final fake = FakeBuyerRepository();
    addTearDown(fake.session.close);
    await tester.pumpWidget(MainApp(repository: fake));
    Finder authField(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
    await tester.enterText(authField('Email address'), 'buyer@example.test');
    await tester.enterText(authField('Password'), 'Password!123');
    await _tap(tester, find.widgetWithText(FilledButton, 'Log In'));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Profile'));
    await tester.pumpAndSettle();
    await _tap(tester, find.widgetWithText(ListTile, 'Track a parcel'));
    await tester.pumpAndSettle();
    expect(find.byType(ParcelTrackingPage), findsOneWidget);
    expect(fake.loginCalls, 1);
    expect(_input(), findsOneWidget);
  });

  testWidgets(
    'search and confirmed result survive a window and keyboard change',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1024, 768);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_app(repository, initialNumber: 'BAGOO-1'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(375, 667);
      await tester.pumpWidget(
        _app(repository, initialNumber: 'BAGOO-1', scale: 2, keyboard: 220),
      );
      await _reveal(tester, _input());
      expect(tester.widget<TextField>(_input()).controller!.text, 'BAGOO-1');
      await _reveal(tester, find.text('Doorstep handover recorded'));
      expect(find.text('Doorstep handover recorded'), findsOneWidget);
      expect(session.pageRequests, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  for (final layout in [
    (size: const Size(375, 812), scale: 1.0, keyboard: 0.0),
    (size: const Size(320, 640), scale: 2.0, keyboard: 220.0),
    (size: const Size(812, 375), scale: 2.0, keyboard: 150.0),
    (size: const Size(1024, 768), scale: 2.0, keyboard: 0.0),
  ]) {
    testWidgets('tracking fits $layout', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = layout.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final number = layout.size.width == 320
          ? List.filled(64, 'A').join()
          : 'BAGOO-1';
      await tester.pumpWidget(
        _app(
          repository,
          initialNumber: number,
          scale: layout.scale,
          keyboard: layout.keyboard,
        ),
      );
      await tester.pumpAndSettle();
      await _reveal(tester, _input());
      expect(
        tester.getBottomRight(_input()).dy,
        lessThanOrEqualTo(layout.size.height - layout.keyboard),
      );
      await _reveal(tester, find.text('Collected from seller'));
      expect(find.text('Collected from seller'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(session.posts, isEmpty);
    });
  }
}
