<?php

declare(strict_types=1);

namespace App\Domain\Authorization\Voter;

use App\Domain\Authorization\Subject;

/**
 * Canonical Voter shape. One Voter per aggregate.
 * Per authorization.md AZ-001 / AZ-003.
 *
 * Rename {Aggregate} to your aggregate (Board, Charge, Professional, …).
 * Add one method per protected action (canView, canDelete, canPublish, …).
 *
 * Rules:
 * - Returns bool, never throws (the handler turns false into ForbiddenActionException).
 * - Pure: no DB calls, no logging, no event dispatch. Aggregate loaded by the handler.
 * - Multi-tenant aggregates: subject.tenantId === aggregate.tenantId comes BEFORE role checks.
 */
final readonly class AggregateVoter
{
    public function canView(Subject $subject, object $aggregate): bool
    {
        // Replace `tenantId` access with the actual property of your aggregate.
        if ($subject->tenantId !== $aggregate->tenantId) {
            return false;
        }
        return $subject->hasRole('viewer')
            || $subject->hasRole('editor')
            || $subject->hasRole('admin');
    }

    public function canDelete(Subject $subject, object $aggregate): bool
    {
        if ($subject->tenantId !== $aggregate->tenantId) {
            return false;
        }
        // Owner OR admin. Replace `ownerId` with your aggregate's owner field.
        return $subject->id === $aggregate->ownerId
            || $subject->hasRole('admin');
    }
}
