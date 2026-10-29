# Selectable buyer device preview

The owner requested a Linux preview with selectable Samsung and iPhone frames before continuing the connected-phone Google test. Add a separate debug entrypoint that displays the existing buyer application inside real device presets. Preserve the existing buyer design, session handling and mobile entrypoint. All sibling products remain read-only; keep this branch unpublished.

## Acceptance

- A copyable terminal command opens the framed Linux preview against the existing ignored owner configuration.
- Select Samsung, iPhone and Pixel presets, rotate the screen, toggle the frame and adjust text size from accessible controls in the preview window.
- Put controls in a left sidebar and fit portrait phones to the full window height while preserving aspect ratio. Narrow windows use a side drawer. Preserve useful buyer navigation/form state while changing devices or orientation. Device metrics, safe areas and platform theme follow the selected preset.
- Use a development-only pure-Flutter frame dependency and a separate entrypoint; normal Android/iOS/Linux startup keeps the existing buyer UI. No provider SDK or operating-system emulation is claimed.
- Verify preset metrics, pointer/control interaction, state preservation, small/wide windows and enlarged text with isolated tests. Run analysis, the regression suite and Linux preview compilation; verify normal Android compilation if shared application/dependency changes warrant it.

## Implementation choice

Use `device_frame` 1.4.0 as a development dependency with a small native Flutter control panel. Its catalog includes Samsung Galaxy S25, Pixel and iPhone frames. The current `device_preview` 3.x puts its controls in DevTools; the owner specifically wants the picker inside the Linux window. The direct frame package supplies that appearance without adding native plugins or a state-management framework to the buyer application.

## Commit slices

1. This plan and dependency rationale.
2. Preview dependency, separate entrypoint, device controls and focused regressions.
3. Verification evidence, README run command and updated local PR handoff.

The connected Android phone is detected. Its actual Google/provider test remains separate and will continue after this requested preview work; do not launch it as part of preview verification.

## Result and verification

The preview is implemented at `tool/preview.dart`. Its controls sit on the left at desktop widths, with a side drawer below640 logical pixels. The frame fills the available height when the device aspect ratio and window width permit it. Changing presets, rotation, frame visibility or text scale keeps the buyer app mounted. The normal entrypoint has optional theme/scroll injection with unchanged defaults; development dependencies stay in the separate tool entrypoint.

```sh
flutter run -d linux -t tool/preview.dart --dart-define-from-file=config/buyer.local.json
```

For a running preview, press `r` in its Flutter terminal to hot reload. Owner-specific backend/client values remain ignored.

- Full isolated regression suite: **386 passed**, including seven new preview checks.
- Static analysis, edited Dart formatting and whitespace checks: clean.
- Final sidebar preview Linux debug build: passed using the entrypoint/configuration above.
- Regular Android debug build: passed using `lib/main.dart` and the existing approved owner configuration.
- Focused coverage verifies nested app metrics/platform, retained email drafts across device/orientation changes, text/frame controls, full-height portrait layout, narrow side-drawer selection, and small/wide windows with200% host text.

The owner has opened the framed preview and requested the sidebar refinement, which is included in these checks. No browser automation, desktop screenshots, live account writes or automatic phone Google login was used for verification. All sibling repositories remain unchanged by this work. Commits remain local; the cumulative PR title/body is an updated local draft.

Implementation commits: `5205d41` (plan) and `c4640ad` (preview/dependency/tests). This final documentation pass records the run command, verification and current handoff.
