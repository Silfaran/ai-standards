# Observability Standards

## Philosophy

- You cannot optimize what you cannot measure. Every user-facing request and every async message must be observable without attaching a debugger.
- Three pillars, one correlation id: logs, metrics, and traces are only useful together. Every request gets a `trace_id` that flows through every log line, every span, and every metric label that can carry one.
- Rules here are enforceable by reading the code — they are about wiring, naming, and field presence, not about dashboards or alert policies (those live in the project docs).
- Cost discipline: emit what you would actually use in an incident. Cardinality explosions are silent wallet drains.

---

## The three signals

| Signal | Answers | Cardinality | Retention |
|---|---|---|---|
| Logs | "What exactly happened in this request?" | High — per event, unsampled | Days (hot), weeks (cold) |
| Metrics | "How is the system behaving in aggregate?" | Low — bounded label sets | Months |
| Traces | "Where did the time go in this request?" | Medium — sampled | Days |

Rules:

- Never embed high-cardinality values (`user_id`, `trace_id`, `board_id`) as metric labels. They go in logs and trace attributes.
- Never emit per-request logs without a `trace_id` field. An unindexed log is a log you will not find during an incident.
- Never rely on a single signal. An alert that fires on metrics must link to the trace and logs that explain it.

---

## Tracing — OpenTelemetry

Every service (backend and frontend) exports OTLP spans to the project's collector endpoint. Vendor-lock-in is avoided by standardizing on OpenTelemetry semantic conventions.

### Backend (Symfony)

Required instrumentation:

- HTTP server spans on every inbound request (`symfony/opentelemetry-bundle` or the OTel SDK directly)
- DBAL client spans on every SQL query — the span name is the SQL operation (`SELECT boards`, `INSERT board_members`), never the full query
- Messenger spans around handler execution — one span per command/query handler and one per async message consumer
- HTTP client spans on every outgoing request

Every span must carry these attributes, using OTel semantic conventions where one exists:

| Attribute | Value | Example |
|---|---|---|
| `service.name` | The service name | `task-service` |
| `service.version` | Git SHA or semver from build | `0.7.0` or `1a2b3c4` |
| `http.request.method` | HTTP method on server spans | `POST` |
| `http.route` | Route template, not the rendered path | `/api/boards/{id}/members` |
| `http.response.status_code` | Status code | `201` |
| `user.id` | Authenticated user id, never email | UUID |
| `enduser.id` | Same as `user.id` when authenticated, omitted for anonymous | UUID |

Forbidden span attributes: passwords, tokens (access/refresh/API), request bodies containing PII, full response bodies, full SQL statements with literal values.

### Frontend (Vue 3)

Every frontend instruments:

- Page navigation as a parent span (`page.view`) with `page.route` attribute
- TanStack Query `useQuery` / `useMutation` as client spans (`http.client`) — one per network call, linked to the navigation parent
- Core Web Vitals as span events on the navigation span (LCP, INP, CLS, TTFB) — complementing the `web-vitals` log pipeline defined in [`performance.md`](performance.md)

The access token is never included in span attributes, even when it is attached to the outgoing request.

### Propagation

Traces must cross service boundaries. The backend and frontend both propagate the W3C `traceparent` and `tracestate` headers on every HTTP call. Cross-service async messages propagate context via Messenger stamps (see [`backend-reference.md`](backend-reference.md)).

If a service handles a request without an incoming `traceparent`, it starts a new trace and logs the root `trace_id` at info level so it can be correlated with the client log if needed.

---

## Metrics — RED + resource

Every service emits the four signals below at a minimum. Anything beyond this set is motivated by a specific SLO or incident.

### Request / handler metrics (RED)

For each HTTP route and each async handler:

| Metric | Type | Labels | Purpose |
|---|---|---|---|
| `http_server_requests_total` | counter | `route`, `method`, `status_class` (`2xx`/`4xx`/`5xx`) | Rate |
| `http_server_errors_total` | counter | `route`, `method`, `status_class` (only `4xx`/`5xx`) | Errors |
| `http_server_request_duration_seconds` | histogram | `route`, `method` | Duration |
| `messenger_handler_duration_seconds` | histogram | `bus`, `message` (the `messageName()`) | Duration of async handlers |
| `messenger_handler_errors_total` | counter | `bus`, `message` | Error rate of async handlers |

All histograms expose p50, p95, p99 (the buckets are the OTel default unless a service explicitly overrides). Never label any of these with `user_id`, `trace_id`, or free-form strings.

### Infrastructure / resource metrics

Each service exposes:

- Messenger consumer lag per transport (`messenger_queue_depth`, labeled by `transport` and `queue`)
- Cache hit/miss counters for every cached operation (`cache_operations_total`, labeled by `operation`, `result` ∈ {`hit`, `miss`}) — see [`caching.md`](caching.md)
- Rate limiter decisions (`rate_limiter_decisions_total`, labeled by `limiter`, `decision` ∈ {`allowed`, `limited`}) — see [`security.md`](security.md)

Metrics are scraped from a `/metrics` endpoint protected from public exposure (internal network or basic auth) or pushed to the collector.

---

## Structured logs

Logging rules live in [`logging.md`](logging.md). This section adds the observability-specific constraints:

- Every log entry MUST include `trace_id` and, when available, `span_id`. A log line without these is useless during an incident.
- Every log entry MUST include `service.name` and `service.version` so cross-service queries are possible.
- `level` values are limited to `debug`, `info`, `warn`, `error`, `critical`. No custom levels.
- Error logs include the exception class and message, never the full stack trace containing file paths that leak infrastructure details (handled by the backend logger's redaction pipeline).
- No log sampling on `error` and `critical` — sample `info` / `debug` instead if volume is a concern.

---

## Health and readiness

Every backend service exposes two distinct endpoints, both unauthenticated and safe to hit from load balancers and probes:

| Endpoint | Purpose | Checks |
|---|---|---|
| `GET /health/liveness` | "Is the process alive?" | Returns `200` if the HTTP server responds. No dependency checks. |
| `GET /health/readiness` | "Is the service ready to serve traffic?" | Checks DB connectivity (`SELECT 1`), cache ping if wired, message broker ping. Returns `503` with a JSON body listing the failing check. |

Readiness endpoints are authoritative — a load balancer with a flaky readiness probe is a load balancer that eats user requests.

---

## SLOs and error budgets

Every user-facing service defines at least one SLO in the project docs. The standards enforce the **shape** of the SLO, not the target:

1. An SLI (indicator) — e.g. "fraction of `GET /api/boards` responses served in < 500 ms with a 2xx status code, measured over 30 days"
2. An SLO (objective) — e.g. "99.5% of requests"
3. An error budget derived from the SLO — e.g. "0.5% × total requests / month"
4. A burn-rate alert on the error budget, with at least two windows (fast burn and slow burn)

Services that do not define an SLO get a default 99% availability SLO on each user-facing route. "No SLO" is not an option — an unmeasured service is by definition unreliable.

---

## What the reviewer checks

Observability rules are enforced during review via the backend reviewer checklist (see [`backend-review-checklist.md`](backend-review-checklist.md) → "Observability") and the frontend reviewer checklist ("Observability"). Checklists are the authoritative review surface — when this standard changes, update the matching checklist entries in the same commit.
