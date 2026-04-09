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

## Axios and Interceptors

- Never import the store inside a service file — circular dependency risk
- Set up Axios interceptors in a dedicated `src/services/setupInterceptors.ts`
- Call `setupInterceptors()` from `main.ts` after `app.use(createPinia())`
- Use `isAxiosError` from axios for type-safe error handling — never use unsafe casts
- Base URL from environment variable (e.g. `VITE_API_URL`)

## Component Rules

- Always use `<script setup lang="ts">` — no Options API
- Keep pages thin — delegate all logic to composables
- Composables own mutations/queries via TanStack Query
- Never call backend APIs directly from components — always through a service class
- Extract reusable logic into composables — never duplicate API call logic
- Always handle loading, error and empty states in the UI
- Always implement responsive design
- Follow basic accessibility standards (semantic HTML, aria attributes where needed)

## State Management

- Pinia stores for global state only
- `useAuthStore` pattern: access token in memory + localStorage; sets Authorization header on Axios

## Routing

- Route meta: `requiresAuth: true` / `requiresGuest: true`
- Navigation guards handle redirects — components never check auth directly

## Standard Libraries

| Purpose | Library |
|---|---|
| HTTP client | `axios` |
| Server state (queries/mutations) | `@tanstack/vue-query` |
| Global state | `pinia` |
| Routing | `vue-router` |
| UI components | `shadcn-vue` |
| Form validation | `vee-validate` + `zod` |
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
