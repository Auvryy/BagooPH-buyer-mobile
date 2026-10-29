# Buyer returns, evidence and account misuse review

This continues the active review after published batch `fix/buyer-misuse-regressions` (`5ac5dc4`). The branch started from merged main `5b021f2`, then locally integrated the published first batch so further tests cover the cumulative buyer changes. GitHub main still awaits the owner's review/merge. Keep `fix/buyer-return-identity-regressions` local until publication is explicitly requested.

## Acceptance and sequence

1. Exercise return creation, decisions, repayment confirmation and private evidence with malformed inputs, duplicate taps, uncertain responses, denied access, navigation and account changes. Reproduce confirmed defects before fixing them.
2. Verify native file selection limits, cancellation, unsupported types, unreadable/changing files and memory bounds using the installed official picker interface. Preserve backend validation as authoritative.
3. Exercise identity corrections, contact-email verification/preference/removal, session revocation and profile/address forms against their exact existing contracts. Retain useful drafts and clear private state when account context changes.
4. Continue the remaining Bag/product/shop, vouchers/orders/reviews, recovery, notifications/tracking and messaging scenarios from the broader coverage record. Keep evidence by feature; existing passing regressions alone do not complete native exploration.
5. Use the actual Linux app for desktop keyboard, paste, file-dialog and visible-feedback checks. Repeat confirmed cases in the native runner with synthetic fixtures and blocked outbound requests. Pass the full isolated suite, analysis, formatting and relevant native builds before handoff.

Only buyer mobile is writable. Backend source/configuration/Git/database remain read-only. No production accounts, messages, emails, orders, payments or synthetic spam. No website redirect replaces a buyer function. The locally integrated first batch supplies its existing validation fixes and native test tooling without publishing a main-branch merge.

## Coverage and evidence

| Area | Cases to establish | Evidence/status |
| --- | --- | --- |
| Return creation | Missing/invalid quantities, reason, description, photos; exact uncertain retry and one creation | Focused creation cases pass; obsolete selections/reasons reset on refresh and missing signed form tokens block submission |
| Return decisions and repayment | Server-permitted actions, case/version/source-event binding, repeated taps, uncertain retry, denied access | Decision validation, duplicate taps and exact uncertain retries pass; deeper repayment cases remain open |
| Return privacy/lifecycle | Foreign owner/case/order, account changes, navigation, late results, failure after prior success | Account/resume/evidence-navigation cases pass; confirmed details survive temporary refresh failure with decisions disabled |
| Private image/PDF viewing | Trusted-origin transport, empty/unsupported/corrupt files, changed account/path, long failure feedback/retry and small/large-text layout | Pending |
| Native picker | Cancel, empty, maximum and oversized files, unsupported extension/content, read failure, changing file, bounded reads | Pending |
| Identity corrections | Required evidence, dates/choices/text, source conflict, stale identity, failed/repeated submission | Pending |
| Contact emails | Original email immutable, required proof/code, edited destination, cooldown, duplicate/disposed responses, owner changes | Pending |
| Login sessions | Bound owner/session, proof/code, repeated revoke, uncertain intent, expired/changed/denied activity | Pending |
| Remaining buyer features | Dedicated native cases still open in the first batch's broader review | Pending, retain full objective |

## Findings and checks

No completion is claimed by this plan. Real provider/OS/device acceptance remains distinct from native Linux fixture tests.

The initial return suite reproduced eight failures: access-denied refreshes retained private details/actions, another buyer's response was accepted, old-session actions could open, late reads could reveal details, and missing buyer IDs were accepted. Return work now binds to its opening buyer/session and clears private drafts, evidence and actions on access loss. Two existing boundary cases (temporary failure retention and mismatched case rejection) remain covered.

Private-document checks reproduced an overflowing long error message, an image accepted after a session change, and a changed evidence path retaining its previous read. The viewer now binds reads to its session, resets snapshots when the resource changes, rejects late data and keeps failure feedback/retry scrollable at large text sizes. All thirteen isolated return/document widget cases pass; native exploration is still required.

File-picker checks separately reproduced accepting an emptied file, reading a growing file without a bound, and exposing raw filesystem/platform failures. The picker now streams with its existing size limit and reports safe, recoverable failures. Twelve picker checks pass alongside the thirteen widget cases; server content and ownership validation remain authoritative.

The next return pass reproduced five form/action issues: an empty signed request token reached submission, failed refreshes left decision buttons enabled, removed or unavailable purchases remained selected, and removed reason choices crashed the dropdown. Creation and decisions now require current confirmed form details; refreshed options discard obsolete selections without dropping useful descriptions/photos. Existing duplicate-tap and uncertain-retry cases retain their exact original intent.

Four additional boundary cases reproduced old private return details on resume, evidence opening against a changed account during navigation, and a new repository wrapper resetting an expired document scope. Evidence viewers now inherit the opening scope without invalidating their parent when closed; replacing a thin wrapper around the same session cannot renew access. The combined return/document/action suite passes 38 widget cases. Native repayment and remaining account exploration are still pending.

Actual Linux desktop checks used OS keyboard input, the clipboard and the real native file dialog against synthetic data with outbound requests blocked. Invalid quantities/descriptions and short decision reasons showed visible validation, a known temporary PNG was selected through the native picker, and changing the test account removed the open private decision form. Inspection images remain temporary and untracked. Quantity letters were accepted as a draft before submission validation; a dedicated input-filter follow-up remains required.

The same 38 return/action/document cases now pass in the native Linux SDK runner. The driver dismisses input focus and reveals controls centrally before tapping in smaller native windows; it asserts actual hit targets and confirmed request counts. This avoids treating an offscreen tap as a successful test. The standalone review tool exposes the existing device sidebar plus selectable synthetic return, image, long-failure, denied-access and changed-form scenes. A preview semantics regression was reproduced and fixed while preserving the sidebar's visual position and full-height phone; eight preview cases pass. Native large-text failure and explicit retry recovery were also inspected.

Further isolated account-settings exploration reproduced thirteen failing scenarios across email destination/confirmation binding, identity source/conflict handling and login-session privacy. These remain open until their fixes and native acceptance run; the broader audit is still in progress.
