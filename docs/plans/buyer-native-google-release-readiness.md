# Native Google authentication and buyer release readiness

## Goal and boundaries

Connect the Flutter buyer app to the implemented native Google exchange and registration contract, prepare owner-configurable release/link settings, and verify the affected buyer journeys. Keep all buyer functions native. The website, its Git/database/configuration and every sibling product remain read-only.

The baseline is mobile main `73407f5` (merged PR #9). The web handoff is the implemented `BUYER_NATIVE_GOOGLE.md`, `BUYER_APP_ASSOCIATIONS.md` and synthetic fixture pack in the web repository, with Google source delivered in `02a887d`. Verify executable source before implementing each operation; do not restore the superseded unsupported auth/push branch.

The owner will connect an Android phone later. Physical-device acceptance is therefore deferred by the owner, not established by isolated tests or Linux preview. Approved buyer hostname and Google public client IDs are requested; no provider secret, signing key or private infrastructure value belongs in tracked files. Device push and the later efficiency proposals remain deferred.

## Deliverables and acceptance

1. **Native identity SDK:** use the maintained Google Sign-In Flutter plugin on Android/iOS, behind an injectable provider. Keep plain-Dart repositories/tools independent of Flutter plugins. No automatic provider sign-in, website OAuth redirect or persistent provider token. Unsupported/unconfigured platforms keep email sign-in usable.
2. **Exact session transport:** direct same-origin JSON exchange/registration with CSRF, session rotation and structured 409/419/422/429/503 handling. Confirm authenticated buyer role/owner through the existing session endpoint; preserve original sign-in email and requested remember behavior. Never automatically replay a POST.
3. **Native account-link proof and registration:** explicit password proof for an existing password buyer, server-verified identity, expiring session-bound challenge, native adult-DOB/personal/canonical optional-address/policy form, retained validation feedback and explicit uncertain-response recovery. Do not create or approve an account locally.
4. **Interaction and accessibility:** reuse existing Bagoo crimson/slate components and Plus Jakarta Sans. Keep email drafts/navigation useful, prevent competing/duplicate auth, discard stale session results, clear sensitive references on cancellation/disposal, and support keyboard, large text, reduced motion and narrow/landscape/tablet layouts.
5. **Owner release setup:** non-secret configuration examples and validation, consistent base/link host, iOS Google callback configuration, and Android release signing that never silently substitutes debug keys. Keep owner overrides and keystores ignored; do not publish placeholder association identities.
6. **Verification:** meaningful isolated provider/controller/real-HTTP/registration/widget tests, full regression suite, analysis, formatting, Android debug and Linux builds. Exercise read-only local contracts without live account/order/payment/email/chat mutations. Prepare a concrete device/deployed-journey checklist with actual evidence and remaining owner prerequisites; no zero-bug or deployment certification claim.

## Logical commits

1. Plan and scope; owner-input/device acceptance ledger.
2. Pure native-auth contract models/repository and direct mutation/error metadata with HTTP regressions.
3. Native Google provider/configuration and dependency/platform integration.
4. Native authentication, link-proof and registration UI/controller with lifecycle and responsive tests.
5. Owner release/link configuration tooling and signing controls with validation.
6. Combined verification, current README/cumulative handoff and local PR title/body.

Complete coherent slices before starting another. Keep commits local; a previous branch's push authorization does not publish this branch.

## Current evidence and pending inputs

- `flutter devices --machine` reports Linux and Chrome only. Flutter web is not a configured buyer target; no Android/iOS device is connected.
- The owner confirmed an Android phone can be connected in the future. No iOS/macOS build host is currently available.
- Existing Google Web application client IDs can be reused as the server audience after owner/backend configuration; Android needs its own package/signing registration. Await approved public IDs and actual buyer hostname. Do not read backend secret files to discover them.
- Implementation and verification are in progress. Record actual checks and residual blockers below as work completes.
