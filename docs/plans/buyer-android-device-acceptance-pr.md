Title: Correct buyer launcher identity, website links and profile session ownership

The Android buyer app used Flutter's launcher artwork and rejected four existing website URL aliases. It now packages the existing Bagoo mark for Android/Apple launchers and resolves those URLs to native destinations while retaining login requirements.

Profile data and voucher actions now retain the opening buyer scope. Expired or denied sessions discard private rows and headers, stale replies cannot restart paging, buyer changes replace retained children, and voucher use opens one Bag with the inherited account scope.

Repeated Bag product taps now open one product route, and retained quantity actions wait until it closes.

Wallet and Buy Again navigation retain their opening session across replies and destination creation; malformed payment context and selected item IDs are rejected.

Purchase buttons retain their opening buyer scope, expired lists hide private rows, and receipt dialogs consume one decision and recheck eligibility before submission. Order receipt confirmation now coalesces rapid taps into one dialog and stops if the buyer session changes while it is open. The order detail also carries its opening scope into cancellation, review, return, wallet and Buy Again routes; expired cancellation and review forms clear their drafts and block writes.

Product detail now applies the same opening-account checks to Add to Bag, Save, sale reminders and Bag navigation. Delayed mutation replies after a session change reload the current product instead of restoring the previous buyer's state.

Verification is recorded in buyer-android-device-acceptance.md. The initial physical Android batch passed 26 synthetic cases. A later live driver run was interrupted by debugging transport failures and is not claimed as passing. The aggregate Android runner is prepared, not yet verified on-device. Normal-app reinstall, final profile-fix phone acceptance, Google/provider and remaining feature journeys are still open. No website edits or publication are included. This PR description remains a local draft.

The current source passes all 831 isolated tests with one worker and static analysis reports no issues. The configured Android debug APK has now installed successfully using Android SDK platform-tools ADB 37.0.1; a Bagoo-targeted shell check and package-path check also succeeded. Physical launch, backend, guest-browsing, sign-in and feature journeys remain unverified because the agent did not operate or capture the phone screen. The host ADB server was restarted once at the owner’s request; no other phone app or user file was accessed.
