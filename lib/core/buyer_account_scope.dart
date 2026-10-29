import 'web_session.dart';

/// Binds private UI work to the session and buyer that opened it. Server
/// authorization remains authoritative for every resource and mutation.
class BuyerAccountScope {
  BuyerAccountScope(this.session) : _epoch = session.identityEpoch;
  final WebSession session;
  final int _epoch;
  int? _owner;
  bool _invalid = false;

  bool get isCurrent => !_invalid && _epoch == session.identityEpoch;

  void invalidate() => _invalid = true;

  void check({WebPage? page}) {
    final owner = page?.user?['id'];
    if (!isCurrent ||
        page != null &&
            (page.user?['role'] != 'buyer' ||
                owner is! int ||
                owner < 1 ||
                _owner != null && owner != _owner)) {
      _invalid = true;
      throw const BackendException(
        'Your buyer account changed or access ended. Reopen this screen from your account.',
        status: 401,
      );
    }
    if (page != null) _owner ??= owner as int;
  }
}
