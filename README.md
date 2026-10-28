# BagooPH Buyer Mobile

Native Flutter buyer shopping and authentication, using the existing BagooPH Laravel backend. Android and iOS targets are included, with a Linux desktop runner for local preview.

## Included

- Buyer email/password login and server-confirmed logout.
- Two-step registration, live email availability, optional canonical address and government ID, server validation, current Terms/Privacy documents, adult birth-date selection, and emailed verification codes.
- Password recovery with email-code verification or an emailed reset link rendered as a native password form.
- Guest browsing and signed-in home with real products, active delivery and application summaries, departments, campaigns when configured, and native catalogue search with canonical ship-from areas, price ranges, stock/rating filters, supported sorts, server suggestions, pagination, refresh, empty states, and retry. Home search and department links open Search with the requested selection.
- Tappable campaign banners with native promotion details and native product, shop, and search destinations.
- Responsive, equal-size product cards with square images, sale prices, comparison prices, stock/vacation states, ratings, location, and independent save controls.
- Full native product pages with gallery navigation/zoom, stock-aware options, variant prices and limits, persistent mobile Add to Bag/Buy Now controls, shop information, offers, focused specifications/review views, related product cards, descriptions, precise sale countdowns/reminder state, native sharing, a combined customer photo gallery, verified reviews/photos, and timestamped seller replies.
- Native shop search, department and nested store categories, sorting/reset, page selection, public shop information, offers and following. Product chat supports text, photo uploads, and private photo viewing.
- Native Shopping Bag shop groups, search/sorting/selection filters, stock-aware quantity changes, confirmed removal, selected-item quotes, per-shop delivery estimates, and responsive summaries.
- Approved-buyer checkout with saved/new canonical Philippine addresses, delivery/payment choice cards, native paginated voucher selection and server comparison, recovery of valid voucher slots, COD or wallet, serving logistics-company and collection-hub choices, optional recipient coordinates/GPS, detailed server shipping weights/routes/tariffs and voucher allocations, and explicit order review. Wide windows use a sidebar payment summary; phones keep the review action within reach.
- Home, Bag, Search, and Profile bottom tabs, with independent search and preserved visited tab/form state.
- A responsive native profile matching the buyer website's crimson/slate design: personal info/avatar, verified contact emails, password, identity evidence/corrections, and login activity with confirmed session revocation.
- Native paginated Saved Products and Followed Shops collections, with confirmed remove/unfollow actions and native product/shop pages.
- A native notification preview with explicit reads limited to displayed notices, plus a full Notifications center with an unread Home badge, All/Unread filters, paging, confirmed read actions, and native buyer destinations.
- Native Help & Support using the existing Bagoo assistant and Customer Care chat, with editable suggested questions, retained drafts and explicit retry, server validation feedback, and keyboard/large-text layouts.
- Native public parcel tracking from Home or Profile, available to guests and buyers: tracking-number lookup, masked recipient details, server-labeled milestones, Philippine times, refresh/retry, and copy-number feedback.
- Delivery address-book editing, demo wallet credit requests/history, and available/saved/used/expired vouchers with native Bag use.
- Paginated purchases, order tracking, cancellation, server-authorized buyer receipt confirmation, recorded milestones and owned order notices, original voucher receipts, Buy Again, review editing/photos, pickup-code handling, and wallet payment review/confirmation/cancellation.
- Native store/courier inbox with rich product references, timestamps and editable inquiry questions, plus return/refund cases with separate barcode/QR labels, route/weight details, evidence purposes, permitted buyer actions, and authenticated image/PDF viewing.
- Account status and native sign-in when a shopping action needs authentication. Pending buyers can browse and use their Bag; checkout permissions remain server-owned.
- Original BagooPH branding, bundled Plus Jakarta Sans, and responsive phone/tablet layouts.

Shopping, support, and profile actions stay in Flutter with no browser or WebView handoff. Native Google sign-in and device push are deferred until the website maintainer supplies verified mobile contracts; this app does not call unsupported endpoints or display controls for those unfinished flows. Registration supports optional address and document fields; existing buyers can also submit permitted evidence from Profile. Account status shows recorded restrictions, review requests and decisions. The app never creates a local account or accepts a locally generated verification code.

