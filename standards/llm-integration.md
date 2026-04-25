# LLM Integration Standards

## Philosophy

- An LLM call is a side-effecting network call to a third party that costs money, may leak personal data, and may return junk. Every property of the call — provider, model, prompt, response shape, cost, latency, retries — has to be visible at code-review time.
- The Domain layer never knows there is an LLM. Calls are gated by an interface (`LlmGatewayInterface`) the same way databases are gated by repositories. A handler that imports the OpenAI SDK directly is a layering defect, not a stylistic choice.
- The output of an LLM is untrusted input. JSON-mode is mandatory for any structured response, and the parsed payload is validated with the same rigor as a request body.
- Cost is observable from day one. Token consumption is a metric, not a mystery surfaced at the end of the month by the provider invoice.
- PII never enters a prompt unless the data subject has consented and the sub-processor (the LLM provider) is in `pii-inventory.md`. See `gdpr-pii.md` GD-011.

---

## When this standard applies

This standard applies whenever the codebase calls a Large Language Model — Anthropic Claude, OpenAI GPT, Google Gemini, Mistral, a self-hosted model via vLLM, anything. It applies to chat completions, embeddings, structured generation, image-text, and tool-use orchestration.

It does NOT cover the *agent pipeline* of `ai-standards` itself (Spec Analyzer, Backend Developer, Reviewer, Tester) — that lives in `agent-reading-protocol.md` and `commands/build-plan-command.md`. This standard is for LLMs called from the *product* code at runtime.

---

## Vocabulary

| Term | Meaning |
|---|---|
| **Provider** | The vendor reachable over the network: Anthropic, OpenAI, Google, Mistral, or a self-hosted endpoint |
| **Model** | The specific model identifier within a provider: `claude-opus-4-7`, `gpt-4o`, `mistral-large-2` |
| **Prompt** | The input text(s) sent to the model, including system prompt and conversation history |
| **Output schema** | The JSON shape the system expects in the response when the call uses structured generation |
| **Token** | The provider's billing unit; counted per direction (input / output / cache-read / cache-write) |
| **Tool use / function calling** | Provider-side mechanism where the model calls back into the application's defined functions to fetch data or take actions |
| **Prompt template** | A versioned, parameterised text whose placeholders are filled per call |

---

## The `LlmGatewayInterface` (canonical seam)

Every LLM call goes through an interface defined in the Domain layer. Implementations live in Infrastructure. Handlers and Application services depend on the interface only.

```php
namespace App\Domain\Llm;

interface LlmGatewayInterface
{
    /** @throws LlmCallFailedException */
    public function complete(LlmRequest $request): LlmResponse;
}

final readonly class LlmRequest
{
    /**
     * @param list<LlmMessage> $messages
     * @param array<string, mixed> $jsonSchema  // null = free-form text response
     */
    private function __construct(
        public string $purpose,                 // stable identifier for observability + cost: 'classify_oficio', 'translate_chat', 'rewrite_bio'
        public string $model,                   // explicit; never "default"
        public array $messages,
        public ?array $jsonSchema = null,
        public ?int $maxTokens = null,
        public ?float $temperature = null,
        public ?int $cacheTtlSeconds = null,    // optional; provider-side prompt cache hint
    ) {}

    public static function from(
        string $purpose,
        string $model,
        array $messages,
        ?array $jsonSchema = null,
        ?int $maxTokens = null,
        ?float $temperature = null,
        ?int $cacheTtlSeconds = null,
    ): self {
        return new self($purpose, $model, $messages, $jsonSchema, $maxTokens, $temperature, $cacheTtlSeconds);
    }
}

final readonly class LlmResponse
{
    public function __construct(
        public string $content,                 // raw text or stringified JSON
        public LlmUsage $usage,                 // tokens + cost
        public string $model,                   // echoed back; may differ from request if provider promotes
        public string $finishReason,            // 'stop' | 'length' | 'tool_use' | 'content_filter'
        public mixed $parsed = null,            // populated when jsonSchema is set; null otherwise
    ) {}
}

final readonly class LlmUsage
{
    public function __construct(
        public int $inputTokens,
        public int $outputTokens,
        public int $cacheReadTokens,
        public int $cacheWriteTokens,
        public int $costMicroDollars,           // integer cents-of-cents; promoted from provider's per-token price
    ) {}
}
```

