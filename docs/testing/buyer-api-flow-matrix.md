# Buyer API and database flow evidence

Audit date: 2026-11-03. Scope: the production buyer mobile `lib/` tree on `test/buyer-exhaustive-sweep`. Backend source was read only. No backend runtime, database command, live mutation, provider exchange, phone, task service or visible browser was used by this audit.

## What the evidence establishes

- **HTTP** means an isolated `dart:io` `HttpServer` receives requests from the real `WebSession`/repository. Requests traverse the actual Dart HTTP client, serialization, cookies, CSRF, redirects and response parsing. The server supplies synthetic replies; it does not run Laravel, middleware, policies, SQL or transactions.
- **Fixture** means a fake repository, `ControlledWebSession`, synthetic preview or widget/native misuse harness supplies the reply. These checks establish client behavior and account/lifecycle safeguards only.
- **Source** means the mobile call and corresponding backend route/controller were inspected. It proves neither deployment nor execution.
- **Database** means assertions against the backend's actual isolated test database. No database suite was executed in this mobile sweep. Every database row below remains open regardless of passing mobile tests.

The existing HTTP files were identified by their loopback `HttpServer.bind` use: `web_session_test.dart`, `web_session_direct_json_test.dart`, `native_auth_transport_test.dart`, `buyer_shopping_repository_test.dart`, `buyer_capability_discovery_test.dart`, `session_persistence_test.dart`, `catalogue_read_transport_test.dart`, `catalogue_cache_test.dart`, and `tracking_repository_test.dart`. Their execution status comes from the root sweep ledger; source presence alone is not a pass.

`test/buyer_api_contract_sweep_test.dart` is new in this sweep. The first root-run regression captured **89 passing and five failing API tests** (94 API tests); every failure was the malformed-XSRF defect described below. After the production fix and stronger recovery/valid-encoding checks, **all 95 API tests passed** in root's serialized 205-test combined run (`/tmp/bagoo-exhaustive-fixed-focused.log`). It adds HTTP evidence for profile mutations, contacts, security actions, identity multipart requests, wallet/reorder/pickup adapter calls, notifications, support and session/error boundaries. A route assertion made through generic `ProfileRepository.json`/`mutate` verifies that adapter and route shape; the separate widget tests own the UI-specific field validation. It does not establish backend acceptance of an arbitrary test payload.

`test/buyer_api_extended_sweep_test.dart` passed **all 123 cases** in the root second-sweep run. That combined run had one unrelated navigation regression (178 passes, one failure); the API group was entirely green. “Extended HTTP” below refers to its route-specific adapter tests. It covers private page/account scopes, security/location JSON, voucher choices/comparison, following/bookmarks, sale reminders, chat sends, wallet commands, session proof payloads, cancellation/reviews, KYC/avatar multipart and return creation/commands/private media. Where a route is implemented inside a widget, the test invokes the same production `WebSession` method and `BuyerAccountScope` boundary using source-confirmed fields; it does not execute or duplicate that widget's business validator. In particular, a deliberately small synthetic page returned by an adapter test is not claimed to satisfy the complete UI schema.

## Route matrix

Paths below are the paths the mobile sends. `{id}`, `{slug}`, `{uuid}` and similar braces denote runtime values, not invented endpoints. `page` means Inertia/HTML data rendered natively; `JSON` means an object response; `binary` means an authenticated image/PDF. Every request is restricted to the configured origin by `WebSession.resolve`.

### Authentication and policies

