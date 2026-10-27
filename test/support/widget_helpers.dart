import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder verticalScroll() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .last;

Future<void> press(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 30 && finder.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(verticalScroll(), const Offset(0, -220));
    await tester.pumpAndSettle();
  }
  expect(finder.hitTestable(), findsWidgets);
  await tester.tap(finder.hitTestable().first);
  await tester.pumpAndSettle();
}
