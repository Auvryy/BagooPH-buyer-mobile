# Bagoo website work needed by the native buyer app

## Copy this scope to the website AI

Work on the Bagoo website only after its owner separately authorizes that repository and creates its website branch. This file is a handoff from `BagooPH-buyer-mobile`; the mobile task changes no website source, dependencies, database or Git state. Preserve the existing buyer website while adding any agreed mobile capability. Do not reapply the reversed native Google/push branch wholesale.

Mobile parity work is tracked in `docs/plans/buyer-web-parity.md`. The detailed proposed Google/push contracts and failure cases remain in [buyer-mobile-contract-requests.md](buyer-mobile-contract-requests.md). Treat every proposed route in that document as unavailable until implemented, reviewed, deployed and verified. Never enable a button by assuming a future endpoint exists.

The next mobile pass is tracked in [buyer-live-updates-offline-catalogue.md](../plans/buyer-live-updates-offline-catalogue.md). Keep this handoff cumulative: implement and verify individual requests on the separately authorized website branch, then return the actual contract/fixtures/deployment details. Completed mobile work does not mean these proposed website additions exist.

| Priority | Website work | Current mobile behavior |
| --- | --- | --- |
| Required for Google parity | Verified native Google identity exchange and native registration (section 1) | Email/password remains available; no website OAuth redirect or unsupported Google button. |
| Required for installed HTTPS links | Owner association files, identifiers and signing configuration (section 2) | Native destinations exist; default host is a placeholder. |
| Needed for background delivery | Owned device-push contract, Firebase/APNs configuration and workers (section 4) | Foreground updates use existing routes; no background push is claimed. |
| Future efficiency and precise chat reads | Cursor/pagination, separate message read acknowledgement, revision/conditional reads and rate-limit guidance (section 6) | Existing full responses are polled only while the relevant screen is visible. |
| Future cache revalidation | Public catalogue revisions, freshness/deletion rules and cacheable public image guidance (section 7) | Bounded public projections support read-only browsing; no private/checkout data is persisted. |

## 1. Required for native Google sign-in

The existing `/auth/google` flow redirects through a browser. The buyer app requires a native identity exchange and native registration; opening that website flow does not satisfy the requirement.

Agree and implement the proposed `POST /auth/google/native`, `GET /auth/google/native/registration` and `POST /auth/google/native/register` contracts described in the linked contract document. Accept a Google ID token, verify signature/issuer/audience/expiry/authorized party/verified email/subject, and bind any short-lived registration challenge to the same session. Establish the buyer role on the server; preserve original sign-in email, account-link rules, age 18+, canonical address, current policies, approval and restriction behavior. Return explicit authenticated or registration-required outcomes and existing JSON field errors. No provider secret belongs in the app. The current mobile branch intentionally has no Google SDK or enabled Google control; after the server contract and owner client registrations are verified, a separate mobile integration must connect the native SDK and agreed exchange rather than opening the website flow.

Supply the approved server audience and Android/iOS client registrations, release signing fingerprints and applicable bundle IDs through owner configuration. Test invalid tokens, wrong clients, linked-account conflicts, underage registration, expired challenges, duplicate completion, suspension/closure and provider failure. Email login and ordinary website OAuth must continue working.

## 2. Required owner setup for HTTPS app links

The app can route only links belonging to its configured buyer origin and approved buyer destinations. The website owner must publish domain association files before Android/iOS can reliably open its HTTPS links in the installed app.

