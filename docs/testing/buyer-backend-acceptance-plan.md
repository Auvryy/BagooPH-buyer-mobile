# Buyer backend and database acceptance plan

Status: **prepared for review; no backend tests or database commands executed**. Source inspected on 2026-11-03. This document lives in the buyer mobile repository. The sibling backend remains read only under the current authorization; “entire workspace” testing does not expand that scope.

The [API flow matrix](buyer-api-flow-matrix.md) separates Dart HTTP adapter tests from actual database acceptance. The first new mobile HTTP suite passed all 95 tests; it used synthetic loopback responses. The extended suite's status is recorded separately in that matrix. Neither suite executes the backend's controllers, authorization policies, transactions or SQL constraints.

## Concrete authorization needed before execution

The later authorized action would be: run the named existing backend feature tests below in an **owner-provided disposable backend copy**, with its own runtime directories, synthetic test configuration and SQLite in-memory database. Allow only the tests' temporary database/schema, fake-storage and runtime/log/report writes inside that disposable environment. Leave the existing backend checkout, its Git state, configuration, dependencies and databases untouched. Do not change backend source or publish anything. Network/provider acceptance and a long-running backend server are separate actions.

That is a bounded proposal, not a request to modify the backend now. Until that exact action and disposable location are authorized, the database acceptance rows remain open. This plan can also be handed to the backend owner to execute and return evidence.

## Isolation supported by existing source

The following safeguards were verified by reading source; none has been runtime-verified during this mobile sweep.

| Existing source | Actual setting or behavior | Practical limit |
| --- | --- | --- |
| `../bagoo/phpunit.xml` | `APP_ENV=testing`, `DB_CONNECTION=sqlite`, `DB_DATABASE=:memory:` and empty `DB_URL`, all with `force="true"` | Select this exact configuration; do not replace it with ordinary application environment defaults |
| `../bagoo/tests/TestCase.php::createApplication` | After application bootstrap, explicitly sets `database.default=sqlite` and `database.connections.sqlite.database=:memory:` | The override occurs after bootstrap. The disposable environment must already be safe before bootstrap; it cannot rely solely on this late override |
| `phpunit.xml` | Array mail, cache and sessions; synchronous queue; null broadcasting; optional telemetry flags disabled | These settings do not prove every application hook is network-free. Keep external network access unavailable unless separately authorized |
| Selected feature classes | `RefreshDatabase`, factories, deliberate failure injection, SQL triggers and rollback assertions | Tests can migrate/reset their test schema and modify test records. This is why they must never run against a shared or real database |
| `Tests\TestCase::be` and `call` | Preserve an explicit cookie-backed test session and adopt response session/remember cookies | Provides backend in-process HTTP session evidence, not the Dart client's real socket or native secure store |
| `Tests\Concerns\WithNativeGoogleTokens` | Generates synthetic signing material, fakes provider key responses and calls `Http::preventStrayRequests()` | Tests identity exchange logic without a real provider account; SDK/provider acceptance remains open |
| `MarketplaceChatImageTest`, `ReviewIntegrityTest`, `PrivateVerificationDocumentsTest` | Use fake local/public storage and inspect uploaded files | Fake storage writes belong only to the disposable copy; this is not real storage-provider acceptance |
| `../bagoo/composer.json` | Requires PHP `^8.3`; declares PHPUnit `^12.5.12`; `composer test` runs `artisan config:clear`; `composer setup` includes installation, key generation, migration and frontend work | Use the existing locked toolchain in the disposable copy. Do not use those broad scripts for this bounded test action |

A later authorized run needs a sanitized disposable copy with the locked dependencies and a suitable PHP runtime. The agent can prepare that copy after the execution scope is authorized; the original backend checkout stays read only. PDO SQLite is required for these database tests; image/file suites also need the image, MIME and XML facilities required by their existing dependencies, and token tests need OpenSSL. Verify requirements against that copy's lockfile and installed platform, not a remembered global PHP version. No dependency installation or runtime preflight has been performed here.

Before any application bootstrap, confirm that the disposable copy has no copied configuration cache containing real settings, no real credentials, no active jobs/scheduler and no symlink from its writable storage/cache/temp locations to shared product data. Use a synthetic application encryption key and synthetic fixture identities supplied for that disposable environment. Do not print environment files, cookies, tokens or credentials. Do not clear another checkout's configuration cache to make the tests run.

## Existing test batches and exact commands

All commands in this section are **examples for the later authorized disposable backend root**. They were not executed. Each command explicitly selects the inspected `phpunit.xml`; run them one at a time, without parallel workers, and record the actual result before continuing. File paths identify existing classes, not proposed tests. The existing test harness creates its own fixtures; no manual seed, migration, database reset or shared data is required for these commands.

