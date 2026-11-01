import 'web_session.dart';

/// Binds private UI work to the session and buyer that opened it. Server
/// authorization remains authoritative for every resource and mutation.
class BuyerAccountScope {
  BuyerAccountScope(this.session)
    : _epoch = session.identityEpoch,
      _parent = null;
  BuyerAccountScope._from(BuyerAccountScope parent)
    : session = parent.session,
      _epoch = parent._epoch,
      _owner = parent._owner,
      _parent = parent;
  final WebSession session;
  final int _epoch;
  final BuyerAccountScope? _parent;
  int? _owner;
  bool _invalid = false;

  bool get isCurrent =>
      !_invalid &&
      _epoch == session.identityEpoch &&
      (_parent?.isCurrent ?? true);

  // A child retains the opening identity across a delayed route build, while
  // closing that child must not invalidate its parent's private screen.
  BuyerAccountScope fork() => BuyerAccountScope._from(this);

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
