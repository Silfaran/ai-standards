# Feature Flags Standards

## Philosophy

- A feature flag is a temporary decoupling of release from deploy. Flags that have lived in code for over a quarter without ramping or removal are not flags — they are config debt with a flag interface.
- Flags are NOT a substitute for authorization. A flag answers "is the system delivering this code path right now?"; authorization answers "is this subject allowed to take that action?". Conflating the two leads to admins toggling permissions.
- Every flag has a name, an owner, an expected lifespan, and a removal plan from the day it lands. A flag with no removal date is a defect.
- Flag evaluations happen at one place per code path, near the boundary, never sprinkled across helpers. The downstream code does not know a flag is involved.
- Flag evaluation is observable. The system records which flag was evaluated, with what context, and what the answer was — so a regression "only on enrolled users" can be reproduced.

---

## When this standard applies

This standard applies whenever the system needs to:

- Ramp a new feature gradually (1% → 10% → 100% of users)
- Hide an in-progress feature behind a switch until launch
- Disable a feature in an emergency without deploying
- Run an A/B experiment that branches behaviour between two cohorts
- Enable a capability per-tenant (a new module turned on for a specific customer)
- Stage rollouts by jurisdiction or country (GDPR-compliant launch in EU first)

It does NOT cover environment configuration (`dev` vs `prod` differences) — that lives in env vars per `secrets.md` and per-environment compose. It does NOT cover authorization decisions — those go through Voters per `authorization.md`.

---

## Vocabulary

| Term | Meaning |
|---|---|
| **Flag** | A named boolean (or small enum) the system evaluates at runtime to decide a code path |
| **Targeting rule** | The logic that decides "is this subject in or out": global on/off, percentage rollout, list of tenants/users, country/region, etc. |
| **Evaluation context** | The inputs passed to the targeting rule: subject id, tenant id, locale, country, plan tier, custom attributes |
| **Variant** | The value returned by an evaluation. For booleans: `true`/`false`. For multivariate (A/B/C tests): a string identifier |
| **Sticky bucketing** | When the same subject always gets the same variant — required for any user-visible flag so the experience stays consistent across requests |
| **Kill switch** | A flag whose only purpose is "turn off in production immediately if this breaks" — read-mostly, no targeting, no experiment |
| **Holdout** | A small percentage permanently excluded from a rollout to keep a baseline measurable |

---

## Flag taxonomy

The standard recognises four kinds of flags. The kind dictates the lifespan and the removal plan:

| Kind | Purpose | Default lifespan | Removal trigger |
|---|---|---|---|
| **Release flag** | Ramp a new feature from 0% to 100% | 1–4 weeks | Reaches 100% globally and stable for 1+ week → remove |
| **Operational / kill switch** | Disable a code path in incident response | Indefinite | Outlives the dependency it protects |
| **Experiment flag** | A/B(/C) test for a hypothesis | The experiment's planned duration + 1 week buffer | Experiment concluded, decision recorded as ADR |
| **Permission / entitlement flag** | "Tenant Acme has the analytics module enabled" | Indefinite | Becomes part of the plan / billing model proper |

A `Release` or `Experiment` flag with no removal date is a defect — it MUST have a target end date in the registry.

---

## The flag registry

Every flag in the system is declared in `{project-docs}/feature-flags.md`, the single source of truth.

| Column | Meaning |
|---|---|
| `key` | The flag identifier as the code uses it: `oficios_search_v2`, `payouts_kill_switch`, `mentor_match_experiment` |
| `kind` | One of `release`, `operational`, `experiment`, `permission` |
| `owner` | The team or person who can ramp / remove the flag |
| `created` | RFC 3339 date the flag was added |
| `expected_removal` | RFC 3339 date the flag should be gone (`indefinite` only for `operational` / `permission`) |
| `default` | The value when no targeting matches: `false`/`true`/variant id |
| `variants` | The set of allowed return values (`[false, true]` for boolean; `["control", "variant_a"]` for experiments) |
| `targeting_summary` | One sentence: "10% rollout to authenticated users in ES" |
| `pii_in_context` | `yes` / `no` — whether the evaluation context carries PII (tightens audit + sub-processor inventory if a hosted provider holds the rules) |

A code path that calls `flags->isEnabled('foo')` with no entry in the registry is a defect — the smoke check rejects the diff.

---

## The `FlagGatewayInterface`

Every flag evaluation goes through a gateway. Implementations live in Infrastructure (a hosted provider — LaunchDarkly, ConfigCat, Statsig — OR a self-hosted store).

