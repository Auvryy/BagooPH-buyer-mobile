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

Implementation in progress on `feat/buyer-profile-navigation`, created from main `de62e3e` after `git pull origin main` succeeded.
