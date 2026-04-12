# Frontend Standards

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

---

## Service Classes

Service classes are the **only** layer that touches Axios. Components, composables, and stores never make HTTP calls directly.

### Structure

One service file per domain, exporting a plain object with methods:

```ts
import axios from 'axios'
import type { LoginPayloadType, LoginResponseType, RegisterPayloadType } from '@/types/User/UserType'

export const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL,
  withCredentials: true,
})

export const UserApiService = {
  register(payload: RegisterPayloadType): Promise<void> {
    return api.post('/register', payload)
  },

  login(payload: LoginPayloadType): Promise<LoginResponseType> {
    return api.post<LoginResponseType>('/login', payload).then((r) => r.data)
  },

  logout(): Promise<void> {
    return api.post('/logout')
  },
}
```

### Rules

- **One `api` instance per domain service** — created with `axios.create()` using `VITE_API_URL`
- **Always set `withCredentials: true`** for cookie-based auth (refresh tokens)
- Methods return unwrapped data (`then((r) => r.data)`) when the caller needs the response body
- Methods return `Promise<void>` when only the status code matters (e.g. register, logout)
- All method parameters and return types must be explicitly typed
- Never import stores inside service files — this creates circular dependencies

---

## Axios Interceptors

Interceptors handle token refresh and auth failures globally. They live in a **dedicated file**, not inside service classes.

### Setup

```
src/services/setupInterceptors.ts
```

- Called from `main.ts` **after** `app.use(createPinia())` — the store must be initialized first
- Intercepts 401 responses → attempts silent token refresh → retries the original request
- On refresh failure, clears the token and redirects to login via the auth store

### Implementation pattern

```ts
import { isAxiosError } from 'axios'
import type { InternalAxiosRequestConfig } from 'axios'
import { api } from '@/services/User/UserApiService'
import { useAuthStore } from '@/stores/User/UserStore'
import type { LoginResponseType } from '@/types/User/UserType'

interface RetryableConfig extends InternalAxiosRequestConfig {
  _retry?: boolean
}

export function setupInterceptors(): void {
  api.interceptors.response.use(
    (response) => response,
    async (error: unknown) => {
      if (!isAxiosError(error)) return Promise.reject(error)

      const originalRequest = error.config as RetryableConfig | undefined
      if (error.response?.status === 401 && originalRequest && !originalRequest._retry) {
        originalRequest._retry = true
        try {
          const { data } = await api.post<LoginResponseType>('/token/refresh')
          useAuthStore().setAccessToken(data.access_token)
          originalRequest.headers['Authorization'] = `Bearer ${data.access_token}`
          return api(originalRequest)
        } catch {
          await useAuthStore().logout()
          return Promise.reject(error)
        }
      }
      return Promise.reject(error)
    },
  )
}
```

### Rules

- Use `_retry` flag to prevent infinite retry loops
- Always use `isAxiosError()` for type-safe error checking — never unsafe casts
- Extend `InternalAxiosRequestConfig` for the `_retry` flag — don't use `any`

---

## Composables

Composables own **all feature-level logic** — mutations, queries, navigation, and error state. Pages are thin wrappers that call composables.

### Structure

One composable per feature action, following the `use{Action}` naming convention:

```ts
import { ref } from 'vue'
import { isAxiosError } from 'axios'
import { useMutation } from '@tanstack/vue-query'
import { UserApiService } from '@/services/User/UserApiService'
import { useRouter } from 'vue-router'
import type { RegisterPayloadType } from '@/types/User/UserType'

export function useRegister() {
  const router = useRouter()
  const serverError = ref<string | null>(null)

  const { mutate, isPending, isError } = useMutation({
    mutationFn: (payload: RegisterPayloadType) => UserApiService.register(payload),
    onSuccess: () => {
      router.push({ name: 'login' })
    },
    onError: (error: unknown) => {
      const message =
        isAxiosError(error) && typeof error.response?.data?.error === 'string'
          ? error.response.data.error
          : 'Registration failed. Please try again.'
      serverError.value = message
    },
  })

  return { mutate, isPending, isError, serverError }
}
```