```php
namespace App\Domain\Flags;

interface FlagGatewayInterface
{
    public function boolean(string $key, FlagEvaluationContext $ctx, bool $default): bool;

    public function variant(string $key, FlagEvaluationContext $ctx, string $default): string;
}

final readonly class FlagEvaluationContext
{
    /** @param array<string, scalar> $attributes */
    private function __construct(
        public ?string $subjectId,
        public ?string $tenantId,
        public ?string $country,
        public ?string $locale,
        public ?string $planTier,
        public array $attributes,
    ) {}

    public static function fromSubject(Subject $subject, ?string $country = null, ?string $planTier = null, array $attrs = []): self
    {
        return new self(
            subjectId: $subject->id,
            tenantId:  $subject->tenantId,
            country:   $country,
            locale:    null,
            planTier:  $planTier,
            attributes: $attrs,
        );
    }

    public static function anonymous(?string $country = null, ?string $locale = null): self
    {
        return new self(null, null, $country, $locale, null, []);
    }
}
```

Rules:

- The interface lives in `src/Domain/Flags/`. Adapters per provider in `src/Infrastructure/Flags/{Provider}FlagGateway.php`.
- The Domain interface NEVER mentions the provider. Migrating from a hosted SDK to self-hosted is a one-line wiring change.
- The handler asks for `FlagGatewayInterface`; tests mock it with canned responses.
- Every evaluation passes a `FlagEvaluationContext` — never the global session, never `$_SERVER`.

---

## Evaluation patterns

### Release / kill switch (boolean)

```php
public function execute(SearchCommand $command): SearchResult
{
    if ($this->flags->boolean('oficios_search_v2', FlagEvaluationContext::fromSubject($command->subject), false)) {
        return $this->v2Search->execute($command);
    }
    return $this->v1Search->execute($command);
}
```

Rules:

- ONE evaluation per code path. The handler decides which path to take and delegates — the downstream services do NOT re-check the flag.
- Defaults are conservative: a release flag defaults to `false` (off); a kill switch defaults to the safe state (e.g. "feature on" so a network outage to the flag store does not shut down the feature).
- Inverted-logic flags are forbidden — `if (flags->boolean('disable_foo')) ...` is harder to remove. Name flags by what they enable: `enable_foo`, `foo_v2`, `foo_kill`.

### Experiment (variant)

```php
$variant = $this->flags->variant('mentor_match_experiment', $ctx, 'control');

return match ($variant) {
    'control'   => $this->controlMatcher->execute($ctx),
    'variant_a' => $this->variantAMatcher->execute($ctx),
    default     => $this->controlMatcher->execute($ctx),    // unknown variant → safe default
};
```

Rules:

- Every variant is enumerated in code with an explicit `match` (or equivalent). Unknown variants ALWAYS fall through to the safe default — never throw.
- Sticky bucketing is mandatory for any user-facing experiment. The provider's bucketing must be deterministic on `subjectId`; the system never randomises per-request.
- The variant is recorded on the user's Subject for the duration of the request so child handlers do not re-evaluate (and risk inconsistency).

### Permission / entitlement

```php
if (!$this->flags->boolean('analytics_module', FlagEvaluationContext::fromSubject($subject), false)) {
    throw new ModuleNotEnabledException('analytics');
}
```

These flags map to a tenant's plan. They co-exist with Voters (`authorization.md`):

- **Flag** answers "does the tenant's plan include analytics?"
- **Voter** answers "given that the tenant has analytics, may THIS user invoke this action?"

Both fail closed. Both produce auditable outcomes (`module.access.denied` for the flag layer, `authz.denied` for the Voter — see `audit-log.md`).

---

## Targeting rules

The targeting logic lives in the provider, not in the application code. The application provides the context; the rule engine decides. This is the whole point of having a flag system instead of `if (in_array($tenantId, [...]))` in code.

Permissible targeting attributes:

- Subject id, tenant id, locale, country (from the request)
- Plan tier, signup date cohort (from the user / tenant aggregate)
- Project-defined attributes (a `professional_validation_level` integer)

Forbidden in the evaluation context:

- Sensitive-PII (per `gdpr-pii.md` GD-005). A flag rule must not know the user's email or government id. If the rule needs an attribute derived from PII, derive it server-side first (`is_minor`, `is_eu_resident`) and pass the derived boolean.
- Free-form text the user typed.
- Secret values (API keys, signing secrets).

