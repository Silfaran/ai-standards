<?php

declare(strict_types=1);

namespace App\Application\Audit;

use Doctrine\DBAL\Connection;
use Symfony\Component\HttpFoundation\RequestStack;

/**
 * Consumes domain events and writes audit_log entries IN THE SAME DB
 * TRANSACTION as the state change.
 *
 * Per audit-log.md AU-005 / AU-006 / AU-007.
 *
 * Two valid patterns to satisfy AU-006 ("same DB transaction"):
 *   1. Same-tx projector (default): the handler runs inside Connection::transactional()
 *      and dispatches the event via SyncTransport so this projector executes
 *      before the commit.
 *   2. Outbox: the handler writes the event to an `audit_outbox` table in the
 *      same tx; a worker drains the outbox to `audit_log`. Required when audit
 *      lives in a separate database.
 *
 * This scaffold implements pattern (1). For pattern (2), wrap the same insert
 * logic in a Messenger consumer and target an `audit_outbox` table first.
 */
final readonly class AuditLogProjector
{
    public function __construct(
        private Connection $connection,
        private RequestStack $requestStack,
    ) {}

    /**
     * Generic recorder. In real code, write one method per event type
     * (`onBoardDeleted`, `onPaymentCaptured`, `onConsentGranted`) and let
     * Symfony Messenger route by event class.
     *
     * @param array<string, mixed> $metadata structured per audit-actions.md
     */
    public function record(
        \DateTimeImmutable $occurredAt,
        string $tenantId,
        string $actorKind,             // 'user' | 'service' | 'system'
        ?string $actorId,
        ?string $actorRole,
        string $action,                 // 'board.delete', 'pii.access', …
        string $resourceType,
        ?string $resourceId,
        string $outcome,                // 'succeeded' | 'denied' | 'failed'
        ?string $denyReason,
        array $metadata = [],
    ): void {
        $request = $this->requestStack->getCurrentRequest();
        $traceCtx = $this->traceContext();

        $this->connection->insert('audit_log', [
            'occurred_at'         => $occurredAt->format(\DateTimeInterface::RFC3339),
            'tenant_id'           => $tenantId,
            'actor_kind'          => $actorKind,
            'actor_id'            => $actorId,
            'actor_subject_role'  => $actorRole,
            'action'              => $action,
            'resource_type'       => $resourceType,
            'resource_id'         => $resourceId,
            'outcome'             => $outcome,
            'deny_reason'         => $denyReason,
            'request_ip'          => $request?->getClientIp(),
            'request_user_agent'  => \substr((string) $request?->headers->get('User-Agent', ''), 0, 256),
            'trace_id'            => $traceCtx['trace_id'] ?? null,
            'span_id'             => $traceCtx['span_id'] ?? null,
            'metadata'            => \json_encode($metadata, JSON_THROW_ON_ERROR),
        ]);
    }

    /** @return array{trace_id?: string, span_id?: string} */
    private function traceContext(): array
    {
        // Replace with your project's OTel span context reader (observability.md).
        return [];
    }
}
