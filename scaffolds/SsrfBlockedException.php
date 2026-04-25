<?php

declare(strict_types=1);

namespace App\Infrastructure\Http;

/**
 * Thrown by SafeHttpClient when a request is blocked because the
 * resolved IP is in the deny-list (RFC 1918, loopback, link-local,
 * cloud metadata).
 *
 * Per attack-surface-hardening.md AS-006.
 */
final class SsrfBlockedException extends \RuntimeException {}
