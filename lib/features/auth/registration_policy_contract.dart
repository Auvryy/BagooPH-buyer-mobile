import '../../core/web_session.dart';

Map<String, String>? checkedBuyerRegistrationPolicies(
  Object? value,
  WebSession session,
) {
  if (value is! Map || value.keys.any((key) => key is! String)) return null;
  final policies = Map<String, dynamic>.from(value);
  if (policies['required'] != true) return null;

  final termsVersion = policies['terms_version'];
  final privacyVersion = policies['privacy_version'];
  if (!_validVersion(termsVersion) || !_validVersion(privacyVersion)) {
    return null;
  }
  final termsUrl = policies['terms_url'];
  final privacyUrl = policies['privacy_url'];
  if (!_isPolicyUrl(session, termsUrl, '/terms/$termsVersion') ||
      !_isPolicyUrl(session, privacyUrl, '/privacy/$privacyVersion')) {
    return null;
  }
  return {
    'terms_version': termsVersion as String,
    'privacy_version': privacyVersion as String,
    'terms_url': termsUrl as String,
    'privacy_url': privacyUrl as String,
  };
}

bool _validVersion(Object? value) =>
    value is String && RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(value);

bool _isPolicyUrl(WebSession session, Object? value, String expectedPath) {
  if (value is! String || value.trim() != value || value.isEmpty) return false;
  try {
    final target = session.resolve(value);
    return target.path == expectedPath && !target.hasFragment;
  } on BackendException {
    return false;
  }
}
