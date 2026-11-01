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
