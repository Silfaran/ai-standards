---
name: vitest-composable-test
description: Use when writing or debugging Vitest tests for Vue 3 composables, Pinia stores, or page components — covering TanStack Query mocking, Pinia setup, vue-router stubs, captured onSuccess/onError callbacks, jsdom shims (matchMedia), and dynamic imports for fresh mocks.
paths: "**/__tests__/**/*.spec.ts, **/*.spec.ts"
---

# Vitest testing patterns — composables, stores, pages

The non-obvious parts of this test suite are: mocks must be declared before imports, TanStack Query callbacks are captured, mutable variables are used to reach them, and each test dynamically re-imports the module under test to pick up the latest mocks.

Get these patterns right and tests are fast and reliable. Get them wrong and you get flakes, stale mocks, and `ReferenceError: Cannot access 'mock' before initialization`.

## Stack

- **Vitest** — runner (configured in `vite.config.ts`).
- **Vue Test Utils** — `mount` + interaction helpers.
- **jsdom** — browser environment simulation.
- Coverage via `@vitest/coverage-v8`.

## What to test (and what NOT to)

| Layer | Test type | What to assert |
|---|---|---|
| Composables | Unit | Mutation/query callbacks, navigation, returned refs |
| Stores | Unit | State changes, computed values, action side effects |
| Pages | Integration | Form submission, validation feedback, loading/error states |
| Services | **Do not test** | Thin wrappers over Axios — tested indirectly |

## Universal rules

- `vi.mock()` at the **top level**, before any imports. Vitest hoists these automatically.
- `vi.clearAllMocks()` in `beforeEach()` — always.
- Dynamic import per test (`await import('../useLogin')`) to apply mocks fresh.
- Capture callbacks in **mutable module-level variables** so each test can invoke them directly.
- **Name test files** `{source}.spec.ts`. Put them in `__tests__/` next to the source.

## Composable test — full template

```ts
import { describe, it, expect, vi, beforeEach } from 'vitest'

// 1. Declare mock refs BEFORE vi.mock calls
const mockMutate = vi.fn()
const mockRouterPush = vi.fn()
let capturedOnSuccess: ((data: { access_token: string }) => void) | null = null
let capturedOnError: ((error: unknown) => void) | null = null

// 2. Mock everything at module level — vitest hoists these above imports
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

### Key tricks

- **Captured callbacks** — `capturedOnSuccess` / `capturedOnError` are module-level mutable refs set inside the `useMutation` mock. Each test calls them directly to simulate success/failure.
- **Dynamic import** — `await import('../useLogin')` is required so the module resolves **after** the mocks are registered.
- **`vi.stubEnv()`** — when a composable reads `import.meta.env`, stub it in the test instead of touching `.env` files.

## Store test — full template

```ts
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { setActivePinia, createPinia } from 'pinia'

vi.mock('@/services/User/UserApiService', () => ({
  UserApiService: { logout: vi.fn().mockResolvedValue(undefined) },
  api: { defaults: { headers: { common: {} } } },
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
})
```

### Key tricks

- **`setActivePinia(createPinia())`** in `beforeEach` — fresh Pinia instance per test.
- **`localStorage.clear()`** — the store reads from `localStorage` on init.
- **Mock the `api` object** — prevents side effects on Axios default headers across tests.
- **When mocking a store that a template accesses via the proxy**, use `reactive()`. A plain object with `ref()` values will NOT auto-unwrap.

## Page test — full template

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
  beforeEach(() => { vi.clearAllMocks() })

  it('calls mutate with form data on valid submit', async () => {
    const { default: RegisterPage } = await import('../RegisterPage.vue')
    const wrapper = mount(RegisterPage, {
      global: { stubs: { 'router-link': true } },
    })

    await wrapper.find('#firstName').setValue('John')
    await wrapper.find('#email').setValue('john@example.com')
    await wrapper.find('#password').setValue('Password1!')
    await wrapper.find('form').trigger('submit')
    await flushPromises()

    expect(mockMutate).toHaveBeenCalledWith({
      first_name: 'John', last_name: '', email: 'john@example.com', password: 'Password1!',
    })
  })
})
```

### Key tricks

- **Mock the composable, never the service** — pages don't touch services directly.
- **`stubs: { 'router-link': true }`** — stub `router-link` to avoid unresolved component warnings.
- **`setValue()` + `trigger('submit')`** — simulate real user interaction.
- **`flushPromises()`** — wait for async operations before asserting.

## jsdom shims that are easy to forget

jsdom does not implement every browser API. Add shims in `src/test-setup.ts`:

```ts
// matchMedia — needed for prefers-reduced-motion and shadcn theme helpers
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: (query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  }),
})

// ApexCharts or similar canvas-based libs — stub if imported at module load
vi.mock('vue3-apexcharts', () => ({ default: { name: 'ApexChart', render: () => null } }))
```

Components that read `prefers-reduced-motion` crash in Vitest without the `matchMedia` shim.

## Common failures and fixes

| Symptom | Cause | Fix |
|---|---|---|
| `ReferenceError: Cannot access 'x' before initialization` inside `vi.mock` | Using a non-hoisted variable inside the factory | Declare mock refs as `let` / `const` at module top, NOT inside the factory |
| Mocks don't apply | Importing the module-under-test statically | Use `await import('../file')` inside each test |
| `prefers-reduced-motion` crash | Missing jsdom shim | Add `matchMedia` shim to `src/test-setup.ts` |
| Pinia store test sees leaked state | Missing `setActivePinia(createPinia())` | Add it to `beforeEach` |
| Template accesses store value but sees `undefined` | Mocked store uses plain `ref()`s, not `reactive()` | Wrap the mock in `reactive({...})` |

## See also

- [standards/frontend.md](../../../standards/frontend.md) — testing rules in concise form.
- [standards/frontend-reference.md](../../../standards/frontend-reference.md) — the authoritative test examples these patterns come from.
- [standards/lessons-learned.md](../../../standards/lessons-learned.md) — Frontend Developer entry on the `matchMedia` crash.
- `vue-composable-mutation` skill — what the composables under test look like.
