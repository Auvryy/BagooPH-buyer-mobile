# Buyer home cards and native product journey

## Acceptance

- Continue the unpushed buyer feature branch; never edit main or publish without the user's instruction.
- Match the web buyer cards: two-column phone/six-column desktop grid, equal card sizing, square images, stock/vacation overlays, compact names, sale/comparison prices, delivery/discount ribbons, rating/sales/location metadata, and real save controls.
- Replace summary sheets with a complete native product screen: real gallery/zoom, option selection, variant/sale pricing, quantity limits, Add to Bag, Buy Now, save/share, shop information, offers, specifications, reviews/photos/replies, and navigation.
- All flows stay native. Never send buyers to the website for shopping, checkout, shop browsing, or chat. Consume existing backend responses internally; no WebView or browser handoff.
- Support a native Bag and checkout through explicit order confirmation, with server-owned validation, quotes, address hierarchy, eligibility, stock, prices, and submission tokens.
- Reuse existing backend contracts wherever possible. Changes to the backend are authorized if a real contract gap requires them, on its own working branch.
- Keep unavailable states factual. In particular, the web's static Free Delivery ribbon conflicts with its checkout-confirmed delivery fees: retain the ribbon styling using the supported COD payment label, rather than inventing a shipping guarantee. Sale discounts still follow actual prices.
- Preserve phone, landscape, tablet, large-text, loading/error/retry, and accessibility behavior.

## Work breakdown

1. Shared product pricing/selection model and backend product, save, Bag, and checkout adapters with focused contract checks.
2. Web-style cards and consistent responsive grid/save controls.
3. Full native product view and native shop/chat/Bag/checkout actions.
4. Verification, source/behavior notes, README and local PR handoff.

## Evidence and limits

Completed on `feat/buyer-auth-home`, with local commits and no publication.

- Cards follow the web hierarchy, prices, badges, stock states, ratings, location, and save controls. The responsive grid uses equal extents and adapts columns for enlarged text; ribbon wrapping and save-error states were checked at 100%, 140%, and 200% text.
- Product pages fetch the full detail contract and render real photos with zoom, options and color/photo swatches, variant prices, quantity limits, sale reminders, descriptions, offers, reviews/photos/replies, and shop data. Share copies a product link to the native clipboard.
- View Shop, Chat Now, Add to Bag, Buy Now, Bag updates, checkout, recorded orders, and wallet payment actions render in Flutter. Native sign-in can resume the original product. Chat has a text composer and authenticated photo viewing.
- Checkout uses canonical location choices, server quotes, actual voucher selections, saved/new addresses, pickup/doorstep options, COD/wallet, and a separate explicit review. Stale quote responses are ignored. Uncertain order responses freeze the exact payload and submission token for an explicit retry; wallet actions retain server request tokens and refresh recorded status.
- Existing Laravel contracts supported the requested journey. No backend source changes or rebuild were necessary; `../bagoo` remains clean on its original main branch.

### Verification

- `flutter analyze`: no issues.
- `flutter test`: all 49 checks passed. These include existing authentication/session coverage, product pricing/stock, confirmed save/Bag/order responses, explicit checkout confirmation, stale quote ordering, exact payload/token retries, native navigation, and phone/tablet/large-text layouts.
- `flutter build linux --debug` and `flutter build apk --debug`: passed.
- `tool/check_backend.dart`: passed against the running local backend, reading home, registration requirements, policies, filtered catalogue, full product, shop, guest Bag, and canonical regions. The current fixture contains 16 departments and 17 listings; these counts are verification observations, not app constants.
- Formatting and diff whitespace checks passed. No visible browser, screenshot, live order/payment submission, chat send, email send, or database reset was used for this work.

### Source and remaining scope

Web source references: `../bagoo/resources/js/Components/ProductCard.tsx`, `Pages/Buyer/ProductDetail.tsx`, `Pages/Checkout/Index.tsx`, product pricing helpers, and the corresponding Laravel controllers/services. Server validation remains authoritative.

Identity-document submission, Google OAuth, chat photo uploads, full address-book editing, and detailed order tracking/cancellation/receipt-confirmation actions are outside this pass. These are not replaced with website links. Sessions are in memory and require sign-in after process restart. iOS builds and physical device rendering were not exercised in this Linux environment. Automated mutation checks used isolated fixtures; no live checkout order was placed. The PR description remains a local draft in `.git/PR_BUYER_AUTH_HOME.md`.
