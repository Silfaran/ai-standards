# Frontend Review Checklist

Closed list of verifiable rules for the Frontend Reviewer agent. Each rule maps to a single, observable check on the diff. If a rule needs context, the source standard is cited at the end.

The reviewer must NOT re-read the full standards — this checklist is the authoritative review surface. If a rule seems missing for the current diff, request it as a `minor` and flag it for inclusion in a future checklist update.

> **Quality gates pre-requisite.** Mechanical checks (ESLint with `--max-warnings=0`, Prettier `--check`, `vue-tsc --noEmit`, Vitest, `vite build`, `npm audit`) are enforced by the pre-commit hook and GitHub Actions CI before the reviewer sees the diff. See [`quality-gates.md`](quality-gates.md). If CI is red, reject immediately with status `QUALITY-GATE-FAILED` and point the developer to the failing job — do not start the full review.

---

## Hard blockers (auto-reject, regardless of iteration)

- [ ] Quality gates CI is green for the current commit (ESLint, Prettier, vue-tsc, Vitest, `vite build`, `npm audit`)
- [ ] `npm run lint` passes (ESLint + Prettier, zero warnings, `--max-warnings=0`) — confirm via CI
- [ ] `npx vue-tsc --noEmit` passes (zero type errors) — confirm via CI
- [ ] No `any` anywhere — use `unknown` + type guards
- [ ] No `v-html` with user-provided content (XSS) — only with developer-authored, sanitized HTML
- [ ] No secrets in `VITE_*` env vars (API keys, tokens, private URLs)
- [ ] No redirects to query-param URLs without `isAllowedRedirect()` validation
- [ ] No `localStorage` for access tokens in consumer frontends (memory `ref` only); `localStorage` allowed only in the auth frontend
- [ ] No SSL verification disabled (`NODE_TLS_REJECT_UNAUTHORIZED=0`, etc.)

## Architecture & layering

- [ ] HTTP calls live ONLY in `services/{Domain}/*ApiService.ts` — never in components, composables, stores
- [ ] Stores never import services that import stores (no circular deps)
- [ ] Composables own ALL feature logic (mutations, queries, navigation, error state) — pages are thin templates
- [ ] Pages: form `ref` + computed validation only; no business logic
- [ ] Stores hold global state only — server-fetched lists/entities go to TanStack Query, NOT Pinia
- [ ] Folder structure follows `src/{components,composables,pages,services,stores,types}/{Domain}/`

## TypeScript

- [ ] Strict mode enabled in `tsconfig.app.json`
- [ ] No `baseUrl` in tsconfig (deprecated in TS 6.0)
- [ ] All service method params and returns explicitly typed
- [ ] Types suffixed with `Type` (`UserResponseType`)
- [ ] `interface` for object shapes, `type` only for unions/intersections/aliases
- [ ] All types exported as named exports

## API & state management

- [ ] One Axios `api` instance per domain service, created via `axios.create()` with `VITE_API_URL`
- [ ] `withCredentials: true` on every API instance
- [ ] Service methods return unwrapped data (`then(r => r.data)`) or `Promise<void>`
- [ ] API payload/response fields use `snake_case` (mirrors backend)
- [ ] Mutations via `useMutation`, queries via `useQuery` from TanStack Query
- [ ] Query keys are descriptive arrays: `['tasks']`, `['task', taskId]`
- [ ] Pages receive ONLY what the template needs from composables — never the full TanStack Query object
- [ ] Errors extracted via `isAxiosError()` + optional chaining + generic fallback message
- [ ] Never `instanceof AxiosError` or unsafe casts

## Pinia stores

- [ ] Composition API syntax: `defineStore('name', () => {...})`
- [ ] Store name lowercase
- [ ] State as `ref()`, derived as `computed()`
- [ ] No destructuring of reactive state from store (only actions)
- [ ] Auth pattern: token in memory + `localStorage` for persistence (auth frontend only)

## Routing

- [ ] All page components use lazy import: `() => import('@/pages/...')`
- [ ] Route meta `requiresAuth` / `requiresGuest` set correctly
- [ ] Navigation via named routes (`{ name: 'login' }`) — no hardcoded paths
- [ ] Route names lowercase, hyphen-separated

## Bootstrap order in `main.ts`

- [ ] Order: `createPinia()` → `router` → `VueQueryPlugin` → `setupInterceptors()`

## Env vars

- [ ] All `VITE_*_URL` values include the full path prefix (e.g. `/api`)
- [ ] Service classes never prepend `/api` themselves

## UX states (every page that fetches/mutates)

- [ ] Loading state shown (`isPending` on submit buttons)
- [ ] Error state shown with `role="alert"`
- [ ] Empty state handled
- [ ] Submit button disabled when `!isFormValid || isPending`
- [ ] Forms use `@submit.prevent`

## Design consistency

- [ ] Implementation respects entries in `design-decisions.md` (read it once if the diff touches UI)
- [ ] First-time UI patterns (first form, first table, first modal, first empty state) added to `design-decisions.md`
- [ ] shadcn/ui components used wherever they cover the need — no custom UI built from scratch when shadcn covers it

## Testing presence (Tester runs them, but reviewer checks they exist)

- [ ] Composable test in `composables/{Domain}/__tests__/*.spec.ts`
- [ ] Store test (if new store) in `stores/{Domain}/__tests__/*.spec.ts`
- [ ] Page test (if new page with form/data flow) covering happy + error paths
- [ ] Mocks: services mocked in composable tests; composables mocked in page tests
- [ ] `vi.clearAllMocks()` in `beforeEach`
- [ ] No real HTTP calls
- [ ] Test files named `{source}.spec.ts`

## Naming

- [ ] Components: `PascalCase.vue`
- [ ] Pages: `XxxPage.vue`
- [ ] Composables: `useXxx.ts`
- [ ] Stores: `XxxStore.ts`
- [ ] Services: `XxxApiService.ts`
- [ ] Handlers: `handleSubmit`, `handleDelete`, `handleSearch`

---

## Sources

For deeper context on any rule above:
- Architecture, stores, composables, services, types, routing → `frontend.md`
- XSS, env vars, redirects, token storage → `security.md` (Frontend Security section)
- Hard security invariants → `invariants.md`
- Full code examples (composables, stores, page tests) → `frontend-reference.md`

If you find a rule violation that is NOT in this checklist, add it as `minor` in your review and include the file/line where the missing rule should live.
