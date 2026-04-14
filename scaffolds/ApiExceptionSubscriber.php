<?php

declare(strict_types=1);

namespace App\Infrastructure\Http\EventSubscriber;

use InvalidArgumentException;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpKernel\Event\ExceptionEvent;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use Symfony\Component\HttpKernel\KernelEvents;
use Symfony\Component\Messenger\Exception\HandlerFailedException;

final class ApiExceptionSubscriber implements EventSubscriberInterface
{
    public static function getSubscribedEvents(): array
    {
        return [KernelEvents::EXCEPTION => ['onKernelException', 10]];
    }

    public function onKernelException(ExceptionEvent $event): void
    {
        $exception = $event->getThrowable();

        // Unwrap exceptions thrown inside Messenger handlers
        if ($exception instanceof HandlerFailedException) {
            $exception = $exception->getPrevious() ?? $exception;
        }

        // Let Symfony handle its own HTTP exceptions (404, 405, etc.)
        if ($exception instanceof HttpExceptionInterface) {
            return;
        }

        $response = match (true) {
            // Map your domain exceptions here:
            // $exception instanceof SomeDomainException => $this->notFound('Resource not found'),
            $exception instanceof InvalidArgumentException => $this->unprocessable($exception->getMessage()),
            default => null,
        };

        if (null !== $response) {
            $event->setResponse($response);
        }
    }

    private function conflict(string $error): JsonResponse
    {
        return new JsonResponse(['error' => $error], Response::HTTP_CONFLICT);
    }

    private function notFound(string $error): JsonResponse
    {
        return new JsonResponse(['error' => $error], Response::HTTP_NOT_FOUND);
    }

    /** @param string[] $details */
    private function unprocessable(string $error, array $details = []): JsonResponse
    {
        $body = ['error' => $error];
        if ([] !== $details) {
            $body['details'] = $details;
        }
        return new JsonResponse($body, Response::HTTP_UNPROCESSABLE_ENTITY);
    }

    private function unauthorized(string $error): JsonResponse
    {
        return new JsonResponse(['error' => $error], Response::HTTP_UNAUTHORIZED);
    }
}
