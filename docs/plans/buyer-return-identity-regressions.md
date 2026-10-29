# Buyer returns, evidence and account misuse review

This continues the active review after published batch `fix/buyer-misuse-regressions` (`5ac5dc4`). Start from current merged main `5b021f2` on `fix/buyer-return-identity-regressions`; the first batch remains separately published for review. Keep this branch local until publication is explicitly requested.

## Acceptance and sequence

1. Exercise return creation, decisions, repayment confirmation and private evidence with malformed inputs, duplicate taps, uncertain responses, denied access, navigation and account changes. Reproduce confirmed defects before fixing them.
2. Verify native file selection limits, cancellation, unsupported types, unreadable/changing files and memory bounds using the installed official picker interface. Preserve backend validation as authoritative.
3. Exercise identity corrections, contact-email verification/preference/removal, session revocation and profile/address forms against their exact existing contracts. Retain useful drafts and clear private state when account context changes.
4. Continue the remaining Bag/product/shop, vouchers/orders/reviews, recovery, notifications/tracking and messaging scenarios from the broader coverage record. Keep evidence by feature; existing passing regressions alone do not complete native exploration.
5. Use the actual Linux app for desktop keyboard, paste, file-dialog and visible-feedback checks. Repeat confirmed cases in the native runner with synthetic fixtures and blocked outbound requests. Pass the full isolated suite, analysis, formatting and relevant native builds before handoff.

Only buyer mobile is writable. Backend source/configuration/Git/database remain read-only. No production accounts, messages, emails, orders, payments or synthetic spam. No website redirect replaces a buyer function. The first batch's reusable SDK fixture tooling may be reused without claiming its unmerged fixes are present on this branch.

## Coverage and evidence

| Area | Cases to establish | Evidence/status |
| --- | --- | --- |
| Return creation | Missing/invalid quantities, reason, description, photos; exact uncertain retry and one creation | Pending |
| Return decisions and repayment | Server-permitted actions, case/version/source-event binding, repeated taps, uncertain retry, denied access | Pending |
| Return privacy/lifecycle | Foreign owner/case/order, account changes, navigation, late results, failure after prior success | Pending |
| Private image/PDF viewing | Trusted-origin transport, empty/unsupported/corrupt files, changed account/path, long failure feedback/retry and small/large-text layout | Pending |
| Native picker | Cancel, empty, maximum and oversized files, unsupported extension/content, read failure, changing file, bounded reads | Pending |
| Identity corrections | Required evidence, dates/choices/text, source conflict, stale identity, failed/repeated submission | Pending |
| Contact emails | Original email immutable, required proof/code, edited destination, cooldown, duplicate/disposed responses, owner changes | Pending |
| Login sessions | Bound owner/session, proof/code, repeated revoke, uncertain intent, expired/changed/denied activity | Pending |
| Remaining buyer features | Dedicated native cases still open in the first batch's broader review | Pending, retain full objective |

## Findings and checks

No completion is claimed by this plan. Record reproduced failures, fixes, exact commands/results and remaining gates as work progresses. Real provider/OS/device acceptance remains distinct from native Linux fixture tests.
