import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';

import '../../core/web_session.dart';

class NativeGoogleSignIn {
  NativeGoogleSignIn._();

  static final NativeGoogleSignIn instance = NativeGoogleSignIn._();
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  final GoogleSignIn _google = GoogleSignIn.instance;
  Future<void>? _initialization;

  Future<String?> requestIdToken() async {
    if (!isSupported) return null;

    const serverClientId = String.fromEnvironment(
      'BAGOO_GOOGLE_SERVER_CLIENT_ID',
    );
    const iosClientId = String.fromEnvironment('BAGOO_GOOGLE_IOS_CLIENT_ID');
    if (serverClientId.isEmpty || (Platform.isIOS && iosClientId.isEmpty)) {
      throw const BackendException(
        'Google sign-in is not configured for this build. Add the Bagoo Android/iOS OAuth client IDs and try again.',
      );
    }

    _initialization ??= _google.initialize(
      serverClientId: serverClientId,
      clientId: Platform.isIOS ? iosClientId : null,
    );
    await _initialization;
    if (!_google.supportsAuthenticate()) {
      throw const BackendException(
        'Google sign-in is available in the Android and iOS apps.',
      );
    }

    try {
      final account = await _google.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw const BackendException(
          'Google did not return a sign-in token. Check the app OAuth configuration and try again.',
        );
      }
      return token;
    } on GoogleSignInException catch (exception) {
      if (exception.code == GoogleSignInExceptionCode.canceled) return null;
      throw const BackendException(
        'Google sign-in could not finish. Check your connection and try again.',
      );
    }
  }

  Future<void> signOut() async {
    if (_initialization == null || !isSupported) return;
    try {
      await _google.signOut();
    } on GoogleSignInException {
      // Ending the Bagoo session must remain successful if Google is offline.
    }
  }
}