If the provider is hosted, the chosen attributes form a sub-processor data flow and MUST be declared in `pii-inventory.md` per `gdpr-pii.md` GD-011.

---

## Local development

Local dev MUST be able to run without contacting the provider. Two acceptable setups:

- **In-memory adapter** for `dev` / `test` environments: a hardcoded map of flag-key → variant, configurable via env or fixtures.
- **Provider's local mode** when supported: an SDK that starts in local-evaluation with a config file checked into the dev environment.

A test that depends on a real provider call is a defect — it is flaky and slow.

```php
// tests bootstrap
$container->set(FlagGatewayInterface::class, new InMemoryFlagGateway([
    'oficios_search_v2' => true,
    'mentor_match_experiment' => 'variant_a',
]));
```

---

## Removal procedure

A `release` flag at 100% for one week is a candidate for removal. The procedure:

1. Add a `release-please`-style commit comment: `feat(flags): mark oficios_search_v2 ready for removal`.
2. Open a PR that:
   - Removes the flag evaluation; the `true` branch becomes the only path.
   - Removes the flag entry from the registry (`feature-flags.md`).
   - Removes the corresponding rule on the provider side (or schedules its removal).
3. Reviewer verifies that:
   - All flag evaluation call sites are gone (`grep` clean).
   - Tests covering the formerly-`false` branch are deleted.
   - The downstream service no longer consumes attributes that were only there for the experiment.

A flag removed from code but still defined on the provider creates a "dead rule" — the cleanup step on the provider is part of the same PR's checklist.

---

## Observability

Every evaluation emits a span event on the parent handler span:

| Attribute | Required | Example |
|---|---|---|
| `flag.key` | yes | `oficios_search_v2` |
| `flag.variant` | yes | `true` / `variant_a` |
| `flag.reason` | yes | `targeted` / `default` / `error_fallback` |
| `flag.error` | when `error_fallback` | `provider_unavailable` / `unknown_key` |

Metrics:

| Metric | Labels | Purpose |
|---|---|---|
| `flag_evaluations_total` | `key`, `variant`, `reason` | Catches missing rollouts (no `targeted` evaluations after launch) |
| `flag_evaluation_errors_total` | `key`, `error_class` | Provider downtime visibility |
| `flag_evaluation_latency_seconds` | `provider`, histogram | Tail latency — when long, consider local-evaluation cache |

A spike of `error_fallback` for a `release` flag means the rollout is silently broken — either users are getting the default when they should be enrolled, or vice versa. This is alertable.

---

## Audit & flag changes

Toggling a flag in production is an `audit-log.md`-significant action:

- `flag.toggled` audit entry with `key`, `from_variant`, `to_variant`, `actor_id`.
- `flag.targeting_changed` for changes to the rule (rollout %, cohort).

Hosted providers usually expose webhooks for these events — the system consumes them and writes audit entries. Self-hosted stores write the entry inline.

---

## Anti-patterns (auto-reject in review)

- A `flags->isEnabled('foo')` call with no entry in `feature-flags.md`.
- Multiple evaluations of the same flag in a single request — pass the result down, do not re-check.
- A flag evaluation in a Domain service. Flags are an Infrastructure concern; Domain services receive a pre-decided strategy.
- Inverted-logic flags (`disable_foo`).
- A flag that has lived in `release` kind for more than 12 weeks without a removal PR queued.
- Sensitive-PII or secrets in `FlagEvaluationContext.attributes`.
- A handler that bypasses authorization "because the flag is on for this tenant" — flags and Voters are separate.
- Tests that hit the real provider.
- `if (env('APP_ENV') === 'prod') { ... }` — that is feature-flag-shaped logic deserving an `operational` flag instead.

---

## What the reviewer checks

Flag rules are enforced during review via the backend reviewer checklist (see [`backend-review-checklist.md`](backend-review-checklist.md) → "Feature flags") and the frontend reviewer checklist (see [`frontend-review-checklist.md`](frontend-review-checklist.md) → "Feature flags"). The checklists are the authoritative surface — if a rule appears here and not in the checklist, file a minor and update the checklist in the same commit.

## Automated drift detection

`scripts/project-checks/check-flag-drift.sh` fails CI when the codebase calls `flags->boolean('KEY', ...)` / `flags->variant('KEY', ...)` (PHP) or `useFlag('KEY')` (TS) without a matching row in `{project-docs}/feature-flags.md`. See [`quality-gates.md`](quality-gates.md) → "Drift validators (consuming projects)".
