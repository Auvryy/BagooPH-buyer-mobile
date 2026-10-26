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

Implementation in progress. Web source references live in `../bagoo/resources/js/Components/ProductCard.tsx`, `Pages/Buyer/ProductDetail.tsx`, `Pages/Checkout/Index.tsx`, product pricing helpers, and the corresponding Laravel controllers/services. Do not place real orders or send chat messages during automated verification; use isolated fixtures. Read-only live product and checkout contracts may be inspected with the documented local demo account.
