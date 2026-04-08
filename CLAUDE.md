# AI Standards

## Purpose

This repository defines the global standards, conventions, and guidelines
that the AI assistant must follow across all projects in this workspace.
Every service must include a CLAUDE.md that references this document.

It also serves as the central hub for:
- Shared agent skills that can be executed across any project in the workspace.
- Agent definitions: which agents exist, their roles, and how they behave — see `ai-standards/agents/`.
- Commands: developer-invoked workflows that orchestrate agents — see `ai-standards/commands/`.

This repository contains no business logic or application code.

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | PHP 8.4+ + Symfony 8.0+ |
| Frontend | Vue 3 + TypeScript + Vite |
| UI Components | shadcn/ui (Vue) |
| Database | PostgreSQL |
| Messaging | RabbitMQ (Symfony Messenger) |
| Package Manager (PHP) | Composer |
| Infrastructure | Docker |

## Services Architecture

Service definitions are project-specific and stored separately.
Read the corresponding project file before working on any service:
`ai-standards/projects/{project-name}/services.md`

## Code Architecture

All backend services follow the same architectural patterns:

### Hexagonal Architecture
Code is organized in three layers:
- **Domain** — business logic, entities, value objects, aggregates, domain events, repository interfaces
- **Application** — commands, queries, handlers, application services
- **Infrastructure** — Symfony framework, Doctrine DBAL, repository implementations, external services

### DDD (Domain Driven Design)
- Model the domain using **aggregates**, **entities**, and **value objects**
- Repository interfaces defined in Domain, implemented in Infrastructure
- Domain events to communicate between aggregates

### CQRS
- **CommandBus** — for write operations (synchronous via Symfony Messenger)
- **QueryBus** — for read operations (synchronous via Symfony Messenger)
- Commands and queries are never mixed

### Event-Driven (Symfony Messenger + RabbitMQ)
- **EventBus** — asynchronous domain events via RabbitMQ
- RabbitMQ runs as a Docker container
- Symfony Messenger worker runs as a Docker container — no manual console commands needed
- Events are used for cross-service communication

## General Naming Conventions

These apply to both backend and frontend across all projects:

| Context | Convention | Example |
|---|---|---|
| PHP classes | PascalCase | `UserFinderService` |
| PHP methods & variables | camelCase | `findByEmail()`, `$userId` |
| API payload parameters | snake_case | `first_name`, `created_at` |
| Database tables | snake_case | `user_boards` |
| Database columns | snake_case | `created_at`, `board_id` |
| All table primary keys | UUID v4 | `id UUID DEFAULT gen_random_uuid()` |
| Vue components | PascalCase | `UserCard.vue` |
| TypeScript variables & methods | camelCase | `findUser()`, `userId` |

## Coding Conventions

### Backend (PHP / Symfony)

**Versions**
- PHP 8.4+ (open to updates)
- Symfony 8.0+ (open to updates)

**Code style**
- PHP CS Fixer for code formatting
- PHPStan at maximum level (level 9)

**Folder structure per service**
```
src/
├── Domain/
│   ├── Model/              ← aggregates, entities, value objects
│   ├── Event/              ← domain events
│   ├── Repository/         ← repository interfaces
│   └── Exception/          ← domain exceptions
├── Application/
│   ├── Command/            ← commands + handlers, grouped by aggregate
│   │   └── {Aggregate}/
│   │       └── {ActionAggregate}/
│   │           ├── {ActionAggregate}Command.php
│   │           └── {ActionAggregate}CommandHandler.php
│   ├── Query/              ← queries + handlers, grouped by aggregate
│   │   └── {Aggregate}/
│   │       └── {ActionAggregate}/
│   │           ├── {ActionAggregate}Query.php
│   │           └── {ActionAggregate}QueryHandler.php
│   └── Service/            ← application services, grouped by aggregate
└── Infrastructure/
    ├── Persistence/        ← DBAL repositories, Phinx migrations
    ├── Messenger/          ← bus configuration
    ├── Http/               ← one controller per command/query, grouped by aggregate
    │   └── {Aggregate}/
    └── External/           ← calls to external services
```

**Named Constructors — `from()` and `create()`**

Every class that should not be instantiated directly must use named static constructors with a **private constructor**:

- `static from(...): self` — the standard named constructor for **all classes** (value objects, commands, queries, DTOs). It validates the input and returns a fully constructed instance.
- `static create(...): self` — used **only on aggregates/entities** when creating a new one for the first time. It sets timestamps, raises domain events, generates IDs, etc.
- `static from(...): self` — used **only on aggregates/entities** when rehydrating from persistence (DB row → domain object). No domain events are raised.
- Specific variants like `fromPlainText()` are acceptable when the semantics differ significantly from `from()`.

