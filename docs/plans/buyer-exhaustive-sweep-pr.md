# PR title

Fix buyer retry, session and linked-navigation failures for presentation flows

# PR description

Invalid search links retain the source screen. Malformed XSRF cookies produce a recoverable session error without replaying writes. Foreground reads recover from synchronous errors, retry deadlines retain fractional precision, and reentrant countdown changes no longer leave orphan timers.

Regression suites exercise buyer sign-in, product/Bag/reviewed checkout, navigation, API adapter contracts and adversarial metadata/session boundaries. The final presentation-focused run passed 557 tests; full Flutter analysis, formatting and diff checks passed. The configured normal Linux build and read-only backend reachability are recorded in `buyer-presentation-priority.md`.

The broader 100% workspace coverage, actual database acceptance and complete native browser suite remain deferred. Unverified experiments were preserved locally and are excluded from this handoff. No backend source or shared database was changed. This is a local PR title/body draft; no GitHub PR has been created.
