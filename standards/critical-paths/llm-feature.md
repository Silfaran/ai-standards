# Critical path — LLM-driven feature

Use when the diff calls a Large Language Model at runtime (Claude / OpenAI / Gemini / Mistral / self-hosted): classification, generation, translation, embedding, tool-use orchestration. Always combine with [`auth-protected-action.md`](auth-protected-action.md) when the call is gated by user permission.

## When to load this path

**PRIMARY trigger** (load this path as core when):
- A new class implements `LlmGatewayInterface` or a new prompt template class with `VERSION` constant
- A new handler invokes `$llmGateway->complete(...)` (or equivalent)
- A new tool-use loop or `ToolDefinition` registered

**SECONDARY trigger** (load only when no primary path covers the diff already):
- A new entry in `pii-inventory.md` for an LLM provider (sub-processor) — `pii-write-endpoint.md` owns the GD-011 sub-processor row when fired in parallel; this path adds it only when no PII-writing diff is present
- A bumped `VERSION` constant on an existing prompt template
- A new circuit-breaker / retry config for an existing LLM gateway
- New observability / cost metrics specific to LLM calls

**DO NOT load when**:
- The diff only modifies tests
- The diff only modifies `*.md`
- The "LLM" reference is to an offline batch job in `scripts/` that does NOT run in product code at runtime (out of scope)

## Backend

### Gateway seam
- LL-001 Every LLM call goes through `LlmGatewayInterface` (Domain) — no SDK imports in handlers
- LL-002 Prompt templates are classes with `VERSION`, `system()`, `user(...)`, optional `jsonSchema()`
- LL-003 `LlmRequest::purpose` is bounded (constant or enum) — finite metric label cardinality

### Structured generation
- LL-004 Calls with `jsonSchema` read `LlmResponse->parsed`; handlers do NOT call `json_decode`
- LL-005 Adapter validates parsed JSON against the schema; throws `LlmInvalidResponseException` on mismatch

### Resilience
- LL-006 Adapter retries only on 408/429/5xx + transport, exponential jittered, max 2; never retries 4xx / validation / content-filter
- LL-007 Per provider+model circuit breaker; handler degrades gracefully on `LlmCircuitOpenException`
- LL-008 Idempotent surrounding handlers (BE-051) — retries cannot double-insert

### Cost & observability
- LL-009 `llm.call` span with provider / model / purpose / prompt_version / tokens / `cost_micro_dollars` / finish_reason / latency_ms — NEVER prompt or response text
- LL-010 Metrics: `llm_calls_total`, `llm_input_tokens_total`, `llm_output_tokens_total`, `llm_cost_micro_dollars_total`, `llm_latency_seconds`, `llm_errors_total` — bounded labels

### Prompt cache
- LL-011 Static prefixes first with provider cache marker; cache hits visible as `llm.cache_read_tokens > 0`

### PII guard
- LL-012 `PiiPromptGuard` invoked synchronously inside `complete()` — checks `pii-inventory.md` AND `ConsentLedger`; bypass only via inventory `processors` exemption

### Tool use
- LL-013 Tool-use loops capped (default 5); tool-driven writes go through Voters (AZ-001)

### Testing
- LL-014 Unit tests mock `LlmGatewayInterface`; real-provider tests behind `@group llm-real` and a daily budget — never default CI

### Sub-processor inventory
- GD-011 LLM provider declared in `pii-inventory.md` with affected fields and region

### Hard blockers
- BE-001 Quality gates green
- SC-001 No secrets committed (provider API key is in `secrets-manifest.md`)
- LO-001 No unredacted sensitive fields in logs

## Coverage map vs full checklist

This path covers these sections of `backend-review-checklist.md`:

- §LLM integration — LL-001..LL-014 (Gateway seam, prompt versions, JSON schema, retries, circuit breaker, cost spans, PII guard, tool use)
- §Sub-processor inventory — GD-011 (provider declared in `pii-inventory.md`)
- §Hard blockers — BE-001, SC-001, LO-001

This path does NOT cover. Load the corresponding checklist section ONLY when the diff touches:

- `tests/` directory (especially `@group llm-real`) → load §Testing
- The Application/Domain service orchestrating the call → load `crud-endpoint.md` (path)
- Storing LLM output as user-facing data → load `pii-write-endpoint.md` (path)
- Outbound webhook for async LLM jobs → load `async-handler.md` (path)
- Frontend rendering of LLM output (streaming, formatting) → load §Frontend UX states

## What this path does NOT cover

- Authorization on the user-facing endpoint → [`auth-protected-action.md`](auth-protected-action.md)
- The Application service orchestrating the call → [`crud-endpoint.md`](crud-endpoint.md) (architecture rules apply)
- LLM-generated content stored as user-facing data → also load [`pii-write-endpoint.md`](pii-write-endpoint.md) when applicable
