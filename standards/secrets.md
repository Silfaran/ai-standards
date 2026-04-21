# Secrets Standards

## Philosophy

- A secret is any value whose leak changes the security posture of the system. Classify first, protect second — an unclassified value is an unprotected value.
- Secrets are never committed, never baked into images, never echoed in CI logs. `invariants.md` is the absolute floor; this standard defines how secrets flow at runtime.
- Dev, staging and prod never share secrets. A secret leak in one environment never becomes a leak in another.
- Every secret has a documented owner, a documented injection path, and a stated rotation policy. If any of the three is missing, the secret is not production-ready.
- Rules here are enforceable by reading the code and the deployment configuration — they are about manifests, injection paths and redaction, not about choice of cloud provider.

---

## What counts as a secret (closed list)

Any value matching the categories below is treated as a secret, regardless of where it appears or how "innocuous" it looks:

| Category | Examples |
|---|---|
| Credentials | database passwords, broker passwords, SMTP credentials |
| Connection URLs that embed credentials | `DATABASE_URL`, `MESSENGER_TRANSPORT_DSN`, `REDIS_URL` with password |
| Cryptographic keys | JWT signing/verification keys (private and public), cookie signing keys, data-at-rest encryption keys |
| Third-party API keys | payment providers, email providers, observability backends, storage accounts |
| OAuth client secrets | OAuth app credentials, machine-to-machine client secrets |
| Internal shared tokens | service-to-service auth tokens, webhook signing secrets |
| Session-bootstrap material | CSRF signing keys, refresh-token hashing pepper |

The following are **not** secrets and may live in plain configuration (`.env.example`, compose files, source):

- Public URLs (`APP_URL`, `CORS_ALLOW_ORIGIN`, `VITE_API_BASE_URL`)
- Port numbers and hostnames of shared infrastructure
- Feature names and toggles whose value is not security-relevant
- JWT public verification key **when distributed via JWKS or an equivalent public channel**

Boundary cases are resolved by the stricter rule: when in doubt, treat the value as a secret.

---

## The secrets manifest

Every project maintains a canonical `secrets-manifest.md` inside the project docs repo (path declared in `{project-docs}/workspace.md` under a `secrets-manifest:` key). This file is the single place that enumerates every secret in the system.

Each row lists:

| Field | Meaning |
|---|---|
| `name` | The env var name exactly as the service reads it (`JWT_PRIVATE_KEY`, `DATABASE_URL`) |
| `owner` | The service that requires it (`login-service`, `task-service`, `shared`) |
| `category` | One of the categories in the table above |
| `environments` | Which environments must provide it (`dev`, `staging`, `prod`) |
| `source` | Where the value comes from in each environment (see injection matrix below) |
| `rotation` | `on-incident` / `scheduled:<cadence>` / `never` (with written justification) |
| `last_rotated` | RFC 3339 date of the last rotation in each non-dev environment |

A pull request that introduces a new secret MUST update this manifest in the same commit. A secret that is not in the manifest does not exist — the reviewer rejects any diff that reads an env var matching the closed list above without a matching manifest row.

Local dev secrets (values in developer `.env.local`) do not appear in the manifest individually; a single row `dev-local` documents that the developer provides their own throwaway values.

---

## Environment-specific injection

### Golden rule

The application code reads every secret exclusively from **process environment variables**. The code does not know and does not care where the value comes from. All the variation happens at the boundary — how the environment is populated before the process starts.

```php
// CORRECT — reads from the environment. The process does not know the source.
$jwtKey = $_ENV['JWT_PRIVATE_KEY'] ?? throw new \RuntimeException('JWT_PRIVATE_KEY is missing');

// WRONG — the application calls a specific provider. Ties the code to the deployment target.
$jwtKey = $awsSecretsManager->getSecretValue('jwt_private_key');
```

This single rule keeps the code portable across deployment targets and testable locally.

### Injection matrix

The source of a secret is declared in the manifest. Supported sources are:

| Source | When to use | Mechanics |
|---|---|---|
| `dotenv-local` | Developer machine only | `.env.local` (gitignored) populated from `.env.example`. Never shared. |
| `runtime-env` | Simple hosts (VPS, Fly, Railway, container registry secret store) | Host-level environment variables set by the platform (dashboard, CLI, or deploy command). The process starts with the variables already in its environment. |
| `docker-secret` | Self-hosted Docker/Swarm | Secret mounted at `/run/secrets/<name>`; an entrypoint script exports it as an env var before the app boots. |
| `cloud-secret-manager` | Managed clouds (AWS Secrets Manager, GCP Secret Manager, Azure Key Vault, HashiCorp Vault) | The deploy pipeline reads the secret at release time and injects it as a runtime env var. The app still only sees env vars. |
| `ci-runtime` | CI jobs only | GitHub Actions `secrets.*` / GitLab masked variables, scoped to the job that needs them. Never propagated to the deployed artifact. |

A project picks one source per environment and documents it in the manifest. A project MAY graduate from `runtime-env` to `cloud-secret-manager` later without touching application code — only the deploy pipeline changes.

### Hard rules (every source)

- Secrets are NEVER baked into Docker images. `COPY .env` is forbidden. `ENV JWT_PRIVATE_KEY=...` in a Dockerfile is forbidden.
- Secrets are NEVER written to disk by the application at runtime. If a library insists on a file, write it to a `tmpfs` mount and delete it in an `atexit` hook.
- Secrets are NEVER printed by the application — not in startup banners, not in error messages, not in health endpoints.
- Secrets are NEVER passed as command-line arguments. `psql -U user -p PASSWORD ...` is visible in `ps`.
- Secrets are NEVER sent to telemetry backends (logs, traces, metrics). Redaction rules below are mandatory.

---

## Backend secrets

### Reading an env var

Every secret read goes through a single helper that fails fast when the value is missing. A missing secret at boot is a deployment bug and must crash the process — silent fallbacks to empty strings mask outages.

```php
// CORRECT — fail-fast, no silent fallback
final readonly class EnvSecret
{
    public static function require(string $name): string
    {
        $value = $_ENV[$name] ?? null;
        if (!is_string($value) || $value === '') {
            throw new \RuntimeException(sprintf('Required secret "%s" is missing or empty', $name));
        }
        return $value;
    }
}

$jwtKey = EnvSecret::require('JWT_PRIVATE_KEY');
```

The `.env.example` file lists every secret the service needs, with a placeholder value (`CHANGE_ME`) and a short comment naming its category. `.env.example` is committed; `.env.local` is never committed.

### Connection URLs

Composite URLs that embed credentials (`postgresql://user:password@host/db`) are themselves secrets. The service does NOT split them into separate env vars and reassemble — that pattern doubles the attack surface and invites typos. Read the URL, pass it to the driver, done.

For tooling that needs the components separately (e.g. migration scripts inspecting the DB name), parse the URL at the boundary into local variables — never re-expose the components as new env vars.

### Key material (JWT, encryption)

- Private keys are PEM files passed via env var (`JWT_PRIVATE_KEY`) or loaded from a file whose path is provided via env var (`JWT_PRIVATE_KEY_FILE`). The `_FILE` convention is preferred when the platform mounts secrets as files.
- Public keys follow the same rule. Public verification keys MAY be distributed via JWKS instead of env vars — when that happens, the JWKS URL is public config, not a secret.
- Key size and algorithm follow [`security.md`](security.md) → JWT Security.
- Rotating a signing key without breaking live sessions requires a two-key window: the service verifies tokens signed by either the current or the previous key, and only signs with the current one. The manifest lists both `JWT_PRIVATE_KEY` and `JWT_PRIVATE_KEY_PREVIOUS` during the window.

---

## Frontend secrets

Frontend secrets are a contradiction in terms. Every `VITE_*` variable is compiled into the JavaScript bundle and is visible to anyone who opens DevTools. [`invariants.md`](invariants.md) forbids putting secrets in `VITE_*`; this section is the constructive side.

### Safe in `VITE_*`

