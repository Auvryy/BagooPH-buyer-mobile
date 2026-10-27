# BagooPH Buyer Mobile

Native Flutter buyer shopping and authentication, using the existing BagooPH Laravel backend. Android and iOS targets are included, with a Linux desktop runner for local preview.

## Included

- Buyer email/password login and server-confirmed logout.
- Two-step registration, server validation, current Terms/Privacy documents, adult birth-date selection, and emailed verification codes.
- Password recovery with email-code verification and a new password.
- Guest browsing and signed-in home with real products, departments, campaigns when configured, and native catalogue search with canonical ship-from areas, price ranges, stock/rating filters, supported sorts, server suggestions, pagination, refresh, empty states, and retry. Home search and department links open Search with the requested selection.
- Tappable campaign banners with native promotion details and native product, shop, and search destinations.
- Web-style, equal-size product cards with square images, sale prices, comparison prices, stock/vacation states, ratings, location, and confirmed save controls.
- Full native product pages with gallery navigation/zoom, stock-aware options, variant prices and limits, persistent mobile Add to Bag/Buy Now controls, shop information, offers, focused specifications/review views, related product cards, descriptions, verified reviews/photos, and seller replies.
- Native shop search/pagination/following and product chat with text, photo uploads, and private photo viewing.
- Native Shopping Bag shop groups, search/sorting/selection filters, stock-aware quantity changes, confirmed removal, selected-item quotes, per-shop delivery estimates, and responsive summaries.
- Approved-buyer checkout with saved/new canonical Philippine addresses, delivery/payment choice cards, native paginated voucher selection and server comparison, recovery of valid voucher slots, COD or wallet, and explicit order review. Wide windows use a sidebar payment summary; phones keep the review action within reach.
- Home, Cart, Search, and Profile bottom tabs, with independent search and preserved visited tab/form state.
- A responsive native profile matching the buyer website's crimson/slate design: personal info/avatar, verified contact emails, password, identity evidence/corrections, and login activity with confirmed session revocation.
- Native paginated Saved Products and Followed Shops collections, with confirmed remove/unfollow actions and native product/shop pages.
- A native Notifications center with an unread Home badge, All/Unread filters, paging, confirmed read actions, and native buyer destinations.
- Delivery address-book editing, demo wallet credit requests/history, and available/saved/used/expired vouchers with native Bag use.
- Paginated purchases, order tracking, cancellation, buyer receipt confirmation, Buy Again, review editing/photos, pickup-code handling, and wallet payment review/confirmation/cancellation.
- Native store/courier inbox and return/refund cases, evidence, permitted buyer actions, and authenticated image/PDF viewing.
- Account status and native sign-in when a shopping action needs authentication. Pending buyers can browse and use their Bag; checkout permissions remain server-owned.
- Original BagooPH branding, bundled Plus Jakarta Sans, and responsive phone/tablet layouts.

Shopping and profile actions stay in Flutter with no browser or WebView handoff. Google OAuth remains outside this pass. Registration may omit optional address and document fields; existing buyers can submit their permitted evidence from Profile. The app never creates a local account or accepts a locally generated verification code.

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

Linux builds require Clang, CMake, Ninja, pkg-config, and GTK 3 development libraries. Build without opening a window with `flutter build linux --debug`.

## Backend integration

Buyer flows currently use Laravel web sessions, JSON endpoints, and Inertia page data. This app renders the existing contracts natively without backend changes:

| Purpose | Existing routes |
| --- | --- |
| Login / logout | `POST /login`, `POST /logout` |
| Registration requirements / validation / creation | `GET /register`, `POST /register/validate`, `POST /register` |
| Send / resend / verify email codes | `POST /otp/send`, `POST /otp/resend`, `POST /otp/verify` |
| Set recovered password | `POST /password/reset-otp` |
| Marketplace | `GET /` with search, category, sort, and page parameters |
| Campaigns / promotion details | `GET /` campaign data, internal `GET /advertisement/{slug}` visit route, and `GET /promotions/{slug}` |
| Dedicated catalogue search | `GET /buyer/search` with search/category/location/price/stock/rating/sort/page filters |
| Full product / saved products | `GET /buyer/product/{slug}`, `GET /buyer/saved-products`, `POST/DELETE /buyer/saved-products/{id}` |
| Shop / followed shops / sale reminders | `GET /shop/{slug}`, `GET /buyer/followed-shops`, `POST/DELETE /buyer/followed-shops/{id}`, `POST/DELETE /buyer/sale-reminders/{id}` |
| Notifications | `GET /notifications/preview`, `GET /notifications`, `PATCH /notifications/{uuid}/read`, and `PATCH /notifications/read-all` using the server-issued read snapshot |
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

The adapter bootstraps CSRF and session cookies from the web page, reads Inertia props, refreshes the asset version after deployments, handles JSON validation errors, and follows redirects only within the configured origin. It never replays a failed mutation automatically. No credentials, cookies, or tokens are logged or written to disk. Sessions last only while the app process remains alive; reopening the app requires login.

Profile changes use the website's existing eligibility and validation contracts. The original sign-in email and account role remain fixed. Reviewed identity changes go through the server's correction review; wallet balances and order status only change after server confirmation. Explicit retries preserve request tokens and payloads where the backend provides replay protection. Responses from an earlier cleared session are discarded.

Checkout fetches server quotes and ignores stale responses. Order placement requires a separate review and confirmation. An uncertain response retains the exact payload and server submission token for an explicit retry; buyers can check recorded orders first. The server revalidates prices, stock, account eligibility, delivery, and vouchers. Wallet payment is a separate confirmed action using the server request token.

When a voucher expires or becomes ineligible, checkout retains the server-confirmed valid slots and fetches a fresh quote before review. A late voucher comparison cannot replace a newer delivery selection. The payment summary separates product savings from shipping savings within the server's total discount. Form fields remain mounted while scrolling so recipient/address validation and entered values survive both long forms and window resizing.

This is a native Android/iOS client with Linux desktop preview; Flutter web is not a configured target. The web-session adapter depends on the backend's existing Inertia contract. A future native buyer API can replace it behind `BuyerRepository`.

## Verification

```sh
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter build apk --debug
flutter build linux --debug
```

Run the optional read-only backend contract check against your running buyer origin:

```sh
dart run tool/check_backend.dart '<BACKEND_ORIGIN>'
```

The check needs at least one published product and reads home, registration requirements, policies, filtered catalogue, dedicated search and canonical filters, full product details, shop catalogue, guest Bag, and checkout location choices. It never signs in, registers users, sends emails, places orders, or accesses private conversations. Automated tests use isolated fixtures and a temporary local HTTP server. They cover auth/session boundaries, native search, selected Bag quotes and stock, confirmed changes, voucher selection/repair/comparison, discount display, explicit checkout review, stale responses, exact retry payloads, and phone/tablet/landscape/large-text layouts. No live order, payment, email, or chat mutations are performed by these checks.

The profile/navigation pass was checked with formatting, static analysis, Android/Linux compilation, and authenticated read-only inspection of the local backend contracts. Its account, wallet, order, return, and messaging mutations have not been exercised against live data. No automated tests were added or run for that pass; the existing test suite's earlier coverage does not verify the new profile flows. Device layout, native picker/PDF interaction, and accessibility checks still need manual review.

The buyer engagement parity pass adds native campaign destinations and promotions, saved-product and followed-shop collections, and a native notifications center. Formatting, static analysis, and Android/Linux debug builds passed. No automated tests were added or run for this pass. Physical-device, screen-reader, and iOS/Xcode checks remain unverified on this Linux host.

For iOS on macOS, run `flutter build ios --no-codesign`; iOS compilation was not available on the Linux development host. Review the [authentication plan](docs/plans/buyer-auth-home.md), [native product journey plan](docs/plans/buyer-products.md), [profile/navigation plan](docs/plans/buyer-profile.md), and [shopping polish plan](docs/plans/buyer-shopping-polish.md) for scope and verification evidence.
