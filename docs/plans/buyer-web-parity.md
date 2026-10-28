# Native buyer web parity

## Scope and acceptance

Start from refreshed mobile main `830cae7` on `feat/buyer-web-parity`. Implement the buyer functions and meaningful information identified in the source audit using native Flutter and verified existing contracts. Preserve server ownership, original account identity, explicit order/payment confirmation, stale-response guards, and Bagoo's responsive crimson/slate components. All sibling repositories are read-only. No publication is authorized for this task.

Keep the website maintainer handoff in `docs/integrations/website-ai-handoff.md`, with detailed proposals in `buyer-mobile-contract-requests.md`. Record exact missing contracts, deployment/configuration requirements, examples and acceptance checks there. Proposed endpoints must never be called as though deployed. Native Google and optional device push depend on separately authorized website/provider work; document those prerequisites instead of introducing a website redirect or a fake success.

The website working tree is evolving independently. Recheck relevant controller/service contracts before each integration. Source observed during the audit included logistics version-two checkout and automatic server completion; mobile must render server status and action eligibility without advancing an order locally. This differs from older prose that described only historical buyer-confirmed completion.

## Complete audit checklist

`Pending` means implementation remains. `Dependency` means an exact prerequisite must be handed to the website maintainer. Update each row with delivered behavior and verification before handoff.

| ID | Audit requirement | Initial status |
| --- | --- | --- |
| P01 | Native Google authentication and registration | Dependency: native identity exchange |
| P02 | Remembered login/email and guest session continuity | Implemented; isolated account/session checks pass |
| P03 | Recognize current sessions on authentication screens | Implemented; isolated account/session checks pass |
| P04 | Emailed password-link recovery and token reset | Implemented; isolated account/session checks pass |
| P05 | Canonical address fields in registration | Implemented; isolated account/session checks pass |
| P06 | Optional identity upload during registration | Implemented; isolated account/session checks pass |
| P07 | Live registration email availability | Implemented; isolated account/session checks pass |
| P08 | Full account status, restriction review requests and decisions | Implemented; isolated account/session checks pass |
| P09 | Home application entry, correction and status refresh | Implemented: Home application/correction entry, resume refresh and native status destination |
| P10 | Home active-shipment summary and order destination | Implemented; isolated discovery checks pass |
| P11 | Home recommendations and related products alongside search matches | Implemented; isolated discovery checks pass |
| P12 | Home advanced filters, price presets and exact five-star option | Implemented; isolated discovery checks pass |
| P13 | Catalogue page selection/range and shop previous navigation | Implemented; isolated discovery checks pass |
| P14 | Shop departments, nested store categories, sorting and reset | Implemented; isolated discovery checks pass |
| P15 | Storefront voucher offers and actions | Implemented; isolated discovery checks pass |
| P16 | Shop address, followers, reply rate and opened date | Implemented; isolated discovery checks pass |
| P17 | Native product sharing beyond clipboard | Implemented; isolated discovery checks pass |
| P18 | Sale countdown, precise times and boundary refresh | Implemented; isolated discovery checks pass |
| P19 | Delivered-reminder acknowledgement and disabled resubscribe | Implemented; isolated discovery checks pass |
| P20 | Combined review photos and seller reply update time | Implemented; isolated discovery checks pass |
| P21 | Logistics-company choice and company-filtered collection hubs | Implemented; checkout/Bag regression checks pass |
| P22 | Company/postal/barangay-aware quotes and stale-choice repair | Implemented; checkout/Bag regression checks pass |
| P23 | Shipping weights, tariff, route and measurement fallback | Implemented; checkout/Bag regression checks pass |
| P24 | Native GPS, manual coordinates and saved coordinate preservation | Implemented; checkout/Bag regression checks pass |
| P25 | Mixed promotional price segments in Bag and final review | Implemented; checkout/Bag regression checks pass |
| P26 | Per-voucher checkout allocations and saved order receipt | Implemented: checkout allocations and immutable order voucher receipt |
| P27 | Voucher issuer, capped benefits and eligible-product navigation | Implemented; isolated discovery checks pass |
| P28 | Correct promotion percent and shipping offer summaries | Implemented; isolated discovery checks pass |
| P29 | Complete wallet receipt, refund evidence and deadline transitions | Implemented; isolated post-purchase checks pass |
| P30 | Order milestones and observed/custody timestamps | Implemented; isolated post-purchase checks pass |
| P31 | Order-linked updates, unread state and explicit acknowledgement | Implemented; isolated post-purchase checks pass |
| P32 | Package partner, pickup, rider, notes and tracking information | Implemented; isolated post-purchase checks pass |
| P33 | Checkout/payment/order/product navigation shortcuts | Implemented; isolated post-purchase checks pass |
| P34 | Scannable return barcode and QR | Implemented; isolated post-purchase checks pass |
| P35 | Return weight, route position and manifest reference | Implemented; isolated post-purchase checks pass |
| P36 | Return next steps, photo purposes and decision/actor labels | Implemented; isolated post-purchase checks pass |
| P37 | Rich tappable chat product cards and message timestamps | Implemented; isolated post-purchase checks pass |
| P38 | Product inquiry action and editable quick questions | Implemented; isolated post-purchase checks pass |
| P39 | Compact notification preview, displayed snapshot and read times | Pending |
| P40 | Native support entry while shopping | Implemented; isolated discovery checks pass |
| P41 | Native incoming links and missing internal destinations/anchors | Pending; owner domain association needed |
| P42 | Advertisement impression measurement | Pending |
| P43 | Native platform information equivalent to Overview/About | Implemented; isolated discovery checks pass |

