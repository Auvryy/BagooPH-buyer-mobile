# Buyer mobile capability integration

## Scope and agreement

The existing web agent and mobile agent agreed a first native integration slice: a guest-safe JSON `GET /buyer/mobile-capabilities` response with `contract_version: 1` and explicit boolean `features.native_google_sign_in` and `features.device_push` fields. The initial backend response disables both features. The route retains `Cache-Control: private, no-store` and does not change existing session, CSRF or Inertia contracts.

The web agent owns implementation on its separate web branch. At the start of this plan, it has confirmed the schema but has not announced implementation, isolated test completion or deployment. Prepare parsing independently; wire production requests only after checking the actual backend source and agreed fixtures. Do not infer endpoint readiness from this plan.

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
2. Capability model: strict version-one parser and isolated contract-boundary checks.
3. Optional discovery: verified route integration and failure/session regression checks, after web implementation is ready.
4. Documentation and combined verification: explain current behavior, capability limits, remaining Google/link prerequisites and prepare an updated local PR description.

## Status

- Both existing agents have authored introductions and acknowledged the capability/session schema in their local exchange.
- The pure version-one parser is implemented. All seven focused contract checks pass, including strict versions, independent booleans, malformed/partial replies and compatible extra fields. `flutter analyze --no-pub` reports no issues; formatting and whitespace checks pass.
- No app network call, Google SDK, push SDK or new provider control has been added by this slice. The optional discovery adapter awaits the web agent's implementation and fixture announcement.
- The web implementation, deployment, provider configuration, association setup and Android/iOS device acceptance remain unverified until their own evidence is available.

This plan describes only the selected first integration slice. Implemented status must be updated from actual source and checks; later proposals remain separately scoped.
