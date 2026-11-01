# Buyer voucher misuse review

Continue the complete buyer audit after the 723-case Bag checkpoint on the current unpublished branch. Use the private Linux display, synthetic replies and blocked outbound requests. Only buyer mobile is writable; backend contracts are read-only references. Do not publish without a new owner instruction.

## Acceptance and logical commits

1. Reproduce stale bookmark actions and replies, changed offer/repository/permission state, invalid revision/saved IDs, repeated requests and explicit failure recovery. Bind each action to its displayed offer and opening session; preserve the exact save/remove intent during an uncertain result. Keep guest sign-in and approved-buyer bookmark behavior native.
2. Reproduce picker access loss, late/duplicate loads, changing checkout inputs, page boundaries and repeated Use/Remove decisions. Preserve the opening checkout scope across navigation, retain the actual selection snapshot and consume each navigation decision once. Server quotes determine eligibility and savings.
3. Check private voucher-list ownership and its parent profile behavior. Add focused cases for confirmed gaps rather than assuming earlier account-form tests cover lists or navigation.
4. Run the affected native Linux cases and actual keyboard/visible-feedback checks on the private display. Verify focused/full tests, formatting, analysis and relevant builds, then update the coverage record and local PR draft. Continue purchases/reviews, discovery/product/shop, messaging, recovery and notifications/tracking afterward.

## Existing contracts and initial inspection

The existing voucher controller and saved-voucher service require an active approved buyer. Saving validates the current available revision and uses a buyer/revision bookmark; it does not reserve or consume a discount. Its reply contains a positive model integer `saved_id`. Removing an absent bookmark is a no-op returning explicit null, while another buyer's bookmark is denied. The client must not invent a payment or reservation transition.

Authenticated choice requests carry selected item/delivery inputs, an optional positive shop ID and a page from 1 to 100000. JSON choice/quote replies do not include a fresh authenticated profile. The opening session and checkout must still be current when these responses arrive.

Inspection found no opening-session guard in OfferTile or VoucherPickerPage. OfferTile's method checks its busy flag but does not recheck a disabled save permission; local saved state is initialized only once. The picker mutates its page counter in retained callbacks and pops routes directly for selection/removal. Reproduce these paths before fixing them. Earlier passing voucher/checkout cases establish normal paging and quote comparison, not these missing ownership and repeated-action cases.

## Bookmark checkpoint

The initial 33 bookmark cases reproduced 28 failures involving expired or disposed callbacks, revoked permission, changed repositories/offers, obsolete saved IDs, late replies and malformed IDs. Each button now captures its displayed revision, saved target and generation. The action checks its opening session and current permission before sending and after replies or refresh callbacks. Changed offer metadata resets local state; unchanged parent rebuilds preserve an acknowledged bookmark. Old callbacks cannot toggle a completed save into removal or overwrite a newer pending offer.

Revision, saved-target and returned saved IDs must be positive integers. Removal still requires explicit null acknowledgement, matching the existing idempotent server contract. Temporary failures retain the same save/remove intent for an explicit retry. Guest sign-in dispatches once without a bookmark request. Access loss clears the visible saved state and ends further bookmark actions.

All 39 final bookmark cases pass in isolation and the native Linux runner, including six additional completion/rebuild/race/denial/sign-in checks. The combined voucher/product/checkout run passes 59 cases. All 762 isolated tests, analysis, formatting of 80 changed/new Dart files, the Linux voucher review build and the Android debug build pass. In the private native window, a confirmed save made one request, a failed removal retained the same action with visible guidance, and session expiry removed the saved state with no extra request. GUI actions used only the private display; no real bookmark or owner desktop input was used.

The picker, private profile voucher-list ownership and the remaining broader feature families are still open. This bookmark checkpoint does not establish those missing paths or provider/device/backend acceptance.

## Picker checkpoint

Picker exploration reproduced queued requests for pages 2 through 9, repeated Use/Remove decisions popping the underlying route, stale choices and replies after account changes, old-page callbacks selecting a newer page, and mutable nested checkout inputs changing later requests. A change between checkout route creation and the picker's first build also sent a request under a new session. The picker now inherits the opening checkout scope, retains its input snapshot, serializes reads and consumes each navigation decision once. Each displayed page has a child scope that expires before paging, immediately stopping cached bookmark actions as well.

Page metadata is checked against the request and the backend's page limit. An unavailable final page gets one bounded correction read; temporary errors keep an explicit retry for the same page. Access denial clears choices and invalidates the supplied checkout scope, so closing the picker also removes obsolete checkout details. Closing a normal child view leaves its parent's scope intact. Three additional bookmark tests cover inherited-scope invalidation and disposal.

Two further cases reproduced cached Review/Compare actions running behind an open picker. Checkout now holds those actions until the picker closes, prevents duplicate picker entries and passes a frozen selection into the route. The chooser checks revision, eligibility and voucher slot before returning a selection; quotes and final eligibility remain server-owned.

All 23 picker cases, 42 bookmark cases and the existing normal picker case pass in the real Linux runner as one 66-case group. The focused voucher/checkout run passes 72 cases. All 788 isolated tests, full analysis, formatting of 82 changed/new Dart files and Android debug build pass. The Linux review build and a focused tool analysis also cover the final synthetic-fixture synchronization change.

Private-window inspection showed one read per page, an acknowledged bookmark refreshing page two, one returned selection and account expiry hiding private rows and actions without another mutation. The review tool models saved IDs and exposes choice-read counts. No real voucher, order, account or owner-desktop input was used.

Private profile voucher-list ownership and the remaining purchase/review, discovery/product/shop, messaging, recovery and notification/tracking exploration remain open. Existing passing account forms do not prove the profile root and its retained lists are scoped correctly. Continue that review before claiming the full buyer audit is complete.

## Pre-publication review, November 1

Finish the existing picker slice before publishing this branch. Acceptance: review the pending diff and unpublished history, pass the full isolated suite and native voucher group on a separate display, verify formatting/analysis and Android build, update the branch PR draft and save the slice as a local commit. A second documentation commit records final evidence if needed. Publication requires the owner's push instruction.

This publication checkpoint covers the existing branch and pending picker slice. The broader feature audit remains open with the profile-list and other families listed above; this checkpoint does not claim full product acceptance.

Fresh verification passed: 788 isolated tests, all 66 native Linux voucher cases on a newly created private display, full Flutter analysis, focused review-tool analysis, formatting of all 82 changed/new Dart files, diff whitespace checks and the Android debug APK build. The native integration run rebuilt the Linux application. The 23 previously unpublished commits were inspected for private-key/token and internal task-management markers with no findings. No new product fix was needed during this review. Existing October 30 private keyboard/feedback evidence remains recorded above; this rerun used native automated interactions.

The local PR draft now includes voucher selection and retains the remaining broad-audit and physical-device/provider/iOS limitations. All pending picker source, regression cases and review-tool changes are saved together locally; no push or GitHub PR publication is part of this checkpoint.
