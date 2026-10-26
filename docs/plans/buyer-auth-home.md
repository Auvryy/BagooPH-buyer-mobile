# Buyer auth and home

## Scope and acceptance

- Start from `main` after `git pull origin main`; implement on `feat/buyer-auth-home`. Keep all commits local until the user requests a push.
- Preserve that branch workflow in `AGENTS.md`.
- Match the buyer web identity: Bagoo logo, crimson `#E00D42`, bundled Plus Jakarta Sans, white forms, split auth imagery on wide layouts, and the slate marketplace canvas.
- Provide native login, two-step buyer registration, registration email verification, password recovery, and navigation to home. Show server field errors, loading, retry, and confirmed outcomes; do not bypass authentication.
- Connect to existing web-session routes without backend changes. Inspect Laravel and Inertia contracts directly; configure the backend origin at build time. Keep session cookies in memory for this first pass, with no persistent credentials.
- Load real campaigns, categories, and products on home. Support guest browsing, search, sorting, category selection, pagination, refresh, empty states, and retry. Product inspection can show the real catalogue summary; checkout and broader buyer portal features are outside this auth/home scope.
- Respect server-owned account access and approval. Do not display fabricated products, ratings, orders, or successful mutations.
- Support narrow phones, landscape, tablets, large text, safe areas, and keyboards.

## Source references

Read from `../bagoo`: `resources/js/Pages/Auth/{Login,Register,ForgotPassword}.tsx`, `resources/js/Layouts/{GuestLayout,BuyerLayout}.tsx`, `resources/js/Pages/Buyer/Home.tsx`, buyer/auth controllers, `HandleInertiaRequests`, registration services, and route files. Reuse original auth imagery and logo. Reuse the licensed shared font from the rider app.

## Logical commits

1. Branch policy and implementation plan.
2. Shared Flutter theme/assets and existing backend session/data adapter.
3. Session redirect correction and isolated transport checks.
4. Native auth pages and account recovery flows.
5. Require explicit server confirmation for account mutations.
6. Buyer marketplace home, app navigation, setup documentation, and verification evidence.

## Verification

Run Dart formatting, static analysis, focused tests for network/session boundaries and auth/home interactions, and an Android debug build. Check the running local backend's actual response contracts. Use isolated fake responses for mutation tests; do not register accounts, send emails, reset passwords, or change shared development data for routine checks. No browser automation or screenshots requested.

## Status

Implementation complete on the working branch. The existing backend serves buyer pages over Inertia and cookie sessions; native rider tokens are not reused. The adapter handles the Inertia asset version, CSRF cookie, redirects, and JSON validation responses.

Before this work, the app showed only a placeholder label. It now provides native auth through to a connected marketplace with the web buyer identity. This assessment covers auth and home only; it does not establish readiness for checkout or other buyer workflows.

## Verification evidence

- Dart formatting and `git diff --check`: clean.
- `flutter analyze`: no issues.
- Ten isolated HTTP/session tests: CSRF/cookies, authenticated redirects, rejected credentials, cross-origin rejection, Inertia asset refresh, session expiration without mutation replay, filter encoding, OTP failure, and rejection of unconfirmed mutation responses.
- Two home controller tests: stale searches cannot replace newer results; pagination retains existing products on failure and deduplicates retry results.
- Thirteen widget checks: login validation and rejection, auth-to-home/logout, guest search and categories, two-step registration with incorrect-code rejection, verified password recovery, restricted-account routing, keyboard/reduced-motion behavior, 320px/375px phones, landscape, tablets, and 200% text on phones/tablets. The enlarged brand-wordmark overflow found during these checks was corrected.
- The read-only backend probe passed against the running local app: home, registration requirements, policies, and filtered catalogue. Categories/listings come from actual responses rather than fixtures in production code.
- A separate session smoke check used the documented local seeded buyer: sign-in, authenticated home continuity, logout, and subsequent guest state all passed. No accounts were created, passwords reset, or verification emails sent by that smoke check.
- `flutter build apk --debug`: passed. Artifact: `build/app/outputs/flutter-apk/app-debug.apk`.
- iOS build/device rendering and live verification-email delivery were not exercised on this Linux host. No browser or screenshots were used.

## Configuration and limits

- `BAGOO_BASE_URL` selects the existing buyer origin. Android debug uses the emulator host alias by default; release requires explicit HTTPS.
- Cookies remain in memory. Process restart requires a new login; no persistent credentials are stored.
- The backend controls adult eligibility, policies, OTP delivery, account access, prices, and catalogue results. Restricted sign-in responses remain on the account status view.
- Optional delivery addresses and identity-document submission, Google OAuth, Shopping Bag, checkout, and full order/account management remain in the web buyer portal.
- A separate PR title/body is saved locally in `.git/PR_BUYER_AUTH_HOME.md`; no GitHub PR or push is part of this handoff.

## Linux local preview

A native Linux runner is included so local development can use `flutter run -d linux`. It uses the existing Dart app and defaults to `http://localhost:8000` in debug mode. The initial window is 430 × 860 and remains resizable for larger layouts. The platform addition and build workflow are documented in the README.

Verification: `flutter build linux --debug` passed, and the read-only backend contract probe still passed. No backend source changes or authentication behavior changes were required. The Linux desktop window was not launched during the build check.