The card ribbon uses COD with the web ribbon styling. Delivery fees and shipping discounts come from the checkout quote; the app does not promise free delivery unconditionally.

## Requirements

- Flutter stable with Dart SDK `^3.13.1`; installed dependencies are locked in `pubspec.lock`.
- Android SDK and a compatible JDK for Android builds.
- macOS and Xcode for iOS builds.
- The existing BagooPH backend, with its buyer web origin accessible from the device. Start/configure it using that repository's README. Email-code flows require working backend mail delivery.

`file_selector` provides the native picker for profile photos and evidence. `pdfrx` renders private PDFs inside the app, with document links disabled. These plugins are included in the native builds; iOS targets iOS 15 or later. Private evidence is fetched through the authenticated session into memory; the app does not save a copy to disk.

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

## Run on Linux

Keep the Bagoo backend running on this computer at `http://localhost:8000`, then run:

```sh
flutter run -d linux
```

The Linux preview opens in a resizable 430 × 860 window. Widen it to inspect the tablet layout. Linux uses the same native authentication and catalogue code as the mobile targets. To select a different backend:

```sh
flutter run -d linux --dart-define=BAGOO_BASE_URL='https://<BUYER_HOST>'
```

Linux builds require Clang, CMake, Ninja, pkg-config, GTK 3, libsecret and jsoncpp development libraries. Persistent sessions also need a working desktop Secret Service; ordinary login remains usable if secure storage is unavailable. Build without opening a window with `flutter build linux --debug`.

## Native link setup

Incoming links stay in Flutter and are accepted only for the configured buyer origin and supported buyer paths. Private destinations wait for buyer sign-in; links cannot automatically pay, cancel, confirm receipt or mark notices read. Signed email verification requires a separate confirmation, and an already signed-in buyer must explicitly sign out before password-link recovery. Recovery secrets stay in memory.

The default association hostname is the non-production placeholder `buyer.example.invalid`. To enable installed-app HTTPS links, the owner must configure the actual hostname and publish the association files described in [the website AI handoff](docs/integrations/website-ai-handoff.md).

- Android reads the Gradle property `BAGOO_LINK_HOST`. For an owner build, supply it with `ORG_GRADLE_PROJECT_BAGOO_LINK_HOST='<BUYER_HOST>'` alongside `--dart-define=BAGOO_BASE_URL='https://<BUYER_HOST>'`. Use approved release signing; the current template still has development release signing.
- iOS reads the Xcode build setting `BAGOO_LINK_HOST`. Set it for the applicable build configurations and provision Associated Domains and Keychain capabilities. `Runner.entitlements` is shared by Debug, Profile and Release.
- Match the hostname to the buyer base origin. Domain association, release signing, physical devices and iOS/Xcode acceptance require owner setup. Linux preview supports the native screens and clipboard fallback; no desktop URL registration is installed by this task.

## Backend integration

Buyer flows currently use Laravel web sessions, JSON endpoints, and Inertia page data. This app renders the existing contracts natively without backend changes:

| Purpose | Existing routes |
| --- | --- |
| Session recognition / login / logout | `GET /auth/session`, `POST /login`, `POST /logout` |
| Registration requirements / validation / creation | `GET /register`, `POST /register/email/validate`, `POST /register/validate`, `POST /register` |
| Send / resend / verify email codes | `POST /otp/send`, `POST /otp/resend`, `POST /otp/verify` |
| Password recovery | Existing email-code routes and `POST /password/reset-otp`; link requests use `POST /forgot-password` and native link reset uses `POST /reset-password` |
| Marketplace | `GET /` with search, category, sort, and page parameters |
| Campaigns / promotion details | `GET /` campaign data, internal `GET /advertisement/{slug}` visit route, and `GET /promotions/{slug}` |
| Dedicated catalogue search | `GET /buyer/search` with search/category/location/price/stock/rating/sort/page filters |
| Full product / saved products | `GET /buyer/product/{slug}`, `GET /buyer/saved-products`, `POST/DELETE /buyer/saved-products/{id}` |
| Shop / followed shops / sale reminders | `GET /shop/{slug}`, `GET /buyer/followed-shops`, `POST/DELETE /buyer/followed-shops/{id}`, `POST/DELETE /buyer/sale-reminders/{id}` |
| Notifications | `GET /notifications/preview`, `GET /notifications`, `PATCH /notifications/{uuid}/read`, `PATCH /notifications/read-displayed`, and `PATCH /notifications/read-all` using the server-issued read snapshot |
| Help & Support | `POST /buyer/support/assistant`, existing Customer Care conversation at `GET /chat/messages/2` and `POST /chat/send` |
| Public parcel tracking | `GET /track?number=...` through the existing `Public/Tracking` page contract |
| Product conversation | `GET /chat/messages/{receiver}`, `POST /chat/send`, private `GET /chat/attachments/{message}` |
| Shopping Bag | `GET/POST /cart`, `PATCH/DELETE /cart/{item}`; selected quotes use JSON `GET /cart` with `item_ids[]` |
| Checkout / quotes / locations | `GET/POST /checkout`, `POST /buyer/vouchers/apply`, `GET /address-locations` |
| Saved vouchers | `POST /buyer/saved-vouchers/{revision}`, `DELETE /buyer/saved-vouchers/{saved}` |
| Checkout voucher choices / comparison | `POST /buyer/vouchers/choices`, `POST /buyer/vouchers/best` |
| Profile / personal info / password | `GET/POST /buyer/profile`, `PUT /password`, `POST /email/verification-notification` |
| Contact emails / identity | `/account/emails/*`, `POST /buyer/kyc/upload`, `POST /kyc/resubmit`, `/account/identity-corrections` |
| Login activity | `GET /account/security`, `POST /account/security/code`, `POST /account/security/sessions/{id}/revoke` or `/account/security/sessions/revoke-others` |
| Delivery addresses | `/buyer/addresses`, `/buyer/addresses/{id}`, `/buyer/addresses/{id}/default` |
| Orders / wallet | `GET /buyer/orders`, `GET /buyer/orders/{id}`, `POST /buyer/orders/{id}/confirm`, `POST /buyer/orders/{id}/cancel`, `POST /buyer/orders/{id}/buy-again`, `POST /wallet/credits`, `/wallet/payments/{id}` and `/pay` or `/cancel` |
| Reviews / pickup code | `POST /buyer/reviews`, `PATCH /buyer/reviews/{id}`, `POST /buyer/orders/{id}/pickup-code` |
| Inbox / returns | `GET /buyer/messages`, `/buyer-returns`, `/buyer-returns/orders/{id}/create`, `/buyer-returns/{id}` and permitted buyer action/evidence routes |
| Account policies | Versioned URLs supplied by `GET /register` |

The adapter bootstraps CSRF and session cookies from the web page, reads Inertia props, refreshes the asset version after deployments, handles JSON validation errors, and follows redirects only within the configured origin. It never replays a failed mutation automatically. Passwords and verification/reset tokens are never persisted or logged. Guest session cookies are kept in native secure storage for Bag continuity. Selecting Remember me also saves the signed-in session and email there; every restored session is checked with the server. An unremembered login lasts for the current app process. Logout and expired-session clearing remove saved cookies, and delayed writes cannot restore them afterward. Secure-storage failure leaves ordinary sign-in usable with explicit feedback when a requested session cannot be saved.

Profile changes use the website's existing eligibility and validation contracts. The original sign-in email and account role remain fixed. Reviewed identity changes go through the server's correction review; wallet balances and order status only change after server confirmation. Explicit retries preserve request tokens and payloads where the backend provides replay protection. Responses from an earlier cleared session are discarded.

Checkout fetches server quotes and ignores stale responses. Order placement requires a separate review and confirmation. An uncertain response retains the exact payload and server submission token for an explicit retry; buyers can check recorded orders first. The server revalidates prices, stock, account eligibility, delivery, and vouchers. Wallet payment is a separate confirmed action using the server request token.

When a voucher expires or becomes ineligible, checkout retains the server-confirmed valid slots and fetches a fresh quote before review. A late voucher comparison cannot replace a newer delivery selection. The payment summary separates product savings from shipping savings within the server's total discount. Form fields remain mounted while scrolling so recipient/address validation and entered values survive both long forms and window resizing.