Rules:

- The interface lives in `src/Domain/Llm/`. Adapters per provider live in `src/Infrastructure/Llm/{Provider}LlmGateway.php`.
- The Domain interface NEVER mentions a provider name, a SDK type, or a transport detail. A migration from Claude to GPT MUST be a one-line wiring change in `services.yaml`.
- The handler asks for `LlmGatewayInterface`, not for `AnthropicGateway`. Mocks in tests return canned `LlmResponse` objects.
- Streaming responses MAY be added as a separate method (`stream(): iterable<LlmChunk>`); they MUST NOT silently change the shape of `complete()`.

---

## Prompt templates

Prompts are first-class artifacts, not string concatenations.

### Storage

Prompt templates live in `src/Domain/Llm/Prompt/{Purpose}Prompt.php`. Each template is a class with:

- A `version` constant — incremented on every text change
- A `system()` method that returns the system prompt
- A `user(...)` method that takes typed parameters and returns the user prompt
- An optional `jsonSchema()` method that returns the expected output schema

```php
namespace App\Domain\Llm\Prompt;

final readonly class ClassifyOficioPrompt
{
    public const VERSION = 'v3';

    public function system(): string
    {
        return <<<TEXT
        You are a taxonomy classifier for skilled trades. Given a free-text job description,
        return the best matching oficio code from the supplied catalog. Respond ONLY in the
        requested JSON shape. If you are not sure, set "confidence" below 0.5 and pick the
        closest match — never invent codes that are not in the catalog.
        TEXT;
    }

    /** @param list<string> $catalog */
    public function user(string $description, array $catalog): string
    {
        $catalogJson = json_encode($catalog, JSON_THROW_ON_ERROR);
        return "Catalog:\n{$catalogJson}\n\nDescription:\n{$description}";
    }

    /** @return array<string, mixed> */
    public function jsonSchema(): array
    {
        return [
            'type' => 'object',
            'required' => ['code', 'confidence'],
            'properties' => [
                'code'       => ['type' => 'string'],
                'confidence' => ['type' => 'number', 'minimum' => 0, 'maximum' => 1],
                'reason'     => ['type' => 'string'],
            ],
            'additionalProperties' => false,
        ];
    }
}
```

### Discipline

- A prompt change = a `VERSION` bump. The new version is logged on every call (`prompt_version` attribute on the span).
- A prompt template is a unit-tested class. The test asserts the rendered text contains the expected anchors — protects against accidental edits to the system prompt.
- No string interpolation of untrusted input into the system prompt. User content lives in the `user()` parameters; the system prompt is developer-authored.
- No prompt template lives in a database row by default. Run-time-editable prompts require an ADR; the cost of "we'll iterate live" is regressions invisible to code review.

### Output validation

When `jsonSchema` is set, the gateway adapter MUST:

1. Send the schema to the provider via the provider's structured-output mechanism.
2. Parse the returned text as JSON.
3. Validate against the schema (e.g. `opis/json-schema`).
4. Populate `LlmResponse->parsed` with the validated decoded payload.
5. Throw `LlmInvalidResponseException` on validation failure — this is a defect, not a retryable error.

A handler that uses `$response->parsed` reads typed data, never `json_decode($response->content)` itself.

---

## Resilience: timeouts, retries, circuit breakers

LLM calls have wide latency tails (p95 multiple seconds, p99 occasionally minutes). Every call MUST declare its budget and degrade gracefully.

### Mandatory parameters per call

| Parameter | Default | Override when |
|---|---|---|
| Connect timeout | 5 s | Never — provider TLS handshake is bounded |
| Read timeout | 30 s | Long-running streaming or batch — declare the new value in code |
| Max retries | 2 | Idempotent generation only; tool-use chains stay at 0 |
| Backoff | exponential, jittered | Always — fixed backoff produces thundering herd on provider degradation |

### Retry policy

The adapter retries ONLY on:
- HTTP 408 / 429 / 5xx
- Transport errors (DNS, connection reset)

It NEVER retries on:
- HTTP 4xx other than 408/429 (the prompt is wrong; retrying does not help)
- Validation failures of the parsed JSON (the prompt or schema is wrong)
- Content-filter rejections (the prompt is policy-violating; the user-facing path needs a different handling)

