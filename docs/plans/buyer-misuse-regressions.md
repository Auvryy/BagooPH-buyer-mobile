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

The final isolated regression run passes **449 tests** across the implemented feature families. The native Linux run passes **25 cases**. Existing regression coverage is distinguished from dedicated native exploratory checks; this first validated batch does not complete the full buyer acceptance audit.

| Feature family | Misuse and recovery cases | Status / evidence |
| --- | --- | --- |
| Email login, registration and policies | Empty/malformed/long fields, age/policy gates, repeated taps, rejected credentials, retained drafts | Isolated auth/account regressions and native login/contact cases pass; desktop email/registration input feedback observed |
| Native Google | Unsupported platform, cancelled provider, link proof, expiry, retry delay, stale callbacks | Isolated Google contract/provider/controller/widget regressions pass; real Android/iOS provider acceptance remains pending |
| Recovery and verification | Invalid/long codes, password mismatch, resend/repeated submission, expired links | Shared verification/recovery regression coverage passes; dedicated native recovery/link exploration remains pending |
| Profile, identity, contact email, sessions | Invalid phone/evidence/code/password, original identity, duplicate mutations, failed saves | Account/session regressions and native contact/password cases pass; native identity/email/security exploration remains pending |
| Addresses, location and checkout | Invalid phone/postcode/coordinates, required selections, approval, stale quotes, duplicate placement | Quote/logistics/checkout regressions and a native invalid-contact-to-reviewed-order journey pass; manual address/GPS exploration remains pending |
| Bag and product purchase actions | Text/negative/zero/excess quantity, stale stock/options, duplicate add/remove, errors | Bag/stock/option/model/widget regressions pass; native product-to-checkout journey passes; further manual quantity exploration remains pending |
| Search, home, campaigns, shop and collections | Invalid prices/pages, long query, rapid changes, empty/error/cache/retry, duplicate toggles | Discovery/search/cache/page regressions pass; desktop keyboard search observed; broader native shop exploration remains pending |
| Wallet, vouchers, orders and reviews | Nonfinite/out-of-range money, codes/photos, repeated financial actions, server eligibility/status | Invalid wallet amounts, duplicate/retry cases and post-purchase/voucher regressions pass; broader native order/review exploration remains pending |
| Inbox, product chat and support | Whitespace/long drafts, repeated send, attachment validation, failed/uncertain delivery | Chat/support validation, repeated-send and lifecycle regressions pass; native attachment exploration remains pending |
| Returns and private evidence | Invalid codes/uploads, duplicate actions, wrong destination/origin, server-permitted actions | Return-label/post-purchase regressions pass; native return-form/upload misuse cases remain pending |
| Notifications, public tracking and incoming links | Invalid IDs/numbers/URLs, read-only lookup, stale identities, explicit mutation confirmation | Link, tracking, notification and session regressions pass; native exploratory link/notification acceptance remains pending |
| Native Linux interaction/layout | Login and registration, navigation, phone entry, repeated taps, keyboard, narrow/large text | 25 native SDK cases pass; real desktop keyboard/clipboard checks cover login, registration contacts and search |

## Findings

Inspection confirms that selecting a phone keyboard does not restrict text entry. Several mobile/contact forms currently have only length checks, while the existing backend accepts canonical Philippine mobile numbers. Reproduce before changing behavior.

Contact input: reproduced five baseline failures (letters accepted, and four malformed profile contacts submitted). Shared native form controls now reject an entire mixed-text edit and validate Philippine mobile formats on submission, including controller/autofill bypass. Optional blank contacts and legitimate local/international formatting remain supported. The final contact suite passes 31 cases; the earlier combined contact, Google, checkout and authentication run passed 59 cases. The checkout scrolling test now bypasses filtering intentionally to preserve its submission-validation coverage.

Account input: reproduced four weak-password submissions from Profile. Password change now shares registration/recovery validation, matching the existing backend's Unicode case/number/symbol and control-character rules. Email availability validation now rejects values over the backend's 255-character limit. Twenty focused authentication/profile tests pass, including twelve invalid wallet amounts, eight repeated credit taps producing one request, and uncertain retries retaining the exact original intent.

Native desktop input: opened `tool/qa_preview.dart` on Linux and used desktop keyboard events and the OS clipboard. Observed malformed email and missing password feedback, letters excluded from registration phone entry, a short number rejected with visible guidance, valid local/international formatting accepted, and a mixed-text paste leaving the prior valid contact unchanged. Missing adult birthday still blocks registration. These are real native-window interactions with synthetic data and blocked network requests, not real account creation or backend acceptance.

Collections: reproduced six baseline failures across Saved Products and Followed Shops: late removal callbacks accessed disposed state, foreign-owner refreshes retained prior private rows, and session changes still allowed a mutation. Both screens now discard obsolete callbacks, clear private state on access loss, and check identity before mutations and after their responses. Ten focused cases pass, including repeated taps, a session change during removal, and retaining rows during a temporary outage while clearing them after denied access.

A further two reproduced failures covered removal requests that fail after the session changes. These now clear the previous private rows as well, and obsolete controls cannot submit after access loss. All twelve collection cases pass in the real Linux runner, as part of a passing 25-case native form/lifecycle/checkout run.


## Native verification and next review

The Flutter SDK `integration_test` dev dependency provides repeatable Linux runs with network access blocked. It reuses the contact, profile and collection misuse cases and adds a login/product/checkout journey with an invalid recipient, explicit review and exactly one synthetic order placement. The isolated preview is available with `flutter run -d linux -t tool/qa_preview.dart`; the normal preview and mobile entrypoint keep their existing backend behavior.

Final checks: 449 isolated unit/widget cases, 25 native Linux cases, clean static analysis and unchanged formatting for all 18 edited/new Dart files. Both the native Linux preview and the normal Android debug application build successfully. The native runner was also exercised in the desktop's short tiled window; lazy-list checks reveal retained content before asserting it, and checkout checks choose the visible review control.

Continue the pending native exploratory rows above after this batch. In particular, return requests/commands, attachments/private evidence, identity/contact-email/security actions, address/GPS changes and deeper voucher/order/review paths still need dedicated native misuse cases. Real provider, permission dialogs, backend authorization and Android/iOS device acceptance are separate and are not inferred from synthetic Linux tests. Keep the broader review task in progress.
