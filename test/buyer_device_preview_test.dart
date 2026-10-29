import 'package:bagoo_buyer_mobile/main.dart';
import 'package:device_frame/device_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/preview/buyer_device_preview.dart';
import 'support/fake_buyer_repository.dart';

Future<void> selectDevice(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const ValueKey('preview-device')));
  await tester.pumpAndSettle();
  final choice = find.text(name).last;
  await tester.scrollUntilVisible(
    choice,
    150,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(choice);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('selected device metrics and theme reach the nested buyer app', (
    tester,
  ) async {
    final repository = FakeBuyerRepository();
    addTearDown(repository.session.close);
    await tester.pumpWidget(
      BuyerDevicePreview(
        builder: (context) =>
            MainApp(repository: repository, theme: Theme.of(context)),
      ),
    );
    await tester.pumpAndSettle();
    final email = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Email address',
    );
    await tester.enterText(email, 'draft@bagoo.test');
    await selectDevice(tester, 'iPhone 16');
    expect(find.text('draft@bagoo.test'), findsOneWidget);
    final context = tester.element(email);
    expect(MediaQuery.sizeOf(context), Devices.ios.iPhone16.screenSize);
    expect(Theme.of(context).platform, TargetPlatform.iOS);
    await tester.tap(find.byKey(const ValueKey('preview-rotate')));
    await tester.pumpAndSettle();
    expect(
      MediaQuery.sizeOf(tester.element(email)),
      Size(
        Devices.ios.iPhone16.screenSize.height,
        Devices.ios.iPhone16.screenSize.width,
      ),
    );
    expect(find.text('draft@bagoo.test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'frame and text controls update the preview without resetting the buyer',
    (tester) async {
      await tester.pumpWidget(
        BuyerDevicePreview(
          builder: (_) => const MaterialApp(
            home: Scaffold(
              body: Text('Buyer screen', key: ValueKey('preview-screen')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('preview-text-size')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('200%').last);
      await tester.pumpAndSettle();
      final context = tester.element(
        find.byKey(const ValueKey('preview-screen')),
      );
      expect(MediaQuery.textScalerOf(context).scale(16), 32);
      await tester.tap(find.byKey(const ValueKey('preview-frame')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DeviceFrame>(find.byType(DeviceFrame)).isFrameVisible,
        isFalse,
      );
      expect(find.text('Buyer screen'), findsOneWidget);
    },
  );

  testWidgets('sidebar leaves the portrait phone the full window height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      BuyerDevicePreview(
        builder: (_) => const MaterialApp(home: Scaffold(body: Text('Buyer'))),
      ),
    );
    await tester.pumpAndSettle();
    final phone = tester.getRect(
      find.byKey(const ValueKey('buyer-preview-frame')),
    );
    final device = tester.getRect(find.byKey(const ValueKey('preview-device')));
    expect(phone.height, greaterThan(820));
    expect(phone.top, lessThan(20));
    expect(device.right, lessThan(phone.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow windows open device options in a side drawer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      BuyerDevicePreview(
        builder: (_) => const MaterialApp(home: Scaffold(body: Text('Buyer'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preview-device')), findsNothing);
    await tester.tap(find.byTooltip('Preview options'));
    await tester.pumpAndSettle();
    await selectDevice(tester, 'iPhone 16');
    await tester.tap(find.byTooltip('Close preview options'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<DeviceFrame>(find.byType(DeviceFrame)).device.name,
      'iPhone 16',
    );
    expect(find.byKey(const ValueKey('preview-device')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 568),
    const Size(430, 860),
    const Size(1100, 800),
  ]) {
    testWidgets('preview controls fit $size with large desktop text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: const TextScaler.linear(2),
          ),
          child: BuyerDevicePreview(
            builder: (_) =>
                const MaterialApp(home: Scaffold(body: Text('Preview'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DeviceFrame), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