### Rules

- **Write operations** use `useMutation` from TanStack Query
- **Read operations** use `useQuery` from TanStack Query
- `serverError` is a `ref<string | null>` — reset it at the start of each mutation if needed
- Always extract the error message safely using `isAxiosError()` and optional chaining
- Provide a generic fallback message when the error shape is unknown
- Navigation after success/failure belongs in the composable, not the page
- A composable returns **only** what the page template needs: `mutate`, `isPending`, `isError`, `serverError`, query data, etc.
- Never expose the full TanStack Query object — destructure and return only what's used

### Queries pattern

```ts
import { useQuery } from '@tanstack/vue-query'
import { TaskApiService } from '@/services/Task/TaskApiService'

export function useTaskList() {
  const { data, isPending, isError } = useQuery({
    queryKey: ['tasks'],
    queryFn: () => TaskApiService.list(),
  })

  return { tasks: data, isPending, isError }
}
```

- Query keys must be descriptive arrays: `['tasks']`, `['task', taskId]`
- For queries that depend on a parameter, use a computed or getter for the query key

---

## Stores (Pinia)

Stores hold **global state only** — auth tokens, user profile, app-wide settings. Do not use stores for server state (that belongs in TanStack Query).

### Structure

Use the Composition API syntax (`setup` function), not the Options API syntax:

```ts
import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { UserApiService, api } from '@/services/User/UserApiService'
import { useRouter } from 'vue-router'

export const useAuthStore = defineStore('auth', () => {
  const accessToken = ref<string | null>(localStorage.getItem('access_token'))
  const router = useRouter()

  const isAuthenticated = computed(() => accessToken.value !== null)

  function setAccessToken(token: string): void {
    accessToken.value = token
    localStorage.setItem('access_token', token)
    api.defaults.headers.common['Authorization'] = `Bearer ${token}`
  }

  function clearAccessToken(): void {
    accessToken.value = null
    localStorage.removeItem('access_token')
    delete api.defaults.headers.common['Authorization']
  }

  async function logout(): Promise<void> {
    try {
      await UserApiService.logout()
    } finally {
      clearAccessToken()
      router.push({ name: 'login' })
    }
  }

  // Restore header on page reload
  if (accessToken.value) {
    api.defaults.headers.common['Authorization'] = `Bearer ${accessToken.value}`
  }

  return { accessToken, isAuthenticated, setAccessToken, clearAccessToken, logout }
})
```

### Rules

- Always use the **Composition API** syntax with `defineStore('name', () => { ... })`
- Store name (first argument) must be unique and lowercase: `'auth'`, `'taskBoard'`
- State as `ref()`, derived state as `computed()`, actions as plain functions
- Stores can call service classes directly (e.g. `logout` calls `UserApiService.logout()`)
- Never store server-fetched lists or entities in Pinia — use TanStack Query for server state
- Auth pattern: token in memory (`ref`) + `localStorage` for persistence across reloads
- **Never destructure reactive state from a store** — `const { isLoading } = authStore` captures the value at mount time and loses reactivity. Access state through the store proxy: `authStore.isLoading`, not a destructured local
- **Only actions (functions) are safe to destructure** — `const { logout } = authStore` is fine because functions are not reactive
- **When mocking a store whose properties a template accesses via the proxy, use `reactive()`** — `reactive({ isLoading: false })`. A plain object with `ref()` values won't auto-unwrap when accessed as `mockStore.isLoading`, causing template comparisons to receive a Ref object instead of a boolean

---

## TypeScript Types

### Structure

One type file per domain. All types related to API payloads and responses live here:

