# Native public parcel tracking

## Scope

Continue on `fix/buyer-mobile-only-review`, preserving all existing support and notification work. The initial instruction was to keep changes uncommitted. The user subsequently authorized committing and pushing this mobile branch. Every sibling product, including the Bagoo website/backend, remains read-only.

The website already serves a privacy-filtered public tracking page. The mobile app currently exposes owned-order tracking but has no guest tracking-number lookup. Add that missing native journey using the existing contract.

## Acceptance criteria

- Expand `docs/integrations/buyer-mobile-contract-requests.md` into a maintainer handoff with proposed native Google/push/capability contracts, failure cases, and web compatibility gates. Clearly identify these as future requests, not deployed APIs.
- Use only `GET /track?number=...` through the existing page adapter. Verify `Public/Tracking`, searched number, parcel identity, labels, and result shape before accepting a response.
- Accept the website's tracking-number format: 1–64 ASCII letters/numbers, hyphens, and underscores, starting with a letter/number. Normalize case and outer whitespace. Reject invalid input before any request.
- Provide native guest/buyer entry points, initial guidance, validation, loading, not-found, failure/retry, refresh, and copy-number states.
- Display only the documented public parcel fields and recorded milestones, using server labels and Philippine times. Display delivery/completion exactly as the server labels them without inferring the actor or changing the order. Provide no mutation or receipt-confirmation control.
- Ignore superseded/disposed requests. Editing a number must invalidate an old lookup; refresh failures may retain an explicitly labeled previous confirmed result.
- Render existing internal `/track` links natively and keep same-origin routing enforcement.
- Verify transport, parsing/privacy boundaries, stale-response handling, entry-point navigation, clipboard feedback, and phone/landscape/tablet/large-text/keyboard behavior using isolated checks. Run analysis and relevant native builds.

## Work slices

1. Website maintainer document and typed public tracking repository/controller.
2. Responsive tracker, Home/Profile entries, and existing destination-router integration.
3. Contract/controller/widget regression tests, mobile checks, and final documentation evidence.

## Status

Implemented on the same branch and prepared for the user-authorized mobile publication. No website edits are required for public tracking. Verification results are recorded below.

## Delivered behavior

- Expanded the website contract handoff with proposed route/request/response tables, sample acknowledgements, identity/device ownership rules, failure isolation, and rollout/compatibility gates. These remain future proposals in mobile documentation.
- Added typed public tracking data and validation using the existing `Public/Tracking` page response. The adapter checks the searched and returned number, filters to documented public fields, and uses the server's status/checkpoint labels. Known and new labels are rendered without client business-state inference.
- Added a native tracker reachable from Home for guests and buyers, Profile, and existing internal `/track` path/query links. It supports validation, not-found guidance, editable input, confirmed loading, copy feedback, refresh, and explicit retry.
- Editing a number cancels acceptance of older responses. Refresh errors retain the last confirmed snapshot with a visible stale-result explanation and its original server checked time. Disposal and newer searches reject late responses.
- Displayed public recipient masking, delivery area, recorded ETA/delivery time, and newest-first milestones in Philippine time. No order or receipt action is exposed.

## Verification

- Full Flutter suite: all 129 tests passed, preserving the existing support, notification, authentication, and shopping coverage. The 30 new tracking checks include real local HTML/Inertia transport, input boundaries, malformed/mismatched data, unknown/new labels, privacy-field exclusion, stale queries, retry/refresh, clipboard, native links, Home/Profile entry, and guest access.
- Layout checks passed for phones, landscape, tablet, 200% text, keyboard insets, a 64-character number, and resizing with retained input/results. Reduced-motion mode uses the existing app behavior.
- `flutter analyze --no-pub`: no issues. Changed-file formatting and diff whitespace checks passed.
- `flutter build linux --debug --no-pub` and `flutter build apk --debug --no-pub`: both passed for the final source.
- The public controller/service/route were inspected read-only and rechecked after an additive checkpoint appeared in the website working tree. The public response shape remains compatible; no website file or Git state was changed by this task.

All tests use fixtures or isolated local HTTP servers. No real tracking number, live backend session, message, order, payment, or database mutation was used. iOS builds require macOS/Xcode and were unavailable; physical-device and screen-reader behavior remain unverified. The existing light theme is retained. No dependencies or native provider configuration were added.

The support/notification review remains on this branch. A combined PR description stays in the mobile `.git` directory as a local draft. Publishing the branch does not create a GitHub pull request automatically.

## Completion recheck

Rechecked the current files, Home/Profile/router entry points, website handoff, and existing public controller/service contract. All 30 tracking tests passed again; analysis, formatting, and diff checks passed. The tracking source remains the version covered by the earlier 129-test run and Android/Linux build artifacts. No additional implementation changes were needed.

## Publication handoff

The user authorized pushing the completed mobile work on `fix/buyer-mobile-only-review`. Publication is split into four logical commits:

1. Native Help & Support, its Profile entry, and isolated regression coverage.
2. Notification lifecycle/account guards and their regression coverage.
3. Public parcel tracking, native navigation, and its regression coverage.
4. Mobile repository boundaries, website contract recommendations, and combined documentation.

The publication recheck passed all 129 isolated Flutter tests, static analysis, changed-file formatting, and diff whitespace checks. The earlier successful Android/Linux builds cover the unchanged application source. Push only this mobile branch; leave all sibling repositories and the backend rollback untouched. Report the resulting commit IDs and GitHub comparison link in the handoff; the PR description remains a local draft until saved on GitHub.
