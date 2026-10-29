/// Agreed version-one backend support, independent of installed native SDKs.
class BuyerCapabilities {
  const BuyerCapabilities.unavailable()
    : contractVersion = null,
      nativeGoogleSignIn = false,
      devicePush = false;

  const BuyerCapabilities._({
    required this.contractVersion,
    required this.nativeGoogleSignIn,
    required this.devicePush,
  });

  /// Invalid or unsupported replies never enable an optional capability.
  factory BuyerCapabilities.parse(Object? payload) {
    if (payload is! Map ||
        payload['contract_version'] is! int ||
        payload['contract_version'] != 1) {
      return const BuyerCapabilities.unavailable();
    }
    final features = payload['features'];
    if (features is! Map) return const BuyerCapabilities.unavailable();
    final google = features['native_google_sign_in'];
    final push = features['device_push'];
    if (google is! bool || push is! bool) {
      return const BuyerCapabilities.unavailable();
    }
    return BuyerCapabilities._(
      contractVersion: 1,
      nativeGoogleSignIn: google,
      devicePush: push,
    );
  }

  final int? contractVersion;
  final bool nativeGoogleSignIn, devicePush;

  bool get isSupported => contractVersion == 1;
}
