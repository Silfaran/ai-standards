# Critical path — Authorization-protected action

Use when the diff adds an action that requires a Voter check, role gating, or tenant scoping. Almost every server-side action that mutates state matches this path.

## When to load this path

**PRIMARY trigger** (load this path as core when):
- The diff adds a new Voter under `src/Domain/Authorization/Voter/`
- The diff adds a new handler that mutates state (Command handler) on a tenant-scoped aggregate
- The diff adds a `Subject` field to a new Command/Query
- The diff adds `tenant_id UUID NOT NULL` to a new table

**SECONDARY trigger** (load only when no primary path covers the diff already):
- A new route guard with `meta.requiresAuth` / `meta.requiresRoles` in the frontend router
- A 403 path / role-gated UI component in Vue
- An endpoint that previously was public becoming gated

**DO NOT load when**:
- The diff only modifies tests
- The diff only modifies `*.md`
- The endpoint is genuinely public (no Voter, no role gate, no tenant scope) — verify in the spec before skipping

## Backend

### Authorization (the core of this path)
- AZ-001 Every protected handler calls a Voter before any side effect
- AZ-002 Multi-tenant repositories take `tenantId` as first parameter
- AZ-003 Voters in `src/Domain/Authorization/Voter/`, return bool, no I/O
- AZ-004 `Subject` VO built once in controller, propagated as field of every Command/Query
- AZ-005 Multi-tenant tables declare `tenant_id UUID NOT NULL` leading every relevant index
- AZ-006 Cross-tenant denials return 404 (preferred) or 403
- AZ-007 403 body never includes denial reason / role names / resource metadata
- AZ-008 Authorization denials emit span event + `authz_denied_total` metric (no PII labels)
- AZ-009 Tests for allowed path + denied-by-role + denied-by-tenant
- AZ-010 Service-to-service Subjects use `tenantId='shared'` + `service:*` role
- AZ-011 Authorization decisions NEVER cached
- AZ-012 `Subject` is immutable

### Audit (denials and successful sensitive actions both audit)
- AU-006 Audit write in same DB transaction as state change
- AU-007 Entries on success AND denial; failures emit `outcome=failed`
- AU-008 Voter denial path produces audit entry

### Hard blockers carried over
- BE-001 Quality gates green
- SE-001 No string concatenation in SQL
- LO-001 No unredacted sensitive fields in logs

## Frontend (when the action is reachable from UI)

### Authorization
- AZ-013 Route guards check `meta.requiresAuth` / `meta.requiresRoles`
- AZ-014 UI gating presentation-only; backend ALWAYS re-checks
- AZ-015 Roles never in `localStorage`
- AZ-016 403 treated as a UX state, never silently swallowed

## Coverage map vs full checklist

This path covers these sections of `backend-review-checklist.md` / `frontend-review-checklist.md`:

- §Authorization — AZ-001..AZ-012 (Voter, Subject, tenant scoping, audit on denial)
- §Audit (denials and successful sensitive actions) — AU-006..AU-008
- §Hard blockers (carried over) — BE-001, SE-001, LO-001
- §Frontend Authorization — AZ-013..AZ-016 (route guards, role-gated UI, 403 UX)

This path does NOT cover. Load the corresponding checklist section ONLY when the diff touches:

- `tests/` directory → load §Testing
- Database schema (new tables, columns, migrations beyond `tenant_id` add) → load §Database + §Migrations
- Logging beyond LO-001 → load §Logging
- Audit beyond AU-006..AU-008 (retention, schema, projections) → load §Audit (full)

## What this path does NOT cover

This path is almost always combined with another. Add:
- The CRUD scaffolding around the protected action → [`crud-endpoint.md`](crud-endpoint.md)
- PII writes → [`pii-write-endpoint.md`](pii-write-endpoint.md)
- Money / payments → [`payment-endpoint.md`](payment-endpoint.md)
- File downloads gated by Voter → [`file-upload-feature.md`](file-upload-feature.md)
