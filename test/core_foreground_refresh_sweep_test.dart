import 'dart:async';

import 'package:bagoo_buyer_mobile/core/foreground_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual refresh cannot start a hidden or disposed controller', () async {
    var calls = 0;
    final controller = ForegroundRead(
      read: (_) async {
        calls++;
        return ReadOutcome.success;
      },
    );
    await controller.refresh();
    controller.dispose();
    controller.setActive(true);
    await controller.refresh();
    expect(calls, 0);
    expect(controller.active, isFalse);
  });

  for (final synchronous in [false, true]) {
    testWidgets(
      '${synchronous ? 'synchronous' : 'asynchronous'} read failures retry after backoff',
      (tester) async {
        var calls = 0;
        final controller = ForegroundRead(
          interval: const Duration(seconds: 2),
          read: (_) {
            calls++;
            if (calls == 1) {
              if (synchronous) throw StateError('Fixture read failed.');
              return Future.error(StateError('Fixture read failed.'));
            }
            return Future.value(ReadOutcome.success);
          },
        );
        addTearDown(controller.dispose);
        controller.setActive(true);
        await tester.pump(const Duration(milliseconds: 1));
        expect(calls, 1);
        await tester.pump(const Duration(seconds: 3));
        expect(calls, 1);
        await tester.pump(const Duration(seconds: 1));
        expect(calls, 2);
        expect(controller.active, isTrue);
        expect(tester.takeException(), isNull);
        controller.dispose();
      },
    );
  }

  testWidgets(
    'replacing a foreground controller invalidates pending old reads',
    (tester) async {
      var firstCalls = 0;
      var secondCalls = 0;
      final pending = Completer<ReadOutcome>();
      late ReadTicket oldTicket;
      final first = ForegroundRead(
        read: (ticket) {
          firstCalls++;
          oldTicket = ticket;
          return pending.future;
        },
      );
      final second = ForegroundRead(
        read: (_) async {
          secondCalls++;
          return ReadOutcome.success;
        },
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      Widget scope(ForegroundRead controller, {bool enabled = true}) =>
          MaterialApp(
            home: ForegroundRefresh(
              controller: controller,
              enabled: enabled,
              child: const SizedBox.shrink(),
            ),
          );

      await tester.pumpWidget(scope(first));
      await tester.pump(const Duration(milliseconds: 1));
      expect(firstCalls, 1);
      expect(oldTicket.isCurrent, isTrue);

      await tester.pumpWidget(scope(second));
      await tester.pump(const Duration(milliseconds: 1));
      expect(first.active, isFalse);
      expect(oldTicket.isCurrent, isFalse);
      expect(secondCalls, 1);
      pending.complete(ReadOutcome.success);
      await tester.pump(const Duration(seconds: 30));
      expect(firstCalls, 1);

      await tester.pumpWidget(scope(second, enabled: false));
      expect(second.active, isFalse);
      final callsWhenDisabled = secondCalls;
      await tester.pump(const Duration(minutes: 2));
      expect(secondCalls, callsWhenDisabled);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
