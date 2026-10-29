DateTime verificationCooldownDeadline(
  Map<String, dynamic> data, {
  DateTime? retryAt,
  DateTime? now,
}) {
  final instant = now ?? DateTime.now();
  final value = data['cooldown'];
  final seconds =
      value is num && value.isFinite && value > 0 && value <= 315360000
      ? value.ceil()
      : 60;
  final deadline = instant.add(Duration(seconds: seconds));
  return retryAt != null && retryAt.isAfter(deadline) ? retryAt : deadline;
}
