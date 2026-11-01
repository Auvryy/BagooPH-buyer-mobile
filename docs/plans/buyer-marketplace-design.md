# Buyer marketplace design refresh

## Goal and acceptance

- Make product discovery and detail compact, clear, and convenient, including aligned descriptions and usable options.
- Give the Bag depth and clear purchase controls; replace default-looking chips and borders with consistent Bagoo styling.
- Guide buyers blocked by verification to the existing information submission flow through a clear modal.
- Show purchase statuses as horizontally scrollable tabs with a selected color and underline.
- Use a red branded header with search and accessible notification, Bag, and profile actions; provide seller messages from bottom navigation.
- Reduce oversized typography and spacing while retaining accessible touch targets, text scaling, and responsive layouts.
- Preserve account boundaries, server-authoritative shopping rules, existing navigation, and guest access.

## Delivery slices

1. Purchase filters and shared navigation/header.
2. Product discovery and detail, Bag, and verification guidance.
3. Messaging presentation, shared component polish, responsive and accessibility verification.

Use focused widget tests and static analysis, then inspect representative phone layouts. Keep physical and provider limitations explicit.

## Navigation checkpoint

The home shell now uses a red search header and a compact custom bottom bar with Messages. Guest messages lead to sign-in; signed-in messages use the existing account-bound inbox, which pauses foreground reads when hidden. Search remains a retained destination for existing links and filters. Discovery and design-review widget suites passed 41 cases with one worker, including guest access, inbox visibility, narrow layouts, landscape, enlarged text, and tablet layouts; focused analysis was clean. Product, Bag, verification guidance, messaging polish, and physical-device review remain open.

## Verification guidance checkpoint

Unapproved signed-in buyers can open a verification prompt from product purchase and Bag checkout. The prompt describes pending review or the need to review account information and links to the existing identity section, where eligible buyers can choose and submit an ID. Checkout remains gated by the server-backed approval checks. A session change while the prompt is open prevents the old action from opening account information. The focused product, Bag, discovery, and verification selection passed 26 cases with one worker, followed by five verification cases including the Bag session-change scenario; focused analysis was clean. Physical review and the remaining visual redesign are open.

## Product and Bag presentation checkpoint

Product options and shared chips use compact Bagoo styling, the product title and price are smaller, and specifications align as label/value rows with a stacked layout at narrow widths or enlarged text. The description aligns with its heading. Bag filters have explicit selected states, item cards use borders and elevation, and product and Bag headers use the branded red. Synthetic 375-pixel product and Bag renders were inspected; the fixture has no product image. A 60-case product, Bag, and responsive selection passed with one worker, followed by the updated product design suite and two focused alignment checks. Focused analysis was clean. Live product imagery, messaging polish, remaining shared controls and physical-device review remain open.

## Search and inbox presentation checkpoint

Search uses a smaller heading and tighter spacing. The inbox now presents each conversation with a compact card, message preview, time and accessible unread count, while retaining the existing account-bound refresh behavior. The buyer updates and discovery selection passed 21 cases with one worker; three focused inbox cases and four responsive synthetic inbox layouts passed after adding long-text coverage. The 375-pixel and enlarged-text renders were inspected, and focused analysis was clean. Conversation detail polish, remaining default-looking controls, live imagery and physical-device review remain open.

## Conversation presentation checkpoint

Conversation detail uses the branded header, compact incoming and outgoing bubbles, and a separated composer. Product references use a custom compact row. Chat and product checks passed 18 cases with one worker, and four responsive synthetic conversation layouts passed; the phone and enlarged-text renders were inspected. Focused analysis was clean. Remaining shared controls, end-to-end verification and physical-device review remain open.

## Search entry and navigation accessibility checkpoint

The header search opens the retained search screen with its input focused and preserves an existing draft on return. A queued focus cannot activate the keyboard after switching to another tab. The duplicate Home search field was removed; Home filters still open search with the selected criteria. Bottom navigation grows for enlarged labels instead of overflowing. Discovery and app widget checks passed 22 cases with one worker; the focused filter and hidden-focus cases and five search cases passed. A synthetic 375-pixel Home render was inspected and focused analysis was clean. End-to-end and physical-device review remain open.