### 1. Session, registration and recovery

| Existing class file under `tests/Feature/` | Required behavior represented in source |
| --- | --- |
| `BuyerMobile/ContractFixturesTest.php` | Backend session/capability/native identity responses match sanitized mobile fixtures; account states and closed sessions |
| `Auth/WebSessionTransitionTest.php` | Real login rotates session; logout removes authentication; incorrect credentials and expired sign-in cannot succeed |
| `Auth/BuyerAdultRegistrationTest.php` | Missing/invalid/underage dates reject; exact eighteenth birthday uses the Philippine calendar |
| `Auth/OtpVerificationTest.php` | OTP records, expiry, attempts, mail-failure cleanup, registration and password reset |
| `Auth/OtpRecoveryGuardTest.php` | Recovery identity ownership, malformed codes, purpose/network limits and raw control characters |
| `BuyerMobile/NativeGoogleTest.php` | Linking proof, immutable identity/role, expiring session-bound registration, real CSRF rejection and redacted errors with synthetic provider responses |

```sh
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/BuyerMobile/ContractFixturesTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Auth/WebSessionTransitionTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Auth/BuyerAdultRegistrationTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Auth/OtpVerificationTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Auth/OtpRecoveryGuardTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/BuyerMobile/NativeGoogleTest.php
```

Database acceptance: one permitted account identity, no account/OTP after rejected input, token consumption once, password/session state updated only after proof, no role conversion. These backend tests do not demonstrate delivered email, native SDK configuration or a real provider exchange.

### 2. Contacts, security, addresses and reviewed identity

| Existing class file | Required behavior represented in source |
| --- | --- |
| `AccountEmailSettingsTest.php` | Additional-address verification/preference/removal; original sign-in email remains fixed even under direct writes |
| `Security/AccountSessionBoundariesTest.php` | Session/history ownership and pagination, closed/restricted accounts, email proof binding, failed-save retry, authentication-generation races |
| `ProfileInputValidationTest.php` | Phone/name/contact validation, fixed reviewed identity, invalid avatar changes leave existing state untouched |
| `Buyer/BuyerAddressBookTest.php` | Parent geography, tenth/eleventh address boundary, default deletion rules, foreign-owner denial, saved pin and delivery-snapshot preservation |
| `Buyer/BuyerCheckoutKycGateTest.php` | Actual document upload and pending status; unapproved/inactive buyers cannot place orders |
| `Auth/PrivateVerificationDocumentsTest.php` | Real bytes/private storage and cache headers; disguised content, foreign users and inactive reviewers denied |
| `Admin/IdentityCorrectionTest.php` | Separate evidenced requests, current reviewer/source, immutable evidence, idempotent decisions and audit-failure rollback |
| `Auth/AccountReviewFlowTest.php` | Owner-only/current-source review requests, duplicate protection, restrictions remain authoritative and original decisions cannot be rewritten |

```sh
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/AccountEmailSettingsTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Security/AccountSessionBoundariesTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/ProfileInputValidationTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Buyer/BuyerAddressBookTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Buyer/BuyerCheckoutKycGateTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Auth/PrivateVerificationDocumentsTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Admin/IdentityCorrectionTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Auth/AccountReviewFlowTest.php
```

Database acceptance: original identity preserved; proof belongs to the correct account/action; only owned address/contact/session rows change; one valid default; review/status/evidence writes roll back together. Admin or other-role fixtures here support buyer boundary checks; they do not expand this mobile implementation's scope.

### 3. Bag, checkout, stock and repeat purchases

| Existing class file | Required behavior represented in source |
| --- | --- |
| `Buyer/BuyerCartQuantityTest.php` | Strict quantity syntax, exact stock/99-unit boundaries, foreign Bag line denial, failed update preserves old quantity |
| `Buyer/InventoryCheckoutTest.php` | Stock changes at checkout instead of Bag addition; aggregate variants cannot oversell; cancellation restores once |
| `Buyer/CombinationInventoryTest.php` | Combination-specific stock, option integrity and once-only restoration |
| `Buyer/CheckoutReplayTest.php` | Server-issued checkout confirmation, original-result replay, foreign/changed token rejection, network destination eligibility and failure rollback |
| `Buyer/BuyerBuyAgainTest.php` | Current price/options, owned selection, stable retry and token binding; partial line failure rolls the full selection back |
| `Buyer/BuyerCancellationTest.php` | Eligible early cancellation only, correct reason, foreign/custody denial, once-only stock restoration and failure rollback |

```sh
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Buyer/BuyerCartQuantityTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Buyer/InventoryCheckoutTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Buyer/CombinationInventoryTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Buyer/CheckoutReplayTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Buyer/BuyerBuyAgainTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Buyer/BuyerCancellationTest.php
```

