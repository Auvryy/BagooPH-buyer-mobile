# Buyer workspace testing sweep

## Scope and acceptance

User request: exhaustively test the buyer mobile workspace with subagents, target 100% branch coverage, add adversarial/null/invalid/boundary cases, exercise API/database integrations and critical journeys through an automated Playwright or Cypress suite, fix reproduced bugs, and keep a durable build backlog.

The writable product is this mobile repository. The website/backend and rider repositories remain read-only. No task-service calls are needed. GUI checks must run off the user's active desktop, without focus changes. Run one resource-heavy build or test process at a time.

- [ ] Inventory all source domains, API flows, existing tests, and platform constraints.
- [x] Run and record a full branch-coverage baseline; preserve the complete uncovered-branch inventory in a reproducible report.
- [ ] Add meaningful branch and adversarial tests across uncovered domains, fixing reproduced production bugs.
- [ ] Reach 100% branch coverage across the declared workspace source inventory, or explicitly keep this criterion open with every remaining branch reported.
- [ ] Map every mobile API flow to integration evidence, including failures, authorization/session changes, and malformed responses.
- [ ] Identify actual database integration ownership and prerequisites; do not represent a mocked reply as database verification.
- [ ] Add and run automated Playwright/Cypress critical-journey checks against a supported app target, documenting any platform gap.
- [ ] Run native Linux journeys on a virtual display if supported, without affecting the user's desktop.
- [ ] Finish appropriate formatting, analysis, tests and final coverage checks; keep a build/fix backlog with evidence and commands.
- [ ] Package coherent local commits and a separate PR draft. Publication needs a later push instruction.

## Commit slices

1. Coverage/inventory tooling and this evidence ledger.
2. Core validation and parsing regressions with demonstrated fixes.
3. HTTP/API integration coverage and contract matrix.
4. Critical-journey automation and native Linux execution.
5. Remaining domain coverage slices, final findings, and handoff.

## Current evidence

- Base: freshly pulled `main` at `c2c2342`; previous presentation-review branch is merged.
- Working branch: `test/buyer-exhaustive-sweep`.
- Fresh baseline: 1,515 isolated Flutter tests passed across 103 original tracked test entrypoints in 11 minutes 48 seconds. Flutter reported 4,307/5,942 branch counters hit (72.484%); 1,635 counters remain uncovered before new regressions/fixes.
- Existing native suites: buyer, account, Bag, checkout, voucher, returns, and private-document misuse entrypoints.
- Initial platform inspection: production code imports `dart:io`; there was no web target or Playwright configuration. A native-browser harness is now authored and awaits current-source execution.
- Virtual display inspection: `Xvfb`/`xvfb-run` are not on PATH. No visible app has been opened.

## Evidence ledger and build backlog

This section will be updated as each test slice finishes. Passing isolated tests do not close native-provider, deployed API, or database acceptance requirements.

| Area | Evidence | Remaining work |
| --- | --- | --- |
| Branch coverage | Fresh baseline 4,307/5,942 (72.484%); reproducible complete inventory via `tool/testing/coverage_report.dart` | 1,635 uncovered counters, unmeasured tooling/native source, and source-line counter precision still keep 100% open |
| Core inputs/models | 51 new core cases pass within the 205-test combined post-fix run; detailed evidence in `../testing/buyer-core-sweep.md` | Continue uncovered helper branches and callback reentrancy |
| API contracts | 95 new local HTTP cases pass within the 205-test combined post-fix run; route inventory in `../testing/buyer-api-flow-matrix.md` | Close remaining per-route HTTP gaps and keep actual DB prerequisites explicit |
| Database behavior | Mobile has no database owner identified yet | Verify ownership and isolate any required backend acceptance |
| Critical journeys | Existing Flutter integration suites | Add requested browser automation against a valid supported target |
| Native Linux | Archived isolated QA snapshot rendered through loopback GTK Broadway + software rendering in headless Chromium | Build current-source fixture and run repeatable native/browser journeys |

## Findings and build queue

| ID | Status | Trigger / evidence | Expected next work |
| --- | --- | --- | --- |
| B01 | Fixed; combined 205-test run passed | Two new tests observed zero seconds while the deadline was still future | Uses integer microsecond ceiling; precision regressions now pass |
| B02 | Fixed; combined 205-test run passed | Corrected timer fixture showed synchronous failure stuck at one call while asynchronous control retried | Await a normalized Future before cleanup; old and new foreground suites pass |
| B03 | Fixed; combined 205-test run passed | Five HTTP tests saw raw ArgumentError/FormatException for malformed/unsafe XSRF cookie encoding | Abort without replay, clear invalid session, and expose recoverable BackendException419 |
| B04 | In progress | Flutter reports branch hit/miss counters by source line; default report omits `tool/` and uninstrumented sources | Keep exact counter inventory and missing source list; do not equate the percentage to every boolean alternative |
| B05 | In progress | Native app imports `dart:io` and has no web target | Drive the real native canvas through Broadway using Playwright; no replacement mock website |
| B06 | Open prerequisite | The mobile workspace owns HTTP adapters, while SQL/transactions belong to the read-only backend | Keep actual database acceptance distinct from synthetic loopback HTTP tests |
| B07 | Adversarial reproduction pending | A retry countdown's notification callback restarts its own timer | Verify there is only one active timer and disposal leaves no orphan |

The initial baseline uses an explicit manifest of the original tracked test files. Agents may author new tests during that run, but production and existing test sources stay unchanged until the baseline terminates. This keeps baseline evidence tied to the pulled base rather than a moving collection of new cases.

## Reproduction record

The first new suite run finished with 159 passes and 11 failures. Seven failure cases established two production defects (two timer precision cases and five XSRF cookie cases). Four failures were new-test setup errors: zero-duration timers were not advanced, or active timers were disposed after the widget invariant check. Those fixtures were corrected. The next run finished with 76 passes and one failure, confirming the third production defect: synchronous foreground reads did not retry. No passing full-suite claim applies to the changed source until the post-fix full run finishes.

After the three fixes, the combined new core/API/coverage-reporter cases and existing foreground, retry, verification, web-session and native-auth transport suites passed **205 tests**. The new browser-runner safety/provenance unit suite also passed **20 Python tests** without opening an app or browser. A post-fix full Flutter coverage run and actual current-source browser/native journeys remain open.

## Coverage commands and interpretation

```sh
flutter test --no-pub --branch-coverage --coverage-path=coverage/lcov.info --concurrency=1
dart run tool/testing/coverage_report.dart coverage/lcov.info
dart run tool/testing/coverage_report.dart coverage/lcov.info --require-complete
```

The reporter writes ignored `coverage/workspace-branches.json` and `.md` files, including every reported missing branch key and every unmeasured Dart source under `lib/`, `tool/`, and `e2e/`. The strict command exits nonzero while completeness is unproven; files are not removed from scope to improve the percentage. Default Flutter coverage filters package `lib/` source, leaving tooling imports unreported. The abstract `SessionVault` interface also has no runtime counters; it needs declaration-only classification rather than invented executable coverage. Native Android/iOS/Linux host coverage is separate and unmeasured by Dart LCOV.

In installed `coverage` 1.15.1, branch hits/misses are merged by source line before BRDA formatting. The reported counters therefore do not prove both outcomes of every boolean expression, and a 100% emitted-counter rate alone would not establish exhaustive behavior. Adversarial outcome assertions and source inventory remain required.
