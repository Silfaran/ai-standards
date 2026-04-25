# Frontend Review Checklist

Closed list of verifiable rules for the Frontend Reviewer agent. Each rule has a stable ID (`FE-*`, `SE-*`, `PE-*`, …) prefixed by the source-standard domain; quoting the ID is enough to disambiguate a violation. Each rule maps to a single, observable check on the diff.

The reviewer must NOT re-read the full standards — this checklist is the authoritative review surface. If a rule seems missing for the current diff, request it as a `minor` and flag it for inclusion in a future checklist update (new rules get the next free ID within their prefix — IDs are never reassigned).

> **Quality gates pre-requisite.** Mechanical checks (ESLint with `--max-warnings=0`, Prettier `--check`, `vue-tsc --noEmit`, Vitest, `vite build`, `npm audit`) are enforced by the pre-commit hook and GitHub Actions CI before the reviewer sees the diff. See [`quality-gates.md`](quality-gates.md). If CI is red, reject immediately with status `QUALITY-GATE-FAILED` and point the developer to the failing job — do not start the full review.

---

## Hard blockers (auto-reject, regardless of iteration)

- [ ] **FE-001** — Quality gates CI is green for the current commit (ESLint, Prettier, vue-tsc, Vitest, `vite build`, `npm audit`)
- [ ] **FE-002** — `npm run lint` passes (ESLint + Prettier, zero warnings, `--max-warnings=0`) — confirm via CI
- [ ] **FE-003** — `npx vue-tsc --noEmit` passes (zero type errors) — confirm via CI
- [ ] **FE-004** — No `any` anywhere — use `unknown` + type guards
- [ ] **SE-019** — No `v-html` with user-provided content (XSS) — only with developer-authored, sanitized HTML
- [ ] **SC-008** — No secrets in `VITE_*` env vars (API keys, tokens, private URLs)
- [ ] **SE-020** — No redirects to query-param URLs without `isAllowedRedirect()` validation
- [ ] **SE-021** — No `localStorage` for access tokens in any frontend (memory `ref` only) — auth frontends included; per ADR-001 the auth frontend also performs a silent refresh from its HttpOnly cookie on boot
- [ ] **SE-003** — No SSL verification disabled (`NODE_TLS_REJECT_UNAUTHORIZED=0`, etc.)

## Architecture & layering

- [ ] **FE-005** — HTTP calls live ONLY in `services/{Domain}/*ApiService.ts` — never in components, composables, stores
- [ ] **FE-006** — Stores never import services that import stores (no circular deps)
- [ ] **FE-007** — Composables own ALL feature logic (mutations, queries, navigation, error state) — pages are thin templates
- [ ] **FE-008** — Pages: form `ref` + computed validation only; no business logic
- [ ] **FE-009** — Stores hold global state only — server-fetched lists/entities go to TanStack Query, NOT Pinia
- [ ] **FE-010** — Folder structure follows `src/{components,composables,pages,services,stores,types}/{Domain}/`

## TypeScript

- [ ] **FE-011** — Strict mode enabled in `tsconfig.app.json`
- [ ] **FE-012** — No `baseUrl` in tsconfig (deprecated in TS 6.0)
- [ ] **FE-013** — All service method params and returns explicitly typed
- [ ] **FE-014** — Types suffixed with `Type` (`UserResponseType`)
- [ ] **FE-015** — `interface` for object shapes, `type` only for unions/intersections/aliases
- [ ] **FE-016** — All types exported as named exports

## API & state management

- [ ] **FE-017** — One Axios `api` instance per domain service, created via `axios.create()` with `VITE_API_URL`
- [ ] **FE-018** — `withCredentials: true` on every API instance
- [ ] **FE-019** — Service methods return unwrapped data (`then(r => r.data)`) or `Promise<void>`
- [ ] **AC-014** — API payload/response fields use `snake_case` (mirrors backend)
- [ ] **FE-020** — Mutations via `useMutation`, queries via `useQuery` from TanStack Query
- [ ] **FE-021** — Query keys are descriptive arrays: `['tasks']`, `['task', taskId]`
- [ ] **FE-022** — Pages receive ONLY what the template needs from composables — never the full TanStack Query object
- [ ] **FE-023** — Errors extracted via `isAxiosError()` + optional chaining + generic fallback message
- [ ] **FE-024** — Never `instanceof AxiosError` or unsafe casts

## Pinia stores

