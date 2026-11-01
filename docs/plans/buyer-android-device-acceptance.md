# Buyer Android device acceptance

Start from merged main `565f69d` on `fix/buyer-android-device-acceptance`. The connected Xiaomi 25078PC3EG runs Android 16/API 36 at 720 by 1600 physical pixels. Build and install through the existing public owner configuration. Keep changes local. Only buyer mobile is writable.

## Acceptance and commit slices

1. Install the configured debug build; verify package, launch, backend connectivity and guest browsing on the physical phone. Record crashes, keyboard/navigation behavior and real screen feedback. Preserve existing device data; no uninstall or clear-data action.
2. Reproduce and fix confirmed device/layout/navigation/input failures, one concern per commit, with meaningful regression checks and another phone run. Verify incoming buyer URL aliases against actual web routes.
3. Complete signed-in account and shopping flows using an approved test buyer/environment. Native Google identity selection and credentials remain owner-controlled. Verify configuration separately from real provider success. Shopping, payments, emails, messages and account changes require an appropriate test context; synthetic integration cases exercise failure/repeated-action paths without live mutations.
4. Run relevant native Android integration cases, remaining feature-family exploration and full isolated regression/analysis/format/build checks. Reinstall the final configured normal entrypoint after integration runs. Record every result, blocker and untested provider/OS path; no claim of zero bugs or iOS acceptance from Android checks.
5. Update coverage and the local PR draft, save coherent commits and update the existing review task. Publication needs a new owner push instruction.

## Evidence

Device detection succeeded. Owner public configuration passed the Android debug validation. No buyer package was installed at initial detection. Installation and device journeys are in progress.

### Website link compatibility

Five new regression cases initially failed: four explicit website aliases were rejected and an incoming guest Bag alias never opened its native screen. Normalize `/buyer/cart`, `/buyer/checkout`, `/buyer/disputes` and `/buyer/catalog` only after validating the original origin/path. The destination router now uses the parsed canonical URI, preserving query and fragment and existing login gates. All 22 link tests pass after the fix; full static analysis reports no issues. Foreign origins and action URLs remain rejected. Physical installed-link verification remains separate.

### Launcher branding

The installed baseline still used the Flutter launcher icon. Render the existing Bagoo favicon vector into the Android density icons and Apple icon catalog, and provide native adaptive foreground/background and Android 13 themed resources. Apple catalog images have their declared dimensions and opaque RGB channels. Android resource XML parses and the Android integration APK compiles with these resources. Installed launcher resource inspection is recorded with the phone run; iOS compilation is not established on Linux. No new branding was invented.

### Phone control boundary

The owner permits Bagoo-only phone interaction and approved seeded buyer sign-in. Never open other apps, browse personal files or manipulate system settings. Before external taps or captures, verify that Bagoo is the focused package. Android currently rejects shell input with INJECT_EVENTS even after reconnect; the owner is checking the separate OEM security setting. Continue using in-app integration actions, not an attempted privilege escalation. Google selection remains owner-controlled. The existing task timer belongs to a rider session and is left untouched; any buyer time entry must use a measured interval.

The owner enabled the OEM debugging switches; after returning to Bagoo, a guarded shell tap succeeded. External control remains restricted to the Bagoo package. Do not send manual taps while native automated cases are running.

### November 1 verification checkpoint

The initial 26 native contact/account/collection and synthetic purchase cases passed on the physical phone. All 793 isolated cases pass after the link changes. The opted-in live guest/seeded-buyer run did not complete: screen capture and shell commands stopped responding, then a targeted reconnect left no device listed and the live runner ended with lost-device/finalization errors. This is not evidence of successful sign-in or a proven app defect. Ask the owner to reconnect and revalidate before rerunning.

The SDK's native-test command defaults to uninstalling its test app at teardown. There was no buyer package on initial detection; future device runs must use `--no-uninstall` and reinstall the saved normal configured APK afterward. No other phone app was opened or user file browsed. The one generated UI-dump artifact was removed. The owner is responsible for system/debug settings and Google account selection.

### Profile and voucher ownership follow-up

