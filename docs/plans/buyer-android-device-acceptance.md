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