### Circuit breaker

Every provider+model pair has a circuit breaker. When the rolling 1-minute error rate exceeds 25%, the breaker opens for 30 s; in the open state, calls fail fast with `LlmCircuitOpenException`. The handler MUST have a graceful degradation path — for example, "match later when the model is back" instead of "show error to the user".

### Idempotency for write-side LLM use

When an LLM call drives a write (a generation that creates content, a classification that mutates data), the surrounding handler is idempotent (BE-051). The retry loop MUST NOT cause double inserts: either the handler uses a deduplication key (request-id + purpose) or the write is wrapped in a "create-if-not-exists" pattern.

---

## Cost observability

Every call emits two signals:

### Span attributes (per call)

On the handler span (see `observability.md`), add a child span `llm.call` with:

| Attribute | Required | Example |
|---|---|---|
| `llm.provider` | yes | `anthropic` |
| `llm.model` | yes | `claude-opus-4-7` |
| `llm.purpose` | yes | `classify_oficio` |
| `llm.prompt_version` | yes | `v3` |
| `llm.input_tokens` | yes | `1842` |
| `llm.output_tokens` | yes | `87` |
| `llm.cache_read_tokens` | when supported | `1500` |
| `llm.cache_write_tokens` | when supported | `0` |
| `llm.cost_micro_dollars` | yes | `4200` (= $0.0042) |
| `llm.finish_reason` | yes | `stop` |
| `llm.latency_ms` | yes | `1342` |

NEVER add: prompt text, response text, user identifiers, message contents. The span is for cost and shape, not content. See `observability.md` OB-005.

### Metrics (aggregate)

| Metric | Labels | Purpose |
|---|---|---|
| `llm_calls_total` | `provider`, `model`, `purpose`, `finish_reason` | Volume by purpose |
| `llm_input_tokens_total` | `provider`, `model`, `purpose` | Token consumption — drives invoice prediction |
| `llm_output_tokens_total` | `provider`, `model`, `purpose` | Same |
| `llm_cost_micro_dollars_total` | `provider`, `model`, `purpose` | Spend in microdollars (integer) |
| `llm_latency_seconds` | `provider`, `model`, `purpose`, histogram | Tail-latency tracking for SLOs |
| `llm_errors_total` | `provider`, `model`, `purpose`, `error_class` | Reliability tracking |

`purpose` is bounded (one per `Purpose` constant in code) — high-cardinality labels (user id, prompt hash) are forbidden, see OB-007.

A burn-rate alert on `llm_cost_micro_dollars_total` per purpose flags runaway features before the monthly invoice does.

---

## Prompt caching

Most providers support server-side prompt caching: if the first N tokens of the prompt match a previous call (within the cache TTL), they are billed cheaper and processed faster. This is non-trivial cost savings for static system prompts and large catalogs.

Rules:

- Static prefixes (system prompt + injected catalogs) MUST come first in the message list to maximize cache reuse.
- Variable inputs come last.
- The adapter sets the provider-specific cache marker (`cache_control: { type: 'ephemeral' }` for Anthropic; provider-equivalent for others) on the static prefix.
- Cache hits are observable as `llm.cache_read_tokens > 0`. A purpose with a static prefix and zero cache reads is a defect (the prefix changed between calls or the cache marker was missed).

---

## PII in prompts

A prompt is a payload that travels to a third-party sub-processor. PII rules from `gdpr-pii.md` apply with one extra constraint: every LLM call that may receive PII MUST go through a `PiiPromptGuard` before it leaves the gateway adapter.

```php
namespace App\Application\Service\Llm;

final readonly class PiiPromptGuard
{
    public function __construct(
        private PiiInventoryReader $inventory,    // reads pii-inventory.md row state
        private SubjectConsentLedger $consent,
    ) {}

    public function execute(LlmRequest $request, LlmCallContext $ctx): void
    {
        // Static check — prompt bytes scanned for known PII patterns
        // (email, phone, government id formats per the project's PII inventory)
        if ($this->inventory->scanForUnclassifiedPii($request->messages) !== []) {
            throw new PiiInPromptException(
                'Prompt contains PII not declared in pii-inventory.md for purpose '.$request->purpose
            );
        }

        // Dynamic check — the affected data subjects have consented to this purpose
        if (!$this->consent->allows($ctx->dataSubjectId, $request->purpose)) {
            throw new ConsentMissingException($ctx->dataSubjectId, $request->purpose);
        }
    }
}
```

