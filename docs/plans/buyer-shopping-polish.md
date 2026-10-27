# Native shopping parity and polish

Start: `feat/buyer-shopping-polish` from merged main `b3db8ea`, after `git pull origin main` succeeded. Only change this mobile repository; inspect `../bagoo` as the reference. Keep all buyer flows native and keep commits local until separately authorized to push.

## Acceptance

1. Search uses the actual `Buyer/Search` contract, with department, canonical shop location, price range, in-stock, minimum rating, all supported sorts, pagination, active-filter removal/reset, server suggestions and related products. Mobile filters are easy to apply/dismiss and wide layouts offer an accessible filter workspace. Preserve query state and ignore stale results.
2. Cart remains the bottom-tab label and its content uses Shopping Bag language. Match the website's shop grouping, search/sort/selection controls, stock-aware quantity changes, confirmed removal, selected-items pricing and per-shop delivery summary. Show meaningful loading, unavailable, empty, error/retry and eligibility states.
3. Product view keeps the real gallery, options, prices, stock, verified reviews, shop and native actions. Polish mobile purchase access, option/availability feedback, section navigation and related-product browsing while retaining server-owned stock/prices and approved checkout gates.
4. Checkout matches the website's delivery/address/payment/voucher/order-summary hierarchy with responsive panels, clear selected-item/shop totals, server quotes, useful validation and a separate explicit review. Preserve exact payload/token retry behavior and never infer payment/order success from navigation.
5. Use the existing crimson/slate theme, Plus Jakarta Sans, generous white panels and restrained controls. Respect safe areas, keyboard, text scaling, small/landscape/wide layouts, accessible labels and minimum touch targets. Never redirect to the website.

## Commit slices

- Search contract/controller, native filtering and responsive results.
- Shopping Bag selection/stock/pricing and responsive shop groups/summary.
- Product viewing and native purchase controls.
- Checkout layout, voucher/quote handling and explicit review.
- Focused regression verification, scope documentation and combined local PR draft.

## Verification

Inspect executable web/backend contracts before implementing. Run formatting, static analysis, focused isolated tests for changed behavior, and Android/Linux compilation. Read-only local backend checks may inspect catalogue, product, Bag and quote contracts. Never submit live orders/payments/messages/emails, reset the shared database, open a visible browser, use browser automation or take screenshots for routine checks. Record actual evidence and remaining device/iOS limitations here.

## Implemented outcome

- Search consumes `/buyer/search` with all verified filters and sorts. Phones use an apply/reset sheet; wide layouts use a filter sidebar. Chips remove individual filters; empty results show server suggestions and related products. Home search and department links open the full native Search destination, preserving subsequent tab state.
- Shopping Bag groups rows by shop, supports local search/sort/selection filters, defaults to the server selection or most recently added eligible row, and bounds quantity controls using actual global/option stock. Server-confirmed changes replace rows; failed removals retain the item. JSON selected-item quotes validate returned IDs, ignore stale results, and drive per-shop delivery and total estimates. Native sign-in resumes Cart.
- Product view retains real variant/sale pricing, gallery/zoom, stock/limits, shop, reviews and specifications. Mobile actions stay within reach and guide incomplete selections back to options. Unavailable colors/sizes are disabled, gallery arrows and focused detail views are native, and related products use real cards and save controls.
- Checkout uses separate delivery/address/item/voucher/payment panels, a wide sidebar summary and a phone review footer. Fields stay mounted through long scrolling and are retained across width changes. Failed validation focuses the first invalid recipient field. Paginated native voucher choices, server comparison, slot-specific removal and structured expiry repair preserve other valid choices and discard stale comparisons. Savings are split correctly within the server's total discount. Explicit review and exact payload/token retries are preserved.
- Regression review also fixed the Profile panel's Material surface for visible control feedback and replaced real-network attempts in old Profile test fixtures with isolated responses. No backend source was changed.

## Verification — 2026-10-27

- `flutter test --reporter expanded`: all 76 isolated checks passed. New coverage includes encoded search/Bag requests, stale searches/quotes/comparisons, filter validation and pagination, matrix/legacy quantity bounds, confirmed removal, voucher slot preservation/repair, native voucher paging, separate savings display, recipient validation after scrolling/resizing, native Home-to-Search navigation, explicit order review and exact retries.
- Widget checks cover 320/375/430 phone widths, 820 × 375 landscape, 1024/1200 wide windows, 200% text, and existing reduced-motion/keyboard scenarios. No visible browser or screenshots were used. Source review checked native navigation, theme, labels, disabled/loading/error states and safe-area placement.
- `flutter analyze`: no issues.
- `flutter build apk --debug` and `flutter build linux --debug`: passed.
- `dart run tool/check_backend.dart <BACKEND_ORIGIN>`: passed against the running local backend for home, registration/policies, catalogue, dedicated search and canonical filters, full product, shop, guest Bag and checkout regions. Observed 16 departments and 17 listings; these are fixture observations, not app constants.
- Formatting and `git diff --check`: passed.

No live Bag changes, order/payment submission, messages, emails or database resets were performed. Order/quote/voucher mutation behavior was exercised with isolated fixtures and a temporary local HTTP server. Physical-device interaction, screen-reader review and iOS compilation remain unverified; iOS needs macOS/Xcode. This pass preserves the existing light theme.

Status: implemented and verified on `feat/buyer-shopping-polish`. Commits remain local. The combined PR title/body is prepared in `.git/PR_BUYER_SHOPPING_POLISH.md` for a later authorized push.