- Serve `/.well-known/assetlinks.json` over HTTPS without authentication or redirects. Use relation `delegate_permission/common.handle_all_urls`, namespace `android_app`, the actual application ID and approved release SHA-256 signing-certificate fingerprints. Use the current mobile manifest/application configuration as authority, not an invented package name or debug certificate.
- Serve `/.well-known/apple-app-site-association` as JSON without a filename extension. Use the approved Apple team ID plus app bundle ID and restrict paths/components to buyer links: products, shops/store categories, buyer search/profile/orders, owned returns, wallet payment details, public tracking, email verification and password reset. Keep administrative and other-product paths outside the association.
- Agree the production buyer hostname, Android release certificate, Apple team/bundle IDs, and mobile build settings. Android consumes the Gradle property `BAGOO_LINK_HOST` (or `ORG_GRADLE_PROJECT_BAGOO_LINK_HOST`); iOS consumes the Xcode build setting `BAGOO_LINK_HOST`. Both default to `buyer.example.invalid` and must match `BAGOO_BASE_URL`. Placeholder domains in the mobile repository must be replaced through owner build configuration, not committed private infrastructure values.
- Preserve signed email verification query parameters exactly. A link must not confirm receipt, pay an order, cancel an order or acknowledge a notice just because it opened the app. Private destinations must require the current authenticated buyer and current ownership checks.

Verify cold/warm app launches, signed-out destinations followed by native sign-in, expired/foreign links, malformed/overlong IDs, external origins and owner-switch boundaries. Browser access to existing website links must remain usable.

## 3. Existing contracts to retain; these do not need new endpoints

The mobile implementation should consume these current contracts. Website maintenance should preserve their shape or publish an agreed version before changing them.

| Buyer feature | Existing contract and required fields |
| --- | --- |
| Session recognition / persistence | `GET /auth/session`, normal cookie/CSRF login/logout. Retain the existing `authenticated` boolean and, for authenticated replies, `code` and same-origin `redirect`. The mobile client fetches that allowed buyer destination and verifies its authenticated buyer role; the session JSON itself has no role field. The server still validates every restored session; a stored cookie is not proof of login. Secure-cookie/domain settings must match the actual HTTPS buyer origin. |
| Registration | `GET /register` policy/birth-date requirements, `POST /register/email/validate`, `POST /register/validate`, multipart `POST /register` with optional `id_document` and canonical address. Preserve server validation and OTP requirements. |
| Password recovery | Existing password-link request and `/reset-password/{token}` form contract plus existing email-code recovery. Links remain expiring, single-purpose, role-bound and server-validated. |
| Account status / review requests | `GET /account/status` → `Auth/AccountStatus` with status/account/sources/requests and correction/access flags. `POST /account/review-requests` uses subject type/ID, current source token and message. A review request never reactivates an account. |
| Home and discovery | `Buyer/Home` includes `activeShipment` and `relatedProducts`; Search includes canonical filters/locations/suggestions, related products and paginator metadata. Shop details include visible `storeCategories`, filters, `shopOffers`, follower count and shop stats. |
| Checkout logistics | `Checkout/Index` includes `logisticsCompanies` and company-owned `pickupHubs`. Quote requests to `/buyer/vouchers/apply`, `/choices` and `/best` include `logistics_company_id`, province, city, postal code, barangay, delivery type and collection hub. Quote/error replies retain updated `logisticsCompanies` where available. Order placement revalidates route/company eligibility. |
| Shipping explanation | Preserve each quote shop's `shipping_quote`: company name, actual/volumetric/billable grams, included grams, base/extra-kilogram cents, route hubs, bypass flag and missing-measurement product IDs. Do not require the app to calculate tariffs or fabricate a route. |
| Coordinates | Existing paired `shipping_latitude`/`shipping_longitude` and saved-address latitude/longitude. Coordinates are optional recipient data, not proof of geographic or logistics serviceability. |
| Prices and discounts | Preserve item `price_segments`, voucher `redemptions`/allocations, current selected-product scope, eligible-product URLs and immutable order `voucher_receipt`. The server owns all cents, allocations and original purchase prices. |
| Orders / notifications | Order detail returns server tracking, current action flags, package details and `orderNotices`; keep existing owned read routes. Public tracking remains privacy-filtered for guests and signed-in users alike. |
| Wallet / returns | Preserve wallet payment items, confirmed payment and refund references/times, last-attempt outcome and expiry. Return details retain custody barcode, position, hubs, measured weight, manifest reference, evidence purpose, decisions, money history and buyer-permitted actions. The app must not perform admin/courier/finance actions. |
| Messaging / support | Existing owned conversation, product-reference and attachment routes, idempotent message keys, and `/buyer/support/assistant`. No new assistant endpoint is needed. |
| Notifications / advertisement measurements | Existing preview, read-displayed, owned-read and read-snapshot routes. Keep signed measurement tokens and endpoint limits; a measurement failure must not block shopping. |