This is a native Android/iOS client with Linux desktop preview; Flutter web is not a configured target. The web-session adapter depends on the backend's existing Inertia contract. A future native buyer API can replace it behind `BuyerRepository`.

All sibling products, including the Bagoo website/backend, are read-only references for mobile work. Required website additions are recommendations in [mobile contract requests](docs/integrations/buyer-mobile-contract-requests.md), not changes to the website repository.

The Notifications screen refreshes its current filter and page when the app resumes. Read acknowledgements remain explicit buyer actions. Support history and drafts live only on the current screen; they are cleared when the account or access changes. Short windows and enlarged text use a scrollable composer to keep its fields and send action reachable with the keyboard.

Open shop/courier conversations now refresh automatically every eight seconds; inbox unread badges and order detail refresh every fifteen seconds. Reads run serially, pause while backgrounded or covered by another route, and recover with backoff up to two minutes. Returning to the screen refreshes it. Chat drafts, selected photos, search text and order action feedback survive updates; new replies follow the conversation only when the buyer is already near its bottom. The existing chat GET marks incoming messages read on the server, so it runs only for the visible conversation. This is foreground polling; device push needs the separate backend/provider setup in the [cumulative website AI handoff](docs/integrations/website-ai-handoff.md). Sends and order/payment actions are never retried automatically.

Previously loaded Home/Search pages and product details are available as read-only saved browsing data when a connection fails. Cached screens show their recorded time; product shopping, saving, reminders and chat require a successful refresh. The cache stores public catalogue fields and search parameters, never full authenticated responses or private account/commerce data. It uses the existing native secure store under a separate origin-specific key, with a memory fallback if storage is unavailable. It is limited to 32 entries/768 KiB, 96 KiB per entry and seven days. Use **Home → Clear saved browsing data** to remove the persisted snapshots; an already open page stays in memory until refreshed/closed. Earlier pending requests cannot restore the cleared snapshots. If device deletion fails, the app clears the in-process cache and asks for a retry instead of claiming the device copy was deleted. Photos are not newly persisted, so some need a connection. Removed/denied products do not fall back after the server reports their status. No offline order/payment queue is created.

Use **Home → Track a parcel** or the Profile shortcut to look up a waybill number without signing in. Tracking accepts up to 64 ASCII letters/numbers, hyphens, and underscores, starting with a letter/number. Its timeline uses the website's public labels and recorded events; recipient fields remain masked. A refresh failure clearly labels the previous confirmed lookup. Changing the input invalidates older pending results. Internal `/track` links open this native screen. Order changes and buyer receipt confirmation remain in the owned order flow.

Home and Search use one native sort menu, stable initial placeholders, and visible progress while retaining previous results and scroll position. Exact saved public pages can appear while a fresh request is pending; they remain read-only and show their saved time. A valid initial Home response is reused, identical pending catalogue reads share one request within the current account/submission scope, and successful online pages no longer wait for optional cache writes. Account changes, cache removal and newer queries invalidate earlier previews.

Public image previews decode near their displayed physical size, with bounded resolution and preserved proportions. Full-size viewing and authenticated media keep their original providers. Static image placeholders avoid per-photo progress spinners and per-byte rebuilds. Sale reads run every 30 seconds only on a visible foreground product route, back off after failures, and refresh on return. Their first scheduled read waits after the initial product response; countdowns and hidden Home-tab tickers pause when covered. These client changes reduce avoidable work and waits; server response time and source image download sizes still depend on the backend.

## Verification

```sh
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter build apk --debug
flutter build linux --debug
```

The [buyer design and loading review](docs/plans/buyer-design-loading-polish.md) records the design decisions, loading regressions and verification matrix. To export the optional off-screen native fixture renders without opening an app or browser window:

```sh
flutter test --no-pub --dart-define=BAGOO_RENDER_REVIEW=true --dart-define=BAGOO_REVIEW_PHASE=review test/design_review_test.dart test/buyer_journeys_design_test.dart
```

These synthetic-data artifacts are machine-local in `.git/buyer-design/review/`. They cover fifteen representative screens at narrow/regular phone, tablet and landscape sizes, including keyboard insets, 200% text and reduced motion. They supplement regression checks; physical-device, screen-reader and iOS acceptance remain separate checks.

