<?php

declare(strict_types=1);

namespace App\Domain\Money;

/**
 * Thrown when arithmetic crosses currencies without an explicit FX conversion.
 * Per payments-and-money.md PA-003.
 */
final class CurrencyMismatchException extends \DomainException
{
    public function __construct(string $left, string $right)
    {
        parent::__construct(\sprintf('Currency mismatch: %s vs %s — explicit FX conversion required', $left, $right));
    }
}
