<?php

declare(strict_types=1);

namespace App\Infrastructure\Http;

use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Messenger\Stamp\HandledStamp;

abstract class AppController
{
    public function __construct(
        protected readonly MessageBusInterface $commandBus,
        protected readonly MessageBusInterface $queryBus,
    ) {}

    protected function dispatchCommand(object $command): mixed
    {
        $envelope = $this->commandBus->dispatch($command);
        return $envelope->last(HandledStamp::class)?->getResult();
    }

    protected function dispatchQuery(object $query): mixed
    {
        $envelope = $this->queryBus->dispatch($query);
        return $envelope->last(HandledStamp::class)?->getResult();
    }

    /** @return array<string, mixed> */
    protected function body(Request $request): array
    {
        $data = json_decode($request->getContent(), true);
        return is_array($data) ? $data : [];
    }

    protected function json(mixed $data = null, int $status = JsonResponse::HTTP_OK): JsonResponse
    {
        return new JsonResponse($data, $status);
    }

    protected function noContent(): JsonResponse
    {
        return new JsonResponse(null, JsonResponse::HTTP_NO_CONTENT);
    }

    protected function created(): JsonResponse
    {
        return new JsonResponse(null, JsonResponse::HTTP_CREATED);
    }
}
