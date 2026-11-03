# Buyer core adversarial sweep

Evidence recorded on November 3, 2026, on `test/buyer-exhaustive-sweep`.

This slice adds 54 isolated tests across four new files. It uses synthetic inputs,
fake timer advancement, and a substituted native file selector. It does not open
a phone, desktop window, browser, real file picker, or live backend connection.

## Cases

| Test file | Tests | Observable behavior checked |
| --- | ---: | --- |
| [core_adversarial_sweep_test.dart](../../test/core_adversarial_sweep_test.dart) | 20 | Complete rejection of malformed form metadata and resource rows; preserved choice values and order; pagination bounds, clamped pages, empty results and exact ranges; invalid calendar dates and timezone limits; nested multipart values, binary bytes and empty payloads; UUID version and variant; optional application text |
| [core_retry_cooldown_sweep_test.dart](../../test/core_retry_cooldown_sweep_test.dart) | 11 | Fractional and maximum server durations; positive submillisecond remainders and `Duration` precision; active restrictions with a nonzero label; countdown cap transitions, expiry, daily wakeups, duration bounds, cancellation, disposal and callback restarts |
| [core_foreground_refresh_sweep_test.dart](../../test/core_foreground_refresh_sweep_test.dart) | 4 | Hidden/disposed reads stay inactive; synchronous and asynchronous failures retry after backoff; replacing a controller invalidates pending old reads and honors disabled state |
| [core_file_selection_sweep_test.dart](../../test/core_file_selection_sweep_test.dart) | 19 | Avatar/evidence permission filters; GIF87a and uppercase extensions; 16 truncated or corrupt JPEG/PNG/PDF/GIF/WebP signatures; recoverable stream errors without private paths |

## Reproduced defects and fixes

### Active cooldown displayed zero seconds

`verificationCooldownSecondsUntil` truncated the remaining duration to whole
milliseconds before rounding to seconds. A deadline one microsecond in the future
returned zero. `RetryCooldown.active` still returned true, so authentication and
other actions could remain disabled while their label displayed `0s`.

The first regression run reproduced two failures with `Expected: 1, Actual: 0`:

- `a future submillisecond deadline still has one second remaining`
- `active retry restriction never displays zero before its deadline`

[verification_cooldown.dart](../../lib/core/verification_cooldown.dart) now computes
the integer ceiling from microseconds. Tests also cover one second plus one
microsecond, exact expiry, elapsed deadlines and the existing one-hour display cap.
Both failing cases passed in the corrected reproduction run.

### Synchronous read failure prevented subsequent refreshes

`ForegroundRead.refresh` assigned `_running` from `_perform`. When its callback
threw synchronously, `_perform` finished its cleanup before `refresh` assigned the
completed future to `_running`. The next scheduled retry saw that completed
future as an ongoing read and never invoked the callback again.

After correcting the test timer setup, `synchronous read failures retry after
backoff` reproduced `Expected: 2, Actual: 1` after the four-second backoff. The
asynchronous-failure control passed. Current product callbacks are asynchronous;
this failure concerns an allowed callback shape in the shared controller.

[foreground_refresh.dart](../../lib/core/foreground_refresh.dart) now awaits
`Future<ReadOutcome>.sync(() => read(ticket))`, ensuring synchronous errors are
delivered after `_running` has been assigned. Existing error handling and backoff
remain in effect.

### Explicit retry durations discarded microseconds

Two further public-API boundary cases reproduced precision loss in
`RetryCooldown.startFor`. A one-microsecond `Duration` produced an inactive
cooldown (`Expected: true, Actual: false`). A one-second-plus-one-microsecond
duration displayed one second rather than two (`Expected: 2, Actual: 1`). The
method converted durations to whole milliseconds before setting the deadline.
These cases concern the shared `Duration` API; the current verification screen
supplies whole seconds.

`startFor` now preserves microseconds while retaining the existing nonnegative
and ten-year bounds. Both boundary regressions passed after this correction.

### Callback restart left a timer after disposal

A countdown callback can use the public `startFor` method to begin another
cooldown. During this reentrant call, the restart scheduled a new timer; after
the callback returned, the old timer handler scheduled another timer and lost
the first handle. `dispose` could then cancel only one of the two timers.

The regression restarts a two-day cooldown from the notification callback, then
disposes the instance inside the test body's `finally` block. Flutter reports a
pending 24-hour timer after disposal. Unlike the initial fixture cleanup error,
this case disposes before the widget invariant check and still leaks a timer.

`_schedule` now cancels any current timer before creating its replacement. The
callback-restart disposal regression passed after this correction.

## Verification ledger

| Phase | Result | Local evidence |
| --- | --- | --- |
| Original tracked tests, before production changes | 1,515 passed in 11:48 | `/tmp/bagoo-exhaustive-baseline.log` |
| First added core cases | 45 passed, 6 failed: two cooldown defects and four test fixture errors | `/tmp/bagoo-exhaustive-first-regressions.log` |
| Corrected core fixtures and cooldown precision fix | 50 core cases passed, one synchronous-read regression failed; the accompanying 26 coverage-reporter tests passed, for 76 passed and one failed overall | `/tmp/bagoo-exhaustive-core-repro.log` |
| Both core production fixes and affected transport/session regressions | All 205 combined tests passed, including the 51 new core cases and existing foreground, retry, verification, session and native transport checks | `/tmp/bagoo-exhaustive-fixed-focused.log` |
| Additional duration and callback-restart regressions | 8 retry cases passed, 3 failed: both explicit-duration boundaries and callback timer disposal | `/tmp/bagoo-retry-reentrancy-repro.log` |
| Retry duration and reentrant timer fixes | All 11 retry cases passed, including the 3 additional regressions and existing cap, expiry and cancellation cases | `/tmp/bagoo-retry-reentrancy-fixed.log` |
| Targeted Dart formatting | Passed for the three changed source files and four new test files | `dart format` |

The initial fixture errors were three zero-duration timer pumps that did not
advance the fake clock and one active timer disposed after the widget invariant
check. These were corrected in the tests before attributing the foreground
failure to production code.

Run this slice together with existing timer regressions:

```sh
flutter test --no-pub --concurrency=1 \
  test/core_adversarial_sweep_test.dart \
  test/core_retry_cooldown_sweep_test.dart \
  test/core_foreground_refresh_sweep_test.dart \
  test/core_file_selection_sweep_test.dart \
  test/verification_cooldown_test.dart \
  test/retry_cooldown_test.dart \
  test/foreground_refresh_test.dart
```

## Coverage limits

The installed Dart `coverage` package, version 1.15.1, stores branch hits by source
line and emits `BRDA:<line>,0,0,<hits>`. This measures emitted branch counters; it
does not independently measure every true/false alternative or condition in a
compound expression. Passing these cases does not establish 100% decision
coverage for these files or for the workspace.

Tests exercise public outcomes without private-method access or production-only
test hooks. Defensive stale-timer checks and branches guarded by strict upstream
validation still require separate reachability review. The workspace coverage
inventory remains the authority for measured and unmeasured source files.
