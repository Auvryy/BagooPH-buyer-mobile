# Native buyer support, Google sign-in, and push

## Goal

Close three high-impact gaps between the native Flutter buyer app and the Bagoo buyer website while keeping each customer flow native. Support uses Bagoo's existing authenticated backend; Google account identity is verified by Bagoo; push taps reopen the native notification center.

## Work slices

### 1. Native Support

- Add a Help & Support entry in the buyer profile.
- Build a native assistant screen with quick prompts, optional order number, conversation history, loading/error states, suggested follow-ups, and a clear handoff to Bagoo Customer Care (receiver ID 2).
- Use `POST /buyer/support/assistant` through the existing cookie/CSRF session. Keep the backend's buyer/approval rules and rate limit.
- Explain when account approval is required; never send the buyer to the website.

### 2. Native Google sign-in and registration

- Add Google Sign-In to the Flutter login screen, returning only the Google ID token to Bagoo over the existing HTTPS session.
- Verify signature, issuer, expiry, verified email, subject, and an allowlisted audience on the server. Never trust client-supplied identity fields.
- Preserve buyer-only account matching/linking rules and existing Google registration policy/age/address validation. Collect any missing fields in native Flutter and complete registration through a JSON endpoint.
- Regenerate the Laravel session after authentication; load the signed-in buyer from the Bagoo origin.
- Keep Linux preview behavior graceful when native Google Sign-In is unavailable.

### 3. Native push notifications

- Add Firebase Messaging client support with runtime permission, token registration/refresh, logout revocation, foreground handling, and native taps into Bagoo's notification page.
- Persist per-user device tokens safely and send only generic, non-sensitive notification payloads containing the owned notification UUID.
- Create push delivery intents transactionally with durable in-app notification creation; retry provider failures and deactivate invalid tokens.
- Read the notification after a push tap using the existing authenticated notification center and destination router.
- Gate delivery on Firebase project configuration; document Android/iOS Firebase setup and APNs requirements without committing credentials.

## Acceptance criteria

- All three flows are native Flutter screens and do not open the buyer website or a WebView.
- Existing buyer authorization, registration-policy, notification ownership, and session rules remain server-owned.
- Push payloads contain no order, payment, address, or other private details.
- Missing platform/provider credentials produce a clear unavailable state and do not prevent the marketplace app from opening.
- Feature branches remain based on the merged `main`; user-owned backend files remain untouched.

## External configuration needed for production

- Google Android/iOS OAuth client IDs (with the Web client ID used as the server audience where the plugin requires it).
- Firebase Android/iOS app registrations and generated platform configuration, Firebase project ID, and a backend service-account credential with Firebase Cloud Messaging API enabled.
- An APNs authentication key uploaded to Firebase and the iOS Push Notifications / Background Modes capabilities enabled.

No credentials or generated provider files belong in Git.

## Implementation status

Implemented on `feat/native-buyer-support-auth-push` across the Flutter buyer app and the matching Laravel backend branch. Native support uses the current account-aware assistant and Bagoo Customer Care chat. Google identity is verified server-side before linking or registering a buyer. Push devices are opt-in, encrypted at rest, and delivered through a transactional outbox with expiry, retry, and invalid-token cleanup. Push taps open the native notification center.

Flutter and PHP source formatting and `git diff --check` passed. Automated tests, analyzers, and native builds were not run for this pass. Production Google OAuth client IDs, Firebase app IDs/configuration, APNs setup, the backend Firebase service-account file, and the scheduler are still required to exercise Google sign-in and push end to end. No provider secrets or generated Firebase app files are committed.