```ts
export interface RegisterPayloadType {
  first_name: string
  last_name: string
  email: string
  password: string
}

export interface LoginPayloadType {
  email: string
  password: string
}

export interface LoginResponseType {
  access_token: string
}
```

### Rules

- Suffix all types with `Type`: `RegisterPayloadType`, `TaskResponseType`
- Use `interface` for object shapes — use `type` only for unions, intersections, or aliases
- API payload fields use **snake_case** (mirrors the backend) — never camelCase
- API response fields also use **snake_case** — transform to camelCase in the composable if needed, not in the type definition
- Never use `any` — use `unknown` and narrow with type guards when the shape is uncertain
- Export all types as named exports — no default exports for type files

---

## Pages (Route Components)

Pages are **thin**: they own the template and delegate all logic to composables.

### Structure

```vue
<script setup lang="ts">
import { ref, computed } from 'vue'
import { useRegister } from '@/composables/User/useRegister'

const firstName = ref('')
const lastName = ref('')
const email = ref('')
const password = ref('')

const { mutate, isPending, serverError } = useRegister()

const isFormValid = computed(
  () =>
    firstName.value.trim() !== '' &&
    email.value.trim() !== '' &&
    password.value !== '',
)

function handleSubmit(): void {
  if (!isFormValid.value) return
  mutate({
    first_name: firstName.value.trim(),
    last_name: lastName.value.trim(),
    email: email.value.trim(),
    password: password.value,
  })
}
</script>

<template>
  <!-- Template uses Tailwind CSS classes and shadcn/ui components -->
</template>
```

### Rules

- Always use `<script setup lang="ts">` — no Options API, no `<script>` block without `setup`
- Form state (`ref`) and computed validation live in the page — they are template-specific
- Business logic, API calls, and navigation live in the composable
- Handler functions follow the `handle{Action}` naming: `handleSubmit`, `handleDelete`, `handleSearch`
- Always show loading state (`isPending`) on submit buttons
- Always show error state (`serverError`) with `role="alert"` for accessibility
- Disable submit buttons when `!isFormValid || isPending`
- Use `@submit.prevent` on forms — never rely on default form behavior

---

## Routing

### Configuration

```ts
import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/User/UserStore'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/login',
      name: 'login',
      component: () => import('@/pages/User/LoginPage.vue'),
      meta: { requiresGuest: true },
    },
    {
      path: '/dashboard',
      name: 'dashboard',
      component: () => import('@/pages/User/DashboardPage.vue'),
      meta: { requiresAuth: true },
    },
  ],
})

router.beforeEach((to) => {
  const authStore = useAuthStore()
  if (to.meta.requiresAuth && !authStore.isAuthenticated) return { name: 'login' }
  if (to.meta.requiresGuest && authStore.isAuthenticated) return { name: 'dashboard' }
})
```

### Rules

- Use **lazy loading** for all page components: `() => import('@/pages/...')`
- Route meta: `requiresAuth: true` for protected pages, `requiresGuest: true` for login/register
- Navigation guards in the router file — components never check auth directly
- Always use **named routes** (`{ name: 'login' }`) — never hardcode paths in navigation
- Route names are lowercase, hyphen-separated: `'login'`, `'task-detail'`, `'board-settings'`

---

## Application Bootstrap

`main.ts` follows a strict initialization order:

```ts
import { createApp } from 'vue'
import { createPinia } from 'pinia'
import { VueQueryPlugin } from '@tanstack/vue-query'
import App from './App.vue'
import router from './router'
import { setupInterceptors } from '@/services/setupInterceptors'
import './assets/main.css'

const app = createApp(App)

app.use(createPinia())    // 1. Pinia first — stores depend on it
app.use(router)           // 2. Router second — guards use stores
app.use(VueQueryPlugin)   // 3. TanStack Query third

setupInterceptors()       // 4. Interceptors last — they use stores

app.mount('#app')
```

