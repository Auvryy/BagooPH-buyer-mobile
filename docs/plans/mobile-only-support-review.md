# Mobile-only support and notification review

## Scope

Review the native buyer work, improve the supported mobile flows, and keep every sibling product read-only. The user requested the earlier backend changes be reversed. That local rollback restored `/bagoo` to its original `main` tree at the time of the rollback. Its previously published branch was left unchanged because the user explicitly prohibited pushing the backend rollback.

The mobile review starts on `fix/buyer-mobile-only-review` from freshly pulled `main` at `493d09b`. The earlier mobile feature changes were brought into this working tree without creating commits. The initial instruction was to leave these changes uncommitted. The user subsequently authorized committing and pushing this mobile branch; that authorization does not include any sibling repository.

## Acceptance criteria

- Add an explicit sibling-product read-only rule to the mobile `AGENTS.md`.
- Use only routes verified in the existing website/backend source. Remove active Google and FCM integrations that depend on the reversed backend additions; document their required contracts for the website maintainer.
- Keep Bagoo Support and Customer Care native, with retained input after failure, clear retry and validation states, safe asynchronous handling, and layouts that fit small phones, landscape, and enlarged text.
- Keep the existing native Notifications center useful without push configuration or unsupported backend routes.
- Verify changed mobile behavior with isolated tests, formatting, static analysis, and relevant native builds. Do not mutate backend data, run backend tooling, or use a visible browser.
- Record proposed website/backend additions only in mobile documentation, clearly labeled as recommendations and absent contracts.

## Work slices

1. Restore the previous backend tree and dependency state; preserve unrelated files and publish nothing.
2. Record the mobile-only boundary and remove unsupported provider integrations and their platform/dependency changes.
3. Improve native support and in-app notification behavior using verified contracts.
4. Add focused regression coverage, run mobile checks, and document website requirements and review evidence.

## Status

Implementation and verification are complete on `fix/buyer-mobile-only-review`. The support and notification changes are included in the authorized mobile publication handoff described in the public tracking plan. Backend publication remains unauthorized.

## Review findings and changes

- The previous Google and FCM clients called routes absent from the original backend. Removed those clients, active controls, provider dependencies, and platform configuration. Android/iOS configuration, dependency manifests, authentication, and app bootstrap now match this branch's `main` base. Future contracts are described in `docs/integrations/buyer-mobile-contract-requests.md`.
- The support screen could lose a failed suggested question and overflow with large text or the keyboard. Suggestions now fill an editable draft, errors preserve the message and order number for explicit retry, and compact layouts scroll the composer. Input limits and server field errors match the existing support controller. Account/access changes clear private screen state, and late replies are ignored.
- Customer Care opens the existing native chat with its supported photo picker. The profile entry waits for server-owned eligibility and prevents duplicate navigation.
- Notification read completions could start requests after disposal or update another buyer's badge. Requests and navigation now check the current owner and screen generation. App resume refreshes the selected filter/page without acknowledging notices automatically.
- The mobile `AGENTS.md` explicitly makes every sibling product read-only and requires missing website contracts to be documented here.

## Verification evidence

- Full `flutter test --no-pub --reporter expanded`: all 99 tests passed. This includes 22 support and notification regressions covering contract validation, retained retries, duplicate sends, access/session changes, stale responses, disposal, explicit snapshot acknowledgements, and app resume.
- Layout checks passed for 320/375-pixel phones, landscape, and tablet windows, including 200% text, keyboard insets, reduced motion, and preserved input when resizing.
- `flutter analyze --no-pub`: no issues.
- Formatting checks for all changed Dart files and `git diff --check`: passed.
- `flutter build linux --debug --no-pub`: passed.
- `flutter build apk --debug --no-pub`: passed.
- Android/iOS provider configuration, `pubspec.yaml`, `pubspec.lock`, app bootstrap, and authentication source were compared to mobile `main` and have no diff.

Tests use isolated fixtures and local test servers. No live support message, chat, email, order, payment, or profile mutation was sent. iOS compilation requires macOS/Xcode and was unavailable; physical-device interaction and screen-reader behavior remain unverified. The app retains its existing light theme.

## Backend rollback evidence

Local commit `8b311d7` (`revert: remove native buyer backend integration`) exactly reverses `e679d8b`. Its staged tree was compared to the earlier commit's parent and matched exactly. The installed Google dependency additions were removed using the restored lockfile with scripts disabled.

Immediately after the rollback, the backend checkout was on original `main` at `ac9a893`, with no tracked working or staged diff. The pre-existing untracked audit retained the same SHA-256. No migrations were run. The user explicitly prohibited pushing that rollback, so it remained local. These are historical rollback results, not a claim about subsequent website work. The older published feature branches must not be used as the reviewed mobile result.
