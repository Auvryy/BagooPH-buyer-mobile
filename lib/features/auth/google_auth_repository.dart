import 'dart:convert';

import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import 'google_auth_contract.dart';

class GoogleAuthRepository {
  GoogleAuthRepository(this.buyer, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final BuyerRepository buyer;
  final DateTime Function() now;
  DateTime? retryAt;
  int? _epoch;
  bool _remember = false;
  bool _active = false;

  Future<void> begin({required bool remember}) async {
    _checkRetry();
    await buyer.session.prepareAuthentication();
    _epoch = buyer.session.identityEpoch;
    _remember = remember;
    _active = true;
  }

  void abandon() {
    _active = false;
    _epoch = null;
    _remember = false;
  }

  void _check() {
    if (!_active || _epoch != buyer.session.identityEpoch) {
      throw const BackendException(
        'Your session changed. Start Google sign-in again.',
        status: 401,
      );
    }
  }

  void _checkRetry() {
    if (retryAt != null && now().isBefore(retryAt!)) {
      throw BackendException(
        'Please wait before trying Google again.',
        status: 429,
        retryAt: retryAt,
      );
    }
  }

  Future<GoogleAuthOutcome> exchange(
    String idToken, {
    String? accountPassword,
  }) async {
    _check();
    if (idToken.isEmpty ||
        utf8.encode(idToken).length > 16384 ||
        (accountPassword != null && accountPassword.length > 255)) {
      throw const BackendException(
        'Start Google sign-in again with a valid account.',
      );
    }
    final result = await _write('/auth/google/native', {
      'id_token': idToken,
      'remember': _remember,
      'account_password': ?accountPassword,
    });
    _check();
    if (result.length == 1 && result['authenticated'] == true) {
      return _confirmed();
    }
    if (result.length == 1 && result['registration_required'] == true) {
      try {
        return GoogleAuthOutcome.registration(await registration());
      } on BackendException {
        throw const GoogleAuthUncertain();
      }
    }
    throw const GoogleAuthUncertain();
  }

  Future<GoogleRegistrationContract> registration() async {
    _check();
    _checkRetry();
    Map<String, dynamic> data;
    try {
      data = await buyer.session.jsonGetDirect(
        '/auth/google/native/registration',
      );
    } on BackendException catch (error) {
      if (error.status == 429) {
        retryAt = error.retryAt ?? now().add(const Duration(minutes: 1));
      }
      rethrow;
    }
    _check();
    return GoogleRegistrationContract.parse(data, buyer.session);
  }

  Future<GoogleAuthOutcome> complete(
    GoogleRegistrationContract contract,
    Map<String, dynamic> values,
  ) async {
    _check();
    // Identity, role, approval and provider claims are never client writers.
    const fields = {
      'first_name',
      'last_name',
      'middle_initial',
      'sex',
      'birthday',
      'phone',
      'address',
      'region',
      'province',
      'city',
      'municipality',
      'barangay',
      'postal_code',
    };
    final result = await _write('/auth/google/native/register', {
      for (final entry in values.entries)
        if (fields.contains(entry.key)) entry.key: entry.value,
      'registration_nonce': contract.nonce,
      'policy_accepted': values['policy_accepted'] == true,
      'terms_version': contract.policies['terms_version'],
      'privacy_version': contract.policies['privacy_version'],
    });
    _check();
    if (result.length != 1 || result['authenticated'] != true) {
      throw const GoogleAuthUncertain();
    }
    return _confirmed(expectedEmail: contract.email);
  }

  Future<Map<String, dynamic>> _write(
    String path,
    Map<String, dynamic> values,
  ) async {
    _check();
    _checkRetry();
    try {
      return await buyer.session.jsonPostDirect(path, values);
    } on BackendException catch (error) {
      if (error.status == 429) {
        retryAt = error.retryAt ?? now().add(const Duration(minutes: 1));
      }
      if (error.connectionFailure ||
          error.status == null ||
          (error.status != null && error.status! >= 500) ||
          (error.status != null &&
              error.status! >= 300 &&
              error.status! < 400) ||
          error.data['code'] == 'ALREADY_AUTHENTICATED') {
        throw const GoogleAuthUncertain();
      }
      rethrow;
    }
  }

  Future<GoogleAuthOutcome> _confirmed({
    String? expectedEmail,
    WebPage? confirmedPage,
  }) async {
    try {
      _check();
      final page = confirmedPage ?? await buyer.currentSession();
      _check();
      if (page == null ||
          expectedEmail != null &&
              page.user?['email']?.toString().toLowerCase() !=
                  expectedEmail.toLowerCase()) {
        throw const GoogleAuthUncertain();
      }
      // The original Bagoo email comes from the confirmed backend, not Google.
      await buyer.session.rememberAuthentication(
        _remember,
        page.user?['email'] is String ? page.user!['email'] : '',
      );
      _check();
      return GoogleAuthOutcome.authenticated(page);
    } on BackendException {
      throw const GoogleAuthUncertain();
    }
  }

  /// Explicit read-only recovery; never retries the preceding exchange/register.
  Future<GoogleAuthOutcome> recover({
    GoogleRegistrationContract? previous,
  }) async {
    _check();
    final page = await buyer.currentSession();
    _check();
    if (page != null) {
      return _confirmed(expectedEmail: previous?.email, confirmedPage: page);
    }
    return GoogleAuthOutcome.registration(await registration());
  }
}
