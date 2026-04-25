# Authorization Standards

## Philosophy

- Authentication answers *who* you are. Authorization answers *what you may do*. They are separate concerns and live in separate code paths — `security.md` covers the first, this file covers the second.
- Every protected operation has a single, named authorization point. Scattered `if ($user->role === 'admin')` checks are a security defect, not a coding style issue — they drift, get forgotten, and are invisible to review.
- Deny by default. The absence of an explicit allow rule is a deny. A handler that does not name its authorization decision MUST refuse the request.
- Authorization decisions are testable artifacts: every protected endpoint has a test that asserts both the allowed and the denied paths.
- Tenant scoping is part of authorization, not part of querying. A query that "happens to filter by tenant_id" is not a substitute for a checked authorization decision — the next refactor will drop the filter.

---

## When this standard applies

This standard applies the moment any of these is true:

- The system has more than one role beyond "anonymous + authenticated user"
- A resource has an owner and other users may or may not see it
- The system is multi-tenant (organizations, workspaces, accounts that isolate data)
- Different actions on the same resource have different rules (read vs delete vs export)

If none of these is true, the project may rely on `security.md` JWT auth alone and revisit this standard when one of them becomes true.

---

## Vocabulary

The standard uses three terms with strict meanings:

| Term | Meaning |
|---|---|
| **Subject** | The authenticated identity asking to do something — typically a `User`, but may be a service account or an API client |
| **Action** | The operation requested, named in domain language: `board.view`, `board.delete`, `professional.publish_demand`, `payout.export` |
| **Resource** | The object the action applies to — an aggregate instance, a tenant, or a global capability (`*`) |

A decision is always the triple `(Subject, Action, Resource) → allow | deny`. If a piece of code makes an authorization decision without naming all three, it is wrong.

---

## Choosing the model: RBAC, ABAC, or hybrid

Most projects need RBAC at the role-list level and ABAC for ownership/state-dependent decisions. Pick the model **per action**, not per project:

| Decision shape | Model | Example |
|---|---|---|
| "Anyone with role X may do action Y" | RBAC | `admin → user.delete` |
| "The action is allowed when the resource matches a property of the subject" | ABAC | A user may edit a board only if `board.owner_id == subject.id` |
| "The action is allowed when the resource is in a given state and the subject has role X" | hybrid | A reviewer may publish content only if `content.status == 'pending_review'` |

The default for a new aggregate is: define the roles allowed to attempt the action (RBAC), then add an ownership/state predicate (ABAC) inside the Voter. Avoid pure ABAC libraries that require a policy DSL — Voter classes in PHP are explicit, type-safe, and reviewable.

The exact model picked for the project is recorded in an ADR (`{project-docs}/decisions.md`) at the moment the first protected handler is written.

---

## The Voter pattern (canonical implementation)

Every authorization decision is delegated to a Voter — a small class with one method that returns `true | false`. Voters live in `src/Domain/Authorization/Voter/` and are pure: no side effects, no logging, no event dispatch.

```php
namespace App\Domain\Authorization\Voter;

use App\Domain\Authorization\Subject;
use App\Domain\Board\Model\Board;

final readonly class BoardVoter
{
    public function canView(Subject $subject, Board $board): bool
    {
        return $subject->tenantId === $board->tenantId
            && ($subject->hasRole('viewer') || $subject->hasRole('editor') || $subject->hasRole('admin'));
    }

    public function canDelete(Subject $subject, Board $board): bool
    {
        return $subject->tenantId === $board->tenantId
            && ($subject->id === $board->ownerId || $subject->hasRole('admin'));
    }
}
```

The handler asks the Voter and stops if the answer is `false`. No business logic runs before the check.

```php
final readonly class DeleteBoardCommandHandler
{
    public function __construct(
        private BoardFinderService $finder,
        private BoardVoter $voter,
        private BoardRepositoryInterface $boards,
    ) {}

    public function __invoke(DeleteBoardCommand $command): void
    {
        $subject = $command->subject;
        $board = $this->finder->execute($command->boardId);

        if (!$this->voter->canDelete($subject, $board)) {
            throw new ForbiddenActionException('board.delete', $board->id);
        }

        $this->boards->delete($board);
    }
}
```

Rules of the Voter pattern:

