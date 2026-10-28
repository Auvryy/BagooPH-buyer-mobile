import 'dart:async';

import 'package:bagoo_buyer_mobile/core/foreground_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'serial reads discard hidden tickets and resume after pending work',
    (tester) async {
      final reads = <Completer<ReadOutcome>>[];
      final tickets = <ReadTicket>[];
      final controller = ForegroundRead(
        read: (ticket) {
          tickets.add(ticket);
          final read = Completer<ReadOutcome>();
          reads.add(read);
          return read.future;
        },
      );
      controller.setActive(true);
      await tester.pump(const Duration(milliseconds: 1));
      expect(reads, hasLength(1));
      unawaited(controller.refresh());
      await tester.pump(const Duration(seconds: 90));
      expect(reads, hasLength(1));
      controller.setActive(false);
      expect(tickets.first.isCurrent, isFalse);
      controller.setActive(true);
      await tester.pump(const Duration(milliseconds: 1));
      expect(reads, hasLength(1));
      reads.first.complete(ReadOutcome.success);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(reads, hasLength(2));
      expect(tickets.last.isCurrent, isTrue);
      controller.dispose();
      expect(tickets.last.isCurrent, isFalse);
      reads.last.complete(ReadOutcome.success);
      await tester.pump(const Duration(minutes: 5));
      expect(reads, hasLength(2));
    },
  );

  testWidgets(
    'failures back off to a bound and success restores normal cadence',
    (tester) async {
      var calls = 0;
      var outcome = ReadOutcome.retry;
      final controller = ForegroundRead(
        interval: const Duration(seconds: 2),
        maxBackoff: const Duration(seconds: 10),
        read: (_) async {
          calls++;
          return outcome;
        },
      );
      controller.setActive(true);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 3));
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 2);
      await tester.pump(const Duration(seconds: 8));
      expect(calls, 3);
      outcome = ReadOutcome.success;
      await tester.pump(const Duration(seconds: 9));
      expect(calls, 3);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 4);
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 5);
      outcome = ReadOutcome.stop;
      await controller.refresh();
      expect(controller.halted, isTrue);
      controller.setActive(false);
      controller.setActive(true);
      await tester.pump(const Duration(minutes: 10));
      expect(calls, 6);
      controller.dispose();
    },
  );

  testWidgets(
    'covered routes, background and disabled scopes pause foreground reads',
    (tester) async {
      var calls = 0;
      final controller = ForegroundRead(
        read: (_) async {
          calls++;
          return ReadOutcome.success;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ForegroundRefresh(
              controller: controller,
              child: Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const Scaffold(body: Text('Another screen')),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 90));
      expect(calls, 1);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(calls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 3));
      expect(calls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 3);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 3));
      expect(calls, 3);
      controller.dispose();
    },
  );
}
