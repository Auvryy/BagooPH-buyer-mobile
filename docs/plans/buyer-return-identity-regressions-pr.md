Title: Fix buyer input, return and account session regressions

Buyer forms accepted mixed numeric input and inconsistent Unicode lengths. Refreshed return forms retained obsolete selections, and private collection/account/evidence screens could reuse work from an old session. The changes validate against existing server contracts, bind private work to the opening buyer, and preserve exact retry intent when a result is uncertain. Return and account review entrypoints provide synthetic native feedback with outbound requests blocked. Preview dialogs remain within the selected phone.

Only buyer mobile changes. No backend source, configuration, database, deployment or Git changes are included. The branch locally includes the previously published buyer misuse batch so its regressions remain fixed during this continuation; inspect the current PR base before publication.

Validation at this checkpoint:

- 546 isolated unit/widget cases; clean analysis and formatting of 49 changed/new Dart files.
- Native Linux account (52), return/evidence (39), and earlier buyer/collection (26) groups pass on a separate display. Groups overlap.
- Actual keyboard, clipboard and native picker checks showed invalid-field feedback, one request after repeated submits, private-state clearing, pending identity review and server cooldown feedback.
- Linux review and normal Android debug builds pass.

The broad feature audit remains in progress. Deeper repayment/PDF, address/GPS, purchase/review, discovery, messaging, recovery and notification/tracking exploration is still being completed. Physical device, provider and iOS acceptance are separate. This title/body is a local draft; no GitHub PR or publication is claimed.