Partner/admin portal sign-in and merchant branding edits are separate products. Native sharing uses the operating system's app chooser. A buyer role remains fixed. Public website SEO is represented by native links rather than copied browser metadata.

## Logical delivery slices

1. Checkout logistics, coordinates, shipping explanations and price/voucher receipts, with isolated quote/race checks.
2. Home/catalogue/shop discovery and promotion/voucher/product details, with navigation and filter checks.
3. Native account status, registration additions, password recovery and application access, with ownership and retained-draft checks.
4. Orders, wallet receipts, returns and rich messaging, preserving server action authority.
5. Notification preview, support access and advertisement measurements, with explicit read semantics and lifecycle checks.
6. Secure optional session persistence, native sharing/location/code rendering and incoming link handling. Document owner setup and unsupported platform behavior accurately.
7. Combined verification, README and website handoff, and separate local PR description. Use coherent local commits; push only upon a new explicit request.

## Verification requirements

- Meaningful isolated regression tests for changed contracts, ownership, session restore/logout, stale quotes, exact retry payloads and navigation. No live accounts, messages, emails, orders, payments or databases may be mutated.
- Formatting, static analysis and full Flutter tests for the combined source. Android/Linux compilation for added native plugins. iOS requires macOS/Xcode and owner provisioning; report actual limits.
- Phone/landscape/tablet layouts, 200% text, keyboard insets and reduced motion on affected screens. No visible browser automation or screenshots.
- Audit every P01–P43 row against the final files. Requirements depending on website/provider work need a concrete handoff and an honest unavailable state; documentation is not proof of a functioning provider integration.

## Status

Implementation started. Website/backend handoff expansion and checkout integration are the first slice. No website edits, migrations or publications are part of this work.

### Checkout slice verification

Formatting and static analysis pass. All 17 focused checkout/logistics/Bag tests pass, including unavailable and stale company replies, quote context, saved coordinate submission, a late location result after manual edits, voucher repair and exact order retries. Native plugin compilation and physical location/share interaction remain for combined verification. No live backend data was mutated.

### Discovery slice verification

All 38 focused discovery, product, search, Home and authentication baseline tests pass. New checks exercise direct-page races, related products alongside matches, nested shop categories and sorting across pages at 200% text, capped voucher benefits with native eligible-product URLs, and one-time sale boundary refresh. Home filters use the same native filter sheet and open the filtered Search tab. Sharing retains Copy link for the Linux preview; Android/iOS share interaction is still a device acceptance check.

### Account slice verification

The 28 session, transport and authentication baseline tests pass. New account checks cover session recognition, stale email-availability responses, restriction-review conflict tokens and retained drafts, owner changes, optional registration multipart inputs, and explicit native password-link submission and foreign-link rejection. Remembered cookies use native secure storage; passwords and reset/verification tokens remain in memory. Guest cookies survive restarts, unremembered login cookies do not, and queued writes cannot resurrect a cleared session. Native keychain/provisioning and incoming OS links remain for platform verification.

### Purchase follow-up slice verification

Six new isolated checks pass for repeated checkpoint/notice merging, missing milestone evidence, separate return barcode/QR payloads, payment expiry while its refresh is pending, editable chat questions with exact retry keys, and keyboard/200% chat layouts. The six existing checkout widget checks also pass, and static analysis is clean. Payment expiry only disables a local action and fetches recorded status; it never marks a payment expired or successful locally. Scanning printed/device codes and real repayment/parcel actions remain manual acceptance work.
