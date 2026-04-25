<?php

declare(strict_types=1);

namespace App\Test\Performance;

use PHPUnit\Framework\Assert;

/**
 * PHPUnit trait that detects N+1 by asserting an upper bound on the number
 * of database queries executed inside a closure.
 *
 * Per performance.md PE-018 / backend-review-checklist BE-068.
 *
 * Requires QueryCountMiddleware wired into the DBAL connection in the
 * test environment (see services_test.yaml in QueryCountMiddleware doc).
 *
 * Usage in any KernelTestCase / WebTestCase:
 *
 *     final class GetBoardsTest extends WebTestCase
 *     {
 *         use AssertMaxQueriesTrait;
 *
 *         public function testListBoardsDoesNotN1(): void
 *         {
 *             $client = static::createClient();
 *             $this->assertMaxQueries(5, fn() => $client->request('GET', '/api/v1/boards'));
 *         }
 *     }
 *
 * The bound is a project-specific budget. Start at the observed baseline + 1
 * (so one accidental extra query fails the test); tighten as the codebase
 * matures.
 */
trait AssertMaxQueriesTrait
{
    /**
     * Assert the closure executes at most $max database queries.
     *
     * @param positive-int $max
     * @param callable():void $action
     */
    protected function assertMaxQueries(int $max, callable $action, string $message = ''): void
    {
        QueryCountMiddleware::reset();
        $action();
        $actual = QueryCountMiddleware::count();
        Assert::assertLessThanOrEqual(
            $max,
            $actual,
            $message !== ''
                ? \sprintf('%s — got %d, max %d', $message, $actual, $max)
                : \sprintf('Expected at most %d queries, got %d (suspect N+1)', $max, $actual),
        );
    }
}
