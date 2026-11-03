# Presentation priority checkpoint

The user narrowed the work to presentation-impacting fixes on the same branch and requested a final result without further exhaustive expansion. The broader 100% coverage/database/browser sweep is paused, not complete.

Branch: `test/buyer-exhaustive-sweep`, based on merged `main` at `c2c2342`. No feature or backend work is required by this checkpoint.

## Confirmed fixes

- Invalid linked search no longer closes its source screen before rejecting input.
- Malformed session/XSRF cookies now produce a recoverable session error, clear poisoned state, and never replay an unsent mutation.
- Foreground reads recover after a synchronous callback failure.
- Countdown labels preserve fractional deadline precision.
- Explicit retry durations preserve positive submillisecond deadlines.
- Restarting a cooldown from its callback leaves one timer, with no orphan after disposal.

## Final verification

- **557 presentation-focused Flutter tests passed in 1 minute 41 seconds.** Includes sign-in, registration input, Home-to-product-to-reviewed-checkout, product options/pricing, Bag, checkout confirmation/logistics, navigation, HTTP session/mutations and retry lifecycle. The exact 22-file manifest is `../testing/presentation-test-files.txt`.
- Full Flutter analysis: **no issues found**.
- Formatting: **242 Dart files unchanged**. Diff whitespace check passed.
- Existing Linux owner configuration validates for debug.
- A direct anonymous app-like GET to the configured `/auth/session` returned **HTTP 200** and a JSON object. This establishes reachability, not successful buyer authentication or a live placed order. An initial proxy-mediated probe returned 403; the direct client path matches the app's transport behavior.
- Configured normal Linux debug build: **passed**. The executable is `build/linux/x64/debug/bundle/bagoo_buyer_mobile`; keep the bundle together. The compiled snapshot does not contain the isolated browser fixture marker. No app window was opened by the build.

Reproduce the final tests:

```sh
xargs -a docs/testing/presentation-test-files.txt flutter test --no-pub --concurrency=1
flutter analyze --no-pub
flutter build linux --debug --no-pub --dart-define-from-file=config/buyer.local.json
```

For the presentation, keep the configured backend available and use an approved buyer account for checkout. The code checks need no phone or credentials from the user. Real sign-in/order/provider acceptance was not performed by this isolated test run.

## Deferred work

Unverified Home/Profile tests, the broader VM collector and native browser harness are preserved locally under `.git/buyer-testing/deferred-presentation/`, with a restore manifest. They are outside the presentation branch's test set. Existing browser evidence: the actual native invalid/valid login journey passed; the later guest first-frame harness failed and checkout was skipped. No complete browser E2E or 100% coverage claim is made.

The original baseline remains 4,307/5,942 reported Dart branch counters (72.484%); it predates these fixes. Actual database acceptance remains unexecuted under the existing backend read-only scope. Detailed future work remains in the sweep ledger, API matrix and isolated backend acceptance plan.

## Local commits

| Commit | Subject |
| --- | --- |
| `c22b4c7` | test: inventory buyer workspace branch coverage gaps |
| `38b4461` | fix(core): preserve retry precision and recover foreground reads |
| `7b2fd2f` | fix(session): reject malformed XSRF cookies without replaying writes |
| `8cc587d` | test: extend buyer HTTP flow contracts and database acceptance inventory |
| `0b88380` | fix(navigation): preserve source screens when linked search is invalid |
| `acd6ed6` | docs: record coverage backlog and verified sweep checkpoints |

The final presentation handoff commit is reported separately after its creation. No commits from this branch have been pushed.
