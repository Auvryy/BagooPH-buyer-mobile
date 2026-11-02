import 'package:bagoo_buyer_mobile/core/retry_cooldown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late RetryCooldown cooldown;
  var notifications = 0;

  setUp(() {
    now = DateTime.utc(2026, 11, 3);
    notifications = 0;
    cooldown = RetryCooldown(() => notifications++, now: () => now);
  });
  tearDown(() => cooldown.dispose());

  test('uses the longer server cooldown or Retry-After', () {
    cooldown.start({
      'cooldown': 10,
    }, retryAt: now.add(const Duration(seconds: 45)));
    expect(cooldown.active, isTrue);
    expect(cooldown.remainingSeconds, 45);

    now = now.add(const Duration(seconds: 45));
    expect(cooldown.active, isFalse);
    expect(cooldown.remainingSeconds, 0);
  });

  test('keeps the full deadline while capping the displayed countdown', () {
    cooldown.start({'cooldown': 7200});
    expect(cooldown.remainingSeconds, 3600);

    now = now.add(const Duration(hours: 1));
    expect(cooldown.active, isTrue);
    expect(cooldown.remainingSeconds, 3600);

    now = now.add(const Duration(hours: 1));
    expect(cooldown.active, isFalse);
    expect(cooldown.remainingSeconds, 0);
  });

  test('malformed deadlines use a safe fallback and clear cleanly', () {
    cooldown.start({'cooldown': double.infinity});
    expect(cooldown.active, isTrue);
    expect(cooldown.remainingSeconds, 60);

    cooldown.clear();
    expect(cooldown.active, isFalse);
    expect(cooldown.remainingSeconds, 0);
    expect(notifications, 2);
  });
}
