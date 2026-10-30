Title: Fix buyer validation and private shopping state

Buyer forms could accept mixed numeric input and inconsistent Unicode lengths. Private collection, account, address, return, Bag and checkout screens could keep using an old session. The changes discard obsolete drafts, actions and replies, reveal invalid fields, and keep preview dialogs inside the selected phone.

Bag changes now check the opening guest or buyer, current item/stock limits and reply ownership. Quantity/removal dialogs accept one decision and reopen with fresh session state. Checkout also guards delayed navigation and confirmations; invalid GPS preserves the previous pin, while valid seven-decimal manual coordinates appear in order review.

Voucher bookmark actions retain their displayed revision, saved target and session, rejecting disabled or obsolete callbacks and malformed acknowledgements. Uncertain address creation requires reviewing saved addresses before another attempt, and same-titled PDF views render their own evidence. Changes follow existing server contracts and preserve exact retry intent under the same account. Native review entrypoints use synthetic data with outbound requests blocked.

Only buyer mobile changes. No backend source, configuration, database, deployment or Git changes are included. The branch locally includes the previously published buyer misuse batch so its regressions remain fixed during this continuation; inspect the current PR base before publication.

Validation at this checkpoint:

- 762 isolated unit/widget cases; clean analysis and formatting of 80 changed/new Dart files.
- Native Linux voucher bookmarks (39), Bag/controller/dialog/stock/navigation (97), checkout/product/Bag/payment/voucher/layout (71 checkpoint plus separate 3 repeated-decision and 21 recipient-location cases), account/address/layout (80), return/evidence (53), real PDF (4), and earlier buyer/collection (26) groups pass on a separate display. Groups include controller cases and overlap.
- Actual keyboard, clipboard and native picker checks showed invalid-field feedback, one request after repeated submits, private-state clearing, pending identity review and server cooldown feedback.
- Linux review and normal Android debug builds pass.

The broad feature audit remains in progress. Voucher selection and private profile-list ownership, purchase/review behavior, repeated public product navigation, discovery, messaging, recovery and notification/tracking exploration are still being completed. Physical device, provider and iOS acceptance are separate. This title/body is a local draft; no GitHub PR or publication is claimed.
