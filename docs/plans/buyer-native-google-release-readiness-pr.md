# PR title

Add native Google buyer authentication and owner release setup

# PR description

Buyers can now continue through the native Google SDK, explicitly prove an existing Bagoo password when linking, or complete an expiring native registration form. The app confirms the backend buyer session and original email, preserves editable drafts and current policy consent, and offers read-only status recovery after an uncertain result without automatically repeating a write. Session probes and incoming buyer links wait while the provider flow is active.

Google is available only on configured Android/iOS builds with valid owner public IDs and a true version-one backend capability. Email login remains available. New registration preserves server-owned identity, fixed buyer role and checkout approval requirements. No website handoff or backend change is included.

The owner build helper validates a public-only local configuration and derives matching Android link hosts and iOS Google callbacks. Android release builds require an owner keystore and cannot silently use debug signing. Local identities, credentials and keystores remain ignored. Setup and the concrete device/deployed buyer checklist are in [release setup](../release-setup.md).

## Validation

- Full isolated Flutter suite: **379 passed**; `flutter analyze`, edited Dart formatting and whitespace checks pass.
- Android debug APK and Linux debug bundle compile successfully.
- An actual release attempt without owner signing is correctly blocked by the release guard.
- iOS property lists/configuration references parse; iOS compilation requires macOS/Xcode.
- Read-only local buyer contracts pass. The owner's public origin answers the guest session check, but capability/association endpoints return404. No live authentication, account, order, payment, email, chat or database mutation was used for verification.

## Owner prerequisites

The owner has supplied the Web client ID, buyer hostname and newly created Android development OAuth client ID. Actual values are saved only in ignored owner records and the existing backend handoff. Backend allowlist configuration, deployment and enablement, owner release certificates/association identities and real provider acceptance remain pending. The owner deferred connecting an Android phone; iOS also needs its public client ID and Apple provisioning. Device push remains deferred.

This is a **local PR draft**. No branch push, GitHub PR creation, merge or deployment has been performed for this work.