Database acceptance must include `CheckoutReplayTest::test_mid_checkout_failure_rolls_back_shop_orders_stock_voucher_address_and_result`: it asserts rollback across several write stages. Retain `test_original_checkout_result_and_ownership_cannot_be_rewritten` and repeat-purchase rollback/idempotency cases rather than testing only successful HTTP status. Expected evidence includes original Bag/stock snapshots, exactly one accepted checkout result and its original order links, and no partial order/address/voucher writes after failure.

SQLite tests establish behavior in this configured test engine. They do not establish production-engine row-lock behavior or simultaneous multi-process stock contention; those remain a separately authorized engine/concurrency acceptance requirement.

### 4. Catalogue, saved products, vouchers and reviews

| Existing class file | Required behavior represented in source |
| --- | --- |
| `Buyer/BuyerDiscoveryAndSavedProductsTest.php` | Literal/invalid search, stable pagination, owned retry-safe saves and database uniqueness |
| `Buyer/BuyerVoucherQuoteTest.php` | Current prices, eligible selected products/stock, per-shop shipping, deterministic centavo allocation and quote/persisted-order parity |
| `Buyer/BuyerVoucherSelectionTest.php` | Owned idempotent bookmarks, real pagination, best combination/caps/budget dependencies, replayed published terms |
| `Buyer/ReviewIntegrityTest.php` | Purchase-derived reviewer, one owned edit, image/type limits, uniqueness, private identity, failed rating/file write rollback |

```sh
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Buyer/BuyerDiscoveryAndSavedProductsTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Buyer/BuyerVoucherQuoteTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Buyer/BuyerVoucherSelectionTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Buyer/ReviewIntegrityTest.php
```

Database acceptance includes exact quote-to-order totals, unique saves/bookmarks/reviews, no discount reservation by merely saving an offer, and no orphan review photos after failed persistence. `ReviewIntegrityTest::test_database_unique_purchase_constraint_prevents_direct_duplicate_insert` tests a database invariant that a loopback response cannot establish.

### 5. Notifications and conversations

| Existing class file | Required behavior represented in source |
| --- | --- |
| `Notifications/BuyerNotificationPreviewTest.php` | Bounded owned preview, nonmutating reads, displayed-ID scope, original read timestamp on retry and foreign-ID all-or-nothing denial |
| `Notifications/NotificationBulkReadTest.php` | Exact owned snapshot, same-tick/later arrivals excluded, forged/expired/cross-account snapshot rejection and failed-write rollback |
| `Buyer/ProductMerchantChatTest.php` | Product/shop/recipient context and owned buyer conversation/inbox |
| `Buyer/MarketplaceChatImageTest.php` | Private real image, context ownership, stable request-key retry, failed file/message write rollback and snapshot-scoped read acknowledgement |
| `Buyer/ChatUnreadNotificationTest.php` | Real unread count changes and opening a conversation marks incoming messages read |
| `Buyer/ChatAntiSpamTest.php` | Rapid duplicate sends do not create duplicate messages |

```sh
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Notifications/BuyerNotificationPreviewTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Notifications/NotificationBulkReadTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Buyer/ProductMerchantChatTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Buyer/MarketplaceChatImageTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Buyer/ChatUnreadNotificationTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Buyer/ChatAntiSpamTest.php
```

Database acceptance: read timestamps affect only the authorized original rows; a failed bulk write leaves all unchanged; messages and private files are saved once; inbox/unread queries match stored rows. Conversation `GET` is intentionally a database mutation because it acknowledges returned incoming messages. A “read-only API probe” must not casually open live conversations.

### 6. Wallet, payment and delivery gates

| Existing class file | Required behavior represented in source |
| --- | --- |
| `Wallet/WalletHttpTest.php` | Owned payment pages and approved virtual credits, forbidden accounts and detection of a tampered balance |
| `Wallet/WalletPaymentTest.php` | Lost-response payment retry, cancel/expiry, exact deadline, foreign token denial, stale-balance contention and journal failure rollback |
| `Wallet/WalletMoneyTest.php` | Original paid totals, centavo conservation, partial returns, settlement and returned-parcel rollback |
| `Buyer/BuyerReceiptClockTest.php` | Elapsed time/history reads do not substitute for receipt evidence or cash reconciliation |

```sh
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Wallet/WalletHttpTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Wallet/WalletPaymentTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Wallet/WalletMoneyTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Buyer/BuyerReceiptClockTest.php
```

