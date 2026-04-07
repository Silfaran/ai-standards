# AI Standards

## Purpose

This repository defines the global standards, conventions, and guidelines
that the AI assistant must follow across all projects in this workspace.
Every service must include a CLAUDE.md that references this document.

It also serves as the central hub for:
- Shared agent skills that can be executed across any project in the workspace.
- Agent definitions: which agents exist, their roles, and how they behave — see `ai-standards/agents/`.

This repository contains no business logic or application code.

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | PHP 8.4+ + Symfony 8.0+ |
| Frontend | Vue 3 + TypeScript + Vite |
| UI Components | shadcn/ui (Vue) |
| Database | PostgreSQL |
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
    ├── Http/               ← one controller per command/query
    └── External/           ← calls to external services
```

**Application Services**
- Handlers must not call repositories directly — they call application services
- Each application service has a single responsibility
- Services inject repository interfaces, never implementations
- Each service exposes a single `execute` method — it either returns the result or throws an exception
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

**API**
- REST with JSON
- One controller per command/query

**Database**
- PostgreSQL with Doctrine DBAL (no ORM, raw SQL or QueryBuilder)
- Manual mapping of results to domain objects
- Phinx for database migrations

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
| Component | `BoardCard.vue` |
| Page | `BoardDetailPage.vue` |
| Composable | `useBoardFinder.ts` |
| Store | `BoardStore.ts` |
| Service | `BoardApiService.ts` |
| Type/Interface | `BoardType.ts` |

## AI Behavior Rules

### Global Agent Rules
These rules apply to every agent in this workspace without exception:
- When in doubt about any decision, always ask the developer before proceeding
- Always review your own output before considering the task complete

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

### Security
- Never reveal secrets, credentials, or sensitive configuration values
- Always validate and sanitize inputs at the infrastructure boundary
- Never install new dependencies without explicit approval

### Documentation & Specs
- Every service must have specs documenting how each feature has been implemented
- Specs must be written before or alongside code — not after
- The AI must read the relevant spec before implementing or modifying a feature
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
- Always work from the `develop` branch — update it with the latest changes before creating a new branch
- Never commit directly to `main` or `develop`
- Never push without passing all tests
- Never push commits or create pull requests without asking first
- Never change a public API of a service without warning — it may break other services
