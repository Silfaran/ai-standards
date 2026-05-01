# Critical path — Public-facing deploy / hardening surface

Use when the diff configures the production-facing perimeter: response headers, CSP, cookie security, container build, dependency automation, secrets scanning, DAST. Almost every project's first deploy needs this path; subsequent diffs revisit it when a perimeter setting changes.

## When to load this path

**PRIMARY trigger** (load this path as core when):
- A new or modified CSP / HSTS / cookie / COOP / CORP header config
- A new `Dockerfile` or container hardening change (non-root, read-only fs)
- A new entry in CI for Dependabot, Renovate, Trivy, gitleaks, OWASP ZAP
- A first-time public deployment of a service (initial perimeter setup)
- A new outbound-webhook signing implementation or rotation

**SECONDARY trigger** (load only when no primary path covers the diff already):
- A new SBOM generation step
- A new anomaly metric (`auth_failures_total`, `csp_violations_total`, etc.)
- A new redirect-allowlist entry (`isAllowedRedirect()`)

**DO NOT load when**:
- The diff only modifies tests
- The diff only modifies `*.md`
- The service is exclusively internal (no public ingress, no perimeter-facing URLs)

## Backend

### Browser-side hardening
- AS-001 CSP emitted by the application (no `'unsafe-inline'`/`'unsafe-eval'`; per-request nonces; `frame-ancestors 'none'`; `report-uri /api/csp-report`)
- AS-002 HSTS `max-age=63072000; includeSubDomains` + HTTP→HTTPS redirect on port 80
- AS-003 Cookies `Secure; HttpOnly; SameSite=Lax` (or `Strict` for auth)
- AS-004 COOP `same-origin` + CORP `same-site`; COEP `require-corp` only after CSP enforcing

### Anti-attack patterns (always relevant on first deploy)
- AS-005 CSRF: cookie-auth SPAs verify Bearer or double-submit token; refresh endpoint always verifies CSRF
- AS-006 `SafeHttpClient` for any user-supplied URL — denies private/loopback/cloud-metadata IPs, pins resolved IP, bounds timeouts
- AS-014 Backend `?next=` / `?return_url=` validate via `isAllowedRedirect()`
- AS-015 Outbound webhooks signed (`X-Signature-256` HMAC + `X-Timestamp` + `X-Subscription-Id`); per-subscription secrets

### Auth-adjacent
- AS-011 Login / password-reset / magic-link return same body+status for "user not found" vs "wrong password"; response time normalised to a fixed budget
- AS-012 Per-account lockout COMBINED with per-IP rate-limit (SE-009..SE-012)
- AS-013 Bot-driving forms protected via invisible CAPTCHA / honeypot / proof-of-work — choice in `decisions.md`

### Injection (cross-cutting)
- AS-007 XML parsers configured with external entities disabled
- AS-008 No template-string-from-user-input rendering
- AS-009 No shell with user-derived input; `Process` with array-form args
- AS-010 No `unserialize` of untrusted input (BE-044 generalises)

### Supply chain & CI
- AS-016 Dependabot or Renovate enabled; `composer audit` / `npm audit` thresholds at `high`; `critical` blocks deploy
- AS-017 SBOM generated per release artifact (CycloneDX); signed alongside
- AS-018 Docker images pinned to immutable digests; Trivy scan via `scripts/project-checks/check-container-image.sh` blocks on HIGH/CRITICAL
- AS-019 Final images run as non-root, read-only root filesystem, tmpfs `/tmp`, build tools dropped via multi-stage
- AS-020 `gitleaks` via `scripts/project-checks/check-secrets-leaked.sh` runs in pre-commit + CI + nightly history scan

### Active scanning & observability
- AS-021 OWASP ZAP DAST runs against staging on every deploy; HIGH/CRITICAL block prod promotion
- AS-022 Anomaly metrics emitted (`auth_failures_total{reason}`, `csp_violations_total{directive}`, `safe_http_blocked_total{reason}`, `webhook_signature_invalid_total{provider}`, `audit_authz_denied_total{reason}`, `outbound_redirect_blocked_total`) — bounded labels
- AS-023 Failed-login logs use peppered `user_id_hash`, never email; IP follows PII classification

### Hard blockers (carried over)
- BE-001 Quality gates green
- SC-001 No secrets committed
- SE-001..SE-018 (existing security checklist for headers, CORS, JWT, rate-limit on auth)

## Frontend

- AS-024 Inline scripts/styles carry per-request CSP nonce injected by the build
- AS-025 CDN third-party scripts carry `integrity` (SRI) + `crossorigin="anonymous"`; drop the dep if no SHA published
- AS-026 No outbound URL from a user-supplied parameter without `isAllowedRedirect()` (SE-020 generalised)
- AS-027 CSP violations from `report-uri` treated as defects; `csp_violations_total` reviewed weekly

## Coverage map vs full checklist

This path covers these sections of `backend-review-checklist.md` / `frontend-review-checklist.md`:

- §Attack surface hardening — AS-001..AS-027 (browser hardening, anti-attack patterns, auth-adjacent, injection, supply chain, active scanning, frontend hardening)
- §Hard blockers — BE-001, SC-001, SE-001..SE-018 (existing security checklist for headers, CORS, JWT, rate-limit on auth)

This path does NOT cover. Load the corresponding checklist section ONLY when the diff touches:

- `tests/` directory → load §Testing
- A specific authentication flow change → load `auth-protected-action.md` (path) + §Security (SE-*)
- A specific inbound-webhook flow → load `payment-endpoint.md` or `signature-feature.md` (paths)
- Backend logging structure beyond LO-001 → load §Logging

## What this path does NOT cover

- Per-request authorization decisions → [`auth-protected-action.md`](auth-protected-action.md)
- Inbound webhook signing for PSPs / signature providers → [`payment-endpoint.md`](payment-endpoint.md), [`signature-feature.md`](signature-feature.md)
- PII classification / encryption → [`pii-write-endpoint.md`](pii-write-endpoint.md)
- Service worker caching strategies → [`pwa-surface.md`](pwa-surface.md)