Run the optional read-only backend contract check against your running buyer origin:

```sh
dart run tool/check_backend.dart '<BACKEND_ORIGIN>'
```

The check needs at least one published product and reads home, registration requirements, policies, filtered catalogue, dedicated search and canonical filters, full product details, shop catalogue, guest Bag, and checkout location choices. It never signs in, registers users, sends emails, places orders, or accesses private conversations. Automated tests use isolated fixtures and a temporary local HTTP server. They cover auth/session boundaries, native search, selected Bag quotes and stock, confirmed changes, voucher selection/repair/comparison, discount display, explicit checkout review, stale responses, exact retry payloads, and phone/tablet/landscape/large-text layouts. No live order, payment, email, or chat mutations are performed by these checks.

The profile/navigation pass was checked with formatting, static analysis, Android/Linux compilation, and authenticated read-only inspection of the local backend contracts. Its account, wallet, order, return, and messaging mutations have not been exercised against live data. No automated tests were added or run for that pass; the existing test suite's earlier coverage does not verify the new profile flows. Device layout, native picker/PDF interaction, and accessibility checks still need manual review.

The buyer engagement parity pass adds native campaign destinations and promotions, saved-product and followed-shop collections, and a native notifications center. Formatting, static analysis, and Android/Linux debug builds passed. No automated tests were added or run for this pass. Physical-device, screen-reader, and iOS/Xcode checks remain unverified on this Linux host.

The [mobile-only support review](docs/plans/mobile-only-support-review.md) passed all 99 tests, static analysis, formatting, and Android/Linux debug builds. Its new tests cover support drafts/retries and notification account/lifecycle boundaries, plus keyboard, landscape, large-text, and resize behavior. No live backend mutation was performed. iOS and physical-device checks remain unverified.

The [native public tracking pass](docs/plans/native-public-parcel-tracking.md) passed the full 129-test suite, static analysis, formatting, and Android/Linux debug builds. Its tracking tests cover real local HTML/Inertia transport, public response validation, input limits, labels/timezones, stale lookups, native navigation, clipboard feedback, and phone/landscape/tablet layouts with keyboard insets and 200% text. Tests use isolated data and do not look up real parcels. iOS and physical-device checks remain unverified.

For iOS on macOS, run `flutter build ios --no-codesign`; iOS compilation was not available on the Linux development host. Review the [authentication plan](docs/plans/buyer-auth-home.md), [native product journey plan](docs/plans/buyer-products.md), [profile/navigation plan](docs/plans/buyer-profile.md), and [shopping polish plan](docs/plans/buyer-shopping-polish.md) for scope and verification evidence.

The [buyer web parity pass](docs/plans/buyer-web-parity.md) implements the audited native controls against existing contracts. Checkout detects whether the backend supplies logistics-company choices: earlier contracts keep their original server-quoted flow, while an explicit empty serving-company list blocks checkout. The website worktree was evolving during inspection, so this does not prove its newest logistics contracts are deployed. Google identity exchange and installed-app domain association require the separate [website handoff](docs/integrations/website-ai-handoff.md).

This parity branch passed all **179 isolated tests**, formatting, static analysis, and Android/Linux debug compilation. Checks include remembered sessions and cookie-clear races, quote and company changes, old-contract compatibility, native link ownership/confirmation, notification visibility and account boundaries, message retries, payment deadlines, and responsive layouts. No live account, email, order, payment, chat or backend database mutation was used for verification. iOS compilation, physical-device GPS/sharing/scanning, screen readers, domain association and production signing remain manual owner acceptance checks.

The subsequent [buyer updates and offline catalogue pass](docs/plans/buyer-live-updates-offline-catalogue.md) passed all **214 isolated tests**, formatting, static analysis, and Android/Linux debug builds. Its 35 new tests cover foreground navigation/lifecycle/backoff, chat and order action races, cache privacy/persistence/expiry, refused local HTTP connections, failed device deletion/retry and enlarged keyboard/error layouts. Physical-device and iOS acceptance remain unverified. Website/backend requirements accumulate in the existing [website AI handoff](docs/integrations/website-ai-handoff.md); the website repository was not modified.