| Flow / production owner | Actual method and path | Client evidence and assertions | Remaining backend/database acceptance |
| --- | --- | --- | --- |
| Recognize restored session, `BuyerRepository.currentSession` | `GET /auth/session`, then `GET` server `redirect` | Existing session HTTP contracts; new sweep tests buyer destination allowlist, cross-origin/other-role destinations | Real expired/revoked/closed sessions, server role/ownership, guest Bag merge |
| Password sign-in, `BuyerRepository.login` | `POST /login` | Existing HTTP checks normalized email, fixed buyer role, remember flag, validation errors and buyer confirmation | Real password proof, rate limits, session rotation and login-history persistence |
| Sign out, `BuyerRepository.logout` | `POST /logout` | Existing HTTP/session persistence checks; final page must have no user | Backend invalidation and device session revocation |
| Optional capabilities, `discoverCapabilities` | Direct `GET /buyer/mobile-capabilities` | Dedicated loopback discovery rejects malformed versions/flags, redirects and unavailable replies | Deployed flags/configuration, throttle and private cache headers |
| Native Google, `GoogleAuthRepository` | Direct `POST /auth/google/native`; direct `GET /auth/google/native/registration`; direct `POST /auth/google/native/register` | `native_auth_transport_test` tests real CSRF/cookie rotation, no redirect adoption/replay; Google repository/controller tests otherwise use fixtures | Google SDK/provider identity, backend token verification, linking proof, nonce expiry, transactional registration |
| Registration metadata, `registration` | `GET /register` | Existing HTTP bootstrap/registration tests and form fixtures | Real policy versions, field options, age limits and availability |
| Registration email, `registrationEmailAvailable` | `POST /register/email/validate` | Existing session HTTP tests require matching normalized email, role and boolean availability | Unique account identity, ownership, races and throttling |
| Validate registration, `validateRegistration` | `POST /register/validate`, JSON or multipart | Existing HTTP requires `valid: true`; multipart builder tests inspect encoding | Server birth date/adult rules, document validation, field eligibility |
| Create account, `register` | `POST /register`, JSON or multipart with `role: buyer`, `otp_token` | Existing HTTP confirmation/validation; registration UI fixtures | Database uniqueness, OTP single use, fixed role, document storage and rollback |
| Email codes, `sendCode` / `verifyCode` | `POST /otp/send`; `POST /otp/resend`; `POST /otp/verify` | Existing HTTP tests enforce explicit success/token; extensive code/cooldown UI fixtures | Real mail delivery, purpose binding, attempt limits, expiry and replay resistance |
| OTP reset, `resetPassword` | `POST /password/reset-otp` | Existing HTTP confirmation and error propagation | Consuming token atomically, password hash update, old-session revocation |
| Password email/reset link | `POST /forgot-password`; `POST /reset-password` | Existing HTTP page/status confirmation; link parsing and UI fixtures | Delivered signed/reset link, expiry, original-email binding and single use |
| Verify email link, `EmailVerificationLinkPage` | `GET` validated signed `/verify-email/{id}/{hash}` with server query | Link and widget fixture tests; shared page transport HTTP | Signature/expiry verification, authenticated owner binding and persisted verification |
| Versioned policy reader, `PolicyPage` / registration policy contract | `GET` server-supplied `/terms/{version}` and `/privacy/{version}` | Policy/link fixtures, shared HTTP page parser | Exact deployed policy document and accepted version persistence |

### Catalogue, promotions and saved lists

| Flow / production owner | Actual method and path | Client evidence and assertions | Remaining backend/database acceptance |
| --- | --- | --- | --- |
| Home, `BuyerRepository.home` | `GET /` with optional `search`, `category`, `sort`, `page` | Existing HTTP query encoding, catalogue cache/failure/read coalescing | Real visibility, prices/stock and pagination consistency |
| Search, `search` | `GET /buyer/search` with encoded filters/page | `buyer_shopping_repository_test` asserts all query values; catalogue HTTP/caching | Real filters, ranking, stock/rating/location predicates |
| Product, `product` | `GET /buyer/product/{encoded slug}` | Existing HTTP requires correct component/positive product ID, rejects duplicate offers | Real variants, prices, sale clock, hidden/deleted products |
| Shop, `shop` | `GET /shop/{encoded slug}` with `page` and optional `search`, `category`, `store_category`, `sort` | Existing HTTP component and offer-uniqueness checks; shop widget fixtures | Shop moderation, category ownership and product pagination |
| Save product, `saveProduct` | `POST /buyer/saved-products/{id}`; `DELETE /buyer/saved-products/{id}` | Existing HTTP asserts method, CSRF and returned product ID/saved state | Cross-buyer access, uniqueness and persisted removal |
| Saved products, `BuyerEngagementRepository.savedProducts` | `GET /buyer/saved-products?page={page}` | New HTTP checks page-two query and strict metadata; collection fixtures validate IDs, pagination and buyer account | Full adversarial HTTP page matrix and database ownership |
| Follow shop, shop and followed-shops widgets | `POST /buyer/followed-shops/{id}`; `DELETE /buyer/followed-shops/{id}` | Shop/collection fixture assertions; extended HTTP method/payload/403 tests | Widget acknowledgement with real transport and persisted follow ownership |
| Followed shops, `followedShops` | `GET /buyer/followed-shops?page={page}` | New HTTP checks page-two query/metadata; collection fixtures validate account, rows and pagination | Full adversarial HTTP matrix and real persistence |
| Sale reminders, `reminder` | `POST /buyer/sale-reminders/{id}`; `DELETE /buyer/sale-reminders/{id}` | Extended HTTP methods/referer/subscribed acknowledgement/local-ID rejection; widget fixtures | Subscription uniqueness and notification delivery |
| Promotion visit/detail, destination router / `promotion` | `GET /advertisement/{slug}` follows internal redirect; `GET /promotions/{encoded slug}` with optional `publication` | New HTTP serializes slug/publication and parses native promotion; campaign/promotion/destination fixtures; shared same-origin redirect HTTP | Deployed publication/visibility and tracked visits |
| Advertisement measurement, `reportAdvertisement` | `POST` server-issued measurement endpoint (backend currently `/advertisement-events`) with token/type | New HTTP sweep verifies real 204, JSON payload and off-origin refusal; existing exposure fixtures | Signed token validation, deduplication, retention and impression eligibility |
| Public media | `GET` server image/artwork URL through Flutter image provider | Image sizing/provider fixtures; source | Real assets, cache headers, network/media failures and decode behavior |

