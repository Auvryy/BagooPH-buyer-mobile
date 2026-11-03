import 'package:bagoo_buyer_mobile/core/retry_cooldown.dart';
import 'package:bagoo_buyer_mobile/core/verification_cooldown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fractional server cooldowns round upward at the valid boundaries', () {
    expect(verificationCooldownSeconds({'cooldown': 0.001}), 1);
    expect(verificationCooldownSeconds({'cooldown': 315360000}), 315360000);
    expect(verificationCooldownSeconds({'cooldown': 315360000.1}), 60);
    expect(verificationCooldownSeconds({'cooldown': false}), 60);
  });

  test('a future submillisecond deadline still has one second remaining', () {
    final now = DateTime.utc(2026, 11, 3);
    expect(
      verificationCooldownSecondsUntil(
        now.add(const Duration(microseconds: 1)),
        now: now,
      ),
      1,
    );
    expect(
      verificationCooldownSecondsUntil(
        now.add(const Duration(seconds: 1, microseconds: 1)),
        now: now,
      ),
      2,
    );
    expect(verificationCooldownSecondsUntil(now, now: now), 0);
    expect(
      verificationCooldownSecondsUntil(
        now.subtract(const Duration(microseconds: 1)),
        now: now,
      ),
      0,
    );
  });

  test('active retry restriction never displays zero before its deadline', () {
    var now = DateTime.utc(2026, 11, 3);
    final cooldown = RetryCooldown(() {}, now: () => now);
    addTearDown(cooldown.dispose);
    cooldown.start({'cooldown': 1}, notify: false);
    now = now.add(const Duration(microseconds: 999999));
    expect(cooldown.active, isTrue);
    expect(cooldown.remainingSeconds, 1);
  });

  for (final boundary in [
    (duration: const Duration(microseconds: 1), seconds: 1),
    (duration: const Duration(seconds: 1, microseconds: 1), seconds: 2),
  ]) {
    test('startFor preserves a ${boundary.duration} deadline', () {
      final now = DateTime.utc(2026, 11, 3);
      final cooldown = RetryCooldown(() {}, now: () => now);
      addTearDown(cooldown.dispose);
      cooldown.startFor(boundary.duration, notify: false);
      expect(cooldown.active, isTrue);
      expect(cooldown.remainingSeconds, boundary.seconds);
    });
  }

  testWidgets('countdown notifies at the next visible change after its cap', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 11, 3);
    var notifications = 0;
    final cooldown = RetryCooldown(() => notifications++, now: () => now);
    addTearDown(cooldown.dispose);
    cooldown.startFor(const Duration(seconds: 3661), notify: false);
    expect(cooldown.active, isTrue);
    expect(cooldown.remainingSeconds, 3600);

    now = now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 60));
    expect(notifications, 0);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(notifications, 1);
    expect(cooldown.remainingSeconds, 3600);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(notifications, 2);
    expect(cooldown.remainingSeconds, 3599);
    cooldown.dispose();
  });

  testWidgets('the timer releases the restriction at the actual deadline', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 11, 3);
    var notifications = 0;
    final cooldown = RetryCooldown(() => notifications++, now: () => now);
    addTearDown(cooldown.dispose);
    cooldown.startFor(const Duration(milliseconds: 1001), notify: false);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(cooldown.active, isTrue);
    expect(cooldown.remainingSeconds, 1);
    expect(notifications, 1);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(cooldown.active, isFalse);
    expect(cooldown.remainingSeconds, 0);
    expect(notifications, 2);

    await tester.pump(const Duration(seconds: 10));
    expect(notifications, 2);
  });

  testWidgets('long deadlines wake daily and remain bounded to ten years', (
    tester,
  ) async {
    final start = DateTime.utc(2026, 11, 3);
    var now = start;
    var notifications = 0;
    final cooldown = RetryCooldown(() => notifications++, now: () => now);
    addTearDown(cooldown.dispose);
    cooldown.startFor(const Duration(days: 36500), notify: false);

    now = start.add(const Duration(days: 1));
    await tester.pump(const Duration(days: 1));
    expect(notifications, 1);
    expect(cooldown.active, isTrue);
    expect(cooldown.remainingSeconds, 3600);

    now = start.add(const Duration(seconds: 315360000));
    await tester.pump(const Duration(days: 1));
    expect(notifications, 2);
    expect(cooldown.active, isFalse);
    expect(cooldown.remainingSeconds, 0);
  });

  testWidgets('nonpositive durations have no pending timer', (tester) async {
    final now = DateTime.utc(2026, 11, 3);
    var notifications = 0;
    final cooldown = RetryCooldown(() => notifications++, now: () => now);
    addTearDown(cooldown.dispose);
    for (final duration in [Duration.zero, const Duration(seconds: -1)]) {
      cooldown.startFor(duration);
      expect(cooldown.active, isFalse);
      expect(cooldown.remainingSeconds, 0);
    }
    expect(notifications, 2);
    await tester.pump(const Duration(seconds: 2));
    expect(notifications, 2);
  });

  testWidgets('restart, silent clear and disposal cancel earlier timers', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 11, 3);
    var notifications = 0;
    final cooldown = RetryCooldown(() => notifications++, now: () => now);
    addTearDown(cooldown.dispose);
    expect(cooldown.active, isFalse);
    expect(cooldown.remainingSeconds, 0);

    cooldown.startFor(const Duration(seconds: 5));
    cooldown.startFor(const Duration(days: 10), notify: false);
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(notifications, 1);
    expect(cooldown.active, isTrue);

    cooldown.clear(notify: false);
    expect(notifications, 1);
    expect(cooldown.active, isFalse);
    cooldown.clear();
    expect(notifications, 2);

    cooldown.start({'cooldown': 1}, notify: false);
    cooldown.dispose();
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(notifications, 2);
    expect(cooldown.active, isFalse);
    expect(cooldown.remainingSeconds, 0);
  });

  testWidgets(
    'restart inside a countdown callback leaves no timer on disposal',
    (tester) async {
      var now = DateTime.utc(2026, 11, 3);
      var notifications = 0;
      late RetryCooldown cooldown;
      cooldown = RetryCooldown(() {
        notifications++;
        if (notifications == 1) {
          cooldown.startFor(const Duration(days: 2), notify: false);
        }
      }, now: () => now);
      try {
        cooldown.startFor(const Duration(seconds: 1), notify: false);
        now = now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(notifications, 1);
        expect(cooldown.active, isTrue);
        expect(cooldown.remainingSeconds, 3600);
      } finally {
        cooldown.dispose();
      }
      expect(cooldown.active, isFalse);
      expect(cooldown.remainingSeconds, 0);
    },
  );
}