## Purchase status visibility checkpoint

The horizontal status strip reveals the selected status when the section opens or its filter changes, including statuses initially outside the viewport. Nine purchase-section tests passed with one worker, four responsive synthetic purchase layouts passed, and the 375-pixel preview was inspected. Focused analysis was clean. Broader regression and physical-device review remain open.

## Editable search header checkpoint

The red header is now the actual editable search field; the embedded results page no longer duplicates it. Search preserves the draft and filter context, ignores cursor-only changes, and applies a filter request received while hidden when the page reopens. Single-page catalogues no longer show disabled pagination controls. Thirty-eight focused discovery, authentication, search and catalogue cases passed with one worker, followed by four responsive embedded-search layouts and a narrow enlarged-text check; synthetic phone and landscape renders were inspected. Whole-project analysis was clean. Before this final search change, the full isolated suite passed 853 cases and a constrained Android debug build succeeded; both need refreshing for the current source. Physical-device review remains open.

## Regression and signed-in header checkpoint

The full isolated suite passed 861 cases with one worker at the editable-header checkpoint, and a configured Android debug APK built with a 1.5 GB Gradle heap and one worker. Whole-project analysis was clean. A signed-in 320-pixel preview then revealed a truncated search prompt; the prompt was shortened, 28 focused discovery and app cases passed, and the updated signed-in preview was inspected. The current source still needs a refreshed APK and physical-device review.

## Current Android build checkpoint

The current source at the signed-in header checkpoint passed whole-project analysis and 28 focused discovery and app cases after the prompt wording adjustment. The preceding full isolated suite passed 861 cases with one worker. A configured debug APK was rebuilt from the current source with one Gradle worker and a 1.5 GB heap cap. Android SDK tooling emitted an XML version warning but the build succeeded; package inspection reported the Bagoo buyer package, app label and adaptive launcher icon resource. The connected phone was not confirmed to have Bagoo in the foreground, so this APK has not been installed for this review. Live product imagery and physical-device acceptance remain open.

## Verification dialog accessibility checkpoint

Synthetic review revealed that the verification explanation could be squeezed out in landscape with enlarged text and a keyboard inset. The dialog now dismisses keyboard focus, uses a compact scrollable layout, and provides shorter status-specific guidance. Six verification cases passed, including scrolling and selecting the account action on a constrained screen; 52 synthetic responsive layouts passed with the media settings applied to dialog overlays. Phone and landscape dialog renders were inspected and focused analysis was clean. The previous APK predates this dialog fix and must be rebuilt; physical-device review remains open.

## Current verification-fix Android build

The configured debug APK was rebuilt after the compact verification-dialog fix with one Gradle worker and a 1.5 GB heap cap. The build succeeded with the existing Android SDK XML version warning. Package inspection confirmed the Bagoo buyer package, label and adaptive launcher resource. Whole-project analysis is clean; the earlier full run passed 861 cases, followed by 28 focused search/app cases, six verification cases and 52 responsive synthetic layout cases for the later changes. Bagoo was not confirmed in the foreground on the connected phone, so this APK has not been installed for device review. Physical acceptance and live imagery remain open.

## Navigation accessibility checkpoint

At a 320-pixel width with enlarged text, synthetic checks confirmed at least 48 logical pixels for header actions, the search field and bottom tabs. A separate 360-pixel check confirmed the selected purchase status meets the same minimum. The selected Home, Messages and purchase status expose button and selected semantics. The two relevant suites passed 25 cases with one worker, and focused analysis was clean. Static color calculations gave 6.21:1 for the strong brand red on white, 4.88:1 for the primary red on white, and 7.58:1 for muted text on white. The app source and APK are unchanged from the verification-fix build; device acceptance remains open.

## Narrow search editing checkpoint

A signed-in 320-pixel preview showed that the three header actions left too little room to read a query while editing. During search editing the field now expands and shows a Done action; notification, Bag and profile controls return when focus leaves. The focus border is visible on the white field. The full sample query was visible in the updated synthetic phone preview, and 91 discovery, app, search and responsive layout cases passed with one worker. Focused analysis was clean. The previous APK predates this change; the updated build and physical review remain open.
