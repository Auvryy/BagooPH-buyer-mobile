# PR title

Add native Google buyer authentication and owner release setup

# PR description

Buyers can now continue through the native Google SDK, explicitly prove an existing Bagoo password when linking, or complete an expiring native registration form. The app confirms the backend buyer session and original email, preserves editable drafts and current policy consent, and offers read-only status recovery after an uncertain result without automatically repeating a write. Session probes and incoming buyer links wait while the provider flow is active.

Google is available only on configured Android/iOS builds with valid owner public IDs and a true version-one backend capability. Email login remains available. New registration preserves server-owned identity, fixed buyer role and checkout approval requirements. No website handoff or backend change is included.

The owner build helper validates a public-only local configuration and derives matching Android link hosts and iOS Google callbacks. Android release builds require an owner keystore and cannot silently use debug signing. Local identities, credentials and keystores remain ignored. Setup and the concrete device/deployed buyer checklist are in [release setup](../release-setup.md).

## Validation

- Full isolated Flutter suite: **379 passed**; `flutter analyze`, edited Dart formatting and whitespace checks pass.
- Android debug APK and Linux debug bundle compile successfully.
- A fresh configured Android debug APK bundles the approved buyer origin/Web client ID, with a matching native link host and registered development package/signing fingerprint.
- An actual release attempt without owner signing is correctly blocked by the release guard.
- iOS property lists/configuration references parse; iOS compilation requires macOS/Xcode.
- Read-only local buyer contracts pass. After backend deployment/configuration, fresh app-transport checks confirm hosted guest session200, native Google capability200/version1/enabled and missing-registration-challenge422. A fresh focused identity/configuration/screen selection passed17 tests. No real provider authentication, account, order, payment, email, chat or database mutation was used for mobile verification.

## Owner prerequisites

The owner has supplied the Web client ID, buyer hostname and newly created Android development OAuth client ID. Actual values are saved only in ignored owner records and the existing backend handoff. Backend allowlist configuration, deployment and enablement are now confirmed, and the ignored Android configuration enables Google. Real device/provider acceptance, owner release certificates and association identities remain pending. The owner deferred connecting an Android phone; iOS also needs its public client ID and Apple provisioning. Device push remains deferred.

This is a **local PR draft**. No branch push, GitHub PR creation or merge has been performed for this mobile branch.
