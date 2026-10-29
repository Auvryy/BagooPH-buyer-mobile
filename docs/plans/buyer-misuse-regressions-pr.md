# PR title

Fix buyer form validation and collection session handling

# PR description

Buyer contact fields accepted letters, Profile submitted weak replacement passwords, and Saved Products/Followed Shops could update disposed state or retain a previous buyer's rows after an account change. Validate Philippine mobile contacts and server-compatible passwords locally, reject mixed-text contact pastes, and discard collection work after navigation, access loss or session changes, including failed requests.

Add an isolated native Linux preview and repeatable SDK integration checks using the real buyer widgets with synthetic data and blocked network requests. The regular app keeps its existing backend configuration; only buyer mobile changes.

Validation:

- 449 isolated unit/widget tests pass; static analysis and formatting pass.
- 25 native Linux cases pass, including repeated taps, uncertain retries, obsolete collection callbacks and a login/product/checkout journey requiring valid input and explicit order review.
- Actual desktop keyboard and clipboard checks confirm login feedback, rejected phone letters/short numbers/mixed pastes, valid Philippine formats, required birthday and native search input.
- The native Linux debug preview and normal Android debug application build successfully.

This is the first validated bug-fix batch. Dedicated native exploration of remaining identity/email/security, address/GPS, returns/evidence and deeper order/voucher/review paths is recorded in `docs/plans/buyer-misuse-regressions.md`. Real Google, permission dialogs, backend authorization and Android/iOS device acceptance remain separate; iOS cannot be built on this Linux host. No real accounts, messages, orders, payments or emails were created during these checks.
