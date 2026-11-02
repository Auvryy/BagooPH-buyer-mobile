int verificationCooldownSeconds(Map<String, dynamic> data) {
  final value = data['cooldown'];
  return value is num && value.isFinite && value > 0 && value <= 315360000
      ? value.ceil()
      : 60;
}

DateTime verificationCooldownDeadline(
  Map<String, dynamic> data, {
  DateTime? retryAt,
  DateTime? now,
}) {
  final instant = now ?? DateTime.now();
  final seconds = verificationCooldownSeconds(data);
  final deadline = instant.add(Duration(seconds: seconds));
  return retryAt != null && retryAt.isAfter(deadline) ? retryAt : deadline;
}

int verificationCooldownRemainingSeconds(
  Map<String, dynamic> data, {
  DateTime? retryAt,
  DateTime? now,
}) {
  final instant = now ?? DateTime.now();
  final deadline = verificationCooldownDeadline(
    data,
    retryAt: retryAt,
    now: instant,
  );
  return verificationCooldownSecondsUntil(deadline, now: instant);
}

int verificationCooldownSecondsUntil(DateTime deadline, {DateTime? now}) {
  final instant = now ?? DateTime.now();
  final milliseconds = deadline.difference(instant).inMilliseconds;
  if (milliseconds <= 0) return 0;
  final seconds = (milliseconds + 999) ~/ 1000;
  return seconds > 3600 ? 3600 : seconds;
}