Four initial valid regression cases reproduced retained private voucher rows on resume/account change, a same-owner reply surviving an expired session, and a pagination correction read after expiry. Denied-access and retained-use paths were also inspected and covered. The root profile now binds reads, replies and private children to its opening account scope, replaces repositories and child state when the supplied buyer changes, and clears expired identity headers and denied-access rows. Voucher use rejects expired and repeated decisions; its Bag child inherits the opening scope before its first read. Nine root cases and the existing Bag regressions form the focused verification. All 119 focused root/Bag/link checks pass on the final source, and full analysis is clean. The full isolated suite is still running; the updated profile source has not yet been installed or verified on the phone.

The normal configured app with Bagoo icons and link fixes was reinstalled successfully after the interrupted live run. It does not yet contain the profile follow-up. The device remained physically connected according to the owner. Earlier ADB reconnect commands were initiated by this agent and interrupted the driver; do not attribute those interruptions to the owner's cable. Stop connection resets and framebuffer captures. ADB still lists the device but a bounded Bagoo-process query timed out. No other phone app or personal file is in scope.

The new aggregate Android runner and opted-in live smoke runner are prepared and statically checked. The aggregate has not yet run on the phone; the live smoke driver did not complete. A later UI-tree read showed the seeded buyer profile, which is an observation rather than a completed test pass. Google, actual permissions and the remaining physical journeys still require evidence.

### Coding continuation

The owner deferred further phone interaction and requested coding first. Leave the ADB server, connection and phone alone. The initial full run that began before the final identity-header change finished with 801 passing cases and that header case failing; do not report it as a passing suite. The final focused 119-case selection passed on the updated source.

One additional case reproduced a Bag's first read starting through a different repository session from its supplied parent account. The initial read now requires both the inherited scope and matching session. All ten root cases pass and analysis is clean. A fresh full run on the final source is in progress in `.git/buyer-current-full.log`; verify its actual process/result before restarting.

### Bag product navigation

Two additional cases reproduced three product reads/routes from three retained taps and an unintended quantity change through a cached Bag control while its product route was open. Product navigation now sets the existing opening guard synchronously and releases it when the child closes; returning refreshes the same Bag once. All 43 navigation/dialog/profile checks pass on the final source and analysis is clean. The aggregate Android runner includes these cases for later device acceptance. The earlier full suite is still being collected and predates this navigation slice, so it is not full-suite evidence for the new source.

### Purchase navigation and late replies

Two new cases reproduced a delayed wallet-payment read and Buy Again acknowledgement navigating after the opening session ended. Capture a scope before each request, check it after the reply and pass it into the payment/Bag destination. Wallet navigation validates the existing backend `Buyer/WalletPayment` component and requested payment ID. Buy Again requires positive integer Bag item IDs before building the selected-item route.

All ten final purchase-navigation cases pass, including both current-session destinations and six malformed-ID responses. The related checkout/post-purchase selection passes 29 cases and full analysis is clean. The preceding configured Android build passed before this slice; current-source build/device acceptance are still required. The preceding full-suite run is still being collected and is not evidence for these new cases. Phone interaction remains deferred at the owner's request.

### Retained purchase actions and confirmations

Four initial cases reproduced an expired purchase list remaining visible, a cached Buy Again callback starting a mutation after expiry, and queued accept/cancel decisions popping beyond their confirmation dialog. A fifth case reproduced multiple receipt dialogs from queued parent callbacks. Purchases now use the existing buyer-bound form state and inherit the root account. Reads/actions/navigation check that scope, while receipt confirmation rechecks current eligibility before sending. A confirmation dialog consumes one decision and marks external closure before old callbacks can act.

The first 25 focused purchase/profile/helper cases pass. Added normal and expired receipt-decision paths are being verified with the final combined selection; the new tests scroll to their controls before tapping. The earlier 50-case account/helper selection passed before receipt-dialog coalescing. Final analysis and the latest combined result remain to be collected.

### Verification resource limit

The owner requested lower RAM use. Run one heavy verification job at a time; use a single Flutter test worker and perform analysis/builds sequentially. The overlapping 815-case full-suite run was deliberately interrupted to release memory and is cancelled, not passing, regardless of the CLI exit code. Do not stop another session's rider checks or shared services. Final full-suite/build evidence must be gathered within this limit.

Final purchase-action selection: all 27 purchase/profile/helper cases pass with one test worker, including both valid and expired receipt decisions. Analysis is clean after the test run. The resource-limited full suite and current-source Android build are still outstanding; the earlier 815-case full run was cancelled. Keep the broader audit and physical acceptance open.

