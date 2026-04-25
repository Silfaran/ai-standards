<?php

declare(strict_types=1);

namespace App\Domain\Llm;

/**
 * Adapter-populated response. Per llm-integration.md LL-004 / LL-005 / LL-009.
 */
final readonly class LlmResponse
{
    public function __construct(
        public string $content,        // raw text or stringified JSON
        public LlmUsage $usage,        // tokens + cost (drives observability)
        public string $model,           // echoed back; may differ from request if provider promotes
        public string $finishReason,    // 'stop' | 'length' | 'tool_use' | 'content_filter'
        public mixed $parsed = null,    // populated when jsonSchema set; null otherwise
    ) {}
}

/**
 * Token + cost accounting for one call. cost_micro_dollars is integer
 * cents-of-cents (1_000_000 = $1.00). Computed by the adapter from the
 * provider's per-token price table.
 */
final readonly class LlmUsage
{
    public function __construct(
        public int $inputTokens,
        public int $outputTokens,
        public int $cacheReadTokens,    // LL-011: hit on the static prefix
        public int $cacheWriteTokens,
        public int $costMicroDollars,
    ) {}
}

final class LlmCallFailedException extends \RuntimeException {}
final class LlmInvalidResponseException extends \RuntimeException {}
final class LlmCircuitOpenException extends \RuntimeException {}
final class PiiInPromptException extends \RuntimeException {}
final class LlmToolLoopExhaustedException extends \RuntimeException {}