- [ ] **FE-025** — Composition API syntax: `defineStore('name', () => {...})`
- [ ] **FE-026** — Store name lowercase
- [ ] **FE-027** — State as `ref()`, derived as `computed()`
- [ ] **FE-028** — No destructuring of reactive state from store (only actions)

## Routing

- [ ] **FE-029** — All page components use lazy import: `() => import('@/pages/...')`
- [ ] **FE-030** — Route meta `requiresAuth` / `requiresGuest` set correctly
- [ ] **FE-031** — Navigation via named routes (`{ name: 'login' }`) — no hardcoded paths
- [ ] **FE-032** — Route names lowercase, hyphen-separated

## Authorization (route guards & UI gating)

- [ ] **AZ-013** — Route guards check `meta.requiresAuth` and `meta.requiresRoles` (when set) before resolving — UI route definitions do NOT trust component-level `v-if` for access control
- [ ] **AZ-014** — UI gating (hiding a button the user cannot use) is presentation-only — the backend ALWAYS re-checks; a 403 from the API is handled gracefully (toast + redirect, not a broken page)
- [ ] **AZ-015** — The frontend NEVER stores roles in `localStorage` — roles live in the in-memory auth store, refreshed from the backend on app boot (per `SE-021` token-storage rule)
- [ ] **AZ-016** — A 403 response is treated as a UX state, never silently swallowed — the user sees an explicit "no permission" message with the action that was denied

## Personal data (PII) & GDPR

- [ ] **GD-015** — PII fields (email, phone, tax id) NEVER appear in URL paths, query strings, hash fragments, or `localStorage` — anything browser-cached is a leak surface
- [ ] **GD-016** — Forms that collect Sensitive-PII (government id, payment instrument, biometrics, health) use `autocomplete="off"` AND submit over a single TLS request — no multi-step localStorage drafts
- [ ] **GD-017** — Consent UI presents one consent per purpose (marketing, analytics, ML personalization) — no "by using this site you agree to everything" dark patterns
- [ ] **GD-018** — Withdrawal of consent is reachable in <=2 clicks from the settings entry point and surfaced as effective immediately ("opt out applied"); the UI does NOT promise a "next batch" lag
- [ ] **GD-019** — Analytics / observability calls (web-vitals, page.view spans) carry the hashed `user_id` only — never the email, tax id, display name in plain text

## Payments & money

- [ ] **PA-021** — Money values in API payloads use `{ amount_minor: <int>, currency: 'XXX' }` — no float prices, no string-formatted "12.34" on the wire
- [ ] **PA-022** — Frontend renders money via `Intl.NumberFormat` with `style: 'currency'` and explicit locale (see IN-018) — never concatenates symbol + number, never `toFixed(2)` for display
- [ ] **PA-023** — Card / payment-method capture uses the PSP's hosted element (Stripe Elements, Adyen Drop-in, …) — raw card numbers NEVER touch frontend state, localStorage, sessionStorage or any analytics call
- [ ] **PA-024** — Payment confirmation pages do NOT trust client-side state for "paid" status — they re-fetch the charge from the backend (which is webhook-driven) before showing a success message

## File & media storage

- [ ] **FS-023** — Uploads use the presigned PUT flow: `POST /uploads` → upload directly to bucket → `POST /uploads/:key/finalize` — NEVER stream bytes through the application API
- [ ] **FS-024** — A presigned URL is consumed once and forgotten — never stored in localStorage, sessionStorage, or a Pinia store
- [ ] **FS-025** — Image / video tags pointing at private content fetch a fresh signed URL on render — no cached URLs reused after expiry
- [ ] **FS-026** — Forms accepting file uploads enforce client-side `accept`, max-size and visible error states — the backend validation is authoritative, the frontend prevents wasted bandwidth

## Geo & search

- [ ] **GS-024** — Map components fetch a bounding-box query bounded to the project's max area; pan/zoom triggers a debounced re-fetch — never "fetch everything"
- [ ] **GS-025** — Markers are clustered at the rendering layer when count exceeds 50 in the viewport (`leaflet.markercluster` or equivalent)
- [ ] **GS-026** — Search inputs are debounced (default 250 ms) — each keystroke does NOT issue a request
- [ ] **GS-027** — A user's coordinates are NEVER inlined into HTML, NEVER stored in `localStorage` — they are fetched on demand from a private endpoint
- [ ] **GS-028** — Result lists render the qualitative `MatchLabel` and the structured `explanations` translated via i18n — they NEVER display the raw numeric score