**Order matters:** interceptors call `useAuthStore()`, which requires Pinia to be installed. Breaking this order causes runtime errors.

---

## Environment Variables

### Base URL convention

All `VITE_*_URL` variables that point to an API must include the **full path prefix** at which the API is actually mounted. Never use a bare host.

```dotenv
# Wrong — missing /api prefix
VITE_API_URL=http://localhost:8080

# Correct
VITE_API_URL=http://localhost:8080/api
```

Service classes build paths relative to this base URL:

```ts
// With VITE_API_URL=http://localhost:8080/api
api.post('/token/refresh')  // → POST http://localhost:8080/api/token/refresh  ✓

// With VITE_API_URL=http://localhost:8080
api.post('/token/refresh')  // → POST http://localhost:8080/token/refresh       ✗ (404)
```

**Rule:** the env var owns the full base — service classes never prepend `/api`.

---

## Error Handling

### API errors in composables

```ts
onError: (error: unknown) => {
  const message =
    isAxiosError(error) && typeof error.response?.data?.error === 'string'
      ? error.response.data.error
      : 'Something went wrong. Please try again.'
  serverError.value = message
}
```

- Always use `isAxiosError()` — never `instanceof AxiosError` or unsafe casts
- Always check `typeof error.response?.data?.error === 'string'` before reading the message
- Always provide a generic fallback for unexpected error shapes
- Backend error responses follow the format: `{ "error": "message", "details": [...] }`

### Client-side validation in pages

- Use `computed` properties for real-time validation feedback
- Show validation errors only after the user has interacted with the field (check `value.length > 0`)
- Disable submit until the form is valid — never submit and rely only on server validation

---

## Testing

### Stack

- **Vitest** — test runner (configured via `vite.config.ts`)
- **Vue Test Utils** — component mounting and interaction
- **jsdom** — browser environment simulation
- **@vitest/coverage-v8** — coverage reporting

### Folder structure

Test files live in a `__tests__/` folder **next to their source file**:

```
src/
├── composables/
│   └── User/
│       ├── useLogin.ts
│       ├── useRegister.ts
│       └── __tests__/
│           ├── useLogin.spec.ts
│           └── useRegister.spec.ts
├── stores/
│   └── User/
│       ├── UserStore.ts
│       └── __tests__/
│           └── UserStore.spec.ts
├── pages/
│   └── User/
│       ├── LoginPage.vue
│       └── __tests__/
│           └── LoginPage.spec.ts
```

### What to test

| Layer | Test type | What to assert |
|---|---|---|
| Composables | Unit | Mutation/query callbacks (onSuccess, onError), navigation, returned refs |
| Stores | Unit | State changes, computed values, action side effects |
| Pages | Integration | Form submission, validation feedback, loading/error/empty states |
| Services | Do not test | Thin wrappers over Axios — tested indirectly through composables |

---

### Composable tests

Composable tests mock all external dependencies and capture TanStack Query callbacks to test them in isolation.

```ts
import { describe, it, expect, vi, beforeEach } from 'vitest'

// 1. Define mocks BEFORE vi.mock calls
const mockMutate = vi.fn()
const mockRouterPush = vi.fn()
let capturedOnSuccess: ((data: { access_token: string }) => void) | null = null
let capturedOnError: ((error: unknown) => void) | null = null

// 2. Mock all dependencies at module level
vi.mock('@tanstack/vue-query', () => ({
  useMutation: ({ onSuccess, onError }: {
    onSuccess: (data: { access_token: string }) => void
    onError: (error: unknown) => void
  }) => {
    capturedOnSuccess = onSuccess
    capturedOnError = onError
    return { mutate: mockMutate, isPending: { value: false }, isError: { value: false } }
  },
}))

vi.mock('@/services/User/UserApiService', () => ({
  UserApiService: { login: vi.fn() },
}))

vi.mock('@/stores/User/UserStore', () => ({
  useAuthStore: () => ({ setAccessToken: vi.fn() }),
}))

vi.mock('vue-router', () => ({
  useRouter: () => ({ push: mockRouterPush }),
  useRoute: () => ({ query: {} }),
}))

describe('useLogin', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    capturedOnSuccess = null
    capturedOnError = null
  })

  it('redirects to dashboard on successful login', async () => {
    const { useLogin } = await import('../useLogin')

    useLogin()
    capturedOnSuccess?.({ access_token: 'token123' })

    expect(mockRouterPush).toHaveBeenCalledWith({ name: 'dashboard' })
  })

  it('sets serverError on failed login', async () => {
    const { useLogin } = await import('../useLogin')

    const { serverError } = useLogin()
    capturedOnError?.(new Error('Network error'))

    expect(serverError.value).toBe('Invalid email or password.')
  })
})
```

