# Attack Surface Hardening Standards

## Philosophy

- The attacker is patient, automated, and unimpressed with your test coverage. The system survives by reducing what the attacker can reach AND by making each reachable surface costly to abuse.
- Defence is layered. A CSP that blocks an XSS, a CSRF token that blocks the same XSS turning into a state change, an audit log that detects the third attempt, a rate limiter that slows the fourth — each is independently insufficient and collectively effective.
- The framework cannot guarantee security; it can guarantee that omitting a known control is visible. Every rule in this file is verifiable on a diff or in CI; nothing relies on "remember to think about security".
- Security work that is purely policy ("we will pen-test annually") belongs in `runbooks.md` (when shipped) — this standard is for code- and CI-enforceable controls.
- This standard complements `security.md` (HTTP headers, CORS, JWT, input validation, rate-limit on auth), `authorization.md` (Voter, Subject, tenant scoping), `secrets.md` (manifest, injection), `gdpr-pii.md` (data classification, encryption). It does not replace them.

---

## When this standard applies

This standard applies to every project the moment it is reachable from the public internet — staging or production. Internal-only admin tools may relax some rules; the relaxation is recorded as an ADR.

It is the controls layer for the attacker-facing perimeter, organised loosely by OWASP Top 10 (2021) plus the supply-chain and operational angles OWASP does not cover well.

---

## Vocabulary

| Term | Meaning |
|---|---|
| **CSP** | Content Security Policy — a response header that declares which origins the browser may load scripts/styles/etc from. Reduces the blast radius of XSS to "almost zero" when strict |
| **HSTS** | HTTP Strict-Transport-Security — a header that tells browsers to refuse plain HTTP for the domain for N seconds |
| **CSRF** | Cross-Site Request Forgery — an attacker tricks a logged-in user's browser into issuing a state-changing request |
| **SSRF** | Server-Side Request Forgery — the application is tricked into issuing a request to an attacker-chosen URL (often internal) |
| **XXE** | XML External Entity — XML parser is tricked into loading external data, typically `file:///etc/passwd` |
| **SSTI** | Server-Side Template Injection — user input is rendered as a template expression |
| **DAST** | Dynamic Application Security Testing — black-box scan of a running app (e.g. OWASP ZAP) |
| **SCA** | Software Composition Analysis — automated audit of dependency vulnerabilities |
| **SBOM** | Software Bill of Materials — machine-readable list of every dependency, version, license, transitive included |

---

## OWASP Top 10 — coverage map

This file's purpose is to make explicit which standard covers which OWASP category, and to fill the gaps that none of the existing standards covers.

| OWASP 2021 | Primary cover | Gap filled here |
|---|---|---|
| A01 Broken Access Control | `authorization.md` (Voter + Subject + tenant scoping) | Mandatory `Vary: Cookie` + 4xx-cache rules below |
| A02 Cryptographic Failures | `secrets.md`, `gdpr-pii.md` (encryption-at-rest) | TLS / HSTS / cookie security below |
| A03 Injection | `backend-review-checklist.md` (SE-001, SE-005, BE-029) + `security.md` (input validation) | XXE, SSTI, command injection, deserialization patterns below |
| A04 Insecure Design | Spec process + ADR framework | DAST + threat-model template (deferred — see `runbooks.md` plan) |
| A05 Security Misconfiguration | `security.md` (headers) | CSP, HSTS, COOP/COEP/CORP, secure cookies below |
| A06 Vulnerable & Outdated Components | `quality-gates.md` (`composer audit`, `npm audit`) | SCA automation (Dependabot/Renovate) + SBOM + container image scan below |
| A07 Identification & Authentication Failures | `security.md` (JWT, rate-limit on auth) | Username enumeration, account lockout, bot protection below |
| A08 Software & Data Integrity Failures | `data-migrations.md`, `payments-and-money.md` (idempotent webhooks) | Supply chain pinning + outbound webhook signing below |
| A09 Security Logging & Monitoring Failures | `logging.md`, `audit-log.md`, `observability.md` | Anomaly metrics + DAST in CI below |
| A10 Server-Side Request Forgery | Not currently covered | SSRF rules below — major gap closer for any app with file uploads, geo lookups, LLM URL fetch, webhook subscribers |

---

## Browser-side hardening

### Content Security Policy (CSP)

Every HTML response from a public-facing endpoint MUST emit a `Content-Security-Policy` header. The policy is constructed once per project, recorded in `{project-docs}/csp-policy.md`, and shipped from the application (not from the reverse proxy) so it stays in version control.

Default baseline for an SPA:

