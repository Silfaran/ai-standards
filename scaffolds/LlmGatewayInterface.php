<?php

declare(strict_types=1);

namespace App\Domain\Llm;

/**
 * Domain seam for every LLM call (Anthropic / OpenAI / Gemini / Mistral / self-hosted).
 * Per llm-integration.md LL-001.
 *
 * Adapters live in src/Infrastructure/Llm/{Provider}LlmGateway.php and depend on the
 * provider SDK. Handlers depend on this interface only — never on the SDK directly.
 *
 * Migration from one provider to another is a one-line wiring change in services.yaml.
 */
interface LlmGatewayInterface
{
    /**
     * @throws LlmCallFailedException        provider unreachable / 5xx after retries
     * @throws LlmInvalidResponseException   parsed JSON failed schema validation (LL-005)
     * @throws LlmCircuitOpenException       per provider+model breaker is open (LL-007)
     * @throws PiiInPromptException          PiiPromptGuard blocked the call (LL-012)
     */
    public function complete(LlmRequest $request): LlmResponse;
}
