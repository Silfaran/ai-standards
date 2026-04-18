# Frontend Reference

> This file contains detailed code examples and full configurations.
> Read this file only when you need to implement a new pattern or scaffold a component for the first time.
> For rules and conventions, read `frontend.md`.

---

## Service Class Example

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

---

## Axios Interceptor Implementation

File: `src/services/setupInterceptors.ts`

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

---

## Composable Example (Mutation)

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

## Composable Example (Query)

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

---

## Store Example

```ts
import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { AuthApiService, api } from '@/services/Auth/AuthApiService'
import { useRouter } from 'vue-router'

export const useAuthStore = defineStore('auth', () => {
  const accessToken = ref<string | null>(null)
  const isLoading = ref(true)
  const router = useRouter()

  const isAuthenticated = computed(() => accessToken.value !== null)

  function setAccessToken(token: string): void {
    accessToken.value = token
    api.defaults.headers.common['Authorization'] = `Bearer ${token}`
  }

  function clearAccessToken(): void {
    accessToken.value = null
    delete api.defaults.headers.common['Authorization']
  }

  // Silent refresh on boot — the HttpOnly cookie bootstraps the session.
  async function initialize(): Promise<void> {
    isLoading.value = true
    try {
      const token = await AuthApiService.refresh()
      setAccessToken(token)
    } catch {
      clearAccessToken()
    } finally {
      isLoading.value = false
    }
  }

  async function logout(): Promise<void> {
    try {
      await AuthApiService.logout()
    } finally {
      clearAccessToken()
      router.push({ name: 'login' })
    }
  }

  return { accessToken, isAuthenticated, isLoading, setAccessToken, clearAccessToken, initialize, logout }
})
```

**Never read or write `localStorage` for the access token in any frontend.** Persistence across reloads is achieved via `initialize()` calling the refresh endpoint — the cookie is the persistence layer, not `localStorage`.

---

## Page Example

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

---

## Routing Configuration

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

**Order matters:** interceptors call `useAuthStore()`, which requires Pinia to be installed.

---

## TypeScript Types Example

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

---

## Redirect Validation

```ts
function isAllowedRedirect(url: string): boolean {
  const allowed = (import.meta.env.VITE_ALLOWED_REDIRECT_ORIGINS ?? '')
    .split(',')
    .map((o: string) => o.trim())
    .filter(Boolean)

  try {
    const { origin } = new URL(url)
    return allowed.includes(origin)
  } catch {
    return false
  }
}
```

---

## Composable Test Example

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

### Key patterns

- **`vi.mock()` at the top level** — before any imports. Vitest hoists these automatically
- **Capture callbacks** — store `onSuccess` and `onError` in mutable variables so you can call them directly
- **Dynamic import per test** — use `await import('../useLogin')` so module-level mocks are applied fresh
- **`vi.clearAllMocks()` in beforeEach** — reset all call counters and captured callbacks
- **`vi.stubEnv()`** — mock `import.meta.env` values without touching `.env` files
- **Mock `window.location`** for external redirect tests

### What to test in composables

| Scenario | Assert |
|---|---|
| Successful mutation | `onSuccess` navigates to the correct route |
| Successful mutation with store update | `onSuccess` calls `store.setAccessToken()` |
| Failed mutation with API error | `onError` extracts the server message and sets `serverError` |
| Failed mutation with network error | `onError` sets a generic fallback message |
| Security: redirect whitelist | Allowed origins pass, disallowed origins fall back to default |

---

## Store Test Example

```ts
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { setActivePinia, createPinia } from 'pinia'

vi.mock('@/services/Auth/AuthApiService', () => ({
  AuthApiService: {
    refresh: vi.fn(),
    logout: vi.fn().mockResolvedValue(undefined),
  },
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
    vi.clearAllMocks()
  })

  it('setAccessToken updates state and Axios header, never touches localStorage', async () => {
    const { useAuthStore } = await import('../AuthStore')
    const store = useAuthStore()

    store.setAccessToken('my-token')

    expect(store.accessToken).toBe('my-token')
    expect(store.isAuthenticated).toBe(true)
    expect(localStorage.getItem('access_token')).toBeNull()
  })

  it('initialize loads token from silent refresh on boot', async () => {
    const { AuthApiService } = await import('@/services/Auth/AuthApiService')
    vi.mocked(AuthApiService.refresh).mockResolvedValue('fresh-token')

    const { useAuthStore } = await import('../AuthStore')
    const store = useAuthStore()
    await store.initialize()

    expect(store.accessToken).toBe('fresh-token')
    expect(store.isAuthenticated).toBe(true)
    expect(store.isLoading).toBe(false)
  })

  it('initialize clears the store when refresh fails', async () => {
    const { AuthApiService } = await import('@/services/Auth/AuthApiService')
    vi.mocked(AuthApiService.refresh).mockRejectedValue(new Error('401'))

    const { useAuthStore } = await import('../AuthStore')
    const store = useAuthStore()
    await store.initialize()

    expect(store.accessToken).toBeNull()
    expect(store.isAuthenticated).toBe(false)
    expect(store.isLoading).toBe(false)
  })
})
```

### Key patterns

- **`setActivePinia(createPinia())`** — fresh Pinia instance per test
- **Never assert on `localStorage` for the access token** — it must not be written there; a `localStorage.getItem('access_token')` returning anything non-null is a bug
- **Mock the refresh endpoint** — `initialize()` drives the bootstrap, success AND failure paths must be covered
- **Mock api object** — prevent side effects on Axios default headers
- **When mocking a store whose properties a template accesses via the proxy, use `reactive()`** — a plain object with `ref()` values won't auto-unwrap

---

## Page Test Example

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
})
```

### Key patterns

- **Mock the composable, not the service** — pages don't touch services directly
- **`global: { stubs: { 'router-link': true } }`** — stub router-link to avoid warnings
- **`setValue()` + `trigger('submit')`** — simulate real user interaction
- **`flushPromises()`** — wait for async operations before asserting
- **Dynamic import** — `await import('../RegisterPage.vue')` to apply mocks correctly

### What to test in pages

| Scenario | Assert |
|---|---|
| Empty form | Submit button is disabled |
| Valid form submission | `mutate` called with correct payload |
| Invalid form submission | `mutate` is NOT called |
| Client-side validation | Error messages appear for invalid fields |
| Server error display | Error message shown with `role="alert"` |
| Loading state | Button text changes and button is disabled during `isPending` |
