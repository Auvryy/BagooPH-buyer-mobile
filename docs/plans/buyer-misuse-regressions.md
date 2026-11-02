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

The first published batch passed **449 isolated tests** and **25 native Linux cases**. A prior continuation checkpoint passed **788 isolated tests**, with native voucher bookmarks and picker (66), Bag/controller/dialog/stock/navigation (97), checkout/product/Bag/payment/voucher/layout (71 checkpoint plus separate 3 confirmation and 21 recipient-location cases), account/address/layout (80), return/evidence (53), actual PDF rendering (4), and earlier buyer/collection (26) runs. These native groups include controller cases, overlap and are not summed as distinct cases. The November 2 mainline baseline passed **923 isolated tests** with one worker. The current search-price branch passes 30 focused input/search tests and Flutter analysis; its full suite has not been rerun. See the [return/account review](buyer-return-identity-regressions.md), [checkout review](buyer-checkout-misuse-regressions.md) [Bag review](buyer-bag-misuse-regressions.md) and [voucher review](buyer-voucher-misuse-regressions.md) for their current evidence. The complete buyer acceptance audit remains open.

| Feature family | Misuse and recovery cases | Status / evidence |
| --- | --- | --- |
| Email login, registration and policies | Empty/malformed/long fields, age/policy gates, repeated taps, rejected credentials, retained drafts | Isolated auth/account regressions and native login/contact cases pass; desktop email/registration input feedback observed |
| Native Google | Unsupported platform, cancelled provider, link proof, expiry, retry delay, stale callbacks | Isolated Google contract/provider/controller/widget regressions pass; real Android/iOS provider acceptance remains pending |
| Recovery and verification | Invalid/long codes, password mismatch, resend/repeated submission, expired links | Shared verification/recovery regression coverage passes; dedicated native recovery/link exploration remains pending |
| Profile, identity, contact email, sessions | Invalid phone/evidence/code/password, original identity, duplicate mutations, failed saves | Native account/contact/password/credit cases pass; real typing, repeated submits, code rejection, identity proposals, session expiry and throttled resend feedback inspected; provider/device acceptance remains separate |
| Addresses, location and checkout | Invalid phone/postcode/coordinates, required selections, approval, stale quotes, duplicate placement | Native account/address and checkout/location checks pass; keyboard entry, expired confirmations, invalid GPS recovery and reviewed coordinates inspected; real OS permission/provider acceptance remains separate |
| Bag and product purchase actions | Text/negative/zero/excess quantity, stale stock/options, duplicate add/remove, errors and late replies after session changes | Native Bag privacy/dialog/stock/navigation checks pass; delayed Add to Bag, Save and sale-reminder replies reload account-scoped product data; focused product, checkout, cache and Bag suites pass; deeper native product navigation/options and voucher exploration continue |
| Search, home, campaigns, shop and collections | Invalid prices/pages, long query, rapid changes, empty/error/cache/retry, duplicate toggles | Search price inputs reject malformed typing/pastes while preserving the last valid edit; submit validators still reject over-cap and inverted ranges, including direct-controller bypasses. Thirty focused input/search tests and analysis pass; broader native shop exploration remains pending |
| Wallet, vouchers, orders and reviews | Nonfinite/out-of-range money, codes/photos, repeated financial actions, server eligibility/status | Native bookmark ownership/reply/repeated-action checks and wallet/post-purchase/quote regressions pass; order receipt/cancel/review session-scope regressions pass; private profile-list checks and broader native order/review exploration remain pending |
| Inbox, product chat and support | Whitespace/long drafts, repeated send, attachment validation, failed/uncertain delivery | Chat/support validation, repeated-send and lifecycle regressions pass; native attachment exploration remains pending |
| Returns and private evidence | Invalid codes/uploads, duplicate actions, wrong destination/origin, server-permitted actions | Native creation/decision/repayment/account/evidence and bounded picker regressions pass; actual file selection and separate/corrupt PDF rendering inspected; real backend acceptance remains separate |
| Notifications, public tracking and incoming links | Invalid IDs/numbers/URLs, read-only lookup, stale identities, explicit mutation confirmation | Link, tracking, notification and session regressions pass; native exploratory link/notification acceptance remains pending |
| Native Linux interaction/layout | Login and registration, navigation, phone entry, repeated taps, keyboard, narrow/large text | Three native SDK groups pass on a private display; actual keyboard/clipboard/picker feedback inspected; preview dialogs stay inside the phone with accessible side options; further checks respect the owner's desktop-input restriction |

