<?php

declare(strict_types=1);

namespace App\Test\Performance;

use Doctrine\DBAL\Driver\Middleware\AbstractStatementMiddleware;
use Doctrine\DBAL\Driver\Statement;

/**
 * DBAL middleware that counts the queries executed during the wrapped
 * driver's lifetime. Used by AssertMaxQueriesTrait to detect N+1 in
 * integration tests.
 *
 * Per performance.md PE-018 / backend-review-checklist BE-068.
 *
 * Wire-up in services_test.yaml (only loaded in `when@test`):
 *
 *     App\Test\Performance\QueryCountMiddleware:
 *         tags:
 *             - { name: doctrine.middleware }
 *
 * The middleware exposes a static counter so the test trait can read it
 * without dependency injection plumbing across the test boundary.
 */
final class QueryCountMiddleware extends AbstractStatementMiddleware
{
    private static int $count = 0;

    public static function reset(): void
    {
        self::$count = 0;
    }

    public static function count(): int
    {
        return self::$count;
    }

    public function execute($params = null): \Doctrine\DBAL\Driver\Result
    {
        self::$count++;
        return parent::execute($params);
    }
}