- One Voter per aggregate. Cross-aggregate decisions (e.g. "may a Board owner export Payouts of their tenant?") live in an `Application/Authorization/` service that composes Voters — never on the aggregate Voter itself.
- Voters return `bool`, never throw. The handler is the only place that turns a `false` into `ForbiddenActionException`.
- Voters never load data. The aggregate is loaded by the handler (via the Finder) and passed in. A Voter that touches the database is a sign of missing data on the aggregate.
- Voters are unit-tested with raw `Subject` and aggregate fixtures — no Symfony container, no DBAL.

---

## The `Subject` Value Object

The Subject crosses every layer and must be a Value Object, not a `User` entity. The entity may grow fields a Voter has no business reading.

```php
namespace App\Domain\Authorization;

final readonly class Subject
{
    /** @param list<string> $roles */
    private function __construct(
        public string $id,
        public string $tenantId,
        public array $roles,
    ) {}

    /** @param list<string> $roles */
    public static function from(string $id, string $tenantId, array $roles): self
    {
        return new self($id, $tenantId, $roles);
    }

    public function hasRole(string $role): bool
    {
        return in_array($role, $this->roles, true);
    }
}
```

The Subject is built once per request from the JWT claims (see "JWT integration" below) and propagated as part of the Command/Query DTO. Handlers never reach into a global session — every command carries the Subject explicitly.

---

## Tenant scoping (multi-tenant systems)

In a multi-tenant system, `tenant_id` is part of every aggregate's identity, every query's filter, and every authorization decision. The rules:

### Schema rule

Every multi-tenant table has `tenant_id UUID NOT NULL`. The column is part of every index that supports a tenant-scoped query.

```sql
CREATE TABLE boards (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id UUID NOT NULL,
    owner_id UUID NOT NULL,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_boards_tenant_owner ON boards (tenant_id, owner_id);
CREATE INDEX idx_boards_tenant_created ON boards (tenant_id, created_at DESC);
```

A query that does not filter by `tenant_id` on a multi-tenant table is a **cross-tenant leak** — `MUST` reject in review.

### Repository rule

Tenant-scoped repository methods accept the tenant id as the first argument. There is no "current tenant" magic — the value comes from the Subject and is passed explicitly.

```php
public function findById(string $tenantId, string $boardId): ?Board;
public function search(string $tenantId, string $query, int $limit, int $offset): array;
```

### Voter rule

Every Voter check on a tenant-scoped aggregate compares `subject.tenantId === resource.tenantId` first. This check is in addition to role/ownership rules, never instead of them.

### Anti-pattern

```php
// WRONG — pulls "current tenant" from a service. The handler signature lies about its inputs.
$board = $this->boards->findById($id);
if ($board->tenantId !== $this->tenantContext->current()) { ... }

// CORRECT — tenant id flows in via the command, comparison happens in the Voter.
$board = $this->boards->findById($command->subject->tenantId, $command->boardId);
$this->voter->canView($command->subject, $board) || throw new ForbiddenActionException(...);
```

A "tenant context" service is acceptable as a *boundary helper* (controller reads JWT, mints Subject, hands it off). It is not acceptable as a way to *avoid passing tenant id through the layers*.

---

## JWT integration

The JWT carries the minimum identity needed to mint a Subject. Per `security.md`, the payload contains `user_id`, `tenant_id`, `roles`, `exp` — and nothing else.

A request handler builds the Subject in the controller before dispatching the command:

```php
final class DeleteBoardController extends AppController
{
    public function __invoke(string $boardId, Request $request): Response
    {
        $subject = $this->subjectFromRequest($request);
        $this->dispatchCommand(new DeleteBoardCommand($subject, $boardId));
        return new Response(null, 204);
    }
}
```

Where `subjectFromRequest()` lives in `AppController` and reads the validated JWT once. Roles in the JWT are an authoritative snapshot at login time — the application MUST treat role revocation as effective at most one access-token TTL after the change (15 min per `security.md`). Projects that need shorter MUST NOT extend access-token TTL — they MUST add a per-request role re-check via a fast cache, declared as a project ADR.

---

## API responses

| Situation | Status | Body |
|---|---|---|
| Subject is unauthenticated | 401 | `{ "error": "unauthorized" }` |
| Subject is authenticated but the action is denied | 403 | `{ "error": "forbidden", "details": [{ "action": "board.delete", "resource_id": "..." }] }` |
| The resource does not exist AND the subject would not be allowed to know it does | 404 | Same shape as a real "not found". Avoid leaking existence via 403/404 distinction |

