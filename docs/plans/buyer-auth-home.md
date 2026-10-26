# Buyer auth and home

## Scope and acceptance

- Start from `main` after `git pull origin main`; implement on `feat/buyer-auth-home`. Keep all commits local until the user requests a push.
- Preserve that branch workflow in `AGENTS.md`.
- Match the buyer web identity: Bagoo logo, crimson `#E00D42`, bundled Plus Jakarta Sans, white forms, split auth imagery on wide layouts, and the slate marketplace canvas.
- Provide native login, two-step buyer registration, registration email verification, password recovery, and navigation to home. Show server field errors, loading, retry, and confirmed outcomes; do not bypass authentication.
- Connect to existing web-session routes without backend changes. Inspect Laravel and Inertia contracts directly; configure the backend origin at build time. Keep session cookies in memory for this first pass, with no persistent credentials.
- Load real campaigns, categories, and products on home. Support guest browsing, search, sorting, category selection, pagination, refresh, empty states, and retry. Product inspection can show the real catalogue summary; checkout and broader buyer portal features are outside this auth/home scope.
- Respect server-owned account access and approval. Do not display fabricated products, ratings, orders, or successful mutations.
- Support narrow phones, landscape, tablets, large text, safe areas, and keyboards.

## Source references

Read from `../bagoo`: `resources/js/Pages/Auth/{Login,Register,ForgotPassword}.tsx`, `resources/js/Layouts/{GuestLayout,BuyerLayout}.tsx`, `resources/js/Pages/Buyer/Home.tsx`, buyer/auth controllers, `HandleInertiaRequests`, registration services, and route files. Reuse original auth imagery and logo. Reuse the licensed shared font from the rider app.

## Logical commits

1. Branch policy and implementation plan.
2. Shared Flutter theme/assets and existing backend session/data adapter.
3. Native auth pages and account recovery flows.
4. Buyer marketplace home, app navigation, setup documentation, and verification evidence.

## Verification

Run Dart formatting, static analysis, focused tests for network/session boundaries and auth/home interactions, and an Android debug build. Check the running local backend's actual response contracts. Use isolated fake responses for mutation tests; do not register accounts, send emails, reset passwords, or change shared development data for routine checks. No browser automation or screenshots requested.

## Status

Implementation in progress. The existing backend serves buyer pages over Inertia and cookie sessions; native rider tokens must not be reused for buyers. The adapter must negotiate the Inertia asset version, CSRF cookie, redirects, and JSON validation responses.
