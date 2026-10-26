# BagooPH Buyer Mobile Repository Instructions

Keep work direct, scoped, and concise. Inspect existing code before changing it; do not invent API endpoints, models, fields, or behavior.

## Safety and Git

- Work only inside this repository unless the user authorizes work elsewhere. The related backend/web repository is `../bagoo`; inspect it as needed to verify shared contracts, but do not change it without authorization.
- Never implement changes or create commits on `main`. If starting on `main`, or the previous working branch has already been pushed, first switch to `main` and run `git pull origin main` to get the latest GitHub changes. Then create a new descriptive working branch before editing. Preserve local changes and stop dependent work if the pull fails or conflicts; never reset or discard work to force synchronization.
- Continue related work on its unpushed working branch. Keep commits local until the user explicitly says to push. Local `git add` and `git commit` are allowed; `git push` requires the user's explicit instruction. After publishing a branch, start the next task from freshly pulled `main` on a new branch.
- For coding tasks, split work into small logical commits by feature or concern instead of one large commit. Keep each commit coherent; avoid mixing unrelated UI, API, configuration, and cleanup work. A small documentation-only task may use one commit.
- Give every commit a clear subject and a concise description in the message body. Explain the concrete problem, what changes for the user, and why the change matters in plain language. Include relevant verification and remaining limitations; never invent checks or rely on filenames alone to explain the work.
- Prepare a readable pull request title and description for the final branch handoff, covering the combined outcome and validation. Individual commit descriptions explain their own logical changes; the branch description must reflect the final scope.
- Commit bodies do not automatically populate GitHub's pull request description. Prepare a separate PR title and body, and report whether they were saved on GitHub or remain a local draft. Use an authorized connected integration when available; publish commits only after the user's explicit push instruction.
- Report every commit created, including its short hash and subject.
- Preserve unrelated user changes. Never discard or overwrite work to make checks pass.
- Never commit credentials, tokens, private keys, real infrastructure addresses, or secrets. Use placeholders such as `<API_BASE_URL>` in examples and configuration templates.

## Planning and Task Management

- For work spanning multiple features or concerns, write a short plan with acceptance criteria and a logical commit breakdown before implementation. Update it when scope changes and finish each coherent slice before moving on.
- Keep durable plans in `docs/plans/` when the task warrants repository documentation. Do not add planning ceremony for a small, direct change.
- If `docs/Task Management.md` exists, read it before repository work and follow its local workflow. It is machine-local guidance: never force-add it or copy private contents into tracked documentation. If absent, continue without inventing tracker configuration, history, or time records.

## Stack and Architecture

- This is a Flutter application written in Dart, targeting Android and iOS, with a Linux desktop runner for local preview. Use `pubspec.yaml` and `pubspec.lock` as the authority for SDK constraints and dependencies; inspect platform build files for native requirements.
- Reuse existing widgets, themes, patterns, and dependencies. Do not add a state-management framework, networking library, or external or paid service without a concrete requirement and an explanation of the choice.
- Keep widgets focused on presentation and interaction. Keep networking, persistence, and domain logic outside widget build methods; follow the repository's established structure as it develops.
- Verify backend routes, authentication, request/response fields, pagination, and error formats against actual contracts before implementing integrations. If a contract is missing, identify the gap rather than inventing a working endpoint.
- The server owns authorization, prices, totals, stock, account approval, and order status transitions. Client validation improves usability but does not replace server validation.
- Handle loading, empty, error, retry, and success states for affected asynchronous flows. Prevent duplicate submissions and avoid updating disposed widgets.
- Keep secrets out of app source, logs, and assets. Build-time configuration and bundled assets are not secret storage. Use appropriate secure storage when persistent authentication is introduced.
- Do not modify generated Flutter files or build outputs as a substitute for changing their source configuration.

## Buyer Domain Rules

- Preserve the original BagooPH/Bagoo identity and Philippine pesos (`PHP` / `₱`). Customer-facing copy uses “Bag,” “Shopping Bag,” and “Add to Bag.” Follow existing API/model names such as `Cart` when required by the contract.
- An account's role is fixed when created. Do not add role conversion or mutate an account's role.
- Buyers may browse, use their own profile/history, and view their Bag before approval; active or pending buyers may change Bag items. Checkout requires an active approved account. New buyer registrations require a real birth date proving age 18 or older. Confirm enforcement against the backend before wiring these flows.
- Preserve the original registration/sign-in email. Recovery/contact changes and reviewed identity corrections must follow the backend's documented verification and review processes.
- Canonical order flow: `PLACED -> CONFIRMED -> PREPARING -> READY_FOR_PICKUP -> PICKED_UP -> AT_SORTING_CENTER -> SORTED -> ASSIGNED_TO_RIDER -> OUT_FOR_DELIVERY -> DELIVERED -> COMPLETED`.
- Failure branch: `DELIVERY_FAILED -> RETURNED` or documented rescheduling. Only the buyer's receipt confirmation advances `DELIVERED` to `COMPLETED`; do not advance it automatically in the app.
- Display server-authoritative order, payment, shipping, and refund information. Do not infer successful payment or completed delivery from a local navigation event.

## Product Language and UI

- Primary accent: `#E00D42`. Use Plus Jakarta Sans as the shared product typeface when implementing the app theme; declare required font assets or dependencies explicitly.
- No emojis in code, UI copy, comments, commit messages, or repository documentation.
- Follow buyer-specific designs and existing app components. Do not copy rider-only navigation, radius, or layout rules into the buyer experience without a buyer requirement.
- Keep layouts responsive across phone sizes and larger supported screens. Respect safe areas, the keyboard, text scaling, and accessible touch targets. Use clear labels, focus states, and readable contrast.
- Keep navigation predictable and preserve useful form and shopping state. Show clear saved-result feedback and actionable validation messages.
- Avoid ornamental clutter, unnecessary gradients, and continuous GPU-heavy effects. Respect reduced-motion settings for animations.

## Documentation and Shared Contracts

- Read this repository's `README.md`, relevant source, and relevant plans first. Document setup, configuration, and behavior when changes affect them.
- When shared product behavior needs clarification, consult only relevant documents in `../bagoo`, such as `docs/BUYER_FLOWCHART.md`, `docs/SYSTEM_FLOW_AND_SPECIFICATIONS.md`, `docs/FORM_VALIDATION_REVIEW.md`, and `docs/STYLE_GUIDE.md`, then inspect the actual backend implementation.
- Do not copy private task-management guidance or assume backend documentation files exist locally in this repository.
- Identify conflicts between documentation and executable code. Do not silently invent a new business rule to resolve them; use the shared canonical flow unless the user explicitly changes it.
- Keep changing implementation status in plans or roadmap documentation, rather than presenting unfinished features as established architecture.

## Verification and Responses

- Use focused checks appropriate to the change: Dart formatting for edited Dart files, `flutter analyze`, and relevant Flutter tests for changed behavior. Build the Android target when platform or packaging changes warrant it. iOS builds require macOS and Xcode; report that limitation when applicable.
- Follow the user's verification scope. Documentation-only changes need content and diff review, not an app build. Never claim a check ran when it did not.
- Keep tests isolated from live services and production data. Never wipe a shared backend database during app verification.
- Never open a visible browser, use browser automation, or take screenshots for routine checks. Use browser UI testing only when the user explicitly requests it for that task.
- Do not claim success when checks are blocked or failing; state the exact blocker and what remains unverified.
- After coding, briefly describe the user-visible improvement, supporting verification, and remaining gaps. If giving a before/after rating, scope it to the changed feature and base it on evidence.
- Keep final responses short: outcome, verification, commits created, and any blocker.
