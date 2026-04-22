---
name: empty-loading-error-states
description: Use when writing or reviewing a Vue 3 page (or component) that renders server data fetched with TanStack Query — to ensure the three non-negotiable UI states are implemented consistently: loading (skeleton or spinner), error (with retry and role="alert"), and empty (distinct empty-set vs filtered-empty copy). Applies whenever a page uses `isLoading`/`isError`/a list response from a composable.
paths: "**/src/pages/**/*.vue, **/src/components/**/*.vue"
---

# Loading / error / empty states for data-driven pages

Every page that renders server state has three states the happy path does not cover: data is loading, data fetch failed, the result set is empty. Missing any of the three is a visible bug — a spinner that never appears, an empty grid with no explanation, an error that crashes silently.

This skill is the canonical shape. The Frontend Reviewer verifies it against the frontend review checklist.

## Canonical template structure

```vue
<script setup lang="ts">
import { useBoards } from '@/composables/Board/useBoards'
import { Loader2 } from 'lucide-vue-next'
import BoardCard from '@/components/Board/BoardCard.vue'
import { Button } from '@/components/ui/button'

const { data: boards, isLoading, isError, refetch } = useBoards()
</script>

<template>
  <!-- 1. LOADING -->
  <div v-if="isLoading" class="flex items-center justify-center py-16" data-testid="boards-loading">
    <Loader2 class="h-10 w-10 animate-spin text-primary" />
  </div>

  <!-- 2. ERROR -->
  <div
    v-else-if="isError"
    role="alert"
    class="flex flex-col items-center justify-center gap-4 py-16"
    data-testid="boards-error"
  >
    <p class="text-lg text-destructive">Failed to load boards. Please try again.</p>
    <Button variant="outline" @click="refetch()">Retry</Button>
  </div>

  <!-- 3a. EMPTY — no results for a filter/search -->
  <div
    v-else-if="boards.length === 0 && searchQuery"
    class="flex flex-col items-center justify-center py-16"
    data-testid="boards-empty-filtered"
  >
    <p class="text-lg text-muted-foreground">No boards match your search.</p>
  </div>

  <!-- 3b. EMPTY — no data at all, first-time user -->
  <div
    v-else-if="boards.length === 0"
    class="flex flex-col items-center justify-center gap-4 py-16"
    data-testid="boards-empty-initial"
  >
    <p class="text-lg text-muted-foreground">No boards yet. Create your first one!</p>
    <Button @click="showCreateForm = true">+ New Board</Button>
  </div>

  <!-- 4. HAPPY PATH -->
  <div v-else class="grid grid-cols-3 gap-4" data-testid="boards-grid">
    <BoardCard v-for="board in boards" :key="board.id" :board="board" />
  </div>
</template>
```

## Rules

1. **Always three (or four) branches in this order.** `v-if="isLoading"` → `v-else-if="isError"` → `v-else-if="empty"` → `v-else` happy path. Never ship a page that collapses two branches into one (e.g. showing the grid while loading).
2. **Distinguish "no data at all" from "filter returned nothing".** Same empty-set arithmetic, completely different UX. First-time users need a CTA; filter-empty users need "clear your filter" or just the empty copy. Two separate `v-else-if` branches, two separate `data-testid` values.
3. **Error state carries `role="alert"`** so screen readers announce it. Always offer a retry path — either `refetch()` from TanStack Query or a page reload.
4. **Loading state uses a skeleton for content pages, a spinner for actions.** A list of cards → skeleton cards with the same layout. A form submission → spinner on the button. Never show a blank page for more than ~200 ms.
5. **Never show `isLoading` and the empty state at the same time.** The empty check runs **after** `isLoading` and `isError` are both false. Order matters — a wrong order flashes "No boards yet!" during the first render while data is still in flight.
6. **The happy-path branch uses `v-else`** — never re-test a condition. That is what makes the state machine exhaustive.

## Skeleton vs spinner — quick pick

| Situation | Use |
|---|---|
| Page-level data load (list, detail, dashboard) | Skeleton matching final layout |
| Short operation (form submit, button action) | Spinner on the triggering button |
| Background refetch with stale data on screen | No indicator; let TanStack Query's `isFetching` be silent unless > 1 s |
| Full-page auth check at boot | Full-viewport spinner or app shell |

## Copy conventions

- **Loading:** no copy. The spinner or skeleton is the signal.
- **Error:** one sentence stating the failure in user terms ("Failed to load boards") + a retry button. Never expose the error message from the server; use a generic fallback. (Detailed errors go to logs, not the UI.)
- **Empty (first-time):** action-oriented — "No boards yet. Create your first one!" paired with the CTA that unblocks them.
- **Empty (filtered):** descriptive — "No boards match your search." No CTA needed; the filter bar is still on screen.

## What belongs in the composable, not the page

The composable owns `isLoading`, `isError`, `data`, and `refetch`. The page **reads** these refs. If you find yourself reassigning them from the page, you are putting feature logic where it doesn't belong — see `vue-composable-mutation`.

## Testing

Every branch needs a test. Use `data-testid` to target each state — never rely on text content, which will drift with copy.

```ts
it('shows the loading spinner while fetching', async () => {
  vi.mocked(useBoards).mockReturnValue({ data: ref([]), isLoading: ref(true), isError: ref(false), refetch: vi.fn() })
  const wrapper = mount(BoardsPage)
  expect(wrapper.find('[data-testid="boards-loading"]').exists()).toBe(true)
})

it('shows the empty-initial state with a CTA when the list is empty', async () => {
  vi.mocked(useBoards).mockReturnValue({ data: ref([]), isLoading: ref(false), isError: ref(false), refetch: vi.fn() })
  const wrapper = mount(BoardsPage)
  expect(wrapper.find('[data-testid="boards-empty-initial"]').exists()).toBe(true)
  expect(wrapper.find('[data-testid="boards-empty-initial"] button').text()).toContain('New Board')
})
```

See `vitest-composable-test` skill for mocking composables.

## Common mistakes

- **Collapsing all empty cases into one branch.** `v-else-if="!boards.length"` loses the distinction between "user has no data" and "filter eliminated all data". They need different copy.
- **Showing the empty state before the loader resolves.** Happens when the branch order is `empty → loading → happy`. Always check `isLoading` first.
- **Error state without retry.** A user who sees "Failed to load" with no action has to reload the page manually. Unacceptable.
- **Surfacing the server error verbatim.** `"Error: NetworkError at http://..."` leaks infrastructure and confuses users. Generic fallback only.
- **No `data-testid`.** The Tester agent will have to select by text, tests will drift on the next copy change, the skill's test examples will not apply.
- **Skeleton that doesn't match final layout.** A skeleton with one big gray block while the final page renders a grid of cards creates a visible "jump" on load. Mirror the final layout.

## See also

- [`standards/frontend.md`](../../../standards/frontend.md) → "Pages (Route Components)" — loading/error/empty are listed as page-level requirements.
- [`standards/frontend-review-checklist.md`](../../../standards/frontend-review-checklist.md) — the Frontend Reviewer verifies all three states are present per page.
- `vue-composable-mutation` skill — how `isLoading`/`isError` are exposed from composables.
- `vitest-composable-test` skill — testing each state branch.
- `shadcn-vue-component-add` skill — for installing a `Skeleton` component if the service doesn't yet have one.
