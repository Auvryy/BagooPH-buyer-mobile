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
- No implementation or verification results recorded yet.
