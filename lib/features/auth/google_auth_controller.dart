import 'package:flutter/foundation.dart';

import '../../core/web_session.dart';
import 'google_auth_contract.dart';
import 'google_auth_repository.dart';
import 'google_identity.dart';

enum GoogleAuthStage {
  choosing,
  link,
  registration,
  uncertain,
  error,
  canceled,
  authenticated,
}

class GoogleAuthController extends ChangeNotifier {
  GoogleAuthController({required this.repository, required this.provider});
  final GoogleAuthRepository repository;
  final GoogleIdentityProvider provider;
  GoogleAuthStage stage = GoogleAuthStage.choosing;
  GoogleRegistrationContract? registration;
  WebPage? authenticatedPage;
  String? error;
  Map<String, String> fields = {};
  bool busy = false;
  bool _disposed = false;
  int _generation = 0;
  String? _idToken;
  bool get coolingDown => repository.retryAt?.isAfter(repository.now()) == true;
  int get retrySeconds => coolingDown
      ? (repository.retryAt!.difference(repository.now()).inMilliseconds / 1000)
            .ceil()
      : 0;
  bool get challengeExpired => registration?.expired(repository.now()) == true;
  bool get canSubmit => !busy && !coolingDown && !challengeExpired;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void tick() {
    if (coolingDown || registration != null || repository.retryAt != null) {
      _notify();
    }
  }

  void clearField(String key) {
    fields = Map.of(fields)..remove(key);
    _notify();
  }

  Future<void> start({required bool remember}) async {
    if (busy || coolingDown || _disposed) return;
    final ticket = ++_generation;
    final previousEpoch = repository.buyer.session.identityEpoch;
    busy = true;
    error = null;
    fields = {};
    registration = null;
    _idToken = null;
    stage = GoogleAuthStage.choosing;
    _notify();
    try {
      final capabilities = await repository.buyer.discoverCapabilities();
      if (_disposed || ticket != _generation) return;
      if (!provider.isAvailable || !capabilities.nativeGoogleSignIn) {
        throw const GoogleIdentityException(
          'Google sign-in is unavailable. You can still sign in with email.',
        );
      }
      final token = await provider.authenticate();
      if (_disposed || ticket != _generation) return;
      if (repository.buyer.session.identityEpoch != previousEpoch) {
        throw const BackendException(
          'Your session changed. Start sign-in again.',
          status: 401,
        );
      }
      if (token == null) {
        stage = GoogleAuthStage.canceled;
        return;
      }
      _idToken = token;
      await repository.begin(remember: remember);
      if (_disposed || ticket != _generation) return;
      _apply(await repository.exchange(token));
    } on GoogleAuthUncertain {
      if (!_disposed && ticket == _generation) _uncertain();
    } on BackendException catch (e) {
      if (!_disposed && ticket == _generation) _failure(e);
    } on GoogleIdentityException catch (e) {
      if (!_disposed && ticket == _generation) {
        error = e.message;
        stage = GoogleAuthStage.error;
      }
    } finally {
      if (!_disposed && ticket == _generation) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> link(String password) async {
    if (_idToken == null || stage != GoogleAuthStage.link) return;
    await _run(() => repository.exchange(_idToken!, accountPassword: password));
  }

  Future<void> complete(Map<String, dynamic> values) async {
    final contract = registration;
    if (contract == null ||
        stage != GoogleAuthStage.registration ||
        challengeExpired) {
      return;
    }
    await _run(() => repository.complete(contract, values));
  }

  Future<void> recover() =>
      _run(() => repository.recover(previous: registration), readsOnly: true);

  Future<void> refreshRegistration() => _run(
    () async => GoogleAuthOutcome.registration(await repository.registration()),
    readsOnly: true,
  );

  Future<void> _run(
    Future<GoogleAuthOutcome> Function() action, {
    bool readsOnly = false,
  }) async {
    if (busy || _disposed || !readsOnly && coolingDown) return;
    final ticket = ++_generation;
    busy = true;
    error = null;
    fields = {};
    _notify();
    try {
      _apply(await action());
    } on GoogleAuthUncertain {
      if (!_disposed && ticket == _generation) _uncertain();
    } on BackendException catch (e) {
      if (!_disposed && ticket == _generation) _failure(e);
    } finally {
      if (!_disposed && ticket == _generation) {
        busy = false;
        _notify();
      }
    }
  }

  void _apply(GoogleAuthOutcome outcome) {
    if (_disposed) return;
    error = null;
    fields = {};
    if (outcome.page != null) {
      authenticatedPage = outcome.page;
      registration = null;
      _idToken = null;
      stage = GoogleAuthStage.authenticated;
    } else {
      registration = outcome.registration;
      _idToken = null;
      stage = GoogleAuthStage.registration;
    }
  }

  void _uncertain() {
    _idToken = null;
    stage = GoogleAuthStage.uncertain;
    error = 'We could not confirm the result. Check your sign-in status before starting again.';
  }

  void _failure(BackendException e) {
    error = e.message;
    fields = Map.of(e.fields);
    if (e.status == 409 &&
        e.data['code'] == 'GOOGLE_ACCOUNT_LINK_REQUIRED' &&
        _idToken != null) {
      stage = GoogleAuthStage.link;
    } else if ([401, 419, 403].contains(e.status)) {
      _idToken = null;
      registration = null;
      repository.abandon();
      stage = GoogleAuthStage.error;
    } else if (stage == GoogleAuthStage.uncertain &&
        (e.connectionFailure || e.status == null || e.status! >= 500)) {
      // A failed status read cannot resolve the preceding uncertain write.
    } else if (e.status == 422 &&
        stage == GoogleAuthStage.registration &&
        (e.fields.containsKey('email') ||
            e.fields.containsKey('registration_nonce'))) {
      stage = GoogleAuthStage.uncertain;
    } else if (e.status == 422 &&
        stage == GoogleAuthStage.link &&
        e.fields.containsKey('account_password')) {
      // Keep the in-memory proof step editable for an explicit correction.
    } else if (e.status == 422 && registration != null ||
        e.status == 429 && registration != null) {
      stage = GoogleAuthStage.registration;
    } else {
      stage = GoogleAuthStage.error;
      _idToken = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _idToken = null;
    registration = null;
    authenticatedPage = null;
    fields = {};
    repository.abandon();
    super.dispose();
  }
}
