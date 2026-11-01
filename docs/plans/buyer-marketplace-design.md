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
