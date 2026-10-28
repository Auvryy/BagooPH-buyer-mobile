# Buyer design and loading polish

## Scope and design review

Start from current merged `main` (`39ba22d`) on `feat/buyer-design-loading-polish`. Only buyer mobile is writable. Preserve BagooPH, crimson `#E00D42`, Plus Jakarta Sans, native flows and existing server contracts. Keep commits local until the owner requests a push.

Review each representative journey by asking:

- Is the main task immediately clear, with products and primary actions easy to find?
- Are title, price, supporting details and feedback visually distinct without unnecessary decoration?
- Are spacing, corners, typography and surfaces consistent across discovery, purchase and account screens?
- Can long names, large prices, enlarged text, small windows, safe areas and the keyboard fit without clipped controls?
- Can a buyer distinguish loading, refreshing, saved data, empty results, failure and confirmed success?
- Does refresh preserve useful content, scrolling, drafts and form values?
- Which waits are necessary server confirmation, and which are repeated reads, image decoding or storage work that can be removed?

The skill catalogue's generic landing-page layouts are not a complete match for this established shopping app. Use its general accessibility, interaction, loading and hierarchy rules with the current buyer brand. Review native Flutter fixture renders off-screen; no visible browser, browser automation, live buyer mutations or OS screenshots are needed for this design audit.

## Acceptance criteria

1. Audit and improve the shared design and the main Home/Search/product/Bag/checkout/account/message paths. Preserve all existing functions and make the hierarchy calmer and primary shopping actions easier to scan. Review representative auth, notifications, support, tracking and post-purchase states too; fix concrete defects found rather than replacing working flows arbitrarily.
2. Home exposes search, filtering, departments and buyer utilities without a large stack of duplicate controls before products. Product cards retain accessible save/open controls, aligned content and honest prices/stock, with comfortable targets and readable metadata.
3. Initial loads have stable, useful placeholders. Refresh keeps previous public content visible with clear progress; cached previews stay read-only and never establish account identity, current stock, prices or payment/checkout eligibility.
4. Show previously loaded public Home/Search/product data while a fresh read is pending. Reuse an already fetched initial Home page. Remove avoidable UI waiting on catalogue cache writes and coalesce identical public reads within the current identity only. Account changes, explicit cache clear, new queries/pages and server-denied/removed results must invalidate outdated previews/results. Never coalesce/replay submissions or use a private-response disk cache.
5. Reduce unnecessary image decode/rebuild work for public thumbnails while keeping full-size viewing usable. Pause unnecessary off-screen refresh work. Retain explicit retries and all account/action race protections.
6. Verify native layout/render behavior across narrow phones, regular phones, tablet, landscape, long content, keyboard insets, 200% text and reduced motion. Inspect representative rendered artifacts with real bundled typography. Add regression tests for actual layout or interaction defects and deterministic loading tests proving earlier content/fewer reads; do not invent production latency percentages.
7. Format changed Dart code, run static analysis and the full isolated suite, compile Android/Linux, and prepare a local PR title/body. Record actual evidence, design decisions, remaining backend suggestions and iOS/device limits. Do not claim every possible device is visually bug-free from a finite test matrix.

## Logical commits

1. Record the plan and baseline review.
2. Improve public catalogue loading and prove request/storage/identity behavior.
3. Refine discovery, shared surfaces and cards, with responsive review evidence.
4. Fix additional flow/layout/interaction defects found by the audit; optimize public image/foreground work where supported by evidence.
5. Finish regression/render review, build validation, documentation and local PR draft.

## Baseline findings

- Home stacks a search field, full-width filter action, utility links, department controls, discovery headings, four sort chips and a second sort dropdown before the grid.
- Home/Search hide their existing grids during refresh. Product details show an initial spinner even when a public snapshot exists.
- `BuyerRepository._catalogue` waits for cache persistence before delivering a successful server page. `HomePage` reloads even when authentication already supplied Home data.
- Public product thumbnails decode without a requested size and each loading image runs its own progress spinner. Cards repeat nested open targets and use a large save-button slot.
- These are source findings. Native render and regression evidence will be recorded as the work progresses.

## Progress

