# Frontend Standards

> Full code examples and detailed implementations: `frontend-reference.md`

## Stack

- Vue 3 with Composition API (`<script setup lang="ts">`)
- TypeScript (strict mode — `"strict": true` must be explicit in `tsconfig.app.json`)
- Vite as bundler
- Pinia for global state management
- Vue Router for client-side routing
- TanStack Query for server state (mutations and queries)
- Axios for HTTP calls with interceptors
- shadcn/ui (Vue) for UI components
- Tailwind CSS for styling
- ESLint + Prettier for code formatting
- Vitest + Vue Test Utils for testing

## Folder Structure

```
src/
├── assets/              ← images, fonts, global styles
├── components/          ← reusable UI components grouped by domain
│   └── {Domain}/
├── composables/         ← feature-level logic grouped by domain
│   └── {Domain}/
├── pages/               ← one component per route grouped by domain
│   └── {Domain}/
├── router/              ← Vue Router configuration
├── services/            ← Axios API classes grouped by domain
│   └── {Domain}/
├── stores/              ← Pinia stores grouped by domain
│   └── {Domain}/
└── types/               ← TypeScript interfaces and types grouped by domain
    └── {Domain}/
```

## Service Classes

Service classes are the **only** layer that touches Axios. Components, composables, and stores never make HTTP calls directly.

- One `api` instance per domain service — created with `axios.create()` using `VITE_API_URL`
- Always set `withCredentials: true` for cookie-based auth (refresh tokens)
- Methods return unwrapped data (`then((r) => r.data)`) when the caller needs the response body
- Methods return `Promise<void>` when only the status code matters
- All method parameters and return types must be explicitly typed
- Never import stores inside service files — creates circular dependencies

## Axios Interceptors

Interceptors live in `src/services/setupInterceptors.ts` — not inside service classes.

- Called from `main.ts` **after** `app.use(createPinia())` — store must be initialized first
- Intercepts 401 → attempts silent token refresh → retries original request
- On refresh failure, clears token and redirects to login via auth store
- Use `_retry` flag to prevent infinite retry loops
- Always use `isAxiosError()` for type-safe error checking — never unsafe casts
- Extend `InternalAxiosRequestConfig` for the `_retry` flag — don't use `any`

## Composables

Composables own **all feature-level logic** — mutations, queries, navigation, and error state. Pages are thin wrappers that call composables.

- **Write operations** use `useMutation` from TanStack Query
- **Read operations** use `useQuery` from TanStack Query
- `serverError` is a `ref<string | null>` — reset at the start of each mutation if needed
- Always extract the error message safely using `isAxiosError()` and optional chaining
- Provide a generic fallback message when the error shape is unknown
- Navigation after success/failure belongs in the composable, not the page
- Return **only** what the page template needs — never expose the full TanStack Query object
- Query keys must be descriptive arrays: `['tasks']`, `['task', taskId]`

## Stores (Pinia)

Stores hold **global state only** — auth tokens, user profile, app-wide settings. Do not use stores for server state (that belongs in TanStack Query).

- Always use **Composition API** syntax: `defineStore('name', () => { ... })`
- Store name must be unique and lowercase: `'auth'`, `'taskBoard'`
- State as `ref()`, derived state as `computed()`, actions as plain functions
- Stores can call service classes directly (e.g. `logout` calls `UserApiService.logout()`)
- Never store server-fetched lists or entities in Pinia — use TanStack Query
- Auth pattern: token in memory (`ref`) + `localStorage` for persistence across reloads
- **Never destructure reactive state from a store** — access through the store proxy: `authStore.isLoading`
- **Only actions (functions) are safe to destructure** — `const { logout } = authStore` is fine
- **When mocking a store in tests, use `reactive()`** — a plain object with `ref()` values won't auto-unwrap

## TypeScript Types

- Suffix all types with `Type`: `RegisterPayloadType`, `TaskResponseType`
- Use `interface` for object shapes — use `type` only for unions, intersections, or aliases
- API payload and response fields use **snake_case** (mirrors the backend)
- Never use `any` — use `unknown` and narrow with type guards
- Export all types as named exports — no default exports

## Pages (Route Components)

Pages are **thin**: they own the template and delegate all logic to composables.