These were inspected in the local website working tree during the parity audit. Some checkout source was uncommitted; this document does not assert that every current local website change is deployed. Confirm deployment state before a real-device acceptance run. The client preserves the earlier checkout contract only when company choices are absent; an explicit empty choices list is treated as no available company and cannot bypass version-two route checks.

## 4. Optional future device push

Push is additional native functionality, not an already verified buyer web push feature. Agree opt-in registration/revocation, encrypted tokens, token rotation, account-switch/logout cleanup, generic payloads with owned notice IDs, deduplicated delivery/retries/expiry, and provider configuration using the detailed contract document. Keep optional push failure isolated from normal website notification storage, email login and shopping. Owner Firebase/APNs/service-account setup and workers are separate prerequisites. Leave capability flags disabled until verified.

## 5. Versioned capability discovery and documentation

Agree a versioned read-only mobile capability reply before advertising Google or push. Default optional features to disabled. The existing proposed `/buyer/mobile-capabilities` name is a proposal, not an instruction for the mobile app to call an absent route.

Reconcile the old buyer-confirmed completion prose with current versioned logistics behavior: new version-two orders complete on the server after evidenced handover/payment gates; historical version-one orders can retain buyer receipt confirmation. Publish the version and server action eligibility. Mobile must only display recorded state and permitted actions, never advance completion itself.

## 6. Foreground updates: existing contracts and future efficiency

No website changes are required for the current foreground implementation:

- `GET /chat/messages/{receiverId}` returns the owned conversation's `messages` and `receiver`. Message rows include server `id`, `sender_id`, `receiver_id`, text, timestamp and optional product/attachment fields. Mobile verifies the buyer/receiver pair and deduplicates by message ID.
- `GET /buyer/messages` returns `Buyer/Messages` with the authenticated buyer and `conversations`, including `unread_count`, `last_message`, `last_time`, recipient and recent product references.
- `GET /buyer/orders/{order}` returns `Buyer/OrderDetail` with the authenticated buyer, owned order, server tracking/action flags, pickup claim, notices and purchase details.
- The mobile screen checks chat every eight seconds and inbox/order detail every fifteen seconds after the preceding read finishes. Failures back off to a two-minute maximum. Reads pause on background, covered routes, explicit actions and disposal; returning to a visible screen triggers a fresh read. An already-started HTTP request can still finish on the server; its stale mobile result is discarded.
- Automatic refresh never calls message send, receipt confirmation, cancellation, pickup-code issue, Buy Again, order placement or wallet/payment mutations. Those remain explicit buyer actions. This is foreground polling, not server push or background delivery.

Observed limitation: `ChatController::getMessages` currently marks all returned incoming messages read. There is no separate buyer read-acknowledgement route. The mobile client therefore fetches only the visible conversation; this cannot provide precise per-message visibility acknowledgements when the buyer scrolls through older replies. Inbox polling does not acknowledge conversations.

Proposed website work, for a later agreed version:

1. Return bounded message pages with a stable server-ID cursor, deterministic order, older-history pagination and explicit deletion/availability behavior. Preserve existing full-history behavior for existing clients until versioned migration is agreed.
2. Separate reading messages from acknowledging them. Agree an owned acknowledgement accepting only actually displayed incoming message IDs, with validation, bounded batches and idempotent confirmation. Do not silently change the existing website's read behavior; return sanitized fixtures and a migration plan before mobile switches.
3. Supply a cheap owned inbox summary and conditional order/inbox reads using an agreed revision or ETag. Keep all authorization and server action flags current. Never send order/customer details on a public broadcast channel.
4. Publish intended foreground request limits, HTTP 429 `Retry-After` behavior and denied/expired JSON errors. The current client uses bounded backoff; the present transport does not expose retry headers. Return permission failures as permission failures, not successful empty data.
5. If adding WebSocket/SSE later, agree authenticated buyer subscriptions, token/session expiry, reconnect/cursor recovery and event deduplication. Device push remains a separate opt-in capability. The mobile branch installs no socket service or absent real-time endpoint.

## 7. Read-only public catalogue cache

The current mobile cache needs no website endpoint. It saves an allowlisted public projection after successful Home, Search and product requests. It omits authenticated props, profile/status, addresses, saved-product IDs, Bag quantities, campaigns/measurement tokens, reminders, review authors/photos, orders, messages, private evidence and checkout/payment tokens. Saved search parameters are part of the local browsing cache. Data is isolated by configured backend origin, bounded to 32 entries/768 KiB (96 KiB per entry), expires after seven days, and can be cleared from Home. Earlier pending reads cannot restore cleared snapshots; failed device deletion is reported with an explicit retry while the current in-process cache is cleared. Storage uses the existing native secure-storage plugin with an independent catalogue key; if unavailable, only the in-process cache remains available.

Network data is preferred. Connection failures or temporary HTTP 500/502/503/504 responses can fall back to the exact previously loaded query/page/product. Denied, expired, missing and invalid contracts do not fall back; a received failure invalidates that snapshot. Cached screens show their saved time and require a successful product refresh before Add to Bag, Buy Now, save, reminders or chat. The client does not queue offline purchases or payments. Photos have no new persistent disk cache; previously decoded images may remain in Flutter memory, and other photos need a connection. Saved data cannot reveal an unpublished/deleted product's new status until a server read succeeds.

Future website assistance, not current requirements:

- Agree a versioned public catalogue projection independent of authenticated Inertia shared props. Include stable product revision/update time, canonical slug, availability/deletion outcomes, server freshness limits and conditional GET support. Do not make the client infer current stock, prices or permissions from cached data.
- Document which product image URLs are public/cacheable, their revision/cache headers, permitted retention and removal behavior. Keep chat, identity, return evidence and other authenticated media explicitly outside public caching.
- Provide fixtures for product withdrawal, renamed slugs, expired sales, changed variants/prices, stale revisions, deployment-version changes and an unavailable backend. Preserve normal website catalogue and checkout behavior.

The mobile refresh and fallback approach follows [Flutter route visibility](https://api.flutter.dev/flutter/widgets/ModalRoute/isCurrentOf.html) and [Flutter offline-data guidance](https://docs.flutter.dev/app-architecture/design-patterns/offline-first). These references describe client behavior; they do not establish a deployed Bagoo backend contract.

## Acceptance before handing back to mobile

1. Identify the exact website branch, commits and deployed environment for each implemented contract.
2. Provide sanitized request/response fixtures for success, guest, denied, expired, validation, stale-version and unavailable-provider outcomes. Never include real credentials, cookies, documents or personal parcel data.
3. Preserve existing website login/registration, search, Bag, checkout, order/return and notification behavior; test provider-disabled and provider-failure cases independently.
4. Verify native Google, association files and optional push in separate owner-approved environments. Do not use production buyers/orders/payments for automated checks.
5. State which proposals remain unavailable and retain explicit disabled capability flags. Return the agreed schema/version and owner setup instructions so mobile can connect without another website redirect.

Native capability setup follows the maintainer documentation for [app_links](https://pub.dev/packages/app_links) and [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage). The earlier buyer-parity baseline compiled on Android/Linux and passed 179 isolated tests; current update/cache verification is recorded in its linked plan. These checks do not verify deployed association files, real Google identity exchange, iOS provisioning, or physical-device behavior.