### Bag, checkout and vouchers

| Flow / production owner | Actual method and path | Client evidence and assertions | Remaining backend/database acceptance |
| --- | --- | --- | --- |
| Read Bag, `bag` | Page `GET /cart` | Existing shopping HTTP and Bag fixtures require `Cart/Index` | Guest/account ownership, merge, pending buyer permissions |
| Selected Bag quote, `bagQuote` | JSON `GET /cart?item_ids[]={id}` (repeated array key) | Existing HTTP checks selected array IDs and JSON Accept | Price/stock/totals recalculation and unauthorized item exclusion |
| Add / Buy now, `addToBag` | `POST /cart`, product referer; `buy_now` flag | Existing HTTP checks exact variant/quantity and returned quantity; fixtures cover checkout token | Inventory, combination stock, quantity limits, guest merge and quote totals |
| Update/remove line, `changeBagItem` | `PATCH /cart/{id}`; `DELETE /cart/{id}` | Existing HTTP checks referer, method and actual returned item state | Cross-buyer denial, concurrent stock changes and persisted totals |
| Checkout load, `checkout` / checkout page refresh | `GET /checkout?items={comma IDs}` with optional `quantity` | Checkout fixtures check approved account/component and refreshed quotes | Server approvals, serving logistics, addresses and stock snapshot |
| Place order, `placeOrder` | `POST /checkout`, checkout referer | Existing HTTP success text/component check, conflict token and no automatic replay | Atomic order/inventory/voucher writes, idempotency, balance and totals |
| Apply quote, `quote` | `POST /buyer/vouchers/apply` | Existing HTTP 422 repair metadata/no replay; quote fixtures | Real eligibility, stacking, funding, limits, prices and transaction behavior |
| Voucher choices, `voucherChoices` | `POST /buyer/vouchers/choices` | Extended HTTP quote/shop/page fields and incomplete-acknowledgement tests; picker fixtures | Full paged eligibility and widget contract over real transport |
| Best vouchers, `bestVouchers` | `POST /buyer/vouchers/best` | Extended HTTP quote field serialization and malformed selection/quote checks; selection fixtures | Best-choice correctness and authoritative totals |
| Save/remove voucher, product/profile widgets | `POST /buyer/saved-vouchers/{revision}`; `DELETE /buyer/saved-vouchers/{saved}` | Extended HTTP methods/body/403; bookmark fixtures validate IDs, state and account boundaries | Widget acknowledgement over real transport, revision ownership and persisted save |
| Location choices, `LocationPicker` | `GET /address-locations` with chosen hierarchy query | Extended HTTP hierarchy query encoding and malformed wire-body checks; location fixtures | Complete widget hierarchy validator over real transport and actual geography |

### Notifications, conversations, support and tracking

