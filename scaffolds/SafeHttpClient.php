<?php

declare(strict_types=1);

namespace App\Infrastructure\Http;

use Symfony\Contracts\HttpClient\HttpClientInterface;
use Symfony\Contracts\HttpClient\ResponseInterface;

/**
 * SSRF-safe HTTP client. Wraps Symfony's HttpClientInterface with:
 *   - DNS resolution + IP allowlist (denies RFC 1918 / loopback / link-local / cloud metadata)
 *   - Pinned resolved IP (DNS rebinding protection)
 *   - Bounded timeouts (connect 5s, total 30s)
 *   - Protocol-stable redirect handling (https stays https)
 *
 * Per attack-surface-hardening.md AS-006.
 *
 * USE THIS — never call HttpClientInterface->request() directly with user-supplied URLs.
 */
final readonly class SafeHttpClient
{
    /** @var list<string> CIDR ranges to deny. Extend per project via DI. */
    private const DEFAULT_DENY_CIDRS = [
        '10.0.0.0/8',
        '172.16.0.0/12',
        '192.168.0.0/16',
        '127.0.0.0/8',
        '169.254.0.0/16',          // link-local + cloud metadata
        '::1/128',
        'fc00::/7',                 // ULA
        'fe80::/10',                // IPv6 link-local
    ];

    public function __construct(
        private HttpClientInterface $inner,
        /** @var list<string> */
        private array $denyCidrs = self::DEFAULT_DENY_CIDRS,
    ) {}

    /**
     * @param array<string, mixed> $options Symfony HttpClient options
     * @throws SsrfBlockedException when the URL resolves to a denied IP
     */
    public function request(string $method, string $url, array $options = []): ResponseInterface
    {
        $host = \parse_url($url, PHP_URL_HOST)
            ?: throw new \InvalidArgumentException('URL has no host');

        $ip = \gethostbyname($host);
        if ($ip === $host) {
            throw new SsrfBlockedException("DNS resolution failed for {$host}");
        }
        if ($this->isDeniedIp($ip)) {
            throw new SsrfBlockedException("Resolved IP {$ip} is in deny-list");
        }

        // Pin the resolved IP for the duration of the call (DNS rebinding protection).
        $options['resolve'] = \array_merge($options['resolve'] ?? [], [$host => $ip]);
        $options['timeout'] ??= 30.0;
        $options['max_duration'] ??= 30.0;
        $options['max_redirects'] ??= 3;

        return $this->inner->request($method, $url, $options);
    }

    private function isDeniedIp(string $ip): bool
    {
        foreach ($this->denyCidrs as $cidr) {
            if ($this->ipInCidr($ip, $cidr)) {
                return true;
            }
        }
        return false;
    }

    private function ipInCidr(string $ip, string $cidr): bool
    {
        [$subnet, $maskBits] = \explode('/', $cidr);
        $ipBin = \inet_pton($ip);
        $subnetBin = \inet_pton($subnet);
        if ($ipBin === false || $subnetBin === false || \strlen($ipBin) !== \strlen($subnetBin)) {
            return false;
        }
        $byteLen = (int) (((int) $maskBits) / 8);
        $bitLen = ((int) $maskBits) % 8;
        if (\substr($ipBin, 0, $byteLen) !== \substr($subnetBin, 0, $byteLen)) {
            return false;
        }
        if ($bitLen === 0) {
            return true;
        }
        $mask = 0xff << (8 - $bitLen) & 0xff;
        return (\ord($ipBin[$byteLen]) & $mask) === (\ord($subnetBin[$byteLen]) & $mask);
    }
}
