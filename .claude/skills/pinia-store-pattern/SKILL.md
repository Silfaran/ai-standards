---
name: pinia-store-pattern
description: Use when creating or modifying a Pinia store — global state (auth tokens, user profile, app-wide settings, theme) — in a Vue 3 app. Covers the canonical setup-store shape, what belongs in a store vs. TanStack Query, destructuring rules, testing with `reactive()`, and the recurring mistakes that break reactivity or leak server state into client state.
paths: "**/src/stores/**/*.ts"
---

# Pinia stores — pattern and pitfalls

Pinia holds **global client state only**: auth tokens, current user profile, app-wide UI settings (theme, locale), cross-page flags. Server state — lists, entities fetched from an API — belongs in TanStack Query, not here.

The distinction matters: TanStack Query handles caching, refetching, invalidation, and stale-while-revalidate. Pinia has none of that. Storing a `boards` array in Pinia means you now own cache invalidation yourself — and you will get it wrong.

This skill is the canonical shape for a store plus the five mistakes that recur in review.

## Canonical shape — setup store

```ts
import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { AuthApiService, api } from '@/services/Auth/AuthApiService'

function decodeEmailFromToken(token: string): string {
  try {
    return JSON.parse(atob(token.split('.')[1])).email ?? ''
  } catch {
    return ''
  }
}

export const useAuthStore = defineStore('auth', () => {
  const accessToken = ref<string | null>(null)
  const userEmail = ref<string>('')
  const isLoading = ref(true)
  const router = useRouter()

  const isAuthenticated = computed(() => accessToken.value !== null)

  function setAccessToken(token: string): void {
    accessToken.value = token
    userEmail.value = decodeEmailFromToken(token)
    api.defaults.headers.common['Authorization'] = `Bearer ${token}`
  }

  function clearAccessToken(): void {
    accessToken.value = null
    userEmail.value = ''
    delete api.defaults.headers.common['Authorization']
  }

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
      router.push({ name: 'landing' })
    }
  }

  return {
    accessToken,
    userEmail,
    isAuthenticated,
    isLoading,
    setAccessToken,
    clearAccessToken,
    initialize,
    logout,
  }
})
```

## Rules

1. **Composition API only** — `defineStore('name', () => { ... })`. Never the options-API form. Setup stores get the full `<script setup>` ergonomics and play well with types.
2. **State is `ref()`, derived is `computed()`, actions are plain functions.** Do not declare actions as methods on an object — the setup form has no `this`.
3. **Store name is unique and lowercase** — `'auth'`, `'taskBoard'`, `'theme'`. It is the key in devtools and in persistence plugins.
4. **Return only what the template and callers need.** Internal helpers (like `decodeEmailFromToken` above) stay outside the factory, not in the returned object.
5. **Actions can call service classes directly** — `logout` calls `AuthApiService.logout()`. Stores are not forbidden from touching the network; they are forbidden from **holding** the network result as permanent state.
6. **No server lists in Pinia.** `boards`, `tasks`, `invitations` → TanStack Query. If you catch yourself writing `boards.value = await api.listBoards()` in a store, stop.

## What goes where

| Belongs in a Pinia store | Belongs in TanStack Query | Belongs in a composable |
|---|---|---|
| Access token (memory only) | Paginated list of boards | Form submission + `useMutation` |
| Current user's email, id | A single board by id | Local form validation |
| Theme (`'light'` / `'dark'`) | List of pending invitations | Navigation after success |
| App-wide modal flags (rare) | Activity feed | Debounced search input |
| `isLoading` during app bootstrap | Server-side filters | Toast/notification triggering |

If unsure: ask "does this come from the server?" Yes → TanStack Query. "Does it survive across routes and multiple components?" Yes → Pinia. Both true and you still want it in Pinia? You almost certainly don't.

## Auth state — specific constraints

- **Access token lives in memory only** — `ref<string | null>` in the store. Never `localStorage`, never `sessionStorage`. Persistence across reloads is done by calling `AuthApiService.refresh()` at boot, which returns a new access token from the HttpOnly refresh cookie.
- **`initialize()` is called once in `main.ts`** after `app.use(createPinia())` and before `app.mount('#app')`. Without this, the first render has no auth state.
- **Never expose `accessToken.value` directly to components** — components use `isAuthenticated` (computed) or the API interceptor that reads the token for the `Authorization` header.

See `jwt-security` skill for the full lifecycle.

## Destructuring — the trap

```ts
// ❌ Breaks reactivity — accessToken and isAuthenticated are now plain values
const { accessToken, isAuthenticated } = useAuthStore()

// ❌ Still breaks reactivity — spreading does the same
const auth = { ...useAuthStore() }

// ✅ Access through the store proxy
const authStore = useAuthStore()
console.log(authStore.isAuthenticated) // reactive

// ✅ Only actions (functions) are safe to destructure
const { logout, setAccessToken } = useAuthStore()

// ✅ If you really need individual refs, use storeToRefs
import { storeToRefs } from 'pinia'
const { isAuthenticated, userEmail } = storeToRefs(useAuthStore())
```

## Testing — the `reactive()` trap

Mocking a Pinia store in a component test is not a plain object. Components read `authStore.isLoading` expecting `Ref` auto-unwrapping — which only works for reactive objects.

```ts
// ❌ Template reads authStore.isLoading.value — no auto-unwrap
vi.mocked(useAuthStore).mockReturnValue({
  isLoading: ref(false),
  isAuthenticated: computed(() => true),
  logout: vi.fn(),
})

// ✅ Use reactive() to mimic the proxy
import { reactive, ref, computed } from 'vue'
vi.mocked(useAuthStore).mockReturnValue(reactive({
  isLoading: ref(false),
  isAuthenticated: computed(() => true),
  logout: vi.fn(),
}) as unknown as ReturnType<typeof useAuthStore>)
```

See `vitest-composable-test` skill for the full testing setup (Pinia + router + TanStack Query mocks).

## Folder and file conventions

```
src/stores/{Domain}/
├── AuthStore.ts
├── ThemeStore.ts
└── __tests__/
    └── AuthStore.spec.ts
```

- One file per store. `{Domain}Store.ts`, PascalCase.
- One store per `defineStore('name', ...)` call. Never two stores in the same file.
- Tests live alongside in `__tests__/`.

## Common mistakes

- **Storing server lists in Pinia.** Makes you re-implement TanStack Query badly. Move to `useXList()` composable backed by `useQuery`.
- **Destructuring reactive state** (`const { isLoading } = useAuthStore()`). Silently loses reactivity — the template never updates. Use `storeToRefs()` or access via proxy.
- **Using `localStorage` for the access token.** Violates the auth standard and exposes the token to XSS. Memory only; refresh flow handles persistence.
- **Forgetting `initialize()` in `main.ts`.** First page render shows unauthenticated state even when a valid refresh cookie exists. Always wire it before `app.mount`.
- **Not mocking with `reactive()`.** Tests pass in CI but the actual component binds to `.value` wrappers that never unwrap. Flakes and false negatives follow.
- **Putting mutation logic in the store** instead of a composable. Stores are state holders; mutations (login, register, create) live in composables with `useMutation`. Keeps the store small and the mutation logic testable in isolation.

## See also

- [`standards/frontend.md`](../../../standards/frontend.md) → "Stores (Pinia)" — the authoritative rules.
- [`standards/security.md`](../../../standards/security.md) → Authentication Token Storage — why the access token is memory-only.
- `vue-composable-mutation` skill — how to own write operations (not in the store).
- `vitest-composable-test` skill — Pinia mocking patterns for component tests.
- `jwt-security` skill — the auth lifecycle the store participates in.
