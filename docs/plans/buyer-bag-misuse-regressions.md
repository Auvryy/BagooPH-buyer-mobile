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

Native dialog, lifecycle and visible-feedback checks are the next slice. The preceding 642-case full-suite and native commerce checkpoints do not establish those missing interactions; repeat broader checks after that slice.
