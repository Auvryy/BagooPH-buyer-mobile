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
