---
name: vue-composable-mutation
description: Use when implementing a Vue 3 composable that performs a write operation with TanStack Query's useMutation — login, register, create, update, delete flows — including error handling, navigation after success, and server-error state exposed to the page.
paths: "**/src/composables/**/*.ts, **/composables/**/*.ts"
---

# Vue composables for mutations (write operations)

Composables own **all** feature-level logic: the mutation itself, the error extraction, the navigation. Pages are thin templates that call composables and render state. This separation is non-negotiable in this project.

## Shape of a mutation composable

```ts
import { ref } from 'vue'
import { isAxiosError } from 'axios'
import { useMutation } from '@tanstack/vue-query'
import { useRouter } from 'vue-router'
import { UserApiService } from '@/services/User/UserApiService'
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

## Rules

1. **Navigation lives in `onSuccess`** — never in the page. The page should not know where the app goes next.
2. **Error state is a `ref<string | null>`** named `serverError`. Reset at mutation start only if the UX needs it.
3. **Always use `isAxiosError()`** — never `instanceof AxiosError`, never unsafe casts.
4. **Always provide a fallback error message** — server error shapes are not guaranteed.
5. **Expose only what the template needs** — `mutate`, `isPending`, `isError`, `serverError`. Never return the full TanStack Query object.
6. **Methods return unwrapped data or void** at the service layer — the composable never calls Axios directly.

## Folder and file conventions

```
src/composables/{Domain}/
├── useRegister.ts
├── useLogin.ts
└── __tests__/
    ├── useRegister.spec.ts
    └── useLogin.spec.ts
```

- One composable per feature. No god composables.
- Named `use{Verb}{Noun}`, camelCase. Examples: `useRegister`, `useLogin`, `useUpdateTask`, `useDeleteBoard`.
- All parameters and return types explicitly typed — no inferred `any`.

## Queries (reads) — same pattern, different hook

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

- Query keys are **descriptive arrays**: `['tasks']`, `['task', taskId]`. Never strings.
- Reads never live in stores — TanStack Query owns server state. See [frontend.md](../../../standards/frontend.md).

## What belongs in the page, not here

| Belongs in page | Belongs in composable |
|---|---|
| Template state (`firstName = ref('')`) | Mutation call and navigation |
| `isFormValid` computed for template-local validation | Server error extraction |
| `handleSubmit()` that trims/maps form state → payload | API shape, auth header handling |
| Showing `serverError` with `role="alert"` | Setting `serverError` from the error |

## Common mistakes

- **Calling `router.push` in the page** on successful submit — move it to `onSuccess`.
- **Throwing instead of setting `serverError`** — errors surface via the `ref`, not via thrown exceptions. TanStack Query would otherwise re-throw and crash the render.
- **Exposing `mutateAsync`** — prefer `mutate` for fire-and-forget. Only expose async variants when the page genuinely needs to `await`.
- **Destructuring reactive state from a store inside a composable** — breaks reactivity. Access via the store proxy (`authStore.isAuthenticated`).
- **Making two network calls from one composable** without a reason — if you need sequencing, compose two smaller composables.

## Testing

Tests for composables live in `__tests__/` next to the source. They mock `@tanstack/vue-query` and capture `onSuccess`/`onError` to call them directly. See the `vitest-composable-test` skill for the patterns.

## See also

- [standards/frontend.md](../../../standards/frontend.md) — concise frontend rules, including composable conventions.
- [standards/frontend-reference.md](../../../standards/frontend-reference.md) — full examples (mutation, query, store, page).
- `vitest-composable-test` skill — the test patterns for this composable shape.
- `jwt-security` skill — where token handling hooks into the auth composable and store.
