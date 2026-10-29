# Native Google authentication and buyer release readiness

## Goal and boundaries

Connect the Flutter buyer app to the implemented native Google exchange and registration contract, prepare owner-configurable release/link settings, and verify the affected buyer journeys. Keep all buyer functions native. The website, its Git/database/configuration and every sibling product remain read-only.

The baseline is mobile main `73407f5` (merged PR #9). The web handoff is the implemented `BUYER_NATIVE_GOOGLE.md`, `BUYER_APP_ASSOCIATIONS.md` and synthetic fixture pack in the web repository, with Google source delivered in `02a887d`. Verify executable source before implementing each operation; do not restore the superseded unsupported auth/push branch.

The owner has now connected an Android phone and requested a selectable Linux layout preview before the real Google test. Physical-device acceptance is not established by isolated tests or the Linux preview. Approved buyer hostname and Google public client IDs are supplied only through ignored owner records; no provider secret, signing key or private infrastructure value belongs in tracked files. Device push and the later efficiency proposals remain deferred.

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

- The latest `flutter devices --machine` read detects a supported physical Android16/arm64 device alongside Linux and Chrome. Flutter web is not a configured buyer target. No iOS/macOS build host is currently available.
- The owner requested the [selectable desktop preview](buyer-device-preview.md) before continuing actual Android Google sign-in. No real provider exchange has been performed by this session.
- Existing Google Web application client IDs can be reused as the server audience after owner/backend configuration; Android needs its own package/signing registration. Do not read backend secret files to discover owner configuration.
- The owner supplied the public Web client ID and identified the existing buyer hostname through its web callback screenshot. They also confirmed creating the requested Android development OAuth client and provided its public ID. All actual values are saved only in ignored owner notes/configuration and the existing shared handoff. The backend owner has now confirmed the deployed native Google settings contain both approved entries. Flutter continues using the Web ID as its server client. After an independent successful app-transport readiness check, the ignored mobile configuration now enables Android Google. Runtime provider acceptance is still pending.

## Implementation and verification outcome

Mobile implementation is complete on the unpublished working branch. The deployed backend connection and Android configuration are now verified and prepared. Actual device/provider sign-in and installed-link release acceptance remain pending; the overall readiness work is still open.

- `6336055` records the plan and boundaries.
- `1ec87c7` adds strict native Google exchange/registration contracts, direct JSON writes, CSRF/session handling, rate metadata and explicit read-only recovery.
- `d1bcd60` adds the maintained native Google SDK behind an injectable Android/iOS provider and explicit public configuration gates.
- `5f3db58` adds native account-link proof, expiring registration and policy forms, retained drafts, provider-flow lifecycle guards and responsive regressions.
- `f384162` exposes canonical address errors and avoids repeated screen-reader announcements from the cooldown countdown.
- `e702bb6` adds owner configuration tooling, matching native hosts/callbacks, release signing controls and setup documentation.
- This final documentation pass records combined evidence and a separate local PR draft. No branch publication is authorized for this task.

Observed final checks:

| Check | Result |
|---|---|
| Full isolated Flutter suite | **379 passed**, including 46 additional native Google/configuration checks beyond the 333-test baseline |
| `flutter analyze` | No issues found |
| Edited Dart formatting / whitespace | Clean |
| Android debug APK | Fresh configured APK compiles; package, certificate, native host and bundled owner configuration verified |
| Linux debug bundle | Compiled successfully; Google remains unsupported on Linux |
| Android release without owner signing | Correctly blocked by `validateBuyerReleaseSetup`; no signed release is certified |
| iOS property lists / configuration references | Parse and reference the shared link/callback settings; Xcode compilation unavailable |
| Public configuration helper | Example and ignored owner configuration validate; actual IDs/host are untracked |
| Read-only local backend probe | Core buyer contracts passed at the original implementation cutoff |
| Owner's hosted buyer origin | Fresh mobile reads confirm guest session200, Google capability200/version1/enabled and missing-challenge422 |
| Post-deployment Google regression selection | 17 relevant tests passed again against unchanged application source |

The new regressions cover direct HTTP/CSRF rotation, rejected redirects, strict challenge parsing, original buyer email/role confirmation, password proof, duplicate/rate/expiry/session guards, explicit uncertain-response recovery without POST replay, draft/policy preservation, paused lifecycle probes/queued links, canonical address feedback and narrow/landscape/tablet layouts with keyboard insets, 200% text and reduced motion. No browser automation, visible app launch or live account/order/payment/email/chat/database write was used.

## Operational acceptance status

1. The owner confirmed creating the development Android OAuth client and supplied its public ID. The backend owner has verified that the deployed Web audience and Android authorized-party entries are loaded. The current development APK's public certificate fingerprints are recorded only in the ignored owner setup note. Release/Play signing certificates need their own approved registration; a real provider/device exchange remains unverified.
2. Backend deployment/configuration readiness is now established for the existing native Google connection. The backend owner reports merged main `f001d39` with the integration commits present and post-deployment services healthy. Independent mobile HTTP evidence below supersedes the earlier missing-route observation. This mobile task changes no server settings or source.
3. Supply owner release signing and actual association identities; verify HTTPS association responses and installed cold/warm links on signed builds. No private key was requested or generated for release.
4. Complete native provider and full buyer-journey acceptance using approved test accounts when the owner connects a phone; use the concrete checklist in [release setup](../release-setup.md). iOS additionally needs an iOS public client ID, Apple team/provisioning and macOS/Xcode.

Device push and later efficiency work remain deferred. Passing isolated tests and compilation is not a zero-bug, live-provider or production-parity certification.

## Post-deployment Android preparation

The owner forwarded the backend maintainer's post-deployment handoff. A fresh read-only check using the app's actual `WebSession` transport independently confirms:

- Guest session HTTP200 with `authenticated=false`.
- Direct capability HTTP200 with contract version1, `native_google_sign_in=true` and `device_push=false`.
- Native registration GET without a challenge returns the expected HTTP422, demonstrating an enabled route.

Only GET requests were made by this mobile check. The backend maintainer separately reports an invalid synthetic-token/CSRF rejection check; no real provider login is inferred from it. The owner-approved Android build configuration is now enabled in the ignored local file. The relevant identity/configuration/registration/lifecycle regression selection passed **17 tests** again; the existing full379-test and analysis evidence applies to unchanged application source.

A fresh debug APK compiled with that configuration. APK inspection confirms its application ID and signing SHA-1 match the owner's development registration, its native link host matches the configured buyer origin, and the approved Web/server ID and origin are present in the bundled Flutter debug kernel. This verifies the prepared artifact, not a real Google token exchange. Build outputs and certificate/owner values remain ignored.

A physical Android device is now detected. The owner requested the [selectable desktop preview](buyer-device-preview.md) before continuing actual Google sign-in. iOS remains unconfigured pending its public client ID and a macOS/Xcode host. Domain associations and production release signing remain separate from this Android development registration.

## Handoff

Setup: [release-setup.md](../release-setup.md). PR title/body: [local draft](buyer-native-google-release-readiness-pr.md), not saved on GitHub. Actual build/test logs, owner configuration, certificate notes and web-agent coordination remain ignored machine-local artifacts.
