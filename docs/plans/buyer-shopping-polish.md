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

Status: implementation in progress.