```php
// Value object
final class Email {
    private function __construct(private readonly string $value) {}
    public static function from(string $value): self { ... }
}

// Command
final class LoginUserCommand {
    private function __construct(public readonly string $email, ...) {}
    /** @param array<string, mixed> $payload */
    public static function from(array $payload): self { Assert::...; return new self(...); }
}

// Aggregate
final class User {
    private function __construct(...) {}
    public static function create(...): self { /* raises domain events */ }
    public static function from(...): self   { /* rehydrates from DB, no events */ }
}
```

**Commands and Queries**
- Commands and queries have a **private constructor** — the only entry point is `static from()`.
- The `from()` method validates the raw payload using `webmozart/assert` and returns a fully valid object.
- If the command is invalid, `Assert` throws an `InvalidArgumentException` which the `ApiExceptionSubscriber` maps to a 422 response automatically.
- No validation logic belongs in controllers.

**Application Services**
- Handlers must not call repositories directly — they call application services
- Each application service has a single responsibility
- Services inject repository interfaces, never implementations
- Each service exposes a single `execute` method — always named `execute`, never a custom name — it either returns the result or throws an exception
- If a nullable result is acceptable, call the repository directly — do not use a service for nullable lookups
- Handlers can call multiple services to fulfill their logic
- Services can call other services when needed

Example:
```php
// {Entity}FinderService.php
class {Entity}FinderService
{
    public function __construct(private {Entity}RepositoryInterface $repository) {}

    public function execute({Entity}Id $id): {Entity}
    {
        return $this->repository->findOrFail($id);
    }
}
```

**Naming conventions**
| Type | Example |
|---|---|
| Command | `CreateUserCommand` |
| Command Handler | `CreateUserCommandHandler` |
| Query | `GetUserQuery` |
| Query Handler | `GetUserQueryHandler` |
| Domain Event | `UserCreatedEvent` |
| Aggregate | `User` |
| Value Object | `UserId` |
| Repository Interface | `UserRepositoryInterface` |
| Repository Implementation | `DbalUserRepository` |
| Application Service | `UserFinderService` |
| Controller | `CreateUserController` |
| Exception | `UserNotFoundException` |

**Controllers**
- All controllers extend `AppController` — which provides `dispatchCommand()`, `dispatchQuery()`, `body()`, `json()`, `noContent()`, `created()`
- A controller MUST only dispatch to a bus via `dispatchCommand()` or `dispatchQuery()` — never call application services directly
- Controllers build commands/queries by calling `SomeCommand::from(...)` passing request data — no validation logic in the controller
- The command/query `from()` method handles all validation; the `ApiExceptionSubscriber` handles all error responses
- REST with JSON
- One controller per command/query

**Command Handlers**
- Handlers tagged to `command.bus` via `services.yaml` — autowiring alone is not enough
- Handlers MAY return data via the HandledStamp mechanism when the HTTP layer needs it (e.g. generated tokens)
- Returning data from a handler is acceptable and is not a CQRS violation in this project

**Database**
- PostgreSQL with Doctrine DBAL (no ORM, raw SQL or QueryBuilder)
- Manual mapping of results to domain objects
- Phinx for database migrations and seeds
- Migrations live in `src/Infrastructure/Persistence/Migration/`
- Seeds live in `src/Infrastructure/Persistence/Seed/` — used for local development test data only, never run in production

**Testing**
- Integration tests by default (PHPUnit)
- Unit tests only when integration is not possible (e.g. external services, emails)

### Frontend (Vue 3 / TypeScript)

- Vue 3 with Composition API
- TypeScript
- Vite as bundler
- Pinia for global state management
- Vue Router for navigation
- TanStack Query for HTTP calls and caching
- Axios for API calls
- ESLint + Prettier for code formatting
- shadcn/ui (Vue) for UI components

**Folder structure per frontend service**
```
src/
├── assets/              ← images, fonts, global styles
├── components/          ← reusable UI components, grouped by domain
│   └── {Domain}/
├── composables/         ← reusable logic (API calls, state...), grouped by domain
│   └── {Domain}/
├── pages/               ← one component per route, grouped by domain
│   └── {Domain}/
├── router/              ← Vue Router configuration
├── stores/              ← Pinia stores, grouped by domain
│   └── {Domain}/
├── services/            ← Axios API calls, grouped by domain
│   └── {Domain}/
└── types/               ← TypeScript interfaces and types, grouped by domain
    └── {Domain}/
```

