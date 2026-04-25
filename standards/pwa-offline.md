# PWA & Offline Standards

## Philosophy

- A Progressive Web App is a website that loads fast on a flaky network, behaves predictably without one, and reaches the user when something matters. The PWA toolbox (service worker, manifest, push) is in service of those three properties — not a feature box to tick.
- Offline is a UX state, not a free outcome. A page that breaks silently when the network drops is worse than one that says "you're offline; we'll sync when you reconnect". Treat connectivity loss the same way you treat 401: a state the user sees and can act on.
- The service worker is a **trust boundary**. It intercepts every same-origin request the browser makes for the app. A bug there is a production XSS vector or a stuck-stale-app incident. It deserves the same review rigor as a backend gateway.
- Push notifications are a contract with the user. They cost attention. The system asks for the right at the right moment, sends only what is consent-covered, and lets the user revoke without friction.
- Offline write support is hard. Adopt it deliberately for one or two surfaces; do not "make the whole app offline-capable" without the conflict-resolution and trust-boundary work that requires.

---

## When this standard applies

This standard applies when the product is delivered as a web app and:

- A meaningful portion of users access it from mobile networks with intermittent connectivity
- The product needs to be installable to the home screen (iOS, Android, desktop)
- The product wants to send push notifications outside open browser tabs
- A specific surface needs to function with stale or missing data (read-only offline) or accept user input that syncs later (offline writes)

If none is true, the project may stay as a standard SPA without engaging the service worker layer.

---

## Vocabulary

| Term | Meaning |
|---|---|
| **PWA** | Progressive Web App — a web app that meets installability criteria and enhances itself with service worker capabilities |
| **Service worker** | A script the browser registers under the app's origin; intercepts network requests; runs even when no tab is open |
| **App shell** | The minimal HTML + CSS + JS that renders the chrome of the app; cached aggressively so cold-start is instant |
| **Cache strategy** | The rule a service worker applies per request: `cache-first`, `network-first`, `stale-while-revalidate`, `network-only`, `cache-only` |
| **Manifest** | `manifest.webmanifest` — declares name, icons, start URL, display mode; what makes the app installable |
| **Push subscription** | An opaque token issued by the browser that identifies the user's device for push delivery; sent to the backend; revocable |
| **Background sync** | A service-worker capability to defer a network operation until connectivity returns |

---

## When to adopt PWA capabilities

The standard recognises four progressive levels. Pick the lowest level that meets the requirement; graduate when the requirement grows.

| Level | Adds | When to pick |
|---|---|---|
| **L0 — none** | Plain SPA, no service worker, no manifest | Internal admin tools, surfaces accessed only from corporate desktops |
| **L1 — installable** | Manifest + offline page (a single static "you're offline" route); service worker that caches the app shell | Public web app where users may land repeatedly; "install" is a discovery surface |
| **L2 — read-offline** | L1 + cached read responses for selected APIs (stale-while-revalidate); UI surfaces serve cached data with a "stale as of X" badge | Browse-heavy products where users navigate while connectivity hiccups (training catalogs, news, professional directories) |
| **L3 — write-offline + push** | L2 + background sync for queued mutations + push notifications | Field/manual-trade workflows where the user fills forms in low-coverage areas; messaging-heavy products |

Graduating L0 → L1 → L2 → L3 each adds operational complexity. L3 in particular introduces conflict resolution that needs server-side schema discipline (vector clocks, last-writer-wins per field, CRDT-shaped fields). Skip L3 unless the product hard-requires it.

---

## The service worker setup

Use Workbox (the de-facto standard, well-supported by Vite via `vite-plugin-pwa`). The service worker is generated at build time from a config — never hand-rolled per route.

```ts
// vite.config.ts
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  plugins: [
    VitePWA({
      registerType: 'autoUpdate',
      injectRegister: 'auto',
      strategies: 'generateSW',
      manifest: { /* see Manifest section */ },
      workbox: {
        globPatterns: ['**/*.{js,css,html,svg,png,webp,woff2}'],
        navigateFallback: '/index.html',
        navigateFallbackDenylist: [/^\/api\//, /^\/admin\//],
        runtimeCaching: [
          // see Cache strategies below
        ],
      },
    }),
  ],
})
```

Rules:

- The service worker is **regenerated on every build**. Hand-edited service workers are forbidden — they drift from the build pipeline and produce stuck-stale-app incidents.
- `registerType: 'autoUpdate'` so users get the new SW within minutes; the orchestrating UI prompts the user when an update is ready (see "Update flow" below).
- The `navigateFallbackDenylist` excludes API and admin paths so the SW does not intercept dynamic responses with an HTML shell.
- The SW is registered in `main.ts` only after the app shell has rendered — a SW that fails to register MUST NOT block first paint.

---

## Cache strategies

Each request type gets a strategy. The default for a new project:

