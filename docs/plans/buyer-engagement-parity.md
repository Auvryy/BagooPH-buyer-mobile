# Native buyer engagement parity

Started on `feat/buyer-engagement-parity` from freshly pulled `main` at `06016ab`. Work stays in `BagooPH-buyer-mobile`; the web repository is a read-only contract reference. Keep this branch local until separately authorized to push.

## Acceptance

1. Homepage campaign banners are labeled, tappable controls. Their same-origin visit URLs preserve backend publication eligibility and supported advertisement destinations. Product, shop, search, and promotion destinations open native Flutter screens; no buyer is sent to a website or WebView. Promotion details display current availability, Manila schedule, artwork, offer terms, destination, and available products, with an explicit unavailable state.
2. Signed-in buyers can open paginated Saved Products and Followed Shops collections from Profile. Rows use confirmed availability, native product/shop navigation, remove/unfollow actions, loading, empty, error/retry, stale-response, and sign-in states. Existing save/follow controls keep their server-confirmed behavior.
3. Signed-in buyers can open a native Notifications center from the Home toolbar and Profile. The center supports All/Unread filters, server pagination, opening and marking an individual item read, and mark-all through the server's expiring read snapshot. Unread count comes from the server preview and updates after confirmed actions. Known notification destinations use native order, product, return, wallet, or account screens; unsupported destinations stay inside the native center.
4. Reuse the Bagoo crimson/slate theme, Plus Jakarta Sans, safe areas, existing image/product/shop widgets, constrained wide layouts, minimum touch targets, and readable large-text behavior. Preserve session ownership and server authorization.

## Verified contracts

- Homepage banners come from `AdvertisementReader::homepage()` and contain an internal `href` visit route plus optional signed measurement data. Visit routes redirect to an eligible product, shop, search, or `Buyer/Promotion` page. `Buyer/Promotion` receives `promotion`, `products`, and `categories`; the server decides availability and offer terms.
- `GET /buyer/saved-products` returns `Buyer/SavedProducts` with a paginated `entries` list. Existing save mutations use JSON `POST/DELETE /buyer/saved-products/{product}`.
- `GET /buyer/followed-shops` returns `Buyer/FollowedShops` with a paginated `entries` list. Existing follow mutations use JSON `POST/DELETE /buyer/followed-shops/{shop}`.
- `GET /notifications/preview` returns recent notices, unread summary, and a `readSnapshot`. `GET /notifications?filter=all|unread` returns the full paginated native-renderable contract. JSON `PATCH /notifications/{uuid}/read` marks one item; `PATCH /notifications/read-all` requires the issued snapshot UUID. Notice payloads are deliberately allow-listed by the server.

## Implementation slices

1. Native advertisement destinations and promotion details.
2. Paginated saved-product and followed-shop workspaces reachable from Profile.
3. Notification repository, toolbar unread badge, native center, safe destination routing, and confirmed read actions.
4. Update setup/feature documentation and prepare a combined local PR draft.

## Verification and limits

- `dart format` completed for all changed Dart files.
- `flutter analyze` passed with no issues.
- `flutter build apk --debug` passed and produced the debug APK.
- `flutter build linux --debug` passed and produced the Linux debug bundle.
- No automated tests were added or run, per the mobile repository instructions.
- No live saved-product, follow, notification, order, or profile mutations were performed.
- Physical-device, screen-reader, and iOS/Xcode checks remain unverified on this Linux host.

Status: implementation and local verification are complete. The branch is local and unpushed; see the local PR draft in `.git/PR_BUYER_ENGAGEMENT_PARITY.md`.
