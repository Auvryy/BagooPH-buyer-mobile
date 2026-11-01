Title: Correct buyer launcher identity, website links and profile session ownership

The Android buyer app used Flutter's launcher artwork and rejected four existing website URL aliases. It now packages the existing Bagoo mark for Android/Apple launchers and resolves those URLs to native destinations while retaining login requirements.

Profile data and voucher actions now retain the opening buyer scope. Expired or denied sessions discard private rows and headers, stale replies cannot restart paging, buyer changes replace retained children, and voucher use opens one Bag with the inherited account scope.

Verification is recorded in buyer-android-device-acceptance.md. The initial physical Android batch passed 26 synthetic cases. A later live driver run was interrupted by debugging transport failures and is not claimed as passing. The aggregate Android runner is prepared, not yet verified on-device. Normal-app reinstall, final profile-fix phone acceptance, Google/provider and remaining feature journeys are still open. No website edits or publication are included. This PR description remains a local draft.
