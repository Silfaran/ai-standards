<?php

declare(strict_types=1);

namespace App\Domain\Llm;

/**
 * Bounded LLM request DTO. Per llm-integration.md LL-002 / LL-003 / LL-004.
 *
 * `purpose` MUST be a constant or enum value (never a dynamic string) — it is used
 * as a metric label and must have finite cardinality.
 *
 * `messages` is the raw provider-shape list (system + user + assistant turns); the
 * adapter translates to the SDK call.
 */
final readonly class LlmRequest
{
    /**
     * @param list<array{role: string, content: string}> $messages
     * @param array<string, mixed>|null                  $jsonSchema  null = free-form text
     */
    private function __construct(
        public string $purpose,
        public string $model,
        public array $messages,
        public ?array $jsonSchema = null,
        public ?int $maxTokens = null,
        public ?float $temperature = null,
        public ?int $cacheTtlSeconds = null,
    ) {}

    /**
     * @param list<array{role: string, content: string}> $messages
     * @param array<string, mixed>|null                  $jsonSchema
     */
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