## Feature flags

- [ ] **FF-017** — Frontend flag evaluations go through a single `useFlag(key)` composable; `key` is a literal, declared in `feature-flags.md` — dynamic keys are forbidden
- [ ] **FF-018** — Flag-gated UI never renders the gated content as a flash before the evaluation completes — the composable exposes `{ ready, isOn }` and the template waits on `ready`
- [ ] **FF-019** — A flag-gated route always re-checks the flag on the server (handler / query) — frontend flag state is presentation-only and NEVER trusted by the backend
- [ ] **FF-020** — User-facing experiment variants are sticky (provider bucketing on `subjectId`); a refresh does NOT change the variant the user sees

## PWA & offline

- [ ] **PW-001** — `[critical]` Service worker is generated at build time via `vite-plugin-pwa` (Workbox `generateSW` strategy) — hand-edited service workers are forbidden
- [ ] **PW-002** — `navigateFallbackDenylist` excludes `/api/`, `/admin/` and any other dynamic-response route — the SW does NOT serve an HTML shell for API calls
- [ ] **PW-003** — Cache strategies match the recommended table: app shell `cacheFirst (precache)`; versioned assets `cacheFirst (immutable)`; public CDN images `staleWhileRevalidate`; private API GET `networkFirst` with short timeout (≤ 3s); mutations + auth endpoints `networkOnly`
- [ ] **PW-004** — Each runtime cache bucket declares explicit `maxEntries` AND `maxAgeSeconds` — no unbounded caches
- [ ] **PW-005** — `manifest.webmanifest` declares `name`, `short_name`, `start_url` (with install attribution param), `scope`, `display`, `theme_color`, `background_color`, icons (192 + 512 + maskable), `lang` matching source locale
- [ ] **PW-006** — Service worker registration happens AFTER the app shell renders — a SW failure does NOT block first paint
- [ ] **PW-007** — SW update flow uses the `useServiceWorkerUpdate` composable surfacing a non-modal banner — never auto-reloads mid-flow
- [ ] **PW-008** — `[critical]` IndexedDB / Cache Storage NEVER persists Sensitive-PII (per `gdpr-pii.md` GD-005) — the offline-cache config is validated against `pii-inventory.md` at build
- [ ] **PW-009** — Logout flow clears SW caches AND IndexedDB stores of identified data — `clearOfflineCacheForLogout()` is the canonical helper
- [ ] **PW-010** — Offline reads display staleness (e.g. "Last updated 12 minutes ago") — silent stale UX is forbidden
- [ ] **PW-011** — Cached private responses respect `Cache-Control: private` from the API (CA-002) — public-cache strategies on private endpoints are forbidden
- [ ] **PW-012** — Offline writes (L3) use intent objects with idempotency keys; sensitive operations (payments, RTBF, role grants, anything audit-log significant) are NOT eligible for offline writes
- [ ] **PW-013** — Conflict policy declared per L3 mutation in the spec (`last-writer-wins` / `merge per field` / `manual reconciliation`) — ad-hoc resolution is forbidden
- [ ] **PW-014** — `[critical]` `Notification.requestPermission()` is called only in response to a user gesture AND only after an in-app pre-prompt explaining the categories — first-load prompts are forbidden
- [ ] **PW-015** — Push consent is per category (transactional / marketing / mention-and-reply); each grant/withdrawal produces an `audit-log.md` entry; denials are remembered for 90+ days
- [ ] **PW-016** — Push payloads are SHORT and contain NO Sensitive-PII — text references; the app fetches the full content when the user opens the notification

## Digital signatures

