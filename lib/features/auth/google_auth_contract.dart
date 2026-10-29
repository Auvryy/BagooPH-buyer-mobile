import '../../core/web_session.dart';

class GoogleRegistrationContract {
  const GoogleRegistrationContract._({
    required this.name,
    required this.email,
    required this.nonce,
    required this.expiresAt,
    required this.adultMaximum,
    required this.policies,
  });

  factory GoogleRegistrationContract.parse(
    Map<String, dynamic> data,
    WebSession session,
  ) {
    final identity = mapOf(data['identity']);
    final nonce = data['registrationNonce'];
    final expiry = data['expiresAt'];
    final name = identity['name'], email = identity['email'];
    final dates = mapOf(data['birthDateLimits']);
    final policies = mapOf(data['policies']);
    final maximum = _calendarDate(dates['adult_maximum']);
    final today = _calendarDate(dates['today']);
    final past = _calendarDate(dates['past_maximum']);
    if (name is! String ||
        name.trim().isEmpty ||
        name.length > 255 ||
        email is! String ||
        email.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
        nonce is! String ||
        !RegExp(r'^[A-Za-z0-9]{40}$').hasMatch(nonce) ||
        expiry is! int ||
        expiry <= 0 ||
        expiry > 253402300799 ||
        maximum == null ||
        maximum.isBefore(DateTime(1900)) ||
        today == null ||
        past == null ||
        maximum.isAfter(past) ||
        !past.isBefore(today) ||
        policies['required'] is! bool ||
        !['terms_version', 'privacy_version', 'terms_url', 'privacy_url'].every(
          (key) =>
              policies[key] is String &&
              (policies[key] as String).trim().isNotEmpty &&
              (policies[key] as String).length <= 2048,
        )) {
      throw const BackendException(
        'Google registration details are unavailable. Start Google sign-in again or use email.',
      );
    }
    for (final key in ['terms_url', 'privacy_url']) {
      final target = session.resolve(policies[key]);
      if (target.hasFragment) {
        throw const BackendException(
          'The registration policy link is invalid.',
        );
      }
    }
    return GoogleRegistrationContract._(
      name: name,
      email: email,
      nonce: nonce,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiry * 1000,
        isUtc: true,
      ),
      adultMaximum: maximum,
      policies: Map.unmodifiable({
        for (final key in [
          'required',
          'terms_version',
          'privacy_version',
          'terms_url',
          'privacy_url',
        ])
          key: policies[key],
      }),
    );
  }

  final String name, email, nonce;
  final DateTime expiresAt, adultMaximum;
  final Map<String, dynamic> policies;
  bool expired(DateTime now) => !expiresAt.isAfter(now);

  static DateTime? _calendarDate(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final date = DateTime.tryParse(value);
    if (date == null || date.toIso8601String().substring(0, 10) != value) {
      return null;
    }
    return DateTime(date.year, date.month, date.day);
  }
}

class GoogleAuthOutcome {
  const GoogleAuthOutcome.authenticated(WebPage value)
    : page = value,
      registration = null;
  const GoogleAuthOutcome.registration(GoogleRegistrationContract value)
    : registration = value,
      page = null;
  final WebPage? page;
  final GoogleRegistrationContract? registration;
}

class GoogleAuthUncertain implements Exception {
  const GoogleAuthUncertain();
  @override
  String toString() => 'Check your sign-in status before trying again.';
}
