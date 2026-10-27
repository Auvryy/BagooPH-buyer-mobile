# Native buyer profile and primary navigation

## Requested outcome

- Start from freshly pulled `main` on a new feature branch, keeping all changes in `BagooPH-buyer-mobile`.
- Bottom navigation is exactly Home, Cart, Search, Profile. Cart renders the native Shopping Bag; Search has its own catalogue/search state. Preserve the existing home and native shopping flows.
- Match the existing buyer website profile: Plus Jakarta Sans, crimson accent, slate canvas, rounded white panels, identity summary, clear section navigation, and responsive sidebar/content grouping.
- Render the website's profile sections natively: purchases/order history, personal info/avatar, email/recovery, password, identity verification/correction, login activity, address book, wallet, and vouchers. Use existing server contracts and eligibility rules. Profile shortcuts must remain native.
- The original sign-in email and account role remain fixed. The server owns identity approval, authorization, balances, order transitions, and all saved results.
- Support loading, empty, error/retry, pending/restricted accounts, safe areas, keyboard input, large text, and tablet/desktop widths. Preserve form state and prevent duplicate mutations.
- Never edit the Bagoo web/backend repository or replace native functions with website redirects.

## Implementation slices

1. Verify website design and contracts; add profile transport/repository helpers and native file selection where uploads require it.
2. Build responsive profile shell and native account/security/identity forms.
3. Build address, wallet, voucher, and purchase workspaces with server-confirmed actions and native detail routes.
4. Integrate Home/Cart/Search/Profile navigation, update setup/scope documentation, and prepare a local PR draft.

## Verification and handoff

Use formatting, static analysis, native compilation, source/contract review, and read-only backend inspection. Do not mutate live profiles, send email, revoke sessions, request credits, or change orders for verification. Do not add or run automated tests unless the user requests testing/verification. No visible browser or screenshots for routine checks. Record actual results here and keep commits local until the user asks to push.

## Completed implementation

Implemented on `feat/buyer-profile-navigation`, created from main `de62e3e` after `git pull origin main` succeeded.

- Exact Home, Cart, Search, Profile destinations, independent server-backed search, retained visited tabs, and native sign-in returning to Profile.
- Responsive profile overview/menu on small windows and sidebar/content layout on wider windows. The website's Plus Jakarta Sans, crimson accent, slate canvas, rounded white panels, and identity summary are reused. Visited forms retain input.
- Native personal/avatar, contact-email verification, password, identity evidence/application correction/review requests, and login-activity/session controls using the verified backend contracts.
- Native canonical address editing, demo wallet request/history, voucher collections, paginated purchases/tracking/actions, Buy Again, reviews/photos, pickup codes, return/refund cases/evidence/actions, and inbox/photo messaging.
- Native file selection and authenticated in-app PDF/image viewing. No website handoffs, original-email replacement, role conversion, inferred payments, or automatic receipt confirmation.
- Refresh when returning to Profile/Cart, bounded pagination correction, session-change response rejection, actionable errors, and explicit retries for uncertain commands.

## Verification evidence — 2026-10-27

- `dart format --output=none --set-exit-if-changed lib test tool`: passed, 54 files unchanged.
- `flutter analyze`: passed, no issues.
- `flutter build apk --debug`: passed.
- `flutter build linux --debug`: passed.
- Authenticated local backend inspection: profile/shared application, owned login activity, one existing order/tracking response, return index, inbox list, and canonical regions matched the native implementation. Inspection signed out afterward; only inspection-session metadata changed. No conversation was opened and no profile, email, credit, order, return, or message mutation was performed.
- Source review checked website profile structure, request payloads, eligibility, server-confirmed acknowledgements, native navigation, input retention, constrained/scrollable layouts, labels, and keyboard handling.
- `git diff --check`: passed. Work is confined to this mobile repository. The web repository's existing unrelated audit file and branch were left as found.

No automated tests were added or run for this pass. Existing navigation fixture labels were updated only. iOS compilation requires macOS/Xcode and was unavailable. Manual device interaction, picker/PDF behavior, small-window/landscape/large-text/accessibility checks, and end-to-end mutations remain unverified. The app uses its existing light theme.

The user has now authorized publishing this feature branch to GitHub for merging. A combined PR title/body will be kept in `.git/PR_BUYER_PROFILE_NAVIGATION.md`; GitHub PR creation is separate from pushing the branch.
