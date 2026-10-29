import 'package:bagoo_buyer_mobile/features/auth/google_identity.dart';
import 'package:bagoo_buyer_mobile/features/auth/native_google_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('configuration requires explicit enablement and correct native public client IDs', () {
    const configured = BuyerGoogleConfiguration(
      enabled: true,
      serverClientId: 'server.apps.googleusercontent.com',
      iosClientId: 'ios.apps.googleusercontent.com',
    );
    expect(configured.availableFor('android'), isTrue);
    expect(configured.availableFor('ios'), isTrue);
    for (final platform in ['linux', 'web', 'windows', 'macos']) {
      expect(configured.availableFor(platform), isFalse);
    }
    expect(
      const BuyerGoogleConfiguration(
        serverClientId: 'server.apps.googleusercontent.com',
      ).availableFor('android'),
      isFalse,
    );
    expect(
      const BuyerGoogleConfiguration(
        enabled: true,
        serverClientId: 'not-a-client',
      ).availableFor('android'),
      isFalse,
    );
    expect(
      const BuyerGoogleConfiguration(
        enabled: true,
        serverClientId: 'server.apps.googleusercontent.com',
      ).availableFor('ios'),
      isFalse,
    );
  });

  test(
    'an unconfigured provider fails safely before invoking native SDK code',
    () async {
      final provider = NativeGoogleIdentityProvider();
      expect(provider.isAvailable, isFalse);
      await expectLater(
        provider.authenticate(),
        throwsA(isA<GoogleIdentityException>()),
      );
    },
  );
}
