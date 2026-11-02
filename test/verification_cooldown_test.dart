import 'package:bagoo_buyer_mobile/core/verification_cooldown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 30);
  test('server code cooldown and a longer Retry-After are respected', () {
    expect(
      verificationCooldownDeadline({'cooldown': 900}, now: now),
      now.add(const Duration(minutes: 15)),
    );
    expect(
      verificationCooldownDeadline(
        {'cooldown': 30},
        now: now,
        retryAt: now.add(const Duration(minutes: 20)),
      ),
      now.add(const Duration(minutes: 20)),
    );
    expect(
      verificationCooldownDeadline({'cooldown': 59.1}, now: now),
      now.add(const Duration(seconds: 60)),
    );
  });
  test('malformed code cooldowns use a safe recoverable default', () {
    for (final value in [
      null,
      '900',
      -1,
      0,
      double.nan,
      double.infinity,
      1e300,
    ]) {
      expect(
        verificationCooldownDeadline({'cooldown': value}, now: now),
        now.add(const Duration(seconds: 60)),
        reason: '$value',
      );
    }
  });

  test('remaining code cooldown honors Retry-After and stays bounded', () {
    expect(
      verificationCooldownRemainingSeconds(
        {'cooldown': 10},
        retryAt: now.add(const Duration(seconds: 45)),
        now: now,
      ),
      45,
    );
    expect(
      verificationCooldownRemainingSeconds(
        {'cooldown': 90},
        retryAt: now.add(const Duration(seconds: 30)),
        now: now,
      ),
      90,
    );
    expect(
      verificationCooldownRemainingSeconds({'cooldown': 7200}, now: now),
      3600,
    );
    final longDeadline = now.add(const Duration(hours: 2));
    expect(verificationCooldownSecondsUntil(longDeadline, now: now), 3600);
    expect(
      verificationCooldownSecondsUntil(
        longDeadline,
        now: now.add(const Duration(hours: 1)),
      ),
      3600,
    );
    expect(
      verificationCooldownSecondsUntil(
        longDeadline,
        now: now.add(const Duration(hours: 2)),
      ),
      0,
    );
  });
}
