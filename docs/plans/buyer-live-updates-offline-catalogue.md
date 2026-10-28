# Buyer updates and offline catalogue

## Scope

Start from merged `main` (`fcb00da`) on `feat/buyer-live-updates-offline-catalogue`. Change buyer mobile only. The website and all sibling repositories remain read-only. Keep commits local until the owner requests a push.

## Acceptance criteria

1. Visible shop/courier conversations receive new messages automatically. Preserve typed drafts, selected photos and scroll position; deduplicate by server message ID. Message sends remain explicit and retain the existing retry key.
2. The visible inbox and order detail refresh automatically. Preserve inbox search and order action feedback. Only accept the current buyer's server state; clear private data and stop automatic retries on denied/expired access or identity changes.
3. Share one foreground refresh mechanism: no overlapping reads, bounded failure backoff, immediate refresh on return, and pause while backgrounded, covered by another route, busy with an explicit action, or disposed. Never automatically repeat a message/order/payment/account mutation. Existing chat GET acknowledges incoming messages on the server, so poll only the visible conversation.
4. Cache successfully viewed public Home/Search/product information for later read-only browsing. Persist only an explicit allowlist of public catalogue fields; never store full Inertia props, users, saved IDs, Bag quantities, addresses, orders, messages, tokens or private evidence. Bound entries/size/age, isolate backend origins, handle corrupt/unavailable storage, label cached data and recorded time, and require a fresh product response before shopping actions. Do not cache authoritative checkout, stock or payment decisions.
5. Retain and extend `docs/integrations/website-ai-handoff.md` with actual current contracts, observed limitations and proposed future backend work. Native Google and device push stay deferred until verified backend contracts and owner provider setup exist. No unsupported endpoint calls, website redirects or pretend provider buttons.
6. Isolated tests cover lifecycle/navigation, backoff, overlapping requests, private account boundaries, chat draft/send races, order updates, and cache privacy/freshness/fallback behavior. Format and analyze all changed Dart code; run the full test suite and compile the native preview. Report physical-device and iOS limitations accurately.

## Commit breakdown

1. Record this plan and acceptance criteria.
2. Add foreground refresh and native conversation updates, with focused tests.
3. Add inbox/order refresh and access-boundary handling, with focused tests.
4. Add bounded public catalogue persistence and clearly labeled read-only fallback, with tests.
5. Complete accumulated website handoff, setup/behavior documentation, validation evidence and local PR draft.

## Progress

- Pulled current `main`; created the working branch with a clean tree.
- Verified existing `/chat/messages/{receiver}`, `/buyer/messages` and `/buyer/orders/{order}` source contracts. Chat GET also marks incoming messages read; no separate buyer acknowledgement route exists today.
- Implemented foreground reads and conversation updates in `143141b`, inbox/order updates in `96ea25e`, action-race hardening in `0fdfdde`, and the public cache in `445b4d3`. Cache-clearing race protection is in `4551bea`; confirmed deletion feedback is in `b9386e5`. All commits remain local.
- Extended the existing website handoff instead of editing the website. Google, app-link association setup and background push remain explicit external dependencies. Cursor reads, precise chat acknowledgement, conditional reads and public catalogue/image cache guidance are cumulative future requests.
- The connection-error layout regression reproduced a 292-pixel overflow in a short landscape window at 200% text with the keyboard open. `224ef9c` bounds the scrollable feedback area; eleven focused chat/post-purchase tests passed after the fix.

## Local implementation commits

| Commit | Subject |
| --- | --- |
| `bcf9665` | docs: plan buyer updates and offline catalogue |
| `143141b` | feat: refresh visible buyer conversations automatically |
| `96ea25e` | feat: keep buyer inbox and recorded orders current |
| `0fdfdde` | fix: preserve buyer action feedback across refresh races |
| `445b4d3` | feat: support read-only cached buyer catalogue browsing |
| `4551bea` | fix: keep cleared browsing snapshots from returning |
| `b9386e5` | fix: report failed browsing cache deletion accurately |
| `224ef9c` | fix: keep chat recovery feedback within short windows |

