# BagooPH Buyer Mobile

Native Flutter buyer authentication and marketplace home, using the existing BagooPH Laravel backend. Android and iOS targets are included.

## Included

- Buyer email/password login and server-confirmed logout.
- Two-step registration, server validation, current Terms/Privacy documents, adult birth-date selection, and emailed verification codes.
- Password recovery with email-code verification and a new password.
- Guest browsing and signed-in home with real products, departments, campaigns when configured, search, sorting, pagination, refresh, empty states, and retry.
- Product summary sheets and account status. Pending buyers can browse; approval and checkout permissions remain server-owned.
- Original BagooPH branding, bundled Plus Jakarta Sans, and responsive phone/tablet layouts.

Delivery addresses, identity-document submission, full product/variant purchasing, Shopping Bag, checkout, order management, and Google OAuth remain in the buyer web app. Registration may omit the optional address and document fields. This app never creates a local account or accepts a locally generated verification code.

## Requirements

- Flutter stable with Dart SDK `^3.13.1`; installed dependencies are locked in `pubspec.lock`.
- Android SDK and a compatible JDK for Android builds.
- macOS and Xcode for iOS builds.
- The existing BagooPH backend, with its buyer web origin accessible from the device. Start/configure it using that repository's README. Email-code flows require working backend mail delivery.

## Run

```sh
flutter pub get
flutter devices
flutter run -d <DEVICE_ID>
```

In debug builds, Android defaults to the emulator's host alias `http://10.0.2.2:8000`; other native platforms default to `http://localhost:8000`. Android permits cleartext networking only in the debug manifest. A physical device needs a reachable backend origin:

```sh
flutter run -d <DEVICE_ID> --dart-define=BAGOO_BASE_URL='https://<BUYER_HOST>'
```

Use the buyer origin with no path, query, credentials, or `/api` suffix. Backend cookie domain and secure-cookie settings must match that origin. iOS development should use a trusted HTTPS origin. Release builds require an explicitly configured HTTPS origin; the app shows a configuration error if it is missing or invalid.

## Backend integration

The current backend has native rider endpoints, while buyer auth/home are Laravel web-session and Inertia routes. This app uses those existing buyer contracts without backend changes:

| Purpose | Existing routes |
| --- | --- |
| Login / logout | `POST /login`, `POST /logout` |
| Registration requirements / validation / creation | `GET /register`, `POST /register/validate`, `POST /register` |
| Send / resend / verify email codes | `POST /otp/send`, `POST /otp/resend`, `POST /otp/verify` |
| Set recovered password | `POST /password/reset-otp` |
| Marketplace | `GET /` with search, category, sort, and page parameters |
| Account policies | Versioned URLs supplied by `GET /register` |

The adapter bootstraps CSRF and session cookies from the web page, reads Inertia props, refreshes the asset version after deployments, handles JSON validation errors, and follows redirects only within the configured origin. It never replays a failed mutation automatically. No credentials, cookies, or tokens are logged or written to disk. Sessions last only while the app process remains alive; reopening the app requires login.

This is a native Android/iOS client; Flutter web is not a configured target. The web-session adapter depends on the backend's existing Inertia contract. A future native buyer API can replace it behind `BuyerRepository`.

## Verification

```sh
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter build apk --debug
```

Run the optional read-only backend contract check against your running buyer origin:

```sh
dart run tool/check_backend.dart '<BACKEND_ORIGIN>'
```

The check reads home, registration requirements, policies, and filtered catalogue data. It never signs in, registers users, sends emails, or resets passwords. Automated auth/session tests use isolated fake responses and a temporary local HTTP server. Widget tests cover auth transitions, guest search, pagination state, phone/tablet layouts, landscape, and enlarged text. No live email or account mutations are performed by these checks.

For iOS on macOS, run `flutter build ios --no-codesign`. Review [the implementation plan](docs/plans/buyer-auth-home.md) for scope and verification evidence.