#### Key patterns

- **`vi.mock()` at the top level** — before any imports. Vitest hoists these automatically
- **Capture callbacks** — store `onSuccess` and `onError` in mutable variables so you can call them directly
- **Dynamic import per test** — use `await import('../useLogin')` instead of a top-level import so module-level mocks are applied fresh
- **`vi.clearAllMocks()` in beforeEach** — reset all call counters and captured callbacks
- **`vi.stubEnv()`** — mock `import.meta.env` values without touching `.env` files:
  ```ts
  vi.stubEnv('VITE_ALLOWED_REDIRECT_ORIGINS', 'http://localhost:3002')
  ```
- **Mock `window.location`** for external redirect tests:
  ```ts
  Object.defineProperty(window, 'location', {
    writable: true,
    value: { href: '' },
  })
  ```

#### What to test in composables

| Scenario | Assert |
|---|---|
| Successful mutation | `onSuccess` navigates to the correct route |
| Successful mutation with store update | `onSuccess` calls `store.setAccessToken()` |
| Failed mutation with API error | `onError` extracts the server message and sets `serverError` |
| Failed mutation with network error | `onError` sets a generic fallback message |
| Security: redirect whitelist | Allowed origins pass, disallowed origins fall back to default |

---

### Store tests

Store tests create a fresh Pinia instance per test and verify state changes:

```ts
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { setActivePinia, createPinia } from 'pinia'

vi.mock('@/services/User/UserApiService', () => ({
  UserApiService: { logout: vi.fn().mockResolvedValue(undefined) },
  api: {
    defaults: { headers: { common: {} } },
  },
}))

vi.mock('vue-router', () => ({
  useRouter: () => ({ push: vi.fn() }),
}))

describe('useAuthStore', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    localStorage.clear()
  })

  it('setAccessToken updates state and localStorage', async () => {
    const { useAuthStore } = await import('../UserStore')
    const store = useAuthStore()

    store.setAccessToken('my-token')

    expect(store.accessToken).toBe('my-token')
    expect(store.isAuthenticated).toBe(true)
    expect(localStorage.getItem('access_token')).toBe('my-token')
  })

  it('clearAccessToken removes state and localStorage', async () => {
    const { useAuthStore } = await import('../UserStore')
    const store = useAuthStore()

    store.setAccessToken('my-token')
    store.clearAccessToken()

    expect(store.accessToken).toBeNull()
    expect(store.isAuthenticated).toBe(false)
    expect(localStorage.getItem('access_token')).toBeNull()
  })

  it('isAuthenticated is false when no token', async () => {
    const { useAuthStore } = await import('../UserStore')
    const store = useAuthStore()

    expect(store.isAuthenticated).toBe(false)
  })
})
```

#### Key patterns

- **`setActivePinia(createPinia())`** — fresh Pinia instance per test, no state leaks
- **`localStorage.clear()`** — the store reads from localStorage on init, so clear it in beforeEach
- **Mock api object** — prevent side effects on Axios default headers during tests

---

### Page tests (integration)

