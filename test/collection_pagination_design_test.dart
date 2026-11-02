import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/features/collections/collection_pagination.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget app({required double textScale, required ValueChanged<int> onPage}) =>
      MaterialApp(
        theme: BagooTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 740),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: CollectionPagination(
              current: 1,
              last: 20,
              busy: false,
              onPage: onPage,
            ),
          ),
        ),
      );

  for (final textScale in [1.0, 2.0]) {
    testWidgets('phone page controls stay aligned at ${textScale}x text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 740);
      addTearDown(tester.view.reset);

      final requestedPages = <int>[];
      await tester.pumpWidget(
        app(textScale: textScale, onPage: requestedPages.add),
      );

      final controls = find.byKey(
        const ValueKey('collection-pagination-controls'),
      );
      final previous = find.byTooltip('Previous page');
      final next = find.byTooltip('Next page');
      expect(controls, findsOneWidget);
      expect(previous, findsOneWidget);
      expect(next, findsOneWidget);

      final row = tester.getRect(controls);
      final previousRect = tester.getRect(previous);
      final nextRect = tester.getRect(next);
      expect(row.left, greaterThanOrEqualTo(0));
      expect(row.right, lessThanOrEqualTo(320));
      expect(previousRect.top, nextRect.top);
      expect(previousRect.bottom, nextRect.bottom);
      expect(previousRect.left, lessThan(nextRect.left));
      expect(tester.takeException(), isNull);

      if (textScale >= 1.5) {
        expect(find.text('Previous'), findsNothing);
        expect(find.text('Next'), findsNothing);
        expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
        expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      } else {
        expect(find.text('Previous'), findsOneWidget);
        expect(find.text('Next'), findsOneWidget);
      }

      final pageLabel = find.text('Page 1 of 20');
      expect(pageLabel, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(pageLabel).didExceedMaxLines,
        isFalse,
      );
      await tester.tap(next);
      expect(requestedPages, [2]);
      expect(tester.takeException(), isNull);
    });
  }
}