| Flow / production owner | Actual method and path | Client evidence and assertions | Remaining backend/database acceptance |
| --- | --- | --- | --- |
| Preview, `notificationPreview` | JSON `GET /notifications/preview` | New HTTP row/count/duplicate UUID checks; lifecycle fixtures | Real owner unread counts and visibility |
| Full list, `notifications` | Page `GET /notifications?filter={all or unread}&page={page}` | New HTTP unread-filter/page/row contract; notification fixtures validate portal, owner role, filters/rows/pagination | Full adversarial HTTP page matrix and persisted read state |
| Mark one read, `markNotificationRead` | JSON `PATCH /notifications/{uuid}/read` | New HTTP exact method and timezone-qualified read acknowledgement | Cross-buyer denial and persisted read timestamp |
| Open notice, `openNotification` | `PATCH /notifications/{uuid}/read` with `open: true`, follows page redirect | New HTTP verifies method/body/native redirect and rejects changed buyer | Owner route authorization and read persistence |
| Mark preview read, `markDisplayedNotifications` | `PATCH /notifications/read-displayed`, `ids` array | New HTTP exact scope and count feedback; invalid scopes cause no request | IDs restricted to owner, atomic read and accurate summary |
| Mark snapshot read, `markNotificationSnapshotRead` | `PATCH /notifications/read-all`, server `snapshot` token | New HTTP exact token and summary; snapshot fixtures | Expiry, account binding, only snapshotted rows, rollback |
| Inbox, `InboxPage` | Page `GET /buyer/messages` | Extended HTTP exact route/page parser, account scope, malformed/denied/late reply tests; inbox fixtures | Full inbox row validator over real transport and actual owner conversation/unread query |
| Conversation, `messages` | JSON `GET /chat/messages/{receiver}`; Customer Care uses receiver `2` | Existing HTTP rejects malformed/duplicate/incomplete message rows; foreground fixtures | Participant authorization; this GET marks incoming rows read and requires isolated DB acceptance |
| Send message, `sendMessage` | `POST /chat/send`, JSON or multipart | Extended HTTP real JSON/multipart participant/context/request-key bytes and seven malformed acknowledgement cases; chat fixtures | Participant ownership, rate limits, dedupe and attachment storage |
| Private chat attachment | Binary `GET /chat/attachments/{message}` | New HTTP exact bytes/MIME, empty/HTML/JSON/unknown MIME/login redirect/403 cases; existing HTTP cookie path/origin guards; private document fixtures | Actual attachment participant authorization and media storage |
| Support assistant, `SupportAssistantRepository.ask` | JSON `POST /buyer/support/assistant` | New HTTP trims payload, Unicode 1000 boundary, suggestion cap/dedupe, malformed replies, error matrix and cleared-session race | Actual eligibility, rate limit and authoritative buyer/order context |
| Public tracking, `TrackingRepository.lookup` | Page `GET /track?number={normalized number}` | Dedicated HTTP HTML/Inertia mode tests plus strict result/time/privacy fixtures | Real parcel lookup, redaction, status chronology and access boundaries |

### Profile, security, orders and returns