```http
Content-Security-Policy:
  default-src 'self';
  script-src 'self' 'nonce-{request-nonce}';
  style-src 'self' 'nonce-{request-nonce}';
  img-src 'self' data: https://{cdn-host};
  font-src 'self' https://{cdn-host};
  connect-src 'self' https://{api-host};
  frame-ancestors 'none';
  form-action 'self';
  base-uri 'none';
  object-src 'none';
  upgrade-insecure-requests;
  report-uri /api/csp-report;
```

Rules:

- `'unsafe-inline'` and `'unsafe-eval'` are FORBIDDEN. If a library requires them, replace the library or wrap it.
- Nonces are generated per-request (cryptographic, single-use). The frontend build pipeline injects them into inline scripts/styles.
- `frame-ancestors 'none'` is the modern equivalent of `X-Frame-Options: DENY` and takes precedence — both headers MAY be sent for legacy browsers, with values matching.
- `report-uri` (or `report-to`) sends violations to a `/api/csp-report` endpoint. The endpoint logs structurally and rate-limits per-IP — a flood of reports is itself a signal.
- Migration path: ship as `Content-Security-Policy-Report-Only` first, observe violations for 1-2 weeks, fix them, then promote to enforcing.

### HSTS + transport security

```http
Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
```

Rules:

- `max-age` is two years (`63072000`) once the policy is stable. Start at one week (`604800`) on first deploy to allow rollback.
- `includeSubDomains` is mandatory once every subdomain serves HTTPS.
- `preload` is added only after the domain is submitted to <https://hstspreload.org/> — the directive without submission is a no-op.
- HTTP requests on port 80 redirect to HTTPS; the redirect is the ONLY response served on port 80 (no app rendering, no headers).
- All cookies set by the application carry `Secure; HttpOnly; SameSite=Lax` (or `Strict` for auth cookies). `SameSite=None` requires `Secure` and an explicit reason in `decisions.md`.

### Cross-Origin isolation headers

Public-facing pages SHOULD emit, in this order:

```http
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
Cross-Origin-Resource-Policy: same-site
```

Rules:

- `COOP: same-origin` isolates the page from cross-origin tab access. Mandatory for any page that handles auth or money.
- `COEP: require-corp` is required to enable powerful APIs (`SharedArrayBuffer`, high-resolution timers); it forces every loaded resource to opt in via `CORP` or CORS. Add only after CSP is enforcing — it breaks third-party embeds otherwise.
- `CORP: same-site` is the per-resource counterpart on the responses the application serves.

---

## CSRF

A SPA backed by cookie-based sessions (refresh cookie per `security.md`) MUST defend against CSRF on every state-changing endpoint.

Defaults:

- All cookies use `SameSite=Lax` (or `Strict` for auth) — modern browsers reject most cross-site requests carrying them automatically.
- Every state-changing endpoint (POST / PUT / PATCH / DELETE) requires either a `Bearer` access token in `Authorization` (which CSRF cannot supply) OR a CSRF token mirrored from a cookie (double-submit pattern).
- The token is rotated on every login and on every privilege change.

If the application uses Bearer-only access tokens and refresh-cookie pairs (per `security.md` JWT rules), the CSRF risk is dominated by the refresh endpoint — and the refresh endpoint MUST verify a CSRF token in addition to the cookie.

---

## SSRF — server-side request forgery

Major gap for applications with **any** of: avatar fetch by URL, OAuth profile pictures, webhook subscriber URLs (the customer provides the URL), LLM tool calls that hit arbitrary URLs, geo lookups by address, RSS / opengraph / link previews.

Every outbound HTTP call from server code that involves a user-supplied URL MUST go through a `SafeHttpClient` that:

1. Resolves the host name once and asserts the IP is NOT in:
   - RFC 1918 private ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
   - Loopback (127.0.0.0/8, ::1)
   - Link-local (169.254.0.0/16)
   - Cloud metadata (169.254.169.254, fd00:ec2::254)
   - The configured deny-list of internal CIDR ranges (`SAFE_HTTP_DENY_CIDRS` in secrets manifest)
2. Pins the resolved IP for the duration of the call (DNS rebinding protection).
3. Disallows redirects that change protocol (https → http) or that point at a denied IP after re-resolution.
4. Enforces a connect timeout ≤ 5s and a total timeout ≤ 30s.
5. Logs the destination as `outbound.url.host` (NOT the full URL, which may contain tokens).

Direct use of Symfony's `HttpClientInterface` for user-supplied URLs is a HARD reject in review — wrap it in `SafeHttpClient` or refuse the use case.

---

## Injection (beyond SQL)

`security.md` and the backend checklist (SE-001, SE-005, BE-029) cover SQL and validation. The rest:

### XML / XXE