| Category | Examples |
|---|---|
| Public URLs | `VITE_API_BASE_URL`, `VITE_AUTH_URL` |
| Public identifiers | `VITE_APP_NAME`, app version string, commit SHA |
| Safe allowlists | `VITE_ALLOWED_REDIRECT_ORIGINS` |
| Public analytics ids | Sentry DSN for the browser (the ingest side assumes the DSN is public), PostHog public key |

### Never in `VITE_*`

| Category | Why |
|---|---|
| API keys of any kind | Extractable from the bundle in 10 seconds |
| OAuth client secrets | Defeats the purpose of "secret" |
| Backend URLs that are supposed to be internal | Enumeration surface |
| Private identifiers (tenant ids, feature flags whose leak matters) | Public the moment the bundle ships |

### Secrets that reach the browser via the backend

When the frontend needs a value that is secret on the server but must be used in the browser (e.g. a one-time upload token), the backend mints a short-lived, narrowly scoped token per request and returns it in the response. The token's TTL and scope are documented in the endpoint's OpenAPI description.

---

## Secrets in logs, traces, and metrics

Observability pipelines are a common secret leak. The rules are absolute:

- Logs MUST redact every field whose name appears in the redaction list defined in [`logging.md`](logging.md). The redaction list is extended in the same commit whenever a new secret category enters the system.
- Traces MUST NOT carry secrets as span attributes — see [`observability.md`](observability.md) "Forbidden span attributes". Request bodies that contain secrets are either omitted or replaced with `[REDACTED]` before the span is recorded.
- Metrics MUST NEVER use secret values (or values derived from them) as labels. A label containing a token creates a high-cardinality series AND leaks the token to the metrics backend.
- Error messages surfaced to clients NEVER include secret values, even in development — a developer with a debugger set against production is a common incident pattern.

A secret that appears once in a log is a secret that is compromised. Rotation is the only remediation.

---

## Rotation

Every secret has a rotation policy declared in the manifest:

| Policy | When to use | Cadence |
|---|---|---|
| `scheduled:<cadence>` | Long-lived credentials (DB password, signing keys) | Maximum one year; shorter when the platform supports it |
| `on-incident` | Secrets that are costly to rotate (third-party API keys with long-lead revocation) | Rotation triggered only by leak or suspected compromise |
| `ephemeral` | Tokens minted per request/session (refresh tokens, one-time upload URLs) | Managed by the issuing code path; not rotated manually |
| `never` | Irrotable by design (rare; requires written justification in the manifest) | — |

A `last_rotated` date older than the cadence declared for `scheduled:*` is a hard blocker — the reviewer rejects the diff and the developer rotates before shipping.

### Emergency rotation

When a secret is suspected leaked:

1. Rotate in the target environment first — the new value is available in the secret source.
2. Redeploy or restart the service so the new value is picked up. For key-pair rotations (JWT), deploy the two-key window described above.
3. Invalidate anything derived from the leaked value — refresh tokens, cached session state, signed URLs.
4. Record the rotation in the manifest (`last_rotated` + a short note) and in the project docs `decisions.md` if the rotation changes policy.

---

## Bootstrapping a new service

When DevOps scaffolds a new service, the secret bootstrap is part of the checklist:

1. Enumerate every secret the service needs; write each row into the project's secrets manifest.
2. Create `.env.example` listing each secret with a placeholder and category comment.
3. Add every secret to the platform/secret source for each target environment before the first deploy.
4. Verify the service fails to start if any required secret is missing — there is no fallback, no default, no warning-only path.
5. Confirm the secret names appear in the redaction list of [`logging.md`](logging.md). If a new category is introduced, update the redaction list in the same commit.

See [`new-service-checklist.md`](new-service-checklist.md) for how this integrates with the full service bootstrap.

---

## What the reviewer checks

Secrets rules are enforced during review via the backend reviewer checklist (see [`backend-review-checklist.md`](backend-review-checklist.md) → "Secrets management"). The checklist is the authoritative surface — if a rule appears here and not in the checklist, file a minor and update the checklist in the same commit.
