# Critical path — CRUD endpoint

Use when the diff adds a controller + handler + repository (and optionally a frontend service + composable + page) for a non-sensitive aggregate. Combine with other paths for cross-cutting concerns (auth, PII, files, payments).

## Backend

### Hard blockers
- BE-001 Quality gates green
- BE-002 PHPStan L9 zero errors
- BE-003 PHP-CS-Fixer zero violations
- SE-001 No string concatenation in SQL
- SE-004 No internal details in error responses
- SC-001 No secrets committed
- LO-001 No unredacted sensitive fields in logs
- DM-001 Migrations append-only

### Architecture
- BE-004 Folder layout Domain/Application/Infrastructure
- BE-005 Commands and queries separated
- BE-006 Handlers call services / repositories directly
- BE-007 Services expose one public `execute` method
- BE-008 Service placement (Domain vs Application)
- BE-009 Doctrine / MessageBus → Application
- BE-010 Services declared `readonly class`
- BE-013 Services inject repository INTERFACES
- BE-022 Domain has zero Symfony / Doctrine imports
- BE-023 Aggregates use `static create()` / `static from()`
- BE-024 VOs / commands / queries use `private __construct` + `static from()`

### Controllers
- BE-025 Extends `AppController`
- BE-026 One controller per command/query
- BE-027 Only `dispatchCommand()` / `dispatchQuery()`
- BE-028 No business validation in controllers
- BE-029 Type-guard the request
- BE-030 400 / 422 status codes match
- AC-001 OpenAPI annotations
- BE-032 Buses injected by name in `services.yaml`

### Validation layering
- BE-033 Structural validation in controller
- BE-034 Business invariants in VOs
- BE-035 Domain exceptions mapped in `ApiExceptionSubscriber`
- BE-036 Match arms exhaustive
- BE-037 No domain exception returns 500

### Database & migrations
- BE-038 PK is `id UUID DEFAULT gen_random_uuid()`
- BE-039 Snake_case for tables and columns
- PE-001 Index for every WHERE / ORDER BY / UUID reference
- BE-040 No FK constraints (no-FK ADR)
- BE-041 Each service owns its DB
- BE-042 Phinx seeds added per aggregate

### Repositories & queries
- PE-003 Multi-row methods accept `int $limit, int $offset`
- PE-004 No N+1 (batch via `IN (...)`)
- PE-005 SELECT only required columns
- SE-005 No raw SQL string interpolation

### API responses
- AC-002 List endpoints accept `?page=`/`?per_page=`
- AC-003 List response envelope `{ data, meta }`
- AC-004 Status codes match
- AC-005 Error body shape

### Naming & testing
- BE-061 Classes PascalCase, methods camelCase
- BE-062 API payload fields snake_case
- BE-064 `CreateXxxCommand` / `Handler` naming
- BE-055 Integration test per controller
- BE-057 Tests assert HTTP + DB state
- BE-067 Definition of Done items checked

## Frontend (when the diff includes UI)

### Hard blockers
- FE-001 Quality gates CI green
- FE-004 No `any`

### Architecture
- FE-005 HTTP only in `services/{Domain}/*ApiService.ts`
- FE-007 Composables own logic; pages thin
- FE-009 Server data → TanStack Query, not Pinia

### API & state
- FE-017 One Axios `api` per domain
- FE-019 Service methods return unwrapped data
- AC-014 Snake_case payload fields
- FE-020 Mutations / queries via TanStack Query
- FE-023 Errors via `isAxiosError()`

### UX states
- FE-036 Loading state shown
- FE-037 Error state with `role="alert"`
- FE-038 Empty state handled
- FE-039 Submit disabled when invalid or pending
- FE-040 `@submit.prevent`

## What this path does NOT cover

Open additional paths when the diff also touches:
- Authorization → [`auth-protected-action.md`](auth-protected-action.md) (any non-public endpoint)
- Personal data → [`pii-write-endpoint.md`](pii-write-endpoint.md)
- File uploads → [`file-upload-feature.md`](file-upload-feature.md)
- Money → [`payment-endpoint.md`](payment-endpoint.md)
- LLM calls → [`llm-feature.md`](llm-feature.md)
- Geo / search → [`geo-search-feature.md`](geo-search-feature.md)
- Signed documents → [`signature-feature.md`](signature-feature.md)
- Service worker / push → [`pwa-surface.md`](pwa-surface.md)
