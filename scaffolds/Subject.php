<?php

declare(strict_types=1);

namespace App\Domain\Authorization;

use Webmozart\Assert\Assert;

/**
 * Authenticated identity that crosses every layer as a Value Object.
 * Per authorization.md AZ-004 / AZ-012.
 *
 * Built once in the controller from the JWT and propagated as a field
 * of every Command/Query DTO. Handlers never reach into a global session.
 */
final readonly class Subject
{
    /** @param list<string> $roles */
    private function __construct(
        public string $id,
        public string $tenantId,
        public array $roles,
    ) {}

    /** @param list<string> $roles */
    public static function from(string $id, string $tenantId, array $roles): self
    {
        Assert::uuid($id, 'Subject.id must be a UUID');
        Assert::uuid($tenantId, 'Subject.tenantId must be a UUID');
        Assert::allString($roles, 'Subject.roles must be a list of strings');
        return new self($id, $tenantId, $roles);
    }

    /** Service-to-service Subject — tenantId is the literal `shared`, role uses `service:*`. */
    public static function service(string $serviceName): self
    {
        Assert::regex($serviceName, '/^[a-z][a-z0-9-]+$/', 'Service name must be lower-kebab');
        return new self('00000000-0000-0000-0000-000000000000', 'shared', ["service:{$serviceName}"]);
    }

    public function hasRole(string $role): bool
    {
        return \in_array($role, $this->roles, true);
    }

    /** Highest-priority role for observability labels (AZ-008). */
    public function highestPriorityRole(): ?string
    {
        return $this->roles[0] ?? null;
    }
}