### Order receipt dialog re-entry

A direct rapid callback reproduction opened two receipt dialogs for one order. The order detail now latches the decision before showing its dialog, rechecks session and receipt eligibility after confirmation, clears private order content if the session changed, and ignores delayed actions after disposal. The focused order-update suite passes all eight cases, including one-dialog/one-submit and session-change/no-submit coverage. Static analysis is clean. Full-suite, current Android build and physical acceptance remain outstanding.

### Order detail child-route ownership

A synthetic cancellation form still sent `/buyer/orders/11/cancel` after its buyer session was cleared. Order detail now captures the opening buyer scope and passes it into cancellation, review, return, wallet and Buy Again destinations. Cancel and review forms clear their drafts and hide purchase details after scope expiry, and mutations check the scope before submission and after replies. Successful synthetic cancellation and review replies still update the parent purchase. The combined purchase, return and responsive-journey selection passed 112 cases with one worker; the added expired-form visibility assertions also pass. Static analysis is clean. The full suite, current Android build and physical acceptance remain outstanding.

### November 1 full regression checkpoint

After the receipt-dialog and order-scope changes, `flutter test --no-pub --concurrency=1` passed 828 isolated tests. `flutter analyze --no-pub` reported no issues. The current-source configured Android build and installed-app/device acceptance remained outstanding; physical phone work was deferred at the owner's request. No website or live shopping data was changed.

### Product detail session-bound actions

A delayed Add to Bag response reproduced the previous buyer's product state and success message reappearing after session expiry. Product detail now binds mutations and Bag destinations to the page's opening account, rejects late Add to Bag, Save and sale-reminder replies, and reloads the current session's product data. Regression coverage verifies all three delayed replies. The final one-worker full run passes 831 isolated tests; static analysis reports no issues. No phone, screen-control, Android build or provider checks were performed in this slice. Device and provider acceptance remain open.

### Configured Android installation attempt

The owner requested installation and physical testing. The public Android debug configuration validates, and a current-source debug APK built successfully at `build/app/outputs/flutter-apk/app-debug.apk` with Gradle limited to one worker. The build emitted an SDK XML version warning but completed. ADB continues to list the Xiaomi, while bounded `getprop` and package-path shell reads time out. Both standard and `--no-streaming` `adb install -r` attempts ended with timeout code 124 without a success/error response, and a read-only package-path check also timed out. The install state is unknown and no launch or device test is claimed. No ADB server reset, screen capture, manual input or other-app interaction was performed. Resolve the stalled device shell before retrying install or native tests.

### November 1 ADB recovery and configured installation

At the owner's request, the host ADB server was restarted once. The first post-restart check temporarily showed no ADB device; the USB bus still enumerated a Xiaomi ADB interface. On a later retry, the device returned as `device`, a harmless Bagoo-targeted shell echo succeeded, and Android SDK platform-tools ADB 37.0.1 installed the configured debug APK with `adb install -r` (`Success`). A read-only `pm path shop.bagooph.bagoo_buyer_mobile` confirmed the installed package. This supersedes the earlier unknown install state above. At the time of this checkpoint, the app had not been launched; the later guest run is recorded below. A package-specific process check returned no running app. No screen capture, taps or interaction with another phone app occurred during that earlier recovery checkpoint.

### November 1 owner-authorized guest run

The owner clarified that Bagoo phone control was authorized, while PC-screen control was not. The installed app launched to a Bagoo-branded sign-in screen after its splash state. Tapping **Browse the marketplace** opened the guest home; the Bagoo mark, search controls, department chips and product cards rendered. The home still displayed the cached-catalogue “refreshing” notice and “Updating products…” after several seconds, so live product refresh and backend freshness were not verified. No sign-in, checkout, purchase or other shopping mutation was performed.

A later screenshot and basic `adb shell` request timed out. The phone still appeared in `adb devices -l` at one check, but a targeted reconnect timed out. After an ADB host restart and USB re-enumeration, the SDK ADB listed the device as `unauthorized`; it cannot run shell or screen actions until the phone approves this computer's debugging key. The USB bus still shows the Xiaomi ADB interface and the host user has read/write permission. The guest home was the last observed Bagoo screen; its current screen could not be rechecked after transport loss. This is a device-authorization/transport blocker, not a confirmed app defect.
