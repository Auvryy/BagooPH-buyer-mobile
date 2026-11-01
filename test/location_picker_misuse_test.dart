import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/features/checkout/location_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('selected location labels remain visible at text scale $scale', (
      tester,
    ) async {
      final repository = FakeBuyerRepository();
      addTearDown(repository.session.close);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 780);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Form(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  LocationPicker(
                    repository: repository,
                    initial: const {
                      'region': '0400000000',
                      'province': 'Laguna',
                      'city': 'San Pablo City',
                      'barangay': 'San Rafael',
                    },
                    onChanged: (_) {},
                    onLoading: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in [
        'CALABARZON',
        'Laguna',
        'San Pablo City',
        'San Rafael',
      ]) {
        final value = find.text(label);
        expect(value, findsOneWidget);
        await Scrollable.ensureVisible(tester.element(value), alignment: .5);
        await tester.pumpAndSettle();
        final viewport = tester.getRect(
          find.ancestor(of: value, matching: find.byType(IndexedStack)).first,
        );
        final text = tester.getRect(value);
        final paragraph = tester.renderObject<RenderParagraph>(value);
        final naturalText = TextPainter(
          text: paragraph.text,
          textDirection: TextDirection.ltr,
          textScaler: paragraph.textScaler,
        )..layout(maxWidth: text.width);
        try {
          expect(
            text.height,
            greaterThanOrEqualTo(naturalText.height - .1),
            reason:
                '$label must have enough height to paint its complete text.',
          );
        } finally {
          naturalText.dispose();
        }
        expect(
          text.top,
          greaterThanOrEqualTo(viewport.top - .1),
          reason: '$label must start inside its selected-value viewport.',
        );
        expect(
          text.bottom,
          lessThanOrEqualTo(viewport.bottom + .1),
          reason:
              '$label must be fully readable inside its selected-value viewport.',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