- Baseline native review: 32 cases across eight main screens, using the bundled Plus Jakarta Sans and Material Icons, passed layout checks. Off-screen PNGs are machine-local in `.git/buyer-design/before/`. Visual inspection found products below the first Home viewport, product identity below gallery utility content, and a clipped selected logistics-company label despite no overflow exception.
- Loading foundation now reuses the initial Home response, starts public snapshot previews beside fresh reads, returns online results without waiting for cache writes and coalesces identical in-flight catalogue reads. Identity, submission revision and cache invalidation separate request scopes. Private responses, quotes and mutations are not cached or coalesced by this feature.
- Loading verification: 37 focused cache/controller/widget cases passed; all 12 loading/transport regressions then passed, including late previews, cache clear, account switches and a real isolated HTTP submission racing an earlier read. Static analysis passed. These tests prove request ordering and content availability; no production latency percentage is claimed.
- Discovery now uses a compact search/filter area, one native sort sheet, genuine configured campaigns, a calmer product hierarchy, shared panel/control shapes and independent 48-pixel save targets. The Bag label is consistent with buyer language. Static placeholders cover empty initial loads; refresh/failure retains prior public results with explicit progress/stale feedback and disabled save actions.
- Rendered Home at 375 pixels now shows the first product price before the navigation bar; the review test asserts that outcome. The 320-pixel render also shows product names/prices. Search labels fit without the earlier cramped text. The actual bundled font is preserved in utility-button overrides, and exports wait for the brand image to decode.
- Discovery evidence: the 57-case discovery suite passed; after the last refinements, all 41 render/interaction/card checks passed, including six UX regressions for refresh position/content, failed refresh, placeholders, draft-preserving sort and scrollable sort choices at 200% text. Render artifacts are in `.git/buyer-design/discovery/`. Long prices initially exposed a price-slot overflow; the slot now fits two price lines plus comparison text and all card scales pass.
- Product identity now precedes the phone gallery, with a compact price/selection footer and a separate 48-pixel save control. A lazy horizontal photo strip replaces wrapping thumbnails; its selected photo stays reachable by arrows. Product option/quantity state survives phone-to-tablet reflow.
- Checkout now describes its two real stages, Details and Review. Selected carrier labels have their own unpadded, multiline representation instead of being clipped inside a dense field. Product/checkout action bars use a subtle top border.
- Product/checkout evidence: all 31 focused design, product, quote, voucher, submission and logistics tests passed. Three paint-bound checks cover ordinary and long selected carrier labels at normal/200% text. All 32 main-screen render cases also passed; `.git/buyer-design/flows/` shows the title/price hierarchy and readable carrier selection. The final broad render pass will include the last action-bar border refinement.
- Public card/gallery/Bag/checkout/order thumbnails now request a display-sized decode, rounded into 64-pixel buckets and capped at 1536 pixels per axis. `ResizeImagePolicy.fit` preserves source proportions. Full-size viewers and authenticated image providers retain their original resolution behavior. Static reserved image surfaces replace repeated progress spinners and per-byte loading rebuilds; readiness callbacks report state changes instead of every rebuild. This reduces decode/rebuild work, not the number of source bytes downloaded.
- Sale refresh uses the shared serial foreground reader with a delayed first refresh, avoiding a second initial request. Covered/backgrounded sale routes and their countdowns pause; returning refreshes them. Hidden visited Home tabs retain state with tickers disabled, and Home does not refresh notification summaries behind another route.
- Image/foreground evidence: all 29 focused image, sale visibility, foreground scheduler, notification measurement and product cases passed. Tests verify pixel-density-aware decode bounds, original full/private providers, readiness transitions, no duplicate initial sale read, route/background pause/resume, hidden late-response rejection and countdown boundaries. Static analysis passed before the final public-thumbnail call-site additions; the final suite will cover all additions.
- Broader review now covers notifications, public tracking, support, registration/recovery and owned order/return details, with recorded state assertions and no account/commerce mutations. All 28 additional fixture renders passed; the combined render/product/support/tracking suite passed 103 cases after the additional fixes. Machine-local artifacts are in `.git/buyer-design/final/`.
- The short landscape/200%-text/keyboard test reproduced a 44-pixel overflow in long product failures. The failure panel now scrolls, and its retry action is verified inside the available viewport. Saved product reviews now explain that a refresh is required instead of claiming omitted review data is empty; unknown review counts are not rendered as zero. Tracking retains its lookup and privacy explanation while giving a loaded server status less introductory content to compete with.
- Tablet discovery uses wider cards for readable titles and an inline search/utility/department header to keep the first price visible. Native render assertions cover the first price above navigation on both 375- and 1024-pixel views and the full sample long title at tablet width. Phone controls and all six sort choices remain reachable at 200% text. Bag item-count grammar and action-bar borders are consistent with the shared design.
- After the inline tablet-header refinement, all 46 focused render/discovery/product checks passed. The complete current suite then passed all 309 isolated tests (including the new draft-preserving header resize case), and `flutter analyze --no-pub` reported no issues. Native builds and the completion audit remain in progress.
- iOS compilation, physical devices and screen readers require separate owner acceptance on the appropriate platforms; finite fixture renders cannot prove every possible device/state is visually bug-free.