| Request | Strategy | Reasoning |
|---|---|---|
| App shell (HTML + JS + CSS) | `precache + cacheFirst` | Same content per build; aggressive caching makes cold start instant |
| Versioned assets (`/assets/*.{js,css,woff2,png,svg}`) | `cacheFirst, immutable` | Vite emits hashed filenames; a content change is a new URL |
| Public images served by CDN (`assets.example.com/*`) | `staleWhileRevalidate` | Tolerate slightly stale, refresh in background |
| API GET responses for selected resources | `staleWhileRevalidate` with TTL | Snappy navigation; eventual consistency the user can see |
| API GET responses for personal/private data | `networkFirst` with short timeout | Freshness wins; fall back to cache only on offline |
| API mutations (POST/PUT/PATCH/DELETE) | `networkOnly` (with optional background sync at L3) | Never serve a write from cache |
| Authentication endpoints | `networkOnly` | Always; no caching, no offline replay |
| Webhooks the SW happens to see | `networkOnly` | They are not for the browser at all |

Rules:

- Cache buckets are versioned (`workbox-cache-v${BUILD_HASH}`) — old caches are dropped on activation.
- Per-bucket size and entry caps are explicit (`maxEntries`, `maxAgeSeconds`). An unbounded cache eventually fills the user's quota and the browser evicts unpredictably.
- `networkFirst` with a `networkTimeoutSeconds: 3` — long timeouts on a flaky network produce a hung UI.

---

## The Manifest

```json
{
  "name": "Red de Profesionales",
  "short_name": "Red Pro",
  "start_url": "/?source=pwa",
  "scope": "/",
  "display": "standalone",
  "orientation": "portrait",
  "theme_color": "#0F172A",
  "background_color": "#FFFFFF",
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png" },
    { "src": "/icons/icon-maskable.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ],
  "categories": ["productivity"],
  "lang": "es"
}
```

Rules:

- `start_url` includes `?source=pwa` (or equivalent) — the application can attribute installs in analytics.
- Icons cover the install requirements: 192/512 standard + a maskable 512.
- `display: standalone` (or `minimal-ui`) — full-screen feel, but expose a back button surface in the UI itself.
- `lang` matches the project's source locale; the negotiated locale at runtime overrides for content (see `i18n.md`).
- Icons NEVER include user-generated content.

---

## Update flow (versioning the live app)

A SW update should never be silent for installed PWAs — the user may be mid-flow with stale code.

```ts
// composables/useServiceWorkerUpdate.ts
import { useRegisterSW } from 'virtual:pwa-register/vue'

export function useServiceWorkerUpdate() {
  const { needRefresh, updateServiceWorker } = useRegisterSW({
    onNeedRefresh() {
      // surface a toast: "New version available — refresh"
    },
  })
  return { needRefresh, refresh: () => updateServiceWorker(true) }
}
```

Rules:

- A `needRefresh` event prompts the user with a non-modal banner. The user clicks `Refresh`; the SW activates; the page reloads.
- A user that ignores the banner gets a polite reminder on the next session.
- An emergency revocation (the live SW is broken) is achieved by deploying a SW that unregisters itself + clears all caches + reloads. Document this kill-switch in runbooks.

---

## Offline reads (L2)

A surface that supports offline reading:

1. Declares its routes and TanStack Query keys to a `useOfflineCache(...)` composable.
2. The composable persists those query results to IndexedDB on every successful fetch.
3. On render, the composable reads from IndexedDB before issuing the fetch (`placeholderData`); if offline, the fetch fails gracefully and the UI shows "stale as of X minutes ago" alongside the data.
4. Any field marked sensitive in the project's PII inventory is OPTED OUT of the offline cache — the composable refuses to persist it (validated against the inventory at build time).

Rules:

- Offline reads MUST display the staleness ("Last updated 12 minutes ago"). Silent stale data is a UX defect.
- Authorization is re-applied on the next online fetch — a cached read that the user has lost permission to is re-checked and removed.
- Cached responses respect the original `Cache-Control: private` (`caching.md` CA-002) — a public-cache strategy on a private endpoint is a leak.

---

## Offline writes (L3)

L3 is opt-in per surface. The pattern:

1. The form submit creates an "intent" (a typed object with the operation and its inputs) and stores it in IndexedDB.
2. A background sync registration triggers when the network returns.
3. The service worker drains the queue, posting the intents in order, with idempotency keys (per `payments-and-money.md` PA-005 — the Idempotency-Key concept generalises beyond payments).
4. Conflict on the server (the resource changed since the user's view) returns a structured response; the UI surfaces the conflict to the user with the server's current state and the user's pending intent.

Rules:

- Every offline-eligible mutation has a documented conflict-resolution policy (`last-writer-wins`, `merge per field`, `manual reconciliation`). The policy is part of the spec; ad-hoc resolution is forbidden.
- Idempotency on the server is mandatory — an intent retried after the server already accepted it MUST NOT double-apply.
- Sensitive operations (payments, RTBF, role grants, anything with audit-log significance) are NOT eligible for offline writes — they require the user be online and the synchronous-audit pattern (`audit-log.md` AU-006) to hold.

---

## Push notifications

Push is a permission surface and a sub-processor. It needs explicit consent and a documented purpose.

### Consent flow

- The browser API (`Notification.requestPermission()`) is called only in response to a user gesture AND only after the user has seen a meaningful explanation of what they will receive.
- Pre-prompts ("would you like to enable notifications?") are presented in-app first; the browser API runs only when the user clicks "Yes".
- Denials are remembered in user preferences for 90+ days; the system does not re-prompt on every visit.
- Consent is per purpose (transactional, marketing, mention-and-reply) — a single "yes" does not authorize all categories.

### Subscription lifecycle

- Push subscriptions (`PushSubscription` JSON) are sent to the backend and stored per user-device.
- On revocation (the user disables notifications), the backend marks the subscription `revoked` and stops sending; subscriptions returning 410 from the push provider are auto-pruned.
- Subscriptions older than 30 days without delivery activity are re-validated; expired ones removed.

### Sending

- Payloads sent via web push are SHORT and NEVER include Sensitive-PII (`gdpr-pii.md` GD-005). The notification text references; the app fetches the full content when the user opens it.
- Every push send is rate-limited per user (per category) to prevent fatigue.
- Categories are documented; users see them in settings; the category gates the send.

### Audit

- Push consent grants/withdrawals produce `audit-log.md` entries (`push.consent.granted`, `push.consent.withdrawn`) per category.
- Push sends are logged in operational logs (`logging.md`), NOT audit (volume is too high) — but per-user counts are exposed as metrics.

---

## Privacy & PII

The PWA layer adds new risks because it persists data on the device.

Rules:

- IndexedDB and Cache Storage are NOT secure storage. The SW MUST NOT persist Sensitive-PII (per `gdpr-pii.md` GD-005). The build validates the offline-cache config against `pii-inventory.md`.
- The user's device is not the user — a shared computer may surface the cached data to a different person. A logout flow MUST clear the SW caches and the IndexedDB store of identified data. The composable provides `clearOfflineCacheForLogout()`.
- A request that lands in the SW with an `Authorization` header for a different user (the user changed accounts) MUST drop the cached responses for the previous identity.

---

## Observability

The service worker is a fertile source of silent failures (broken cache, stuck stale, registration errors). Make it noisy.

| Metric | Labels | Purpose |
|---|---|---|
| `sw_registration_total` | `outcome` | Catches registration-failure spikes |
| `sw_cache_hits_total` | `bucket`, `strategy` | Cache effectiveness |
| `sw_cache_evictions_total` | `bucket`, `reason` | Quota / age / version eviction |
| `sw_offline_reads_total` | `route_class` | Visibility into how often offline reads serve users |
| `sw_offline_intent_queued_total` | `intent_class` | L3 only |
| `sw_offline_intent_synced_total` | `intent_class`, `outcome` | L3 only — `outcome` includes `conflict` |
| `push_subscription_active_total` | `category`, gauge | Reach |
| `push_send_total` | `category`, `outcome` | Delivery |
| `push_send_failures_total` | `category`, `error_class` | Provider issues |

Span events on the navigation span (per `observability.md`):

- `sw.update_available` when the user is on stale code
- `sw.cache_hit` / `sw.cache_miss` per request (when sampled — high volume)
- `offline.read` when the response came from cache without network
- `offline.write_queued` when an intent was deferred

---

## Anti-patterns (auto-reject in review)

- A hand-edited service worker — generated by the build only.
- A `cacheFirst` strategy on a private API endpoint.
- A `navigateFallback` that catches `/api/*`.
- An IndexedDB store containing `Sensitive-PII` per the project's inventory.
- Push prompts on first page load with no in-app pre-prompt.
- A push payload with the user's email, address, payment instrument, or any other Sensitive-PII.
- Offline writes for actions that have audit-log significance (payments, role grants, RTBF).
- A SW update flow that auto-reloads the page mid-flow without the user's consent.
- Caches with no `maxEntries` / `maxAgeSeconds`.
- A logout that does not clear SW caches + IndexedDB of identified data.
- Push subscriptions stored without an `audit-log.md`-tracked consent grant.

---

## What the reviewer checks

PWA rules are enforced during review via the frontend reviewer checklist (see [`frontend-review-checklist.md`](frontend-review-checklist.md) → "PWA & offline") and the backend reviewer checklist (see [`backend-review-checklist.md`](backend-review-checklist.md) → "PWA & push") for push subscription storage, idempotency on offline-write endpoints, and consent audit.