- [ ] **DS-021** — Signing UI presents the document for review BEFORE sending — the user confirms the bytes they are about to commit to (matches the audit-trail's "what was signed" record)
- [ ] **DS-022** — Pending-signature UX shows the SigningRequest state (`sent`, `in_signing`, `completed`, `declined`, `expired`) with explicit timestamps; never a silent loading spinner that times out
- [ ] **DS-023** — Signed documents are NEVER rendered inline from the public origin — they are downloaded via a presigned URL with `Content-Disposition: attachment` (FS-010)
- [ ] **DS-024** — Verification surface displays the system's `document_sha256` AND the provider audit trail link — copy-pasteable, comparable to a third party's hash without re-fetching from the provider

## Attack surface hardening

- [ ] **AS-024** — Inline scripts and styles in HTML carry the per-request CSP nonce; the build pipeline injects it (no `'unsafe-inline'`)
- [ ] **AS-025** — Third-party scripts loaded from a CDN carry `integrity` (Subresource Integrity hash) AND `crossorigin="anonymous"` — drop the dependency if the CDN does not publish a SHA
- [ ] **AS-026** — Frontend NEVER builds an outbound URL from a user-supplied URL parameter without `isAllowedRedirect()` (SE-020 generalised)
- [ ] **AS-027** — CSP violations surfaced from `report-uri` are treated as defects; the dashboard for `csp_violations_total` is reviewed weekly

## Bootstrap order in `main.ts`

- [ ] **FE-033** — Order: `createPinia()` → `router` → `VueQueryPlugin` → `setupInterceptors()`

## Internationalization

- [ ] **IN-014** — `vue-i18n` initialised in `main.ts` with `legacy: false`, `fallbackLocale` mirroring the backend chain, `missingWarn: import.meta.env.DEV`
- [ ] **IN-015** — Locale message files lazy-loaded per route — never bundled all locales upfront (broken for code splitting)
- [ ] **IN-016** — `Accept-Language` header set on the Axios instance to the active locale — backend gets the same negotiated locale the user sees
- [ ] **IN-017** — Component templates use `$t('static.key')` / `$tc('static.key', count)` only — no `$t($dynamicKey)`, no `'Hola ' + name` concatenation, no hardcoded user-facing strings
- [ ] **IN-018** — Plurals via `$tc()` (CLDR rules); dates/numbers/currency via `Intl.DateTimeFormat` / `Intl.NumberFormat` with explicit locale — never `toLocaleString()` without an argument
- [ ] **IN-019** — Locale change persists via `PUT /api/v1/me/preferences` AND invalidates active queries (`queryClient.invalidateQueries()`) so server-rendered messages re-fetch
- [ ] **IN-020** — System reference data (countries, currencies, locale names) read from `Intl.DisplayNames` — no hardcoded country lists in frontend source

## Env vars

- [ ] **FE-034** — All `VITE_*_URL` values include the full path prefix (e.g. `/api`)
- [ ] **FE-035** — Service classes never prepend `/api` themselves

## UX states (every page that fetches/mutates)

- [ ] **FE-036** — Loading state shown (`isPending` on submit buttons)
- [ ] **FE-037** — Error state shown with `role="alert"`
- [ ] **FE-038** — Empty state handled
- [ ] **FE-039** — Submit button disabled when `!isFormValid || isPending`
- [ ] **FE-040** — Forms use `@submit.prevent`

## Performance

- [ ] **PE-006** — `web-vitals` wired in `main.ts` reporting LCP, INP, CLS, TTFB to the backend log endpoint
- [ ] **PE-007** — No Core Web Vitals regression on the pages the diff touches (LCP ≤ 2.5 s, INP ≤ 200 ms, CLS ≤ 0.1 on mid-tier mobile)
- [ ] **PE-008** — `vite.config.ts` sets `build.chunkSizeWarningLimit` explicitly and a `manualChunks` split (vendor libraries isolated from app code)
- [ ] **PE-009** — `vite build` output has no chunk-size warnings — CI fails if any appear
- [ ] **PE-010** — Initial JS ≤ 170 kB gzipped, initial CSS ≤ 50 kB gzipped, per-route lazy chunk ≤ 80 kB gzipped
- [ ] **PE-011** — Every `<img>` / `<video>` declares `width` and `height` (or a fixed-ratio container) — no CLS from media
- [ ] **PE-012** — Below-the-fold images use `loading="lazy"`; above-the-fold hero image uses `fetchpriority="high"` and is preloaded
- [ ] **PE-013** — Long lists (>50 visible items) virtualized (no naive `v-for` over thousands of rows)
- [ ] **PE-014** — `@font-face` uses `font-display: swap`; critical fonts preloaded with `rel="preload" as="font" crossorigin`
- [ ] **PE-015** — No polling `setInterval` when TanStack Query `refetchOnWindowFocus` + invalidation covers the use case
- [ ] **PE-016** — Asset URLs use `import.meta.env.BASE_URL` (not hardcoded same-origin paths) — frontend stays CDN-ready
- [ ] **PE-017** — No user/session state serialized into the HTML shell — shell is safe to cache publicly

## Observability

- [ ] **OB-011** — Page navigations emit a `page.view` span with `page.route` (route name, not rendered URL)
- [ ] **OB-012** — Every TanStack Query `useQuery` / `useMutation` emits a client span linked to the navigation parent
- [ ] **OB-013** — Outgoing HTTP calls propagate `traceparent` / `tracestate` headers
- [ ] **OB-014** — Core Web Vitals recorded as span events on the navigation span (LCP, INP, CLS, TTFB) in addition to the `web-vitals` backend log pipeline
- [ ] **OB-015** — No span attribute carries the access token, password, or any field the backend redaction list forbids

## API Contracts

- [ ] **AC-015** — All backend types come from the generated OpenAPI client — no hand-written types for shapes covered by OpenAPI
- [ ] **AC-016** — Consuming frontend never calls an endpoint that does not exist in the currently deployed backend (no merges gated behind a non-existent route)
- [ ] **AC-017** — Deprecated backend endpoints not consumed from the frontend — if a `Deprecation` header is observed, migration issue filed and surfaced in the review
- [ ] **AC-018** — Payload casing is `snake_case` on the wire, `camelCase` only inside the frontend domain layer — no leakage either direction

## Design consistency

- [ ] **FE-041** — Implementation respects entries in `design-decisions.md` (read it once if the diff touches UI)
- [ ] **FE-042** — First-time UI patterns (first form, first table, first modal, first empty state) added to `design-decisions.md`
- [ ] **FE-043** — shadcn/ui components used wherever they cover the need — no custom UI built from scratch when shadcn covers it

## Testing presence (Tester runs them, but reviewer checks they exist)

- [ ] **FE-044** — Composable test in `composables/{Domain}/__tests__/*.spec.ts`
- [ ] **FE-045** — Store test (if new store) in `stores/{Domain}/__tests__/*.spec.ts`
- [ ] **FE-046** — Page test (if new page with form/data flow) covering happy + error paths
- [ ] **FE-047** — Mocks: services mocked in composable tests; composables mocked in page tests
- [ ] **FE-048** — `vi.clearAllMocks()` in `beforeEach`
- [ ] **FE-049** — No real HTTP calls
- [ ] **FE-050** — Test files named `{source}.spec.ts`

## Naming

- [ ] **FE-051** — Components: `PascalCase.vue`
- [ ] **FE-052** — Pages: `XxxPage.vue`
- [ ] **FE-053** — Composables: `useXxx.ts`
- [ ] **FE-054** — Stores: `XxxStore.ts`
- [ ] **FE-055** — Services: `XxxApiService.ts`
- [ ] **FE-056** — Handlers: `handleSubmit`, `handleDelete`, `handleSearch`

---

## Sources

For deeper context on any rule above:
- Architecture, stores, composables, services, types, routing → `frontend.md`
- Core Web Vitals, Vite bundle config, budgets, images, fonts → `performance.md`
- Tracing, Web Vitals span events, propagation → `observability.md`
- OpenAPI client, breaking-change protocol, payload conventions → `api-contracts.md`
- XSS, env vars, redirects, token storage → `security.md` (Frontend Security section)
- Hard security invariants → `invariants.md`
- Full code examples (composables, stores, page tests) → `frontend-reference.md`
- Voter pattern, Subject VO, route guards, tenant scoping → `authorization.md`
- vue-i18n setup, lazy namespaces, locale change flow, Intl APIs → `i18n.md`
- PII in URLs/storage/forms, consent UI, withdrawal flow → `gdpr-pii.md`
- Money serialization, Intl currency formatting, hosted card capture → `payments-and-money.md`
- Presigned upload flow, signed URL hygiene, file form validation → `file-and-media-storage.md`
- Map bbox fetching, marker clustering, debounced search, label/explanations rendering → `geo-search.md`
- useFlag composable, no-flash gating, sticky variants, server-side re-check → `feature-flags.md`
- Service worker setup, cache strategies, manifest, update flow, offline reads/writes, push consent → `pwa-offline.md`
- Pre-sign review, signing-state UX, attachment downloads, verification surface → `digital-signature-integration.md`
- CSP nonces, SRI for CDN scripts, allowlisted redirects, CSP violation dashboard → `attack-surface-hardening.md`

If you find a rule violation that is NOT in this checklist, add it as `minor` in your review and include the file/line where the missing rule should live — the orchestrator will assign the next free ID in the matching prefix.
