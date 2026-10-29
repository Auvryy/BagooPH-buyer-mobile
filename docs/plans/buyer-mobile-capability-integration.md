# Buyer mobile capability integration

## Scope and agreement

The existing web agent and mobile agent agreed a first native integration slice: a guest-safe JSON `GET /buyer/mobile-capabilities` response with `contract_version: 1` and explicit boolean `features.native_google_sign_in` and `features.device_push` fields. The initial backend response disables both features. The route retains `Cache-Control: private, no-store` and does not change existing session, CSRF or Inertia contracts.

The web agent owns implementation on its separate web branch. It delivered local web commit `91795f5` with the route/controller/configuration, documented contract and sanitized disabled fixture. Its authored readiness report records 49 passing isolated capability/session/browser-Google checks with 669 assertions. Mobile inspected those sources read-only; it did not run backend tests or modify that repository. Local readiness does not establish deployment.

The owner's device-push work is deferred, as are chat pagination/read separation, conditional reads and public catalogue/media revisions. Native Google and installed-link association remain separate implementation/configuration work after their contracts are ready. A supported capability flag alone does not make an absent native SDK or owner configuration available.

## Acceptance criteria

1. Preserve the ignored local coordination file and each existing agent's authorship. Both agents introduce themselves and acknowledge the selected capability/session slice.
2. Parse only the agreed version and explicit boolean fields. Missing, malformed, partial, truthy-string and unsupported-version replies disable all optional capabilities. Compatible extra fields must not become new permissions.
3. When the web agent announces its implemented contract, verify the actual route/controller and fixtures read-only. Add a read-only optional discovery adapter using the existing same-origin session transport; do not add a networking framework or authentication scheme.
4. Missing/disabled/unavailable discovery must not block existing email authentication or native shopping. Never queue/replay mutations or log credentials. Do not show an unfinished provider control.
5. Cover the agreed success/disabled/invalid/error/session boundaries using isolated fixtures and local HTTP transport as appropriate. Run focused tests, static analysis and formatting for source changes, then the relevant regression gate.
6. Record actual server/mobile evidence and unperformed deployment/device/provider checks. Keep all sibling products read-only and leave commits local until a new explicit push instruction.

## Logical commits

1. Local communication: ignore the shared notes and make them discoverable from mobile instructions. Completed in `0aa97e7`.
2. Capability model: strict version-one parser and isolated contract-boundary checks. Completed in `3b18141`.
3. Probe runtime repair: keep the vault interface independent of Flutter while preserving the native implementation. Completed in `9e54648`.
4. Optional discovery: verified route integration and failure/session regression checks. Completed in `d6dfeeb`.
5. Documentation and combined verification: explain current behavior, capability limits, remaining Google/link prerequisites and prepare an updated local PR description.

## Status

- Both existing agents have authored introductions and acknowledged the capability/session schema in their local exchange.
- The pure version-one parser is implemented. All seven focused contract checks pass, including strict versions, independent booleans, malformed/partial replies and compatible extra fields. `flutter analyze --no-pub` reports no issues; formatting and whitespace checks pass.
- The on-demand discovery adapter is implemented behind `BuyerRepository.discoverCapabilities()`. A direct same-origin JSON read rejects redirects before accepting their cookies or JSON bodies. Existing login/page redirects remain unchanged. Discovery adds no startup wait, periodic poll or persistent cache; the diagnostic probe reports it separately from core checks.
- All 35 focused capability, direct transport, existing web-session and persistence checks pass. They include the shared web fixture, malformed replies, HTTP errors, redirect grants/cookies, lost connection, stale identity responses and ordinary email login after discovery fails. The publication full suite passes all 333 isolated tests, including the standalone CLI and session-alias regressions.
- No Google SDK, push SDK or new provider control has been added by this slice. The agreed next Google proposal includes explicit existing-account password proof and a server-expiring native challenge; implementation and SDK acceptance remain separately scoped.
- The documented standalone probe initially could not compile because the vault interface imported the Flutter secure-storage plugin. The interface is now pure Dart; the native implementation moved unchanged to `native_session_vault.dart` with the app import updated. All 21 focused storage/session/cache checks and a CLI subprocess regression pass. Native key names and settings are unchanged.
- The anonymous read-only probe passed against the existing local backend: Home, registration/policies, catalogue/search/filters, product/shop, guest Bag and checkout locations, followed by supported capability v1 with both optional flags false. It used no account, email, order/payment/message or database mutation. Azure, native provider configuration, association setup and Android/iOS device acceptance remain separate unperformed checks.

This plan describes only the selected first integration slice. Implemented status must be updated from actual source and checks; later proposals remain separately scoped.

## Final verification

- `flutter test --no-pub --reporter expanded`: all 333 tests passed in 1 minute 34 seconds after the session compatibility follow-up. Evidence: `.git/buyer-capability-push-tests.log`.
- `flutter analyze --no-pub`: no issues. Evidence: `.git/buyer-capability-push-analyze.log`.
- Dart formatting and `git diff --check`: passed. No dependency, platform build setting or native storage behavior changed; Android/iOS packaging was not rebuilt for this Dart/transport slice.
- `dart run tool/check_backend.dart` against the existing local service: public buyer checks and capability v1 passed, with Google and push both advertised false. Evidence: `.git/buyer-capability-local-probe.log`. No production/private/mutation acceptance was performed.
- The local exchange is ignored and untracked; both existing agents authored their own introductions, agreed the schema, reviewed the actual server slice and exchanged test evidence. It contains no provider credentials and is not part of a commit.
- All implementation is mobile-owned. The web agent independently owns its backend branch and verification. Google SDK, final Google contracts, provider identities, signing/domain associations, Azure and physical-device acceptance remain subsequent work.

## Publication compatibility follow-up

The web maintainer's later executed session fixtures revealed that approved and pending buyers restore through the exact `/buyer` Home alias. Before publishing this branch, mobile added that alias while retaining same-origin resolution and the fetched buyer-role/numeric-owner checks. The shared synthetic account-state fixture is retained in `test/fixtures/buyer-session-states.json`; regression checks cover approved/pending/restricted/rejected states, wrong roles, malformed owner IDs and unsupported/foreign paths. Existing `/` support is retained. No server redirect was changed.
