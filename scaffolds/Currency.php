<?php

declare(strict_types=1);

namespace App\Domain\Money;

/**
 * ISO 4217 currency enum. Per payments-and-money.md PA-001.
 *
 * Curated to the most common currencies used across the EU, UK, US, LATAM and
 * APAC. The enum is intentionally NOT exhaustive — uncommon currencies (HUF, RON,
 * SAR, INR, etc.) are added per-project on first use, never speculatively.
 *
 * Why an enum, not a string:
 *   - Type-safe at the boundary: `Money::from(1000, 'EURO')` is impossible at
 *     compile time instead of failing at runtime via Webmozart\Assert.
 *   - IDE autocomplete + refactor across the project.
 *   - The minor-unit count (decimals()) is part of the currency, not a separate
 *     lookup table — see JPY (0 decimals) vs EUR/USD/GBP (2) vs BHD (3).
 *
 * To extend:
 *   - Add the case here using its ISO 4217 alpha-3 code.
 *   - Add to decimals() if non-2-decimal.
 *   - Update the project's pii-inventory entry for any column whose currency
 *     dimension changes.
 */
enum Currency: string
{
    case EUR = 'EUR';
    case USD = 'USD';
    case GBP = 'GBP';
    case CHF = 'CHF';
    case JPY = 'JPY';
    case CNY = 'CNY';
    case CAD = 'CAD';
    case AUD = 'AUD';
    case NZD = 'NZD';
    case SEK = 'SEK';
    case NOK = 'NOK';
    case DKK = 'DKK';
    case PLN = 'PLN';
    case CZK = 'CZK';
    case MXN = 'MXN';
    case BRL = 'BRL';
    case ARS = 'ARS';
    case COP = 'COP';
    case CLP = 'CLP';

    /**
     * Number of decimal places for this currency per ISO 4217.
     * Drives the integer-minor-units conversion: 12.34 EUR is 1234 minor units;
     * 1234 JPY is 1234 minor units (yen has zero decimals); 1.234 BHD is 1234
     * minor units (Bahraini Dinar has three).
     */
    public function decimals(): int
    {
        return match ($this) {
            self::JPY, self::CLP => 0,
            default              => 2,
        };
    }

    /**
     * Common alias for the user-facing display name. Use `Symfony\Component\Intl\Currencies::getName($this->value, $locale)`
     * for the localised display name (per i18n.md "Reference data").
     */
    public function isoCode(): string
    {
        return $this->value;
    }
}