## Findings

Inspection confirms that selecting a phone keyboard does not restrict text entry. Several mobile/contact forms currently have only length checks, while the existing backend accepts canonical Philippine mobile numbers. Reproduce before changing behavior.

Contact input: reproduced five baseline failures (letters accepted, and four malformed profile contacts submitted). Shared native form controls now reject an entire mixed-text edit and validate Philippine mobile formats on submission, including controller/autofill bypass. Optional blank contacts and legitimate local/international formatting remain supported. The final contact suite passes 31 cases; the earlier combined contact, Google, checkout and authentication run passed 59 cases. The checkout scrolling test now bypasses filtering intentionally to preserve its submission-validation coverage.

Account input: reproduced four weak-password submissions from Profile. Password change now shares registration/recovery validation, matching the existing backend's Unicode case/number/symbol and control-character rules. Email availability validation now rejects values over the backend's 255-character limit. Twenty focused authentication/profile tests pass, including twelve invalid wallet amounts, eight repeated credit taps producing one request, and uncertain retries retaining the exact original intent.

Native desktop input: opened `tool/qa_preview.dart` on Linux and used desktop keyboard events and the OS clipboard. Observed malformed email and missing password feedback, letters excluded from registration phone entry, a short number rejected with visible guidance, valid local/international formatting accepted, and a mixed-text paste leaving the prior valid contact unchanged. Missing adult birthday still blocks registration. These are real native-window interactions with synthetic data and blocked network requests, not real account creation or backend acceptance.

Collections: reproduced six baseline failures across Saved Products and Followed Shops: late removal callbacks accessed disposed state, foreign-owner refreshes retained prior private rows, and session changes still allowed a mutation. Both screens now discard obsolete callbacks, clear private state on access loss, and check identity before mutations and after their responses. Ten focused cases pass, including repeated taps, a session change during removal, and retaining rows during a temporary outage while clearing them after denied access.

A further two reproduced failures covered removal requests that fail after the session changes. These now clear the previous private rows as well, and obsolete controls cannot submit after access loss. All twelve collection cases pass in the real Linux runner, as part of a passing 25-case native form/lifecycle/checkout run.

Product detail: reproduced an Add to Bag response restoring the previous buyer's page and success message after the session changed. Product actions now stay tied to the session that loaded the page; late Add to Bag, Save and sale-reminder replies are discarded and the current product is reloaded. Six focused product foreground cases pass, along with product widgets (14), product/checkout layout (8), cached catalogue (4) and Bag (7). The current full isolated suite passes 831 cases with one worker, and static analysis is clean. The configured Android debug APK built; installation, physical-device journeys and provider acceptance remain open after ADB shell and install timeouts.


## Native verification and next review

The Flutter SDK `integration_test` dev dependency provides repeatable Linux runs with network access blocked. It reuses the contact, profile and collection misuse cases and adds a login/product/checkout journey with an invalid recipient, explicit review and exactly one synthetic order placement. The isolated preview is available with `flutter run -d linux -t tool/qa_preview.dart`; the normal preview and mobile entrypoint keep their existing backend behavior.

Final checks: 449 isolated unit/widget cases, 25 native Linux cases, clean static analysis and unchanged formatting for all 18 edited/new Dart files. Both the native Linux preview and the normal Android debug application build successfully. The native runner was also exercised in the desktop's short tiled window; lazy-list checks reveal retained content before asserting it, and checkout checks choose the visible review control.

Continue the pending native exploratory rows above after this batch. In particular, return requests/commands, attachments/private evidence, identity/contact-email/security actions, address/GPS changes and deeper voucher/order/review paths still need dedicated native misuse cases. Real provider, permission dialogs, backend authorization and Android/iOS device acceptance are separate and are not inferred from synthetic Linux tests. Keep the broader review task in progress.
