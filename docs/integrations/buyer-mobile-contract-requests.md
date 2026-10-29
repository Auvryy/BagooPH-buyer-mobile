# Website contracts requested for future native buyer features

For the current parity work, give the website AI [website-ai-handoff.md](website-ai-handoff.md). It records the current existing contracts, owner link setup, versioned logistics documentation and concrete website prerequisites. The older baseline below is historical verification evidence.

The cumulative handoff also records the implemented foreground conversation/inbox/order refresh and read-only catalogue cache. Its sections 6–7 identify future pagination, separate chat read acknowledgements, conditional reads and public cache metadata. Those improvements are proposals, not endpoints called by mobile today.

These are recommendations for the website maintainer. This document lives in the mobile repository. No website code, routes, migrations, dependencies, or deployment configuration are part of this mobile review.

## Existing contracts retained by mobile

Source was inspected read-only on the website's `main` at `ac9a893`.

| Feature | Existing contract | Mobile behavior |
| --- | --- | --- |
| Buyer email authentication | `/login`, `/logout`, registration and OTP routes | Existing native screens and cookie/CSRF session |
| Bagoo assistant | `POST /buyer/support/assistant` | Native message form with a maximum 1,000-character message and optional 50-character order number; server remains responsible for buyer approval and account context |
| Customer Care | `/chat/messages/2`, `/chat/send` | Existing native chat and photo attachment flow |
| Notifications | `/notifications`, `/notifications/preview`, owned read and read-snapshot routes | Native inbox, explicit read actions, and refresh on app resume |
| Public parcel tracking | `GET /track?number=...` | Native guest/buyer lookup with the existing `Public/Tracking` page contract, server labels, masked recipients, and recorded milestones |

The website source for these contracts is `routes/web.php`, `routes/auth.php`, `CustomerServiceAssistantController`, `ChatController`, `NotificationController`, and `NotificationCenterService`.

## 1. Native Google identity exchange

The existing Google authentication routes use browser OAuth redirects. They do not provide a native JSON identity exchange. The app currently uses email authentication and does not redirect a buyer to the website for Google sign-in.

The website maintainer should define a buyer-only endpoint that accepts a Google ID token, verifies its signature, issuer, expiry, audience and authorized party, subject, and verified email, then returns a confirmed authentication result or a bounded registration challenge. Client-supplied email, role, or Google user ID must not establish identity.

New-account completion should reuse current buyer age, name, address, policy-version, approval, and account-linking rules. Document the request/response schema, validation errors, session regeneration, expiration, retry behavior, and allowed OAuth client IDs before the mobile SDK is connected. Keep provider secrets on the server.

The latest agreed next-slice proposal adds optional boolean `remember` (default false) and existing-account `account_password` proof when a verified Google identity would first link an email/password buyer. Missing proof returns HTTP 409 with `code: GOOGLE_ACCOUNT_LINK_REQUIRED`; invalid proof returns 422 field feedback for `account_password`. Already-linked subjects do not require that proof. Registration uses `registration_nonce`; its response includes integer `expiresAt` in UTC Unix seconds, and its session-bound native challenge lasts at most 600 seconds without outliving the verified ID token. Keep native and browser challenge purposes separate. These details await their own implemented/tested server handoff before native SDK integration; credentials and challenges remain in memory and failed POSTs are not replayed automatically.

## 2. Optional device push delivery

The current website does not expose a buyer device-token registration/revocation contract or a Firebase sender. The app therefore retains its native inbox without presenting push as an available feature.

The website maintainer should define authenticated opt-in registration and revocation, platform identification, device-token rotation and account-switch behavior, encrypted token storage, and invalid-token cleanup. Push messages should contain a generic alert and an owned notification identifier; order, payment, address, and contact details should be fetched only after authentication.

Keep push delivery optional and independently retryable. A disabled feature, missing provider credentials, unavailable storage, or Firebase failure must not prevent the website from recording or displaying its existing in-app notifications. Agree a deployment/migration order and verify the disabled and failure cases before enabling push. Android/iOS Firebase configuration, APNs, and backend service-account access are separate owner configuration tasks.

## 3. A versioned mobile capability contract

The web maintainer agreed and implemented guest-safe `GET /buyer/mobile-capabilities` version one in local web commit `91795f5`. It returns integer `contract_version: 1` and required boolean `features.native_google_sign_in` and `features.device_push`, with private/no-store caching and no submitted CSRF requirement. Mobile has a strict on-demand reader; unavailable, invalid, unsupported and redirected responses enable no optional capability. The shared disabled fixture is retained in `test/fixtures/buyer-mobile-capabilities-disabled.json`.

This confirms local source/schema support, not deployment, native SDK setup or device acceptance. The backend probe reports optional discovery separately from core checks; startup and email login do not wait for it. Device push is deferred by the owner and remains false. Google still needs its separately implemented and verified exchange, native SDK and approved owner configuration.

Longer term, stable buyer JSON contracts can reduce the app's dependency on Inertia page props. Preserve the existing web authorization and buyer business rules while providing mobile contracts for the same server-owned results.

## Mobile boundary

The earlier native Google and Firebase SDK integrations were removed from this mobile working tree because their server contracts were reversed. Native support, email authentication, shopping, profile, chat, and in-app notifications continue to use existing contracts. Future website work should be implemented and reviewed in its own authorized website session; this mobile task must only read that product.

## Proposed route and response handoff

The names below remain proposals pending their own implementation/schema verification and mobile integration. The confirmed capability route is documented above. Existing website pages and browser OAuth routes should keep their current contracts; a locally implemented capability response does not establish the other routes as deployed.

