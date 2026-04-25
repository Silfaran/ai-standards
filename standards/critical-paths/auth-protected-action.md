# Critical path — Authorization-protected action

Use when the diff adds an action that requires a Voter check, role gating, or tenant scoping. Almost every server-side action that mutates state matches this path.

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

## What this path does NOT cover

This path is almost always combined with another. Add:
- The CRUD scaffolding around the protected action → [`crud-endpoint.md`](crud-endpoint.md)
- PII writes → [`pii-write-endpoint.md`](pii-write-endpoint.md)
- Money / payments → [`payment-endpoint.md`](payment-endpoint.md)
- File downloads gated by Voter → [`file-upload-feature.md`](file-upload-feature.md)
