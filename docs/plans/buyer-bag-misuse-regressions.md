# Shopping Bag misuse review

Continue the open buyer audit after the recipient-location checkpoint on the existing unpublished branch. Only buyer mobile is writable. All interaction uses the private Linux display with synthetic data and blocked outbound requests; leave the owner's class desktop untouched.

## Acceptance and commit sequence

1. Reproduce account changes, foreign or late Bag/quote/mutation replies, denied access and retained private state. Bind work to the opening session and buyer or guest. Preserve legitimate guest Bags, active/pending buyer changes and restricted-buyer viewing under the existing backend contract.
2. Reject unknown items and invalid/out-of-stock quantities before a mutation. Preserve confirmed rows during temporary failures, prevent duplicate requests and discard obsolete quote results. Server authorization, stock and totals remain authoritative.
3. Exercise quantity/removal dialogs, cancellation, queued callbacks, account changes, tab activation, disposal, keyboard entry and narrow/enlarged layouts. Clear obsolete private rows and drafts and consume each confirmation once.
4. Repeat the affected cases in the native Linux runner and inspect visible feedback through the private display. Save coherent local controller and interaction commits with focused/full checks, analysis, formatting and relevant builds. Update the cumulative local PR draft; publication requires a new owner instruction.

## Existing contract

The read-only Cart controller serves guests by session and signed-in buyers by their owned cart. Buyer account viewing includes eligible active, pending, inactive and suspended states; changes require active or pending status. Quantity must be an ASCII positive integer from 1 to 99 within current product/variant and shared stock. The server rejects another cart's item and performs stock checks under locks. JSON quotes contain selected item totals and offers rather than a new authenticated profile.

Initial testing reproduced 37 failing scenarios in 44 controller cases. Missing guards accepted late or foreign-owner replies, retained private rows after denied access and sent unknown or unavailable item/quantity changes. The controller now binds to its opening session and buyer or guest, checks returned cart ownership, clears private rows/selections/quotes/offers/errors after access loss and validates the current item and quantity before mutations. Guest shopping and restricted-buyer viewing remain supported. Repeated quote retries share the pending request for an unchanged selection.

Two further failures showed a successful change being acknowledged after its follow-up quote lost account access. The result is now checked after that await as well. All 50 new controller cases and the combined 70 Bag/navigation/foreground cases pass, with clean analysis and unchanged formatting of the four affected Dart files. Temporary outages preserve confirmed rows and require explicit recovery; no failed mutation is replayed automatically. Shared stock/quote fixtures are reused by the prior Bag cases.

## Native dialogs and recovery

The first 20 dialog cases reproduced 15 failures: private search/item/quantity details remained after expiry or cancellation, cached entry actions opened obsolete details, repeated entries stacked dialogs, queued decisions popped the underlying Bag route, background quantity steps acted during a dialog and refreshed stock limits were not reflected in the form. Quantity and removal dialogs now check the opening Bag, accept one decision while their own route is current, mask obsolete details and check access even after cancellation. Other quantity and checkout actions wait for the dialog to close.

Tab refreshes are scheduled after the current build so that the independent dialog route updates safely. The form uses the latest available quantity. Reopen Bag creates separate session-bound contents; disposed callbacks cannot act on the new buyer's rows. A further queued-reopen failure is covered by a one-use action on the old contents. Restricted accounts retain their permitted view, while guest and pending buyer quantity changes still work.

All 31 dialog/lifecycle/recovery/layout cases pass, including short landscape windows, enlarged text, keyboard insets and reduced motion. The combined focused run passes 101 cases. The private native runner passes 97 Bag/controller/stock/layout/navigation cases; these include controller cases and overlap prior native groups. All 723 isolated tests, analysis, formatting of 75 changed/new Dart files, the Linux Bag review build and the Android debug build pass.

In the separate native window, actual keyboard input left the previous quantity unchanged after letters, displayed the inline zero error and acknowledged one valid update with one synthetic request. An account change masked the open quantity draft and its underlying rows; closing it exposed Reopen Bag, which issued a fresh read. A synthetic failed removal retained the item, showed recovery feedback and left the unconfirmed total unavailable. All app requests were blocked. The owner's mouse, keyboard and desktop focus were untouched.

The debug Bag review entrypoint and native target are documented in README. Voucher bookmarks/selection, repeated public product navigation and the remaining purchase, discovery, messaging, recovery and update/tracking families still need their dedicated continuation. This checkpoint does not complete the broader buyer audit or establish real provider/device/backend acceptance.