Rules:

- Never include the reason for denial in the response body. "You lack role admin" is enumeration help.
- Never reveal aggregate metadata in a 403 (no name, no owner). The denial is opaque.
- The `Forbidden` is logged with `event=authz.denied`, `action`, `subject_id`, `tenant_id`, `resource_id` (see `logging.md` redaction list — these are not secrets but they ARE PII; see `gdpr-pii.md`).

---

## Service-to-service authorization

When service A calls service B internally, B still applies authorization. The Subject passed across is one of:

- **End-user delegation:** A forwards the original JWT or a propagated `traceparent`-bound subject. B sees the original Subject and applies the same Voters.
- **Service identity:** A calls B with its own credentials. B mints a service Subject (`Subject::from('svc:a', 'shared', ['service:a'])`) and Voters check the `service:a` role. Service Subjects MUST NEVER carry a real tenant id — they use the literal `shared`.

The choice is per call site, recorded in the API contract (see `api-contracts.md`). Mixing the two on the same endpoint without explicit contract is a defect.

---

## Testing

Every protected action has at least three tests:

1. **Allowed path** — happy case, decision is `true`, side effect happens.
2. **Denied by role** — Subject lacks the role, response is 403, side effect does NOT happen, audit log entry exists (see `audit-log.md`).
3. **Denied by tenant** — Subject is in a different tenant, response is 404 (preferred) or 403, side effect does NOT happen.

Voter unit tests are pure — fixture Subject + fixture aggregate, assert the boolean. They run in milliseconds and are the fastest signal that an authorization rule changed.

```php
public function testOwnerCanDeleteOwnBoard(): void
{
    $subject = Subject::from('user-1', 'tenant-1', ['editor']);
    $board = Board::from('board-1', 'tenant-1', 'user-1', 'My board');

    self::assertTrue((new BoardVoter())->canDelete($subject, $board));
}

public function testNonOwnerCannotDeleteBoard(): void
{
    $subject = Subject::from('user-2', 'tenant-1', ['editor']);
    $board = Board::from('board-1', 'tenant-1', 'user-1', 'My board');

    self::assertFalse((new BoardVoter())->canDelete($subject, $board));
}

public function testCrossTenantDeniedRegardlessOfRole(): void
{
    $subject = Subject::from('user-1', 'tenant-2', ['admin']);
    $board = Board::from('board-1', 'tenant-1', 'user-1', 'My board');

    self::assertFalse((new BoardVoter())->canDelete($subject, $board));
}
```

A change to a Voter without an updated test is a hard reject in review.

---

## Observability

Every authorization decision emits a span event on the handler span (see `observability.md`):

| Attribute | Required | Example |
|---|---|---|
| `authz.action` | yes | `board.delete` |
| `authz.decision` | yes | `allow` / `deny` |
| `authz.subject_role` | yes | `editor` (the highest-privilege role considered) |
| `authz.deny_reason` | when `deny` | `cross_tenant` / `missing_role` / `not_owner` |

Denials emit a metric `authz_denied_total{action, deny_reason}` (no subject_id label — high cardinality and PII).

A spike in `cross_tenant` denials is a probe; a spike in `missing_role` after a deploy is a regression. Both deserve alerts (see `observability.md` SLO shape).

---

## Anti-patterns (auto-reject in review)

- A handler with NO Voter call. Even read endpoints declare an explicit `canView()`.
- A repository method without `tenant_id` parameter on a multi-tenant aggregate.
- Authorization decisions made inside a service called by multiple handlers without a Voter being involved (the service does not see all relevant context).
- Caching authorization decisions in Redis. The Voter is fast; cached decisions outlive role revocations and are dangerous.
- Adding a role string at runtime (`$subject->roles[] = 'admin'`). Subject is immutable.
- Logging denial reasons in user-facing responses.
- Storing `tenant_id` only in JWT and trusting the JWT in repository queries (the JWT validation may have been skipped on a misrouted request).

---

## What the reviewer checks

Authorization rules are enforced during review via the backend reviewer checklist (see [`backend-review-checklist.md`](backend-review-checklist.md) → "Authorization") and the frontend reviewer checklist for route guards (see [`frontend-review-checklist.md`](frontend-review-checklist.md) → "Authorization"). The checklists are the authoritative surface — if a rule appears here and not in the checklist, file a minor and update the checklist in the same commit.
