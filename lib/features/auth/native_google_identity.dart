import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';

import 'google_identity.dart';

/// SDK state stays outside the plain-Dart session and backend repositories.
class NativeGoogleIdentityProvider implements GoogleIdentityProvider {
  NativeGoogleIdentityProvider({
    this.configuration = const BuyerGoogleConfiguration.fromEnvironment(),
  });
  final BuyerGoogleConfiguration configuration;
  static Future<void>? _initialization;
  static String? _initializationKey;
  static bool _authenticating = false;

  @override
  bool get isAvailable => configuration.availableFor(Platform.operatingSystem);

  @override
  Future<String?> authenticate() async {
    if (!isAvailable || _authenticating) {
      throw const GoogleIdentityException(
        'Google sign-in is unavailable on this device. Use email sign-in.',
      );
    }
    _authenticating = true;
    try {
      final key =
          '${configuration.serverClientId}|${configuration.iosClientId}';
      if (_initializationKey != null && _initializationKey != key) {
        throw const GoogleIdentityException(
          'Restart the app after changing Google setup.',
        );
      }
      _initializationKey = key;
      _initialization ??= GoogleSignIn.instance.initialize(
        serverClientId: configuration.serverClientId,
        clientId: Platform.isIOS ? configuration.iosClientId : null,
      );
      await _initialization;
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw const GoogleIdentityException(
          'Use email sign-in on this device.',
        );
      }
      // Explicit account selection only; no lightweight/silent authentication
      // or additional Google API scopes are requested.
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw const GoogleIdentityException(
          'Google could not confirm sign-in. Try again or use email.',
        );
      }
      return token;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      throw GoogleIdentityException(switch (error.code) {
        GoogleSignInExceptionCode.interrupted =>
          'Google sign-in was interrupted. Try again or use email.',
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          'Google sign-in is not set up for this app yet. Use email sign-in.',
        _ => 'Google sign-in is unavailable right now. Try again or use email.',
      });
    } on GoogleIdentityException {
      rethrow;
    } catch (_) {
      // SDK diagnostics can contain private provider details; do not expose them.
      throw const GoogleIdentityException(
        'Google sign-in could not start. Use email sign-in.',
      );
    } finally {
      _authenticating = false;
    }
  }
}
