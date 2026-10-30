Title: Fix buyer validation and private shopping state

Buyer forms accepted mixed numeric input and inconsistent Unicode lengths. Private collection, account, address, return and checkout screens could keep using an old session. Checkout now rejects stale drafts, confirmations and late replies, including changes between navigation and its first rendered frame. The changes follow existing server contracts and preserve exact retry intent under the same account. Uncertain address creation requires reviewing saved addresses before another attempt, and same-titled PDF views now render their own evidence. Failed validation reveals the first invalid field, selected locations remain readable at enlarged text, and preview dialogs stay within the selected phone. Native review entrypoints use synthetic data with outbound requests blocked.

Only buyer mobile changes. No backend source, configuration, database, deployment or Git changes are included. The branch locally includes the previously published buyer misuse batch so its regressions remain fixed during this continuation; inspect the current PR base before publication.

Validation at this checkpoint:

- 621 isolated unit/widget cases; clean analysis and formatting of 67 changed/new Dart files.
- Native Linux checkout/product/Bag/payment/voucher/layout (71 checkpoint plus 3 focused repeated-decision cases), account/address/layout (80), return/evidence (53), real PDF (4), and earlier buyer/collection (26) groups pass on a separate display. Groups overlap.
- Actual keyboard, clipboard and native picker checks showed invalid-field feedback, one request after repeated submits, private-state clearing, pending identity review and server cooldown feedback.
- Linux review and normal Android debug builds pass.

The broad feature audit remains in progress. GPS values and pending requests, deeper private Bag/purchase/voucher behavior, discovery, messaging, recovery and notification/tracking exploration are still being completed. Physical device, provider and iOS acceptance are separate. This title/body is a local draft; no GitHub PR or publication is claimed.
