import 'package:bagoo_buyer_mobile/features/auth/google_identity.dart';

class FakeGoogleIdentity implements GoogleIdentityProvider {
  FakeGoogleIdentity({this.isAvailable = true, this.onAuthenticate});
  @override
  final bool isAvailable;
  Future<String?> Function()? onAuthenticate;
  int calls = 0;
  @override
  Future<String?> authenticate() async {
    calls++;
    return onAuthenticate == null ? 'synthetic-id-token' : onAuthenticate!();
  }
}