| Flow / production owner | Actual method and path | Client evidence and assertions | Remaining backend/database acceptance |
| --- | --- | --- | --- |
| Profile tab data, `ProfileRepository.load` | `GET /buyer/profile?tab={tab}` plus tab filters/page query | New HTTP profile context and matching response identity; profile fixtures | Real account metadata, tab pagination and authorized rows |
| Personal details | `POST /buyer/profile` | New HTTP method/referer/context/payload/confirmation; field fixtures | Permitted fields, immutable sign-in email/role and persistence |
| Password | `PUT /password` | New HTTP method and profile return; password-proof fixtures | Correct old password, hash change and session invalidation |
| Resend verification | `POST /email/verification-notification` | New HTTP method and profile return; account fixtures | Mail rate limit/delivery and verification state |
| Additional contact emails | `POST /account/emails/send`; `POST /account/emails/confirm`; `PATCH /account/emails/{id}/preferred`; `DELETE /account/emails/{id}` | New HTTP JSON/method/cookie/referer; contact widgets own proof, cooldown and field cases | Password/OTP proof, preference uniqueness, original-email immutability and ownership |
| Login activity | JSON `GET /account/security?sessions_page={n}&history_page={n}` | Extended HTTP independent page query/JSON parser/late reply; activity fixtures | Full session/history widget validator over real transport and actual persistence |
| Session proof/revoke | `POST /account/security/code`; `POST /account/security/sessions/{uuid}/revoke`; `POST /account/security/sessions/revoke-others` | First HTTP exact method/route/JSON/referer; extended HTTP password/email proof payloads and nullable alternatives; session fixtures | Real mail proof, UUID ownership/current-session rules and invalidation |
| Identity correction | `POST /account/identity-corrections`, JSON or multipart | New HTTP nested multipart fields/raw PDF bytes and JSON acknowledgement; identity fixtures | Source token, permitted identity changes, review queue and protected file storage |
| Buyer ID / resubmit | Multipart `POST /buyer/kyc/upload`; `POST /kyc/resubmit` | Extended HTTP actual `id_document` multipart bytes/profile confirmation/422; identity widget fixtures | Real document validation/review persistence |
| Protected account documents | Binary `GET` server URLs such as `/verification-documents/{user}/{document}` and `/identity-correction-documents/{correction}/{document}` | Extended HTTP source-confirmed `id.pdf` paths, session headers, bytes/403; private-document fixtures | Owner and reviewer authorization, hidden storage and actual MIME/bytes |
| Delivery address create/edit/delete/default | `POST /buyer/addresses`; `PATCH /buyer/addresses/{id}`; `DELETE /buyer/addresses/{id}`; `POST /buyer/addresses/{id}/default` | New HTTP methods/context/JSON and page confirmation; address fixtures | Cross-owner denial, limit/concurrency, one default and geographic validation |
| Account standing/review | Page `GET /account/status`; `POST /account/review-requests` | Extended HTTP read account scope/denials and source-token request JSON; account-status fixtures | Complete widget status schema over real transport; restrictions, eligibility and persisted review request |
| Order history | Page `GET /buyer/orders?page={n}`; profile orders tab also used | Extended HTTP query/page parser/account scope/401/403; history/result fixtures | Full history pagination validator over real transport and real owner history |
| Order detail | Page `GET /buyer/orders/{id}` | New HTTP rejects wrong order ID; order and polling fixtures | Actual order ownership, state/version, totals and tracking |
| Confirm receipt | `POST /buyer/orders/{id}/confirm` | New profile HTTP method/referer and confirmation; order UI fixtures | Versioned eligibility; server delivery/payment gates and atomic completion |
| Cancel order | `POST /buyer/orders/{id}/cancel` | Extended HTTP reason/notes/referer/native redirect and 403/409/422; cancellation fixtures | Widget status confirmation over real transport and permitted refund/stock changes |
| Buy again | JSON `POST /buyer/orders/{id}/buy-again` | New HTTP route/JSON adapter; purchase fixtures validate current availability/result | Real inventory, allowed products and Bag persistence/idempotency |
| Review create/edit | `POST /buyer/reviews`; `PATCH /buyer/reviews/{id}` | Extended HTTP actual rating/comment/item and `images[0]` multipart/native redirect/denials; review fixtures | Server multipart parsing, purchase ownership, one review per item and persisted rating |
| Pickup claim | JSON `POST /buyer/orders/{id}/pickup-code` | New HTTP route/adapter; claim fixtures validate 12-digit hexadecimal code and stale claim | Actual owner/stage checks, expiry, secure source and rate limit |
| Credit request | JSON `POST /wallet/credits`, stable request token | New HTTP route/body; wallet fixtures validate amount/token/retry/feedback | Balance ledger, duplicate/replay/concurrent requests and operator approval |
| Wallet payment | Page `GET /wallet/payments/{id}`; `POST /wallet/payments/{id}/pay`; `POST /wallet/payments/{id}/cancel` | Extended HTTP page owner/denied/late replies, actual request-token/payment proof JSON and explicit same-token 503 retry; wallet fixtures | Full payment widget schema over real transport plus atomic reservation, expiry and ledger integrity |
| Return list/create/detail | Page `GET /buyer-returns?page={n}`; `GET /buyer-returns/orders/{id}/create`; `GET /buyer-returns/{id}` | Extended HTTP exact route/query, account scope, 401/403/late replies; return fixtures | Full return widget validators over real transport, actual windows/quantities/authorization |
| Create return | Multipart `POST /buyer-returns/orders/{id}`, creation referer | Extended HTTP versioned token, nested item IDs/quantities, `photos[0]` bytes, actual detail redirect and 403/409/422; return fixtures | Atomic case/unit claims, server file parsing/storage and replay |
| Return action/custody/money | `POST /buyer-returns/{id}/actions`; `POST /buyer-returns/{id}/custody`; `POST /buyer-returns/{id}/money`, case referer | Extended HTTP actual action/version/token/reason/source-event JSON and denial/no-replay; return fixtures | Full widget saved-result confirmation over real transport, state-machine eligibility and transactions |
| Return evidence/money proof | Binary `GET /buyer-returns/{id}/evidence/{evidence}` and server-supplied `/buyer-returns/{id}/money/{event}/proof` | Extended HTTP exact paths/session/bytes/403; private-document/returns fixtures | Actual private storage and owner authorization |