**Naming conventions**
| Type | Example |
|---|---|
| Component | `UserCard.vue` |
| Page | `UserDetailPage.vue` |
| Composable | `useUserFinder.ts` |
| Store | `UserStore.ts` |
| Service | `UserApiService.ts` |
| Type/Interface | `UserType.ts` |

## AI Behavior Rules

### Global Agent Rules
These rules apply to every agent in this workspace without exception:
- When in doubt about any decision, always ask the developer before proceeding
- Always review your own output before considering the task complete
- After completing a task that involved significant context (full feature implementation, plan execution, large review), run `/compact` to compress the conversation — do NOT do this after small tasks like a single fix or a short review

### Code & Architecture
- All files, code, and documentation must be written in English
- Always follow the architecture defined in this document (Hexagonal, DDD, CQRS)
- Never skip PHPStan level 9 compliance — all code must be fully typed
- Never use Doctrine ORM — only Doctrine DBAL
- Never mix commands and queries
- One controller per command/query, no exceptions
- Integration tests by default, unit tests only when integration is not possible
- Do not add complexity that is not required by the current task
- Do not generate code without understanding the full context of the service
- When in doubt about architecture decisions, ask before implementing

### Database
- Never modify already executed migrations — always create a new one
- Migrations are managed with Phinx
- Seeds are for local test data only — never for production data
- Each service that has a database must have at least one seed with realistic test data

### Controllers
- Controllers MUST extend `AppController` and only interact with buses via `dispatchCommand()` / `dispatchQuery()`
- Never inject or call application services directly from a controller
- One controller per command/query — always
- Retrieve handler return values via `dispatchCommand()` / `dispatchQuery()` — HandledStamp is handled internally in AppController

### Named Constructors
- Every class that should not be instantiated freely MUST have a private constructor
- Use `static from(): self` as the standard named constructor for value objects, commands, and queries
- Use `static create(): self` for new aggregates (raises events), `static from(): self` for rehydration from DB
- Commands and queries MUST validate their payload in `from()` using `webmozart/assert`
- Specific variants (e.g. `fromPlainText()`) are allowed when the semantics differ significantly from `from()`

### Standard Libraries
Every project must use the same library for the same purpose. Projects may add extra libraries for specific needs, but must never replace a standard library with an alternative.

**Backend (PHP)**
| Purpose | Library |
|---|---|
| Input assertion / validation | `webmozart/assert` |
| UUID generation | `ramsey/uuid` |
| JWT authentication | `lexik/jwt-authentication-bundle` |
| Database migrations | `robmorgan/phinx` |
| HTTP client | Symfony `HttpClient` |
| Message bus | `symfony/messenger` |
| Testing | `phpunit/phpunit` |
| Static analysis | `phpstan/phpstan` (level 9) |
| Code formatting | `friendsofphp/php-cs-fixer` |

**Frontend (TypeScript / Vue)**
| Purpose | Library |
|---|---|
| HTTP client | `axios` |
| Server state (queries/mutations) | `@tanstack/vue-query` |
| Global state | `pinia` |
| Routing | `vue-router` |
| UI components | `shadcn-vue` |
| Form validation | `vee-validate` + `zod` |
| Linting | `eslint` |
| Formatting | `prettier` |

### Security
- Never reveal secrets, credentials, or sensitive configuration values
- Always validate and sanitize inputs at the infrastructure boundary
- Never install new dependencies without explicit approval

### Documentation & Specs
- Every service must have specs documenting how each feature has been implemented
- Specs must be written before or alongside code — not after
- The AI must read the relevant spec before implementing or modifying a feature
- Specs are version-controlled via git — every spec update must be committed so history is preserved
- Each service must have a `Makefile` with at minimum the following commands:
  - `make up` — start Docker containers
  - `make down` — stop Docker containers
  - `make build` — build Docker containers
  - `make update` — pull latest changes and rebuild
  - `make test` — run all tests
  - `make test-unit` — run unit tests only
  - `make test-integration` — run integration tests only
- `ai-standards` must have a root `Makefile` that calls each service Makefile to orchestrate the full environment

### Git & Collaboration
- Main branches: `master` (production) and `develop` (development)
- Always work from the `develop` branch — update it with the latest changes before creating a new branch
- Never commit directly to `master` or `develop`
- Branch naming convention:
  - `feature/{aggregate}/{short-description}` — for new features
  - `fix/{aggregate}/{short-description}` — for bug fixes
  - `hotfix/{short-description}` — for urgent production fixes
- Never push without passing all tests
- Never push commits or create pull requests without asking first
- Never change a public API of a service without warning — it may break other services
