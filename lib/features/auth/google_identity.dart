abstract interface class GoogleIdentityProvider {
  bool get isAvailable;
  Future<String?> authenticate();
}

class GoogleIdentityException implements Exception {
  const GoogleIdentityException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BuyerGoogleConfiguration {
  const BuyerGoogleConfiguration({
    this.enabled = false,
    this.serverClientId = '',
    this.iosClientId = '',
  });
  const BuyerGoogleConfiguration.fromEnvironment()
    : enabled = const bool.fromEnvironment('BAGOO_GOOGLE_ENABLED'),
      serverClientId = const String.fromEnvironment(
        'BAGOO_GOOGLE_SERVER_CLIENT_ID',
      ),
      iosClientId = const String.fromEnvironment('BAGOO_GOOGLE_IOS_CLIENT_ID');

  final bool enabled;
  final String serverClientId, iosClientId;
  static bool validClientId(String value) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,199}\.apps\.googleusercontent\.com$')
          .hasMatch(value);

  bool availableFor(String platform) =>
      enabled &&
      validClientId(serverClientId) &&
      (platform == 'android' ||
          platform == 'ios' && validClientId(iosClientId));
}