Navigation aliases (`/buyer/cart`, `/buyer/checkout`, `/buyer/disputes`, `/buyer/catalog`, `/account/settings`, `/buyer/addresses`, `/pending-approval`, `/verify-email`) are normalized or routed to native screens. They do not automatically imply an extra HTTP call. The public tracking JSON `/api/track/{number}` and rider token APIs exist in backend source but are **not called by this mobile product**.

## Session and transport boundary coverage

The existing shared transport tests include cookie path filtering; saved-session origin/expiry rejection; session restore/clear races; JSON validation fields; same-origin redirects; no credential POST replay; CSRF expiration; Inertia version refresh; text response size limits; refused local connections; and optional direct JSON no-redirect semantics. Refer to the individual named tests for their exact cases. The new sweep adds authenticated binary MIME/byte/error checks. It does not yet establish every secure/domain/expiry combination for incoming HTTP cookies or the 20 MiB binary limit. `uploads_multipart_test.dart` tests byte construction rather than an HTTP server; the new identity multipart test covers those bytes crossing the HTTP client.

The new sweep adds the HTTP error table `400, 401, 403, 404, 408, 409, 419, 422, 429, 500, 502, 503, 504` on the real support mutation. Every case requires one write, preserved structured error/repair metadata, and a parsed retry deadline. The 419 case additionally requires cleared cookies and a changed identity epoch. A held support response is released after `session.clear()` to prove that a delayed reply/cookie cannot be adopted. These exercise shared transport; they do not prove each backend route emits those statuses.

The first malformed-XSRF regression run confirmed all five failures: `%` and `%GG` threw raw `ArgumentError` from `Uri.decodeComponent`; `%FF` threw `FormatException` for invalid UTF-8; encoded CR/LF and NUL threw `FormatException` in `HttpHeaders.set`. The malformed cookie remained installed, bypassing normal account-expiry handling on retries. The narrow production fix catches those two exception types only while binding XSRF, attaches an error handler to `request.done` before aborting the unsent request, clears invalid session state and reports `BackendException` with status 419. It never replays the mutation. All strengthened regressions passed: advanced identity epoch, empty cookie headers, no failed-attempt POST and successful next explicit operation after clean CSRF bootstrap, without a manual clear in the test. The valid encoded token counterpart also passed.

Native bridges (`NativeSessionVault`, Google identity SDK, picker/file selector, geolocation, share/clipboard, PDF rendering and installed-app links) require plugin/device acceptance. Stubbed method-channel replies and Linux preview do not establish Android/iOS permission handling, provider registration or secure storage persistence. No phone execution is included in this sweep.

## Database ownership and acceptance prerequisites

Mobile has no SQL database dependency or database schema. `CatalogueCache` persists a sanitized public catalogue snapshot through files; `SessionVault` uses native secure storage for session cookies. Neither is the commerce system of record. Laravel owns accounts, cart rows, orders, stock, voucher uses, notification read state, messages, wallet ledgers and returns.

Read-only backend evidence was inspected in `../bagoo/routes/web.php`, `routes/auth.php`, `database/migrations/` and selected `tests/Feature/` files. Backend `phpunit.xml` specifies forced `APP_ENV=testing`, SQLite `:memory:`, array mail/cache/session and synchronous queue settings. Its feature suites use `RefreshDatabase` and contain actual database assertions. **They were not executed here**; their presence is an ownership/prerequisite finding, not a pass or authorization to run them.