- Every XML parser is configured with `LIBXML_NONET | LIBXML_NOENT_OFF` (or the equivalent in the project's parser).
- `libxml_disable_entity_loader(true)` is set globally in the application bootstrap (PHP < 8 only — ignored on modern PHP where it is the default).
- Accepting XML on an API endpoint requires an ADR — JSON is the default contract.

### SSTI

- Twig / Blade / Vue templates NEVER receive untrusted input as a template string. The renderer takes the template name + a context array of values.
- `eval`, `Function(...)`, `setTimeout('string')`, `vm.runInNewContext` are FORBIDDEN unless the input is developer-authored AND code-reviewed; the use case is documented as ADR.

### Command injection

- `exec()`, `system()`, `passthru()`, `popen()`, backtick operators are FORBIDDEN with any user-derived data on the command line.
- When a shell command is unavoidable, use `Symfony\Component\Process\Process` with array-form arguments (which uses `execvp`, not a shell) — not the string form.

### Deserialization

- `unserialize()` of untrusted input is FORBIDDEN — the precedent in `backend.md` (BE-044 — Messenger transports use `messenger.transport.symfony_serializer`, never `PhpSerializer`) generalises here.
- JSON-only on the wire; YAML / Pickle / Java-style serialization not used for inter-service communication.

---

## Authentication-adjacent attacks

### Username enumeration

- Login, password reset, and "magic link" endpoints respond with the SAME body and HTTP status whether the user exists or not.
- Account creation MAY differ ("email already in use") only when the legal basis for the disclosure is compelling (B2B onboarding); otherwise show "we sent a confirmation if the email is valid".
- Timing differences are also enumeration. The handler MUST normalise its response time to a fixed budget (`min_response_time_ms` from config; pad with `usleep()` if the real path was faster).

### Account lockout vs lockless rate-limit

- Per-account lockout (5 failed attempts → lock for 15 min) is COMBINED with per-IP rate-limit (per `security.md` SE-009..SE-012). Per-account alone is bypassed by botnets; per-IP alone is bypassed by credential-stuffing single-shot per IP.
- Lockout state lives in a fast cache (Redis) with a TTL.
- Lockout produces an `audit-log.md` entry (`auth.account.locked`) AND a metric (`auth_lockouts_total`).

### Bot protection

- Forms that drive cost (registration, password reset, contact, content publication) MUST have either an invisible CAPTCHA (Turnstile, hCaptcha, reCAPTCHA Enterprise) OR a server-side proof-of-work / honeypot field.
- The choice is per surface, recorded in `decisions.md`. CAPTCHAs are user-hostile; use them where automation cost is the dominant defence.

---

## Open redirect (backend equivalent)

- Endpoints that issue `Location` headers based on user input (`?next=`, `?return_url=`) MUST validate the URL via `isAllowedRedirect()` — same allowlist semantics as `SE-020` on the frontend.
- The allowlist is the project's own origins + a documented external-origin set.
- A redirect to a non-allowed URL returns 422 with `error: "redirect_target_not_allowed"`.

---

## Outbound webhook signing

When the application SENDS webhooks to subscribers (the inverse of the inbound webhooks already covered by `payments-and-money.md` PA-006 and `digital-signature-integration.md` DS-010), each request is signed:

```
X-Signature-256: hmac-sha256({secret}, body)
X-Timestamp: {unix-seconds}
X-Subscription-Id: {sub-id}
```

Rules:

- The signing secret is per-subscription (one secret per subscriber URL), generated at subscription time and stored hashed at rest. The plaintext is shown to the subscriber once on creation, then never again.
- Receivers verify the signature on the RAW body within a 5-minute clock window — older requests are rejected.
- The application MUST publish a verification recipe in the public docs (one example per language).

---

## Supply chain

### Dependency vulnerability automation

- Dependabot (or Renovate) is enabled per repository, configured to open weekly grouped PRs for minor/patch bumps and per-vulnerability PRs for critical advisories.
- `composer audit --no-dev` is in CI per `quality-gates.md` (already there). Threshold is `high`. A `critical` advisory is a HARD reject regardless of patch availability — block deploy until a workaround exists.
- `npm audit --omit=dev --audit-level=high` is in CI (already there). Same `critical` rule.

### SBOM

- Every release artifact (Docker image, distributable build) ships with an SBOM in CycloneDX format generated by `composer cyclonedx` (PHP) and `@cyclonedx/cyclonedx-npm` (JS).
- The SBOM lives next to the artifact (`<artifact>.cdx.json`) and is signed alongside it.

### Container image security

- Base images are pinned to immutable digests (`@sha256:...`), not floating tags (`:latest`, `:22`). Bumping the base is a code change reviewed like any other.
- Trivy (`trivy image --severity HIGH,CRITICAL --exit-code 1`) scans every built image in CI. A `CRITICAL` finding fails the build.
- Final images run as a non-root user (`USER 1000:1000` or app-specific UID), with a read-only root filesystem and tmpfs for `/tmp`.
- `apt-get install` and `apk add` lines pin specific versions; multi-stage builds drop build tools (`build-essential`, `node`, `composer` binary) from the final layer.

### Secrets scanning

- `gitleaks` (or `trufflehog`) runs:
  - Pre-commit hook (fast subset).
  - CI on every push (full repo scan).
  - Nightly cron on `master` against the full git history (catches accidentally committed historical secrets).
- A finding fails CI; remediation requires rotation per `secrets.md`.

The `scripts/project-checks/check-secrets-leaked.sh` wrapper runs gitleaks against the working tree with the project's allowlist file.

---

## Active scanning (DAST)

OWASP ZAP runs against the staging environment after every deploy. The job:

1. Loads the staging URL.
2. Authenticates via a known test account.
3. Crawls + actively scans (limited time budget, 10 minutes typical).
4. Reports findings; HIGH or CRITICAL fail the deploy promotion to prod.

The DAST profile is committed in the repo (`security/zap-baseline.yaml`) and reviewed when surfaces change. A surface that opts out of scanning has the opt-out recorded in `decisions.md`.

---

## Anomaly observability

Some attack patterns are only visible in aggregate. The following metrics surface them:

| Metric | Spike pattern | What it indicates |
|---|---|---|
| `auth_failures_total{reason}` | Sustained rise in `wrong_password` | Credential stuffing |
| `auth_lockouts_total` | Sustained rise | Brute-force or stuffing slipped past per-IP limit |
| `csp_violations_total{directive}` | Spike on a single directive | Either a real XSS or a benign third-party regression |
| `safe_http_blocked_total{reason}` | Any non-zero | Active SSRF attempts |
| `webhook_signature_invalid_total{provider}` | Sustained rise | Replay or spoof attempt against inbound webhooks |
| `audit_authz_denied_total{reason="cross_tenant"}` | Spike | Active scanning of tenant boundaries |
| `outbound_redirect_blocked_total` | Any non-zero | Open redirect probes |

Each metric has a default alert in `observability.md` SLO shape (when the alert template ships).

---

## Logging discipline (specific to attack signals)

Per `logging.md` redaction rules. In addition:

- Failed login attempts log the username only as a peppered hash (`user_id_hash`), never the email. Otherwise the log itself becomes an enumeration oracle.
- IP addresses logged on auth/anomaly events MUST follow the project's PII classification (typically Internal-PII per `gdpr-pii.md`) — redacted on export, retained in raw form for investigations.
- A 4xx response cited in an alert ALWAYS includes the `trace_id` of the original request — investigators need to pivot to the full trace, not the masked log line.

---

## Anti-patterns (auto-reject in review)

- A response with no `Content-Security-Policy` header on a public-facing HTML endpoint.
- A `Content-Security-Policy` containing `'unsafe-inline'` or `'unsafe-eval'`.
- Missing `Strict-Transport-Security`, `Cross-Origin-Opener-Policy`, or `Cross-Origin-Resource-Policy` on a public production deploy.
- Cookies without `Secure; HttpOnly` on auth-related sessions.
- A direct call to `HttpClientInterface->request()` with a user-supplied URL — must go through `SafeHttpClient`.
- `unserialize($_REQUEST[...])` or any deserialization of untrusted input.
- `exec($shellCmd)` / `system(...)` with concatenated user input.
- Different HTTP status or response body for "user not found" vs "wrong password".
- A redirect to a `?return_url=` value without `isAllowedRedirect()` validation.
- An outbound webhook without HMAC signature header.
- A Docker `FROM` line with a floating tag (`:latest`, `:22`) in production.
- A build that ships without the Trivy or gitleaks step in CI.

---

## What the reviewer checks

Hardening rules are enforced during review via the backend reviewer checklist (see [`backend-review-checklist.md`](backend-review-checklist.md) → "Attack surface hardening") and the frontend reviewer checklist (see [`frontend-review-checklist.md`](frontend-review-checklist.md) → "Attack surface hardening"). The checklists are the authoritative surface — if a rule appears here and not in the checklist, file a minor and update the checklist in the same commit.

## Automated drift detection

The supply-chain and secrets-scanning controls have CI helpers in [`../scripts/project-checks/`](../scripts/project-checks/) — `check-secrets-leaked.sh` (gitleaks wrapper) and `check-container-image.sh` (Trivy wrapper). See [`quality-gates.md`](quality-gates.md) → "Drift validators (consuming projects)".
