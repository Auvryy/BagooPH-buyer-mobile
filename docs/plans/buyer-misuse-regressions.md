# Buyer misuse regression review

Start: merged buyer main `5b021f2`; working branch `fix/buyer-misuse-regressions`.

## Scope and acceptance

Exercise every implemented buyer feature family against invalid input, repeated actions, failed requests and stale identity. Reproduce confirmed client bugs with isolated regression tests before fixing them. Open the native Linux app using synthetic repositories, never production accounts or shopping mutations. Backend source and configuration remain read-only.

Acceptance requires a coverage record for each family, passing formatting/analysis and the full isolated suite, and a native Linux interaction run. Client checks must match existing server rules; server authorization, stock, payment and order state remain authoritative. Native provider, OS permission and real device acceptance are separate evidence and must not be inferred from Linux tests.

## Commit sequence

1. Record this plan and coverage inventory.
2. Fix contact/numeric input defects, with typed, pasted and submission validation cases.
3. Fix confirmed duplicate-action, failure recovery and session/navigation defects in coherent slices.
4. Add repeatable native Linux misuse checks using the Flutter SDK integration-test package and synthetic data.
5. Run all checks, update the coverage record, and prepare the branch PR description before publication.

## Coverage record

Status starts as **pending**. Existing regression tests are a baseline, not a claim of exhaustive manual testing. Record test files and concrete limitations as each review finishes.

| Feature family | Misuse and recovery cases | Status / evidence |
| --- | --- | --- |
| Email login, registration and policies | Empty/malformed/long fields, age/policy gates, repeated taps, rejected credentials, retained drafts | Pending; `widget_test.dart` baseline |
| Native Google | Unsupported platform, cancelled provider, link proof, expiry, retry delay, stale callbacks | Pending; Google contract/controller/widget baseline; real provider remains separate |
| Recovery and verification | Invalid/long codes, password mismatch, resend/repeated submission, expired links | Pending |
| Profile, identity, contact email, sessions | Invalid phone/evidence/code/password, original identity, duplicate mutations, failed saves | Pending; account parity/session baseline |
| Addresses, location and checkout | Invalid phone/postcode/coordinates, required selections, approval, stale quotes, duplicate placement | Pending; checkout baseline |
| Bag and product purchase actions | Text/negative/zero/excess quantity, stale stock/options, duplicate add/remove, errors | Pending; Bag/product baseline |
| Search, home, campaigns, shop and collections | Invalid prices/pages, long query, rapid changes, empty/error/cache/retry, duplicate toggles | Pending; discovery/cache baseline |
| Wallet, vouchers, orders and reviews | Nonfinite/out-of-range money, codes/photos, repeated financial actions, server eligibility/status | Pending; post-purchase/voucher baseline |
| Inbox, product chat and support | Whitespace/long drafts, repeated send, attachment validation, failed/uncertain delivery | Pending; chat/support baseline |
| Returns and private evidence | Invalid codes/uploads, duplicate actions, wrong destination/origin, server-permitted actions | Pending; post-purchase baseline |
| Notifications, public tracking and incoming links | Invalid IDs/numbers/URLs, read-only lookup, stale identities, explicit mutation confirmation | Pending; links/tracking/notifications baseline |
| Native Linux interaction/layout | Login and registration, navigation, phone entry, repeated taps, keyboard, narrow/large text | Pending; SDK integration harness planned |

## Findings

Inspection confirms that selecting a phone keyboard does not restrict text entry. Several mobile/contact forms currently have only length checks, while the existing backend accepts canonical Philippine mobile numbers. Reproduce before changing behavior.
