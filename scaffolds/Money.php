<?php

declare(strict_types=1);

namespace App\Domain\Money;

use Webmozart\Assert\Assert;

/**
 * Money value object. Integer minor units + ISO 4217 currency.
 * Per payments-and-money.md PA-001..PA-004.
 *
 * NEVER use float for money. NEVER store as a single column without currency.
 * Floats round; missing currency makes 1000 ambiguous (cents EUR? yen?).
 *
 * The `currency` field is a `Currency` enum (type-safe, IDE-completable,
 * carries decimals()). Boundaries that receive currency as a string (an HTTP
 * payload, a CSV row, a Stripe webhook) call `Money::fromMinor(int, string)`
 * which validates and converts to the enum.
 */
final readonly class Money
{
    private function __construct(
        public int $amountMinor,
        public Currency $currency,
    ) {}

    public static function from(int $amountMinor, Currency $currency): self
    {
        return new self($amountMinor, $currency);
    }

    /**
     * Boundary helper — accept the currency as an ISO 4217 string.
     * Use this when parsing payloads from outside the application
     * (HTTP requests, webhooks, imports). Throws if the code is not in the
     * Currency enum (extend the enum if a legitimate currency is missing).
     */
    public static function fromMinor(int $amountMinor, string $currencyCode): self
    {
        Assert::regex($currencyCode, '/^[A-Z]{3}$/', 'Currency must be ISO 4217 3-letter uppercase');
        $currency = Currency::tryFrom($currencyCode)
            ?? throw new \InvalidArgumentException(
                \sprintf('Currency "%s" is not registered in the Currency enum — add the case if legitimate', $currencyCode)
            );
        return new self($amountMinor, $currency);
    }

    public static function zero(Currency $currency): self
    {
        return new self(0, $currency);
    }

    public function add(self $other): self
    {
        $this->assertSameCurrency($other);
        return new self($this->amountMinor + $other->amountMinor, $this->currency);
    }

    public function subtract(self $other): self
    {
        $this->assertSameCurrency($other);
        return new self($this->amountMinor - $other->amountMinor, $this->currency);
    }

    public function times(int $factor): self
    {
        return new self($this->amountMinor * $factor, $this->currency);
    }

    /**
     * Split this Money across N parts so that the parts sum exactly to this.
     * Largest-remainder method: the first (amountMinor mod N) parts get one extra
     * minor unit each. Never loses cents to truncation. Per PA-004.
     *
     * @return list<self>
     */
    public function splitEvenly(int $parts): array
    {
        Assert::greaterThan($parts, 0, 'splitEvenly requires parts > 0');
        $base = \intdiv($this->amountMinor, $parts);
        $remainder = $this->amountMinor % $parts;
        $out = [];
        for ($i = 0; $i < $parts; $i++) {
            $out[] = new self($base + ($i < $remainder ? 1 : 0), $this->currency);
        }
        return $out;
    }

    public function isPositive(): bool { return $this->amountMinor > 0; }
    public function isZero(): bool     { return $this->amountMinor === 0; }
    public function isNegative(): bool { return $this->amountMinor < 0; }

    public function equals(self $other): bool
    {
        return $this->amountMinor === $other->amountMinor && $this->currency === $other->currency;
    }

    /** @return array{amount_minor: int, currency: string} */
    public function toApiArray(): array
    {
        return ['amount_minor' => $this->amountMinor, 'currency' => $this->currency->value];
    }

    private function assertSameCurrency(self $other): void
    {
        if ($this->currency !== $other->currency) {
            throw new CurrencyMismatchException($this->currency->value, $other->currency->value);
        }
    }
}
