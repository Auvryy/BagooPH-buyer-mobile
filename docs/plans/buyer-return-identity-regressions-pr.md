Title: Fix buyer input, return and account session regressions

Buyer forms accepted mixed numeric input and inconsistent Unicode lengths. Refreshed return forms retained obsolete selections, and private collection/account/address/evidence screens could reuse work from an old session. Same-titled PDF routes could display the wrong evidence, and an interrupted address creation could be repeated. The changes validate existing server contracts, bind private work to the opening buyer, isolate PDF reads and preserve confirmed retry intent. Uncertain address creation requires reviewing saved addresses before another attempt. Native review entrypoints use synthetic data with outbound requests blocked, and preview dialogs remain within the selected phone.

Only buyer mobile changes. No backend source, configuration, database, deployment or Git changes are included. The branch locally includes the previously published buyer misuse batch so its regressions remain fixed during this continuation; inspect the current PR base before publication.

Validation at this checkpoint:

- 586 isolated unit/widget cases; clean analysis and formatting of 55 changed/new Dart files.
- Native Linux account/address (78), return/evidence (53), real PDF (4), and earlier buyer/collection (26) groups pass on a separate display. Groups overlap.
- Actual keyboard, clipboard and native picker checks showed invalid-field feedback, one request after repeated submits, private-state clearing, pending identity review and server cooldown feedback.
- Linux review and normal Android debug builds pass.

The broad feature audit remains in progress. Native form-error visibility, location-label rendering, checkout/GPS, purchase/review, discovery, messaging, recovery and notification/tracking exploration is still being completed. Physical device, provider and iOS acceptance are separate. This title/body is a local draft; no GitHub PR or publication is claimed.
