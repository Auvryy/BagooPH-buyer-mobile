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
