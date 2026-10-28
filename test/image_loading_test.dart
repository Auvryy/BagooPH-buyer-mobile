import 'package:bagoo_buyer_mobile/core/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final ratio in [1.0, 3.0]) {
    testWidgets('public thumbnail decoding follows pixel density $ratio', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(devicePixelRatio: ratio),
            child: Center(
              child: SizedBox(
                width: 120,
                height: 80,
                child: RemoteImage(
                  uri: Uri.parse('https://images.example.test/public.png'),
                  thumbnail: true,
                ),
              ),
            ),
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      final decode = image.image as ResizeImage;
      expect(decode.width, greaterThanOrEqualTo((120 * ratio).ceil()));
      expect(decode.width, lessThan((120 * ratio).ceil() + 64));
      expect(decode.height, greaterThanOrEqualTo((80 * ratio).ceil()));
      expect(decode.height, lessThan((80 * ratio).ceil() + 64));
      expect(decode.policy, ResizeImagePolicy.fit);
      expect(decode.allowUpscaling, isFalse);
      expect(image.loadingBuilder, isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.getSize(find.byType(RemoteImage)), const Size(120, 80));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('full-size and authenticated images retain original providers', (
    tester,
  ) async {
    final uri = Uri.parse('https://images.example.test/photo.png');
    for (final private in [false, true]) {
      final headers = private ? {'Cookie': 'fixture-session'} : null;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox.square(
              dimension: 200,
              child: RemoteImage(
                uri: uri,
                headers: headers,
                thumbnail: private,
              ),
            ),
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<NetworkImage>());
      expect((image.image as NetworkImage).headers, headers);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('image readiness reports transitions instead of every rebuild', (
    tester,
  ) async {
    final values = <bool>[];
    Widget screen(String path) => MaterialApp(
      home: Center(
        child: SizedBox.square(
          dimension: 120,
          child: RemoteImage(
            uri: Uri.parse('https://images.example.test/$path.png'),
            onReady: values.add,
            thumbnail: true,
          ),
        ),
      ),
    );
    await tester.pumpWidget(screen('one'));
    await tester.pumpAndSettle();
    expect(values, [false]); // Isolated widget HTTP returns an image failure.
    for (var i = 0; i < 4; i++) {
      await tester.pumpWidget(screen('one'));
      await tester.pumpAndSettle();
    }
    expect(values, [false]);
    await tester.pumpWidget(screen('two'));
    await tester.pumpAndSettle();
    expect(values, [false, false]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
