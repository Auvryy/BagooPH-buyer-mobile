# Selectable buyer device preview

The owner requested a Linux preview with selectable Samsung and iPhone frames before continuing the connected-phone Google test. Add a separate debug entrypoint that displays the existing buyer application inside real device presets. Preserve the existing buyer design, session handling and mobile entrypoint. All sibling products remain read-only; keep this branch unpublished.

## Acceptance

- A copyable terminal command opens the framed Linux preview against the existing ignored owner configuration.
- Select Samsung, iPhone and Pixel presets, rotate the screen, toggle the frame and adjust text size from accessible controls in the preview window.
- Fit the frame to the desktop window and preserve useful buyer navigation/form state while changing devices or orientation. Device metrics, safe areas and platform theme follow the selected preset.
- Use a development-only pure-Flutter frame dependency and a separate entrypoint; normal Android/iOS/Linux startup keeps the existing buyer UI. No provider SDK or operating-system emulation is claimed.
- Verify preset metrics, pointer/control interaction, state preservation, small/wide windows and enlarged text with isolated tests. Run analysis, the regression suite and Linux preview compilation; verify normal Android compilation if shared application/dependency changes warrant it.

## Implementation choice

Use `device_frame` 1.4.0 as a development dependency with a small native Flutter control panel. Its catalog includes Samsung Galaxy S25, Pixel and iPhone frames. The current `device_preview` 3.x puts its controls in DevTools; the owner specifically wants the picker inside the Linux window. The direct frame package supplies that appearance without adding native plugins or a state-management framework to the buyer application.

## Commit slices

1. This plan and dependency rationale.
2. Preview dependency, separate entrypoint, device controls and focused regressions.
3. Verification evidence, README run command and updated local PR handoff.

The connected Android phone is detected. Its actual Google/provider test remains separate and will continue after this requested preview work; do not launch it as part of preview verification.
