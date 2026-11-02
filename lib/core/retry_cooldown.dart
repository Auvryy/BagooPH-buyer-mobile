import 'dart:async';

import 'verification_cooldown.dart';

/// Tracks a server retry deadline without polling continuously while inactive.
class RetryCooldown {
  RetryCooldown(this.onChanged, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final void Function() onChanged;
  final DateTime Function() _now;
  Timer? _timer;
  DateTime? _until;

  bool get active => _until?.isAfter(_now()) == true;
  int get remainingSeconds => _until == null
      ? 0
      : verificationCooldownSecondsUntil(_until!, now: _now());

  void start(
    Map<String, dynamic> data, {
    DateTime? retryAt,
    bool notify = true,
  }) {
    final now = _now();
    _setUntil(
      verificationCooldownDeadline(data, retryAt: retryAt, now: now),
      notify: notify,
    );
  }

  void startFor(Duration duration, {bool notify = true}) {
    final milliseconds = duration.inMilliseconds;
    final bounded = milliseconds < 0
        ? 0
        : milliseconds > 315360000000
        ? 315360000000
        : milliseconds;
    _setUntil(_now().add(Duration(milliseconds: bounded)), notify: notify);
  }

  void clear({bool notify = true}) {
    _timer?.cancel();
    _timer = null;
    _until = null;
    if (notify) onChanged();
  }

  void _setUntil(DateTime until, {required bool notify}) {
    _timer?.cancel();
    _timer = null;
    _until = until;
    if (notify) onChanged();
    _schedule();
  }

  void _schedule() {
    final until = _until;
    if (until == null || !until.isAfter(_now())) {
      _timer?.cancel();
      _timer = null;
      return;
    }

    final actualRemaining = until.difference(_now());
    final visibleTransition = actualRemaining > const Duration(hours: 1)
        ? actualRemaining - const Duration(hours: 1)
        : const Duration(seconds: 1);
    final delay = visibleTransition > const Duration(days: 1)
        ? const Duration(days: 1)
        : visibleTransition;
    _timer = Timer(delay, () {
      if (_until != until) return;
      if (!until.isAfter(_now())) _until = null;
      onChanged();
      _schedule();
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _until = null;
  }
}
