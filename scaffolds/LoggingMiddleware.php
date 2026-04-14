<?php

declare(strict_types=1);

namespace App\Infrastructure\Messenger\Middleware;

use Psr\Log\LoggerInterface;
use Symfony\Component\Messenger\Envelope;
use Symfony\Component\Messenger\Middleware\MiddlewareInterface;
use Symfony\Component\Messenger\Middleware\StackInterface;
use Symfony\Component\Messenger\Stamp\BusNameStamp;

final class LoggingMiddleware implements MiddlewareInterface
{
    private const SENSITIVE_FIELDS = [
        'password', 'password_hash', 'hashed_password',
        'token', 'access_token', 'refresh_token',
        'secret', 'api_key', 'credential', 'card_number',
    ];

    public function __construct(private readonly LoggerInterface $logger) {}

    public function handle(Envelope $envelope, StackInterface $stack): Envelope
    {
        $message = $envelope->getMessage();

        try {
            return $stack->next()->handle($envelope, $stack);
        } catch (\Throwable $e) {
            $this->logger->error('Message handling failed', [
                'message_name'  => $this->resolveMessageName($message),
                'message_class' => $message::class,
                'bus'           => $this->resolveBusName($envelope),
                'payload'       => $this->serializePayload($message),
                'error'         => [
                    'class'   => $e::class,
                    'message' => $e->getMessage(),
                    'file'    => $e->getFile(),
                    'line'    => $e->getLine(),
                    'trace'   => $e->getTraceAsString(),
                ],
            ]);

            throw $e;
        }
    }

    private function resolveMessageName(object $message): string
    {
        return method_exists($message, 'messageName')
            ? $message->messageName()
            : $message::class;
    }

    private function resolveBusName(Envelope $envelope): string
    {
        $stamp = $envelope->last(BusNameStamp::class);

        return $stamp instanceof BusNameStamp ? $stamp->getBusName() : 'unknown';
    }

    private function serializePayload(object $message): array
    {
        $payload = [];

        foreach (get_object_vars($message) as $key => $value) {
            if (in_array(strtolower($key), self::SENSITIVE_FIELDS, true)) {
                $payload[$key] = '[REDACTED]';
                continue;
            }

            $payload[$key] = match (true) {
                is_scalar($value) => $value,
                is_null($value)   => null,
                is_array($value)  => '[array]',
                is_object($value) => $value::class,
                default           => '[unknown]',
            };
        }

        return $payload;
    }
}