Page tests mount the full component and simulate user interaction:

```ts
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'

const mockMutate = vi.fn()

vi.mock('@/composables/User/useRegister', () => ({
  useRegister: () => ({
    mutate: mockMutate,
    isPending: { value: false },
    isError: { value: false },
    serverError: { value: null },
  }),
}))

describe('RegisterPage', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('submit button is disabled when form is empty', async () => {
    const { default: RegisterPage } = await import('../RegisterPage.vue')
    const wrapper = mount(RegisterPage, {
      global: { stubs: { 'router-link': true } },
    })

    const button = wrapper.find('button[type="submit"]')
    expect(button.attributes('disabled')).toBeDefined()
  })

  it('calls mutate with form data on valid submit', async () => {
    const { default: RegisterPage } = await import('../RegisterPage.vue')
    const wrapper = mount(RegisterPage, {
      global: { stubs: { 'router-link': true } },
    })

    await wrapper.find('#firstName').setValue('John')
    await wrapper.find('#lastName').setValue('Doe')
    await wrapper.find('#email').setValue('john@example.com')
    await wrapper.find('#password').setValue('Password1!')

    await wrapper.find('form').trigger('submit')
    await flushPromises()

    expect(mockMutate).toHaveBeenCalledWith({
      first_name: 'John',
      last_name: 'Doe',
      email: 'john@example.com',
      password: 'Password1!',
    })
  })

  it('shows password validation errors for weak password', async () => {
    const { default: RegisterPage } = await import('../RegisterPage.vue')
    const wrapper = mount(RegisterPage, {
      global: { stubs: { 'router-link': true } },
    })

    await wrapper.find('#password').setValue('weak')

    expect(wrapper.text()).toContain('At least 8 characters')
    expect(wrapper.text()).toContain('At least one uppercase letter')
    expect(wrapper.text()).toContain('At least one number')
  })

  it('does not call mutate when form is invalid', async () => {
    const { default: RegisterPage } = await import('../RegisterPage.vue')
    const wrapper = mount(RegisterPage, {
      global: { stubs: { 'router-link': true } },
    })

    await wrapper.find('#email').setValue('john@example.com')
    await wrapper.find('form').trigger('submit')

    expect(mockMutate).not.toHaveBeenCalled()
  })
})
```

#### Key patterns

- **Mock the composable, not the service** — pages don't touch services directly, so mock at the composable level
- **`global: { stubs: { 'router-link': true } }`** — stub router-link to avoid Vue Router warnings
- **`setValue()` + `trigger('submit')`** — simulate real user interaction
- **`flushPromises()`** — wait for all async operations to resolve before asserting
- **Dynamic import** — use `await import('../RegisterPage.vue')` to apply mocks correctly

#### What to test in pages

| Scenario | Assert |
|---|---|
| Empty form | Submit button is disabled |
| Valid form submission | `mutate` called with correct payload |
| Invalid form submission | `mutate` is NOT called |
| Client-side validation | Error messages appear for invalid fields |
| Server error display | Error message shown with `role="alert"` |
| Loading state | Button text changes and button is disabled during `isPending` |

---

### General rules

- **Mock service classes in composable tests** — never make real HTTP calls
- **Mock composables in page tests** — never test service logic through pages
- **Mock `useRouter` and `useRoute`** when testing navigation
- **Test error paths** — not just happy paths (network errors, invalid input, 401, 409, 422)
- **Never test service classes directly** — they are thin Axios wrappers, tested indirectly
- **Name test files** `{source}.spec.ts` — always `.spec.ts`, never `.test.ts`
- **One `describe` per composable/component** — multiple `it` blocks for scenarios
- **`vi.clearAllMocks()` in `beforeEach`** — always, no exceptions

### npm scripts

```json
{
  "test": "vitest run",
  "test:watch": "vitest",
  "test:coverage": "vitest run --coverage"
}
```

---

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
