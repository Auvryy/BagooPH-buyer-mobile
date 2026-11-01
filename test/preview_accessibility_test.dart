import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/preview/buyer_device_preview.dart';

void main() {
  testWidgets(
    'preview controls remain accessible beside nested native routes',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          BuyerDevicePreview(
            extraControls: [
              TextButton(
                onPressed: () {},
                child: const Text('Change test account'),
              ),
            ],
            builder: (_) => const MaterialApp(
              home: Scaffold(body: Text('Native buyer screen')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final labels = <String>[];
        void visit(SemanticsNode node) {
          labels.add(node.label);
          node.visitChildren((child) {
            visit(child);
            return true;
          });
        }

        visit(
          tester
              .binding
              .renderViews
              .single
              .owner!
              .semanticsOwner!
              .rootSemanticsNode!,
        );
        expect(
          labels.any((label) => label.contains('Change test account')),
          isTrue,
        );
        expect(labels.any((label) => label.contains('Device')), isTrue);
        expect(
          labels.any((label) => label.contains('Native buyer screen')),
          isTrue,
        );
      } finally {
        semantics.dispose();
      }
    },
  );
}
