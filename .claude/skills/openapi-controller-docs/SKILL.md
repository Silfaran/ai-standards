---
name: openapi-controller-docs
description: Use when writing a PHP/Symfony controller that exposes a new API endpoint (POST, GET, DELETE, PATCH, PUT) — to add complete OpenAPI attributes (#[OA\...]) covering request body, query params, response schemas per status code, error envelope, tags, and security. Applies whenever a controller is created or modified, or when the API contract changes.
paths: "**/src/Infrastructure/Http/**/*.php, **/src/Infrastructure/Controller/**/*.php"
---

# OpenAPI attributes on Symfony controllers

Every controller exposing a public endpoint carries **complete** OpenAPI attributes from `nelmio/api-doc-bundle` + `zircote/swagger-php`. The generated `openapi.json` is the contract — anything missing from it does not exist, and the frontend type generator will not produce a type for it.

This skill fixes the five mistakes that recur in every backend review.

## Canonical shape — POST with request body

```php
use OpenApi\Attributes as OA;
use Symfony\Component\Routing\Attribute\Route;

#[OA\Post(
    path: '/api/password/reset',
    summary: 'Confirm a new password using a reset token',
    tags: ['Auth'],
    requestBody: new OA\RequestBody(
        required: true,
        content: new OA\JsonContent(
            required: ['token', 'password'],
            properties: [
                new OA\Property(property: 'token', type: 'string', example: 'a1b2c3...'),
                new OA\Property(property: 'password', type: 'string', example: 'NewSecret1!'),
            ],
        ),
    ),
    responses: [
        new OA\Response(response: 204, description: 'Password reset — all sessions invalidated'),
        new OA\Response(response: 400, description: 'Invalid JSON / invalid or expired reset link'),
        new OA\Response(response: 422, description: 'Missing field or password policy violation'),
        new OA\Response(response: 429, description: 'Too many reset attempts'),
    ],
)]
#[Route('/api/password/reset', methods: ['POST'])]
public function __invoke(Request $request): JsonResponse
```

## Canonical shape — GET with query params and 200 response schema

```php
#[OA\Get(
    path: '/api/boards',
    summary: 'List the current user\'s boards',
    tags: ['Boards'],
    security: [['bearerAuth' => []]],
    parameters: [
        new OA\Parameter(name: 'search', in: 'query', required: false, schema: new OA\Schema(type: 'string')),
        new OA\Parameter(name: 'page', in: 'query', required: false, schema: new OA\Schema(type: 'integer', default: 1)),
        new OA\Parameter(name: 'per_page', in: 'query', required: false, schema: new OA\Schema(type: 'integer', default: 20)),
    ],
    responses: [
        new OA\Response(
            response: 200,
            description: 'Paginated board list',
            content: new OA\JsonContent(
                properties: [
                    new OA\Property(
                        property: 'data',
                        type: 'array',
                        items: new OA\Items(
                            properties: [
                                new OA\Property(property: 'id', type: 'string', format: 'uuid'),
                                new OA\Property(property: 'name', type: 'string'),
                                new OA\Property(property: 'created_at', type: 'string', format: 'date-time'),
                            ],
                            type: 'object',
                        ),
                    ),
                    new OA\Property(
                        property: 'meta',
                        properties: [
                            new OA\Property(property: 'total', type: 'integer'),
                            new OA\Property(property: 'page', type: 'integer'),
                            new OA\Property(property: 'per_page', type: 'integer'),
                        ],
                        type: 'object',
                    ),
                ],
            ),
        ),
        new OA\Response(response: 401, description: 'Not authenticated'),
    ],
)]
#[Route('/api/boards', methods: ['GET'])]
```

## Canonical shape — DELETE (no body, no response payload)

```php
#[OA\Delete(
    path: '/api/boards/{id}',
    summary: 'Delete a board owned by the current user',
    tags: ['Boards'],
    security: [['bearerAuth' => []]],
    parameters: [
        new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string', format: 'uuid')),
    ],
    responses: [
        new OA\Response(response: 204, description: 'Board deleted'),
        new OA\Response(response: 403, description: 'Not the owner of the board'),
        new OA\Response(response: 404, description: 'Board not found'),
    ],
)]
#[Route('/api/boards/{id}', methods: ['DELETE'])]
```

## Rules

1. **One `OA\Response` per status code the controller can return.** Read `ApiExceptionSubscriber` and list every mapped status — including 400 / 422 / 429 if the handler can raise them. Missing a status is a contract bug, not a doc gap.
2. **`required:` lists every non-optional request body field.** Fields omitted from `required:` become optional in the generated frontend types — which silently masks broken client code.
3. **Nullable response fields use `nullable: true`** and must still be emitted by the serializer even when `null`. Per [`api-contracts.md`](../../../standards/api-contracts.md), omitting a nullable field is a contract violation.
4. **Use `format:` where the type alone is ambiguous** — `uuid`, `date-time`, `email`, `uri`. The frontend generator uses these to pick stricter types.
5. **`security:` is explicit on every authenticated endpoint** — `[['bearerAuth' => []]]`. Unauthenticated endpoints omit it. Never rely on a default.
6. **`tags:` groups endpoints in the generated UI.** Use the aggregate name (`Boards`, `Tasks`, `Auth`) — never the controller name or the HTTP verb.

## Payload conventions (per `api-contracts.md`)

- Request/response payload field names are `snake_case`. Never mix casing.
- Timestamps: `type: 'string', format: 'date-time'` with RFC 3339 UTC in `example:`.
- Money: `type: 'integer'` for the minor unit, sibling `currency` field — never `type: 'number'`.
- Enums: `type: 'string', enum: ['pending', 'in_progress', 'done']`. Values are `snake_case`.
- UUIDs (ids, foreign keys): `type: 'string', format: 'uuid'`.

## Error envelope

Every controller that can return ≥ 400 follows the error envelope defined once for the service:

```json
{ "error": "Human-readable message" }
```

OpenAPI example on a 422 response:

```php
new OA\Response(
    response: 422,
    description: 'Validation failed',
    content: new OA\JsonContent(
        properties: [new OA\Property(property: 'error', type: 'string', example: 'Invalid email format')],
    ),
),
```

Changing the error envelope is a breaking change for every caller of every endpoint — see `api-contracts.md` → Breaking-change protocol.

## Common mistakes

- **Listing `200` when the controller returns `204`.** Match the status your `AppController` helper emits (`$this->noContent()` → 204, `$this->created(...)` → 201).
- **`OA\JsonContent` with no `properties:`.** The generator emits `{}` and the frontend type becomes `unknown`. Always describe every field the response contains.
- **Forgetting 429 on rate-limited endpoints.** If the controller holds a `RateLimiterFactory` dependency, 429 is possible — document it.
- **Array responses without `OA\Items`.** `type: 'array'` alone generates `unknown[]`. Always provide `items:` with the element schema.
- **Hand-written OpenAPI fragments in YAML files alongside the controller.** The attributes are the single source — duplicate YAML drifts silently.
- **Using the controller class name as the `tags:` value.** Tags group by aggregate, not by class file.

## See also

- [`standards/api-contracts.md`](../../../standards/api-contracts.md) — versioning, breaking-change protocol, payload conventions, response envelope.
- [`standards/backend.md`](../../../standards/backend.md) — controller rules (one per command/query, `AppController` base class).
- [`standards/backend-review-checklist.md`](../../../standards/backend-review-checklist.md) → "API Contracts" section — the closed checklist the Backend Reviewer verifies.
- `cors-nelmio-configuration` skill — when a new endpoint is being added to a service with CORS.
