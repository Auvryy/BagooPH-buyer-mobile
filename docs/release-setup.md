# Owner setup for native Google and release builds

The native Google SDK, account-link proof and buyer registration are implemented. They require owner configuration and a backend reporting native Google capability. Linux keeps email sign-in and the buyer screens available; Google sign-in is supported on Android/iOS only. Physical Android acceptance is deferred until the owner connects a phone. iOS needs macOS/Xcode.

## Public configuration

From the mobile repository root:

```sh
cp config/buyer.example.json config/buyer.local.json
dart run tool/buyer.dart check --config config/buyer.local.json --platform linux
dart run tool/buyer.dart run --config config/buyer.local.json --platform linux --device linux
```

The local file is ignored. Its four allowlisted values are **public and bundled in the app**. Never put client secrets, signing passwords, API tokens, private keys or service-account JSON in it. Unknown keys are rejected. Set `BAGOO_BASE_URL` to the reachable buyer origin, with no `/api` suffix, query or credentials. Android emulators usually reach the development computer through `http://10.0.2.2:8000`; a physical phone needs its own reachable origin. Start the backend separately using its repository instructions.

The helper derives Android's `BAGOO_LINK_HOST` and iOS's ignored `ios/Flutter/Bagoo.local.xcconfig` from that origin. It also derives the iOS Google callback scheme. `check` validates without writing native files or contacting services. Release checks require HTTPS on port 443 with a hostname beyond the supplied development placeholders. Syntactic validation does not establish ownership or deployment readiness.

## Find the Google client IDs

Reuse the existing Bagoo Google Cloud project. Open [Google Auth Platform → Clients](https://console.cloud.google.com/auth/clients) and select that project.

1. Open the existing **Web application** registration. Its public client ID ending `.apps.googleusercontent.com` is `BAGOO_GOOGLE_SERVER_CLIENT_ID`. This is the server audience used by the native SDK; coordinate its allowlist with the backend owner. The web client's secret stays on the server.
2. Add an **Android** OAuth client if this package/signing identity is not already registered: package `shop.bagooph.bagoo_buyer_mobile`, with the SHA-1 of the certificate signing the installed app. Debug, owner release and Google Play app-signing certificates can require separate client registrations. The Android OAuth ID itself is not a Dart setting. Use the Web client ID above as `serverClientId`.
3. For iOS, register bundle ID `shop.bagooph.bagooBuyerMobile` and put its public iOS client ID in `BAGOO_GOOGLE_IOS_CLIENT_ID`. The helper reverses it into the required URL scheme. Run the iOS build through the helper or configure the equivalent Xcode settings explicitly.
4. Set `BAGOO_GOOGLE_ENABLED` to JSON boolean `true` only after these registrations and backend setup are approved. Backend capability must also be true. A disabled, malformed or unsupported capability keeps the Google button unavailable.

The app uses `google_sign_in` 7.2.0. It requests identity through the native SDK after a buyer taps Continue with Google. It does not use browser OAuth redirects, silently select an identity or persist the provider ID token. Existing-account linking needs explicit Bagoo password proof; new buyers complete native personal details, adult birth date and current policies. The backend owns identity, account role and approval. New Google registration does not grant checkout approval.

References: [Android plugin setup](https://pub.dev/packages/google_sign_in_android), [iOS plugin setup](https://pub.dev/packages/google_sign_in_ios), [Google certificate authentication](https://developers.google.com/android/guides/client-auth). The official, unmodified G logo in `assets/auth/google-g.png` comes from [Google Identity branding](https://developers.google.com/identity/branding-guidelines).

## Android signing and installed-app links

Copy `android/key.properties.example` to ignored `android/key.properties` and supply your owner-managed release keystore and credentials locally. Paths are absolute or relative to `android/app`. The build never falls back to the debug signing configuration for release. Missing/incomplete signing, a missing keystore or the known debug key blocks release tasks. Actual keystore validity is checked by Android's signing tools.

Use the certificate of the installed app for provider and association configuration. Google OAuth uses its SHA-1; Android App Links use SHA-256. For Play distribution, use the Play **app-signing** certificate for the installed app, which can differ from the upload certificate. Keep the private key under owner control; no release key is generated or published by this work.

```sh
dart run tool/buyer.dart check --config config/buyer.local.json --platform android --release
dart run tool/buyer.dart apk --config config/buyer.local.json --platform android
dart run tool/buyer.dart appbundle --config config/buyer.local.json --platform android
```

The backend owner must publish `https://<BUYER_HOST>/.well-known/assetlinks.json` for package `shop.bagooph.bagoo_buyer_mobile` and the approved SHA-256 certificate. It must return directly over HTTPS without authentication or redirects. Verify it against the certificate of the installed release. See [Flutter's signing guide](https://docs.flutter.dev/deployment/android) and [Android App Links verification](https://developer.android.com/training/app-links/verify-android-applinks).

## iOS signing and links

On macOS, select the approved Apple development team and provisioning profile in Xcode. Provision Associated Domains and the existing Keychain capability. Publish `https://<BUYER_HOST>/.well-known/apple-app-site-association` with the actual team ID and `shop.bagooph.bagooBuyerMobile`, with the buyer-only paths agreed with the backend owner.

```sh
dart run tool/buyer.dart ios --config config/buyer.local.json --platform ios
```

This is a signed iOS build; it requires Xcode and owner signing. For a compile-only check on macOS, add `--no-codesign` to that helper command. Compilation alone does not verify Google callbacks or installed links. Restore/change local settings when switching environments. Direct Flutter commands do not synchronize native link/callback settings automatically.

## Device and deployed buyer acceptance

Use approved test accounts and a non-production acceptance environment for write journeys. Record the actual host/build/device and outcome; isolated fixtures do not prove a deployed contract. Never report a successful purchase or payment from client navigation alone.

| Journey | Required evidence |
|---|---|
| Google configuration | Matching Web audience, Android signing registration, iOS callback; backend capability true |
| Existing Google buyer | Native chooser, confirmed buyer session, original Bagoo email and intended remember behavior |
| Password buyer first link | Separate explicit password confirmation; wrong proof stays editable; no silent merge |
| New Google buyer | Native adult-date/policy form, field errors, expiry, registration session rotation; checkout remains gated |
| Cancellation and interruptions | Cancel chooser, background/resume, network loss, rate limit and session switch; drafts/recovery behave correctly and no POST is replayed automatically |
| Email regression | Existing email login, registration, recovery, logout and restored-session behavior |
| Browse and Bag | Guest browse, search, product/options, save/follow and owned Bag changes |
| Approved checkout | Server quote, address/logistics/voucher review, explicit placement and payment confirmation |
| After purchase | Server order timeline, permitted receipt/cancel actions, returns, chat/support and notifications |
| Installed links | Cold/warm Android/iOS HTTPS links, signed-out private destination, foreign/action links rejected |
| Native behavior | Picker/PDF, GPS, sharing/scanning, keyboard, large text, screen reader and real-phone navigation |

Current release prerequisites are still pending: approved buyer hostname, public client registrations, owner release certificates/Apple team, deployed endpoint/association acceptance and physical devices. Device push remains a separate deferred feature. This mobile task changes no backend source, configuration, database or Git state.