Database acceptance must retain `WalletPaymentTest::test_journal_failure_rolls_back_debit_paid_state_and_attempt_together` and `test_b9_002_and_005_exact_payment_and_lost_response_recovery_never_charge_twice`. Require balanced retained ledger entries, one original payment result, the server's actual deadline/status and once-only stock/voucher release. A button press, navigation result or synthetic success must never be recorded as financial acceptance.

### 7. Returns, custody, repayment and private proof

| Existing class file | Required behavior represented in source |
| --- | --- |
| `Returns/BuyerReturnReviewTest.php` | Owned original-unit claims, exact return/response deadlines, replay, foreign/stale denial, file limits and case/unit/journal rollback |
| `Returns/BuyerReturnCustodyTest.php` | Original reverse hub sequence, physical custody/capacity/authority, deadline boundaries and failed receipt/intake rollback |
| `Returns/BuyerReturnMoneyTest.php` | Actual backed repayment once, original-buyer confirmation, foreign/stale/forged commands, private proof, SQL immutability and journal/notification rollback |
| `Returns/BuyerReturnMoneyFilesTest.php` | Actual receipt bytes at 5 MiB boundaries, real PDF content and canonical extension; this file test is not itself SQL coverage |
| `Returns/SelectedProductVoucherReturnTest.php` | Original selected-product discount remains attached through real return custody and repayment |

```sh
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Returns/BuyerReturnReviewTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Returns/BuyerReturnCustodyTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Returns/BuyerReturnMoneyTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Returns/BuyerReturnMoneyFilesTest.php
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/Returns/SelectedProductVoucherReturnTest.php
```

Database acceptance: claimed original units cannot exceed the purchase; current expected version and request token bind every command; rejected requests leave no case/claim/file; custody reflects actual receipt; the original buyer receives only evidenced repayment; original discount and all centavo allocations are conserved. Retain explicit journal-failure and private-proof-orphan assertions, not only the happy path.

### 8. Public tracking privacy

```sh
php vendor/bin/phpunit --configuration phpunit.xml tests/Feature/PublicTrackingTest.php
```

Existing source tests masked fields across roles, rejection of unknown/free-text checkpoints, real buyer receipt milestones, normalized valid code boundaries, no lookup for malformed codes, side-effect-free public reads, forbidden mutating methods and shared throttling. Database acceptance means public reads do not change custody, proof, payment or settlement and never expose private recipient/order fields.

## Evidence and pass criteria

For every authorized command, retain backend source revision, selected configuration, test class, actual start/end time, exit status and complete test/failure counts in a sanitized evidence file in this mobile repository. Record which assertions executed and any skipped tests; do not infer the result from a filename. Keep temporary paths, stack traces and logs free of secrets. Retain failure evidence before considering a fix; a failure in backend source is a reported backend issue, not authorization to edit that product.

Acceptance remains open until all selected database batches pass, required transaction-failure/foreign-owner/replay cases execute and missing cases are listed. Record fake provider/storage limitations and SQLite engine scope alongside the result. Passing these batches closes only their backend assertions, not deployed service, device, accessibility or provider acceptance.

## Separate mobile-to-backend socket acceptance

The commands above execute in-process backend HTTP requests and actual SQLite SQL. Mobile loopback tests execute Dart sockets against synthetic responses. Neither alone connects the production mobile adapter to an actual long-lived backend and database.

SQLite `:memory:` is scoped to a process/connection; it cannot be assumed to be the same database for a separate mobile process, a server process and a later inspection command. The existing feature suites do not supply a persistent fixture server, reset endpoint or database-inspection API. Do not invent those endpoints or start the ordinary developer backend.

A later end-to-end action therefore needs explicit authorization for an owner-supplied disposable server/fixture harness, an isolated test database with a defined lifetime, two different buyers plus guest/pending/active/restricted states, synthetic email/identity/file providers and backend-owned before/after assertions. Only then can the mobile adapter exercise real sign-in, Bag mutation, checkout/replay, payment, chat read/send, notification acknowledgement and return creation/commands through actual routes while database effects are checked. Evidence must distinguish that acceptance from both present mobile HTTP tests and the proposed in-process backend batches.

## Outstanding checklist

- [x] Read relevant existing backend configuration, test harness and named test source without changing or executing the backend.
- [x] Map concrete database/authorization/transaction concerns to existing classes and exact bounded commands.
- [ ] Obtain authorization naming disposable backend execution and its owner-provided isolated location.
- [ ] Verify the disposable copy's runtime/dependencies/configuration/storage/network boundaries without accessing real secrets or databases.
- [ ] Run the selected classes serially, capture actual results and report gaps/failures.
- [ ] Obtain separate authorization and fixtures for real mobile-to-backend socket/database acceptance.
- [ ] Complete deployed/provider/native-device acceptance under a later explicit scope.