| Database concern | Existing backend test source observed (read only) | Required acceptance still open |
| --- | --- | --- |
| Native/session/auth/account lifecycle | `BuyerMobile/ContractFixturesTest.php`, `BuyerMobile/NativeGoogleTest.php`, `Auth/WebSessionTransitionTest.php`, `Auth/BuyerAdultRegistrationTest.php`, `Auth/OtpVerificationTest.php`, `Security/AccountSessionsTest.php` | Owner-run isolated backend suite, registration/login/recovery/session-revocation round trips from mobile, mail/provider acceptance |
| Account/contact/address ownership | `AccountEmailSettingsTest.php`, `AccountSettingsUpdatesTest.php`, `ProfileInputValidationTest.php`, `Buyer/BuyerAddressBookTest.php`, `Security/AccountSessionBoundariesTest.php` | Correct rows updated, foreign-owner writes denied, immutable role/sign-in email, default-address uniqueness |
| Checkout/inventory/idempotency | `Buyer/CheckoutReplayTest.php`, `Buyer/InventoryCheckoutTest.php`, `Buyer/CombinationInventoryTest.php`, `Buyer/BuyerCheckoutTest.php` | One accepted order for replayed token, atomic stock/voucher/address/order writes and rollback, concurrent buyer contention |
| Notifications | `Notifications/NotificationBulkReadTest.php`, `BuyerNotificationPreviewTest.php`, `PortalNotificationTest.php` | Owner/snapshot binding, read rollback, post-snapshot rows unchanged and accurate unread count |
| Wallet | `Wallet/WalletHttpTest.php`, `WalletPaymentTest.php`, `WalletMoneyTest.php` | Atomic ledger/payment transitions, no fabricated balance, deadlines, replay and refunds |
| Messaging | `Buyer/ProductMerchantChatTest.php`, `MarketplaceChatImageTest.php`, `ChatUnreadNotificationTest.php`, `ChatAntiSpamTest.php` | Recipient/attachment ownership, stored bytes, read side effects and duplicate-send behavior |
| Returns | `Returns/BuyerReturnMoneyTest.php`, `BuyerReturnMoneyFilesTest.php`, `BuyerReturnCustodyTest.php`, `SelectedProductVoucherReturnTest.php` | Case/unit claim ownership, version/replay, custody, repayment source and ledger conservation |
| Public catalogue/tracking | `Buyer/BuyerDiscoveryAndSavedProductsTest.php`, `BuyerStorefrontAcceptanceTest.php`, `PublicTrackingTest.php` | Actual product visibility, saved-list ownership, tracked parcel privacy and delivery chronology |

Any future mobile-to-Laravel acceptance needs a separately authorized disposable backend/database, stable seed fixtures for two different buyers plus guest/pending/active/restricted states, synthetic email/Google/file providers, and explicit permission for mutations. It must establish a known starting database, capture before/after rows through backend-owned assertions, and clean only that disposable environment. A configured developer/production database must never be reset or used as a substitute.

The [backend acceptance plan](buyer-backend-acceptance-plan.md) supplies 40 existing feature-test commands, source-confirmed isolation safeguards, transaction/ownership pass criteria and the exact later execution scope. It is prepared for review; none of those backend commands has run in this sweep.

## Build and test backlog

- [x] Record root's existing-suite baseline: 1,515 tests passed before production edits. Branch-coverage inventory remains owned by the root ledger.
- [x] Run the first HTTP suite serially: 95 API tests passed after the five captured malformed-XSRF regressions were fixed.
- [x] Run the extended HTTP adapter suite serially: all 123 cases passed; full widget-schema/backend acceptance remains separate.
- [ ] Extend real-HTTP saved/followed-list, promotion and full-notification page tests with every adversarial row/pagination variant; add location hierarchy, profile security/inbox/account-status and wallet payment pages.
- [x] Author route-specific extended adapter tests for voucher choices/best/bookmarks, following/reminders, KYC uploads, reviews/cancellations, wallet pay/cancel and return multipart/action/proof flows. All 123 extended cases passed; complete inline widget-schema validation over HTTP remains separate.
- [ ] Exercise interrupted/chunked responses, invalid XSRF cookie encoding and malformed server cookie headers; require readable `BackendException` outcomes and no duplicate writes.
- [ ] Run owner-approved isolated Laravel suites and mobile-to-backend transactions against a disposable database. Record database assertions independently of HTTP mocks.
- [ ] Complete deployed read-only contracts, native/provider permissions and Android/iOS/device acceptance under the user's later scope.

Low-memory focused command, serialized by the root alongside other checks:

```sh
flutter test --no-pub --concurrency=1 test/buyer_api_contract_sweep_test.dart
flutter test --no-pub --concurrency=1 test/buyer_api_extended_sweep_test.dart
```

No platform build is needed for this transport/test/document slice. Root owns serialized full analysis/coverage and final evidence updates.
