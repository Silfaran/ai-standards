# Critical path — PWA surface

Use when the diff configures the service worker, manifest, offline behaviour, push notifications, or any IndexedDB / Cache Storage write. Mostly frontend; the backend rules cover push subscription storage and offline-write idempotency.

## Frontend

### Service worker
- PW-001 SW generated at build time via `vite-plugin-pwa` (Workbox `generateSW`); hand-edited SW forbidden
- PW-002 `navigateFallbackDenylist` excludes `/api/`, `/admin/`
- PW-003 Cache strategies match the recommended table per request kind
- PW-004 Each runtime cache bucket declares explicit `maxEntries` AND `maxAgeSeconds`
- PW-006 SW registers AFTER app shell renders — never blocks first paint

### Manifest
- PW-005 Manifest declares full install set (name, short_name, start_url with attribution, scope, display, icons 192/512/maskable, lang)

### Update flow
- PW-007 Update flow uses `useServiceWorkerUpdate` non-modal banner — never auto-reloads mid-flow

### Privacy in offline storage
- PW-008 IndexedDB / Cache Storage NEVER persist Sensitive-PII (validated against `pii-inventory.md` at build)
- PW-009 Logout clears SW caches AND IndexedDB stores of identified data
- PW-011 Cached private responses respect `Cache-Control: private` (CA-002)

### Offline reads / writes
- PW-010 Offline reads display staleness ("Last updated X minutes ago")
- PW-012 Offline writes (L3) use intent objects with idempotency keys; sensitive ops NOT eligible
- PW-013 Conflict policy declared per L3 mutation in spec

### Push consent
- PW-014 `Notification.requestPermission()` only after in-app pre-prompt explaining categories — first-load prompts forbidden
- PW-015 Consent per category audited (`audit-log.md`); denials remembered ≥ 90 days
- PW-016 Push payloads SHORT, no Sensitive-PII

## Backend (push + offline-intent endpoints)

- PW-017 Push subscriptions stored per user-device; 410 responses auto-prune; 30-day inactive re-validate
- PW-018 Push send endpoints rate-limit per user per category
- PW-019 Push payloads never include Sensitive-PII (server-side construction)
- PW-020 Offline-write intent endpoints implement deterministic idempotency (PA-005); 409 on conflicts
- PW-021 Push consent grants/withdrawals produce audit entries (`push.consent.granted` / `push.consent.withdrawn`); consent ledger gates sends

### Hard blockers
- BE-001 Quality gates green (backend changes)
- FE-001 Quality gates CI green (frontend changes)
- LO-001 No unredacted sensitive fields in logs

## What this path does NOT cover

- Authorization on offline-write endpoints → [`auth-protected-action.md`](auth-protected-action.md)
- PII rules on push payloads → [`pii-write-endpoint.md`](pii-write-endpoint.md) (GD-005, GD-019)
- Signed media cached by the SW → [`file-upload-feature.md`](file-upload-feature.md)