| Proposed route | Request | Confirmed response |
| --- | --- | --- |
| `POST /auth/google/native` | Google `id_token`, optional boolean `remember`, and `account_password` only when existing-account link proof is required, using the agreed session/CSRF contract | Authenticated buyer session or registration required; explicit 409 link-proof challenge where applicable; no browser redirect or client-trusted identity |
| `GET /auth/google/native/registration` | Same session that received the registration challenge | Verified identity, registration nonce, integer `expiresAt`, adult birth-date limits, and current policy URLs/versions |
| `POST /auth/google/native/register` | `registration_nonce`, native personal/address fields, accepted policy versions | Confirmed registered buyer session using the existing buyer registration service; no client-supplied Google subject or role |
| `POST /buyer/push-device` | Authenticated opt-in buyer; device token and Android/iOS platform | Explicit registration acknowledgement and opaque device handle tied to the authenticated owner; repeated registration is idempotent |
| `DELETE /buyer/push-device` | Authenticated owner and registered device handle; agree token-based compatibility if needed | Explicit revocation acknowledgement; repeated revocation is harmless and does not depend on Firebase returning a fresh token |
| `GET /notifications/{uuid}` (optional) | Authenticated buyer | One currently owned, permitted notice and its existing buyer destination; supports opening a specific push notice without searching paginated inbox pages |

Agree field names, nullability, versions, and examples with the mobile maintainer before implementation. Return JSON validation errors using the existing message/errors shape. Specify 401 for expired authentication, 403 for denied access, 422 for rejected input/challenges, 429 for rate limits, and 503 for unavailable provider configuration. Keep authentication and private responses non-cacheable. The app must never infer success from a redirect or a missing acknowledgement.

Confirmed version-one disabled capability response before provider setup:

```json
{
  "contract_version": 1,
  "features": {
    "native_google_sign_in": false,
    "device_push": false
  }
}
```

Suggested Google outcomes are `{"authenticated": true}` or `{"registration_required": true}`. The registration response should name `identity`, `registrationNonce`, `birthDateLimits`, and `policies`, using the existing registration services as the authority. After an uncertain authentication response, use an agreed read-only session check instead of automatically replaying a registration POST.

Suggested device registration acknowledgement is `{"registered": true, "device_id": "<OPAQUE_DEVICE_HANDLE>"}`; revocation acknowledgement is `{"removed": true}`. The handle is owner-bound and must never authorize another buyer's device. Agree secure client storage and logout/account-switch cleanup before implementing the SDK flow.

### Google authentication acceptance cases

- Reject wrong audience/authorized party, issuer, signature, expired tokens, missing subject, and unverified email. Provider connection failures must return a retryable error without logging tokens or claims.
- Match/link only buyer identities under the current account rules. Reject conflicting Google links; preserve original sign-in email and fixed role. Retain suspended, closed, rejected, pending, and approved account behavior.
- Bind new registration to the same session and a short-lived nonce. Validate name, age 18+, optional canonical address, current policy versions, and challenge expiry with existing services.
- Regenerate the session on confirmed authentication. Define duplicate registration and uncertain-response behavior so the app cannot silently create a second account.
- Supply the approved Web/server audience and Android/iOS client registrations, including release signing fingerprints. Server secrets stay outside mobile source and build defines.

### Push delivery acceptance cases

- Register and revoke only for the authenticated buyer. Handle account changes and token refresh without delivering one account's updates to another; revoke on logout and explicit opt-out.
- Encrypt stored tokens, use a hash for lookup/uniqueness, keep device ownership explicit, and avoid returning/logging credentials. Clean up invalid and expired registrations.
- Record independent, deduplicated delivery intents only for notifications the buyer can currently view. Recheck ownership and device activity before sending. Limit expiry, retry transient failures with backoff, and deactivate tokens only on a confirmed invalid-token response.
- Send generic lock-screen text and a notice UUID. Fetch private details only after authentication. App taps must not mark an order delivered, confirm receipt, issue refunds, or perform another business action.
- Keep provider credentials server-side and document the Firebase/APNs owner setup, worker/scheduler requirement, health signals, and rollback switch.

## Website compatibility and rollout gates

1. Add contract/capability discovery with Google and push disabled. Existing mobile email authentication, shopping, public tracking, and website pages should continue working without these features.
2. Review schema and optional service changes on a separately authorized website branch. Apply the agreed migration/deployment order with features disabled.
3. Verify ordinary website login, registration, checkout, and in-app notification creation when push is off, storage is not ready, provider configuration is missing, and the provider times out. Optional push errors must not roll back or stall existing website notifications.
4. Verify Google identity rejection/linking and registration-policy cases, device ownership/revocation, notification ownership, duplicate delivery, retries, and expired intents in isolated tests.
5. Configure provider credentials, OAuth registrations, Android signing, and APNs. Advertise only the tested contract versions as enabled.
6. Connect and verify the mobile SDKs against those advertised contracts. Keep the current email authentication and native inbox usable during a provider outage. Disable the optional feature through its rollout switch without changing core website behavior.

## What is required for the new native tracker

No new website endpoint or migration is required. The existing controller renders `Public/Tracking` when the request accepts a page/Inertia response and returns a different, smaller JSON shape for a JSON-only request. Mobile deliberately uses its page adapter to receive `searchedNumber`, `notFound`, validation feedback, labels, `observedAt`, and the public parcel.

Keep that public contract privacy-filtered for guests and signed-in users alike. The mobile repository accepts only the documented parcel fields, checks the returned tracking number, and exposes no mutation actions. If this contract changes later, publish its version and examples before updating the app.