The guard is invoked synchronously inside `complete()`. It is not bypassable per call — projects that need to skip it for a specific purpose declare the exemption in the inventory's `processors` field and the guard reads that exemption.

---

## Self-hosted vs hosted models

The interface is the same; the adapter changes. Project-specific decisions (hosted-only, self-hosted-only, mixed by purpose) live in `{project-docs}/decisions.md` as an ADR. The standard does not prefer one — both are first-class.

When mixing, the routing happens at the wiring layer (DI configuration), not inside handlers. A handler does NOT know whether `LlmGatewayInterface` is implemented by a hosted or a self-hosted adapter.

---

## Tool use / function calling

When a purpose needs the model to call back into the application (look up data, place an order, query a catalog), the tools are declared as part of the prompt template:

```php
public function tools(): array
{
    return [
        [
            'name' => 'lookup_oficio_by_code',
            'description' => 'Resolve an oficio code to its canonical name and parent family.',
            'input_schema' => [
                'type' => 'object',
                'required' => ['code'],
                'properties' => ['code' => ['type' => 'string']],
            ],
        ],
    ];
}
```

The adapter loops on tool-use responses, executes the tool, sends the result back, until `finish_reason = 'stop'`. Each tool call is its own span, with the tool name as an attribute. The adapter MUST cap the loop (default: 5 iterations) — runaway tool chains are a known failure mode and the cap is observable as `LlmToolLoopExhaustedException`.

Tools that perform writes (create a record, send a message) are subject to the same authorization rules as any other write — Voters apply (`AZ-001`).

---

## Testing

Unit tests for handlers using LLMs MUST mock `LlmGatewayInterface` — no real network calls. The mock returns a canned `LlmResponse` per purpose; the test asserts the parsed shape is consumed correctly and the failure modes (`LlmCallFailedException`, `LlmInvalidResponseException`, `LlmCircuitOpenException`) are handled.

```php
public function testClassifyOficioStoresParsedResult(): void
{
    $gateway = $this->createMock(LlmGatewayInterface::class);
    $gateway->method('complete')->willReturn(new LlmResponse(
        content: '{"code":"electricista_industrial","confidence":0.92}',
        usage: new LlmUsage(1842, 87, 0, 0, 4200),
        model: 'claude-opus-4-7',
        finishReason: 'stop',
        parsed: ['code' => 'electricista_industrial', 'confidence' => 0.92],
    ));

    $handler = new ClassifyOficioCommandHandler($gateway, $this->repo, $this->prompt);
    $handler($command);

    self::assertSame('electricista_industrial', $this->repo->lastSavedCode());
}
```

Integration tests against a real provider exist behind a `@group llm-real` annotation; they are skipped in default CI runs (cost + flakiness) and run in a nightly job with a strict daily budget.

---

## Anti-patterns (auto-reject in review)

- A handler or service that imports `Anthropic\Sdk\Client` (or an OpenAI / Gemini SDK class) directly — bypasses the gateway.
- Writing the prompt template inline in a handler (`$prompt = "Classify the following: " . $userText;`) — invisible to versioning, cost tracking, and PII guard.
- Calling the LLM without a `purpose` — observability and cost analysis become impossible.
- Skipping `jsonSchema` for a structured response and parsing the text by hand — reintroduces JSON-mode-class bugs.
- Logging the prompt or the response body — see `gdpr-pii.md` GD-005 + `observability.md` OB-005.
- Storing prompts in user-editable rows without an ADR.
- A retry loop without an idempotency guarantee on the surrounding handler — the same generation written to the database twice.
- A purpose whose `purpose` value is generated dynamically (`'classify_'.$tenant`) — destroys the cardinality bound on the metric label.

---

## What the reviewer checks

LLM rules are enforced during review via the backend reviewer checklist (see [`backend-review-checklist.md`](backend-review-checklist.md) → "LLM integration"). The checklist is the authoritative surface — if a rule appears here and not in the checklist, file a minor and update the checklist in the same commit.
