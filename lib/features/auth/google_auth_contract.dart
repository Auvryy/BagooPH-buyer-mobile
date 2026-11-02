import '../../core/strict_datetime.dart';
import '../../core/web_session.dart';
import 'registration_policy_contract.dart';

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
    final policies = checkedBuyerRegistrationPolicies(
      data['policies'],
      session,
    );
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
        policies == null) {
      throw const BackendException(
        'Google registration details are unavailable. Start Google sign-in again or use email.',
      );
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
      policies: Map.unmodifiable({'required': true, ...policies}),
    );
  }

  final String name, email, nonce;
  final DateTime expiresAt, adultMaximum;
  final Map<String, dynamic> policies;
  bool expired(DateTime now) => !expiresAt.isAfter(now);

  static DateTime? _calendarDate(Object? value) {
    return strictDateOnly(value);
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