## Completion evidence

| Requirement | Current evidence |
| --- | --- |
| Conversation updates and draft/send safety | `chat_updates_test.dart` verifies new messages, ID deduplication, preserved draft, delayed reads versus confirmed sends, connection recovery, identity clearing and reachable composition during an enlarged keyboard/error state. Existing post-purchase tests verify editable questions, explicit retry keys and the large-text keyboard composer. `_load` never replaces the draft or selected photo, and scroll-follow is limited to buyers near the bottom. |
| Inbox and recorded orders | `buyer_updates_test.dart` verifies changing unread badges without losing search, changing server status without mutation, retained confirmed state during failures, revoked/changed-account clearing, late responses after identity cleanup and a read racing explicit receipt confirmation. |
| Foreground scheduling | `foreground_refresh_test.dart` verifies serialized reads, stale tickets, bounded backoff, success recovery, access-stop behavior, covered-route pause, background pause, resume and disposal. Screens pause reads during explicit actions; the order action race test exercises that integration. |
| Public persistence and read-only fallback | `catalogue_cache_test.dart` verifies serialized privacy projections and re-sanitization, restart and origin isolation, bounds/expiry/clear/corruption, unavailable storage, a real local HTTP service followed by refused connection, exact filters/pages, fresh prices, denied/missing snapshot invalidation, identity changes during reads/storage writes, pending requests after clear and failed device deletion/retry. `cached_catalogue_widgets_test.dart` verifies disabled shopping until refresh and saved-data feedback at phone/landscape/tablet sizes with 200% text and reduced motion. |
| Cumulative website requests | `docs/integrations/website-ai-handoff.md` lists existing contracts separately from future Google/push, association, message pagination/read acknowledgements, conditional updates and cache guidance. The older contract document points to that cumulative handoff. No sibling files or Git state were changed. |

Final code validation:

- `dart format --output=none --set-exit-if-changed lib test tool`: 113 files, unchanged.
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --reporter expanded`: all 214 isolated tests passed, including the existing 179 tests and 35 new tests.
- `flutter build linux --debug --no-pub`: passed; `build/linux/x64/debug/bundle/bagoo_buyer_mobile`.
- `flutter build apk --debug --no-pub`: passed; `build/app/outputs/flutter-apk/app-debug.apk`.

Test output is machine-local in `.git/buyer-live-updates-tests.log`; focused privacy/race/layout logs are also in `.git`. No live buyer, message, order, email, payment or database mutation was used. No visible browser or screenshot was opened. The readable PR title/body is saved locally in `.git/PR_BUYER_LIVE_UPDATES.md`; no GitHub PR or branch publication was performed.

## Limits and owner acceptance

- This is foreground polling, not background push. One already-started server read can finish after a screen is covered. The current chat GET acknowledges all returned incoming messages, including older messages outside the viewport; precise display-only acknowledgements require the proposed server contract.
- Cached pages contain public text, image URLs and product options. Photos are not newly persisted; Flutter memory may retain decoded images, and other photos need a connection. Only previously fetched queries/pages/product details are available offline. Clearing saved browsing data deletes persisted snapshots; an already open page remains in memory until refreshed/closed.
- Cache storage uses the existing secure-store plugin. Storage failure preserves an in-process cache and ordinary online behavior; persistence across restarts then remains unavailable. Clearing invalidates earlier pending cache saves. If device deletion fails, the app reports that unconfirmed outcome and offers an explicit retry. Cache data never proves current prices, availability, account access, payment or order transitions.
- Physical Android/iOS background/resume, flaky-network behavior, native photo selection, persistent secure storage, scroll behavior and screen-reader acceptance still require device checks. Existing supported light theme is retained; no dark theme is introduced. iOS compilation requires macOS/Xcode and is unavailable on this Linux host.
- The PR description is a local draft; this task does not authorize publishing this new branch.
