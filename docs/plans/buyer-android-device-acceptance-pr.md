Title: Correct buyer launcher identity, website links and profile session ownership

The Android buyer app used Flutter's launcher artwork and rejected four existing website URL aliases. It now packages the existing Bagoo mark for Android/Apple launchers and resolves those URLs to native destinations while retaining login requirements.

Profile data and voucher actions now retain the opening buyer scope. Expired or denied sessions discard private rows and headers, stale replies cannot restart paging, buyer changes replace retained children, and voucher use opens one Bag with the inherited account scope.

Repeated Bag product taps now open one product route, and retained quantity actions wait until it closes.

Wallet and Buy Again navigation retain their opening session across replies and destination creation; malformed payment context and selected item IDs are rejected.

Purchase buttons retain their opening buyer scope, expired lists hide private rows, and receipt dialogs consume one decision and recheck eligibility before submission. Order receipt confirmation now coalesces rapid taps into one dialog and stops if the buyer session changes while it is open. The order detail also carries its opening scope into cancellation, review, return, wallet and Buy Again routes; expired cancellation and review forms clear their drafts and block writes.

Product detail now applies the same opening-account checks to Add to Bag, Save, sale reminders and Bag navigation. Delayed mutation replies after a session change reload the current product instead of restoring the previous buyer's state.

Verification is recorded in buyer-android-device-acceptance.md. The installed current-source debug APK was exercised on the owner-authorized Xiaomi phone. ADB stayed connected and Bagoo-targeted taps, captures, guest browsing, search, guest purchase gating, sign-up validation, seeded-buyer sign-in, and read-only purchase filters worked. The product gallery image delayed but loaded. No purchase or account change was made. Android Back from the purchase list returned to the launcher; reopening Bagoo showed sign-in with Remember me unchecked, so session persistence is not yet classified. Android's Proton Pass credential prompt was not accepted or saved. Full physical acceptance remains in progress. The PR description remains a local draft; no website edits or publication are included.