- Always use `<script setup lang="ts">`
- Form state (`ref`) and computed validation live in the page — they are template-specific
- Business logic, API calls, and navigation live in the composable
- Handler functions: `handleSubmit`, `handleDelete`, `handleSearch`
- Always show loading state (`isPending`) on submit buttons
- Always show error state (`serverError`) with `role="alert"` for accessibility
- Disable submit buttons when `!isFormValid || isPending`
- Use `@submit.prevent` on forms

## Routing

- Use **lazy loading** for all page components: `() => import('@/pages/...')`
- Route meta: `requiresAuth: true` for protected pages, `requiresGuest: true` for login/register
- Navigation guards in the router file — components never check auth directly
- Always use **named routes** (`{ name: 'login' }`) — never hardcode paths
- Route names are lowercase, hyphen-separated: `'login'`, `'task-detail'`

## Application Bootstrap

`main.ts` initialization order — **order matters**:

1. `app.use(createPinia())` — Pinia first, stores depend on it
2. `app.use(router)` — Router second, guards use stores
3. `app.use(VueQueryPlugin)` — TanStack Query third
4. `setupInterceptors()` — Interceptors last, they use stores

## Environment Variables

All `VITE_*_URL` variables must include the **full path prefix**:

```dotenv
# Wrong — missing /api prefix
VITE_API_URL=http://localhost:8080

# Correct
VITE_API_URL=http://localhost:8080/api
```

Service classes build paths relative to this base URL — they never prepend `/api`.

## Error Handling

- Always use `isAxiosError()` — never `instanceof AxiosError` or unsafe casts
- Always check `typeof error.response?.data?.error === 'string'` before reading the message
- Always provide a generic fallback for unexpected error shapes
- Backend error format: `{ "error": "message", "details": [...] }`
- Use `computed` for real-time client-side validation feedback
- Show validation errors only after user interaction
- Disable submit until the form is valid

## Testing

> Full test examples (composable, store, page): see `frontend-reference.md`

### Stack

- **Vitest** — test runner (configured via `vite.config.ts`)
- **Vue Test Utils** — component mounting and interaction
- **jsdom** — browser environment simulation

### Folder structure

Test files live in `__tests__/` **next to their source file**:

```
src/composables/User/
├── useLogin.ts
└── __tests__/
    └── useLogin.spec.ts
```

### What to test

| Layer | Test type | What to assert |
|---|---|---|
| Composables | Unit | Mutation/query callbacks, navigation, returned refs |
| Stores | Unit | State changes, computed values, action side effects |
| Pages | Integration | Form submission, validation feedback, loading/error/empty states |
| Services | Do not test | Thin wrappers over Axios — tested indirectly |

### General rules

- Mock service classes in composable tests — never make real HTTP calls
- Mock composables in page tests — never test service logic through pages
- Mock `useRouter` and `useRoute` when testing navigation
- Test error paths — not just happy paths
- Never test service classes directly
- Name test files `{source}.spec.ts`
- `vi.clearAllMocks()` in `beforeEach` — always
- `vi.mock()` at the top level — before imports
- Dynamic import per test (`await import(...)`) for fresh mock application
- Capture `onSuccess`/`onError` callbacks in mutable variables for direct invocation

### npm scripts

```json
{
  "test": "vitest run",
  "test:watch": "vitest",
  "test:coverage": "vitest run --coverage"
}
```

## Standard Libraries

| Purpose | Library |
|---|---|
| HTTP client | `axios` |
| Server state (queries/mutations) | `@tanstack/vue-query` |
| Global state | `pinia` |
| Routing | `vue-router` |
| UI components | `shadcn-vue` |
| Form validation | `vee-validate` + `zod` |
| Testing | `vitest` + `@vue/test-utils` + `jsdom` |
| Coverage | `@vitest/coverage-v8` |
| Linting | `eslint` |
| Formatting | `prettier` |

## Naming Conventions

| Type | Example |
|---|---|
| Component | `UserCard.vue` |
| Page | `UserDetailPage.vue` |
| Composable | `useUserFinder.ts` |
| Store | `UserStore.ts` |
| Service | `UserApiService.ts` |
| Type/Interface | `UserType.ts` |
| Handler function | `handleSubmit()` |
| Query key | `['tasks']`, `['task', taskId]` |
