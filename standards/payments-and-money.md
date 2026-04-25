# Payments & Money Standards

## Philosophy

- Money is integer minor units, never floating-point. A `float` for money produces silent rounding errors that the customer will eventually notice as a missing cent on an invoice. The currency is part of the value — `1000` without `EUR` is meaningless.
- The provider (Stripe, Adyen, Mollie, Paddle, …) is a hostile third party for the purposes of design: it can return out-of-order events, replay webhooks, return 502 in the middle of an operation, or change a payment's status hours later. Idempotency and reconciliation are non-negotiable.
- Every state change to money is recorded in an append-only ledger. The provider's dashboard is a view; the system's ledger is the source of truth for what the controller intended.
- Webhooks are an unauthenticated POST until you verify the signature. Signature verification is the first line of every webhook handler — before parsing, before persisting, before logging the body.
- Pricing belongs to the database, not to the code. A handler that builds a price from constants in PHP is a feature flag waiting to be requested.

---

## When this standard applies

This standard applies whenever the codebase moves money or maintains money-shaped values: charging a customer, holding funds in escrow, paying out to a recipient, splitting a payment between multiple parties, charging a recurring subscription, refunding, issuing credits.

The patterns are PSP-agnostic — they apply to Stripe, Adyen, Mollie, Paddle, Razorpay, MercadoPago, or a self-hosted ledger. Provider-specific names appear only as examples.

---

## Vocabulary

| Term | Meaning |
|---|---|
| **Minor unit** | The smallest indivisible currency unit (cents for EUR/USD/GBP, yen for JPY, satoshi if relevant). All money in storage and transport is integer minor units |
| **Money** | A value object pairing an integer minor-unit amount with a 3-letter ISO 4217 currency code |
| **PSP** | Payment Service Provider — Stripe, Adyen, Mollie, etc. |
| **Charge / PaymentIntent** | A request to take money from a customer. The provider's name varies; the system's noun is `Charge` |
| **Payout** | Money sent from the controller (or escrow) to a recipient (a marketplace seller, a connected account) |
| **Ledger entry** | An immutable double-entry record: a debit on one account, a credit on another, in the same currency, summing to zero |
| **Reconciliation** | Periodic job that compares the system's ledger to the provider's reported balance — divergence is an incident, not a normal state |
| **Webhook** | An asynchronous notification from the PSP about a state change — replayable, sometimes out-of-order, sometimes duplicated |

---

## The `Money` value object (canonical)

Every monetary amount the system reads, writes, transports or displays is a `Money` value object. There is no other shape for money.

```php
namespace App\Domain\Money;

use Webmozart\Assert\Assert;

final readonly class Money
{
    private function __construct(
        public int $amountMinor,     // integer minor units; never float
        public string $currency,     // ISO 4217, uppercase 3 letters
    ) {}

    public static function from(int $amountMinor, string $currency): self
    {
        Assert::regex($currency, '/^[A-Z]{3}$/', 'Currency must be ISO 4217 3-letter uppercase');
        return new self($amountMinor, $currency);
    }

    public static function zero(string $currency): self
    {
        return self::from(0, $currency);
    }

    public function add(self $other): self
    {
        $this->assertSameCurrency($other);
        return new self($this->amountMinor + $other->amountMinor, $this->currency);
    }

    public function subtract(self $other): self
    {
        $this->assertSameCurrency($other);
        return new self($this->amountMinor - $other->amountMinor, $this->currency);
    }

    public function isPositive(): bool { return $this->amountMinor > 0; }
    public function isZero(): bool     { return $this->amountMinor === 0; }
    public function isNegative(): bool { return $this->amountMinor < 0; }

    private function assertSameCurrency(self $other): void
    {
        if ($this->currency !== $other->currency) {
            throw new CurrencyMismatchException($this->currency, $other->currency);
        }
    }
}
```

Rules:

- The constructor is private. There is no `Money::fromFloat()`, no `Money::fromString('12.34')`. Floats and strings enter only at the **boundary** (parsing a CSV import, parsing a webhook payload), where a single helper `Money::fromMinor((int) $rawCents, $currency)` performs the conversion. The conversion is unit-tested.
- Arithmetic is in the value object. No `$amount + $tax` outside `Money`.
- Currency mismatch throws — never silently coerced. Cross-currency operations require an explicit `ExchangeRate` value object and an FX conversion (out of scope of this standard; project-level decision).
- Multiplication by a quantity returns `Money` — `Money::from(1500, 'EUR')->times(3)` returns `Money(4500, 'EUR')`, never a float.
- Division for splits uses an integer-rounding strategy that never loses cents. The canonical pattern is the largest-remainder method:

```php
/**
 * Split this Money across N parts so that the parts sum exactly to this.
 * The first (totalMinor mod N) parts get one extra minor unit each.
 * Never returns parts whose sum != totalMinor.
 *
 * @return list<self>
 */
public function splitEvenly(int $parts): array { /* ... */ }
```

A divide that produces 33.33333 and silently drops one cent is forbidden.

---

## Storage shape

Every persisted money value is two columns: amount (integer) + currency (text). One-column patterns (`amount_eur INTEGER`, `total NUMERIC(10,2)`) are forbidden.

```sql
CREATE TABLE charges (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id UUID NOT NULL,
    payer_id UUID NOT NULL,
    amount_minor BIGINT NOT NULL,
    currency CHAR(3) NOT NULL,
    psp_charge_id TEXT,                  -- foreign id, nullable until provider replies
    status TEXT NOT NULL,                -- charge state machine; see "States" below
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE charges ADD CONSTRAINT chk_currency_iso CHECK (currency ~ '^[A-Z]{3}$');
ALTER TABLE charges ADD CONSTRAINT chk_amount_nonneg CHECK (amount_minor >= 0);

CREATE INDEX idx_charges_tenant_status ON charges (tenant_id, status, created_at DESC);
CREATE UNIQUE INDEX idx_charges_psp_id ON charges (psp_charge_id) WHERE psp_charge_id IS NOT NULL;
```

`amount_minor` is `BIGINT` (an `INTEGER` overflows for high-value enterprise charges in some currencies). `currency` is `CHAR(3)` so the storage is fixed-width and the constraint catches typos at insert time.

The repository returns a `Money` value object — handlers never read the two columns separately:

```php
public function findById(string $tenantId, string $chargeId): ?Charge;

// Where Charge contains:
public Money $amount;     // built once in the repository hydrator
```

---

## The double-entry ledger

Every change to a tracked balance is a ledger entry. The ledger is append-only — rows are never updated, never deleted. Corrections are new entries (a "reverse" entry that nets to zero with the original).

```sql
CREATE TABLE ledger_entries (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id UUID NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL,           -- the business event time, not insert time
    transaction_id UUID NOT NULL,                -- groups debit + credit lines of the same business event
    account TEXT NOT NULL,                       -- 'platform_revenue', 'escrow:<charge_id>', 'payout_pending:<recipient_id>'
    direction TEXT NOT NULL,                     -- 'debit' | 'credit'
    amount_minor BIGINT NOT NULL,                -- always positive; direction column carries the sign
    currency CHAR(3) NOT NULL,
    cause_type TEXT NOT NULL,                    -- 'charge', 'refund', 'payout', 'fee', 'adjustment'
    cause_id UUID NOT NULL,                      -- the aggregate id this entry attributes to
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX idx_ledger_account_time ON ledger_entries (account, occurred_at DESC);
CREATE INDEX idx_ledger_transaction ON ledger_entries (transaction_id);
CREATE INDEX idx_ledger_cause ON ledger_entries (cause_type, cause_id);
```

Invariants the system MUST enforce:

- Every transaction (group of entries sharing `transaction_id`) sums to zero per currency. A unit-tested invariant runs at write time:

```php
public function record(LedgerTransaction $tx): void
{
    foreach ($tx->byCurrency() as $currency => $entries) {
        $balance = array_reduce($entries, fn(int $acc, LedgerEntry $e) => $acc + $e->signedMinor(), 0);
        if ($balance !== 0) {
            throw new LedgerImbalanceException($tx->id, $currency, $balance);
        }
    }
    // ...persist all entries in a single DB transaction
}
```

- Entries are written in a single DB transaction. A partial transaction (debit persisted, credit failed) is the kind of bug that takes a quarterly close to find.
- A balance is computed by summing `signedMinor()` over the relevant `account` rows. There is NO `balances` table that "stays in sync" — the ledger IS the balance. (A materialized view per account is allowed for read performance; it is not the source of truth.)

### Account naming

Account names are stable identifiers. The standard suggests three patterns; projects pick one and document it as ADR:

| Pattern | Example | When to use |
|---|---|---|
| Static category | `platform_revenue`, `psp_clearing`, `chargeback_reserve` | Few global accounts |
| Per-aggregate scoped | `escrow:<charge_id>`, `payout_pending:<recipient_id>` | Per-instance accounts (escrow, holds) |
| Hierarchical | `revenue:platform:eu`, `revenue:platform:us` | Multi-jurisdiction reporting |

Once chosen, names are immutable. Renaming an account requires writing reversal entries against the old name and new entries on the new name in the same transaction.

---

## State machines

Every payment object has an explicit, finite state machine. The set of allowed transitions is enforced by the aggregate, not by an `if` ladder in handlers.

### Canonical Charge states

```
created → authorized → captured ──────► completed
   │           │           │
   │           │           └─► partially_refunded → refunded
   │           │
   │           └─► canceled
   │
   └─► failed
```

Forbidden transitions throw `IllegalStateTransitionException`. The aggregate exposes one method per allowed transition (`Charge::authorize()`, `Charge::capture()`, `Charge::refund(Money $amount)`); state assignment is encapsulated.

State is reflected in the database column with the same string values; the column is `CHECK`-constrained:

```sql
ALTER TABLE charges ADD CONSTRAINT chk_charge_status CHECK (
    status IN ('created','authorized','captured','completed','partially_refunded','refunded','canceled','failed')
);
```

A transition that fails at the database constraint is a code defect — the aggregate should have rejected it.

### Subscription, Payout, Refund, Dispute

Each gets its own state machine. The full set lives in `{project-docs}/payments.md` (project-specific). The discipline is identical: enumerate states, enumerate transitions, enforce at the aggregate.

---

## Idempotency

### Outbound calls to the PSP

Every PSP call that mutates state passes an `Idempotency-Key`. The key is deterministic — same logical operation, same key, even on retry:

```php
$idempotencyKey = sprintf('charge:%s:%d', $chargeId, $attemptNumber);
$psp->createCharge($amount, $idempotencyKey);
```

The PSP returns the same response on retry — no double charge. The key is stored on the aggregate so a manual retry uses the same value.

### Webhook handling

Every webhook is treated as potentially duplicated. The handler:

1. Verifies the signature (see next section). On failure: 401 + log + DROP — never partially process.
2. Looks up the event id (`evt_*` for Stripe; equivalent per provider) in a `processed_webhooks` table.
3. If found → return 200 immediately. The provider stops retrying.
4. If not found → process; on success, insert into `processed_webhooks` AND return 200, in the same DB transaction as any state change.

```sql
CREATE TABLE processed_webhooks (
    provider TEXT NOT NULL,
    event_id TEXT NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (provider, event_id)
);
```

Returning 200 before the state change is committed risks the provider stopping retries for an event the system did not fully process. Returning 200 only after the commit is the only correct order.

### Out-of-order events

Providers do not guarantee event order. The handler MUST use the event payload's timestamps and the aggregate's current state, not the order of arrival:

```php
public function applyChargeSucceeded(WebhookEvent $event): void
{
    $charge = $this->finder->execute($event->chargeId);
    if ($charge->isAlreadyCompleted()) {
        return; // late event, ignore
    }
    if ($charge->status !== 'captured') {
        // out-of-order — wait for the capture event; do not infer
        return;
    }
    $charge->complete($event->occurredAt);
    $this->repo->save($charge);
}
```

A handler that "trusts the event arrived in order" is a bug waiting to be filed by a customer who saw their `succeeded` notification before the `captured` one.

---

## Webhook signature verification

The first three lines of every webhook handler:

```php
public function __invoke(Request $request): Response
{
    $signature = $request->headers->get('Stripe-Signature') ?? '';
    $payload = $request->getContent();

    try {
        $event = $this->signatureVerifier->verify($payload, $signature);
    } catch (InvalidSignatureException $e) {
        $this->logger->warning('webhook_signature_invalid', ['provider' => 'stripe']);
        return new Response('', 401);
    }
    // ...continue with $event
}
```

Rules:

- The verifier is a single class per provider, in `Infrastructure/Payments/{Provider}WebhookSignatureVerifier`.
- The signing secret lives in `secrets.md` as `{PROVIDER}_WEBHOOK_SECRET` with rotation policy.
- The raw request body is what gets verified — never the parsed JSON. Symfony's `$request->getContent()` is correct; `json_decode` first then re-encode is wrong (whitespace and key order matter to the signature).
- A webhook received over HTTP (not HTTPS) is a misconfiguration; the controller refuses with 426 on dev/staging, drops on prod logs.

---

## Reconciliation

Reconciliation runs daily (or hourly for high volume). It compares the system's ledger to the provider's reported balance and flags divergence.

```
For each provider account:
    expected = sum(ledger_entries.account = '<provider>_clearing') / currency
    reported = provider.balance(date) / currency
    if expected != reported:
        raise ReconciliationDivergenceFound(account, expected, reported, delta)
```

A divergence is an incident — `SEV-2` minimum. The runbook (when the project ships `runbooks.md` per the operational-maturity bundle) lists the resolution path:

1. Identify the missing transactions on either side.
2. If provider-side missing → wait one cycle (events may arrive late).
3. If ledger-side missing → reconstruct from the webhook event log.
4. Adjustment entries are written with `cause_type='adjustment'` and a free-text `metadata.reason`.

A reconciliation that "always shows a small delta" is a process defect. The expected delta after a clean cycle is zero.

---

## Multi-party splits (marketplaces)

A marketplace charges a customer, takes a platform fee, pays the seller. The split is a property of the Charge, not of the payout:

```php
final readonly class ChargeWithSplit
{
    public function __construct(
        public Money $total,
        public Money $platformFee,
        public string $payeeRecipientId,
    ) {}

    public function payeeAmount(): Money
    {
        return $this->total->subtract($this->platformFee);
    }
}
```

When the charge captures, the ledger records:

| Account | Direction | Amount |
|---|---|---|
| `psp_clearing` | debit | total |
| `platform_revenue:<tenant>` | credit | platformFee |
| `payout_pending:<recipient>` | credit | payeeAmount |

When the payout settles:

| Account | Direction | Amount |
|---|---|---|
| `payout_pending:<recipient>` | debit | payoutAmount |
| `psp_clearing` | credit | payoutAmount |

A revenue share that mutates over time (a coupon applied later, a maker bonus) is a separate ledger transaction with `cause_type='adjustment'` — never an in-place update of the original.

---

## Subscriptions

Subscriptions are state machines whose state changes are driven by webhooks (`invoice.created`, `invoice.payment_succeeded`, `invoice.payment_failed`, `customer.subscription.deleted`). The system MUST NOT compute subscription state from a cron job that polls the provider — the webhook is the source.

Rules:

- The `subscriptions` table mirrors the provider's subscription id and status. The system reads its own row, not the provider's API, in hot paths.
- A subscription's renewal does NOT create a charge in the system's `charges` table by polling — it creates one in response to the `invoice.paid` webhook.
- Plan changes go through the PSP (the prorations are a domain the PSP solves). The system records the plan id; the price math is the provider's responsibility.

---

## Refunds

A refund is its own aggregate, not a property of the charge. The refund references the charge it reverses; the charge gains a derived state (`partially_refunded`, `refunded`) computed from the sum of its refunds.

Rules:

- A full refund of a `captured` charge transitions to `refunded`. A partial refund transitions to `partially_refunded`.
- The refund is recorded in the ledger as a reversal of the original charge entries.
- A refund initiated locally calls the PSP with an idempotency key; a refund webhook (PSP-initiated) creates the same aggregate state without double-debiting the ledger — idempotency on `event_id` covers both paths.
- Refunds may take days to settle (chargebacks can run weeks). The `pending` state of a refund is a first-class state, not an ad-hoc flag.

---

## Pricing

Prices live in the database. Hardcoded prices in PHP are forbidden — every price needs an audit trail of when it changed and by whom.

```sql
CREATE TABLE prices (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    sku TEXT NOT NULL,
    amount_minor BIGINT NOT NULL,
    currency CHAR(3) NOT NULL,
    valid_from TIMESTAMPTZ NOT NULL,
    valid_until TIMESTAMPTZ,                  -- null = current
    created_by UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_prices_sku_validity ON prices (sku, valid_from DESC);
```

Pricing logic that is genuinely a function (a tier curve, a usage formula) lives in a Domain service — `PriceCalculatorService::execute(...)` — that returns `Money`. The constants of that formula live in the database (or in `{project-docs}/pricing.md` for slow-changing values), never in source.

---

## API responses

A money field in an API payload uses two keys: `amount_minor` (integer) + `currency` (string). The frontend converts to display with `Intl.NumberFormat` (see `i18n.md`).

```json
// CORRECT
{
  "id": "ch_abc",
  "amount_minor": 1234,
  "currency": "EUR",
  "status": "captured"
}

// WRONG — loses precision; locale-dependent display delegated to clients
{
  "amount": "12.34"
}
```

The `Content-Type: application/json` response NEVER serializes a `float` for money. JSON serializers MUST be configured to refuse `Money` → `float` conversions; the canonical serializer for `Money` produces the two-key shape above.

---

## Observability

Every payment-affecting handler emits:

| Span attribute | Purpose |
|---|---|
| `payment.provider` | `stripe` / `mollie` / `adyen` |
| `payment.kind` | `charge` / `refund` / `payout` / `subscription_renewal` |
| `payment.status_after` | new state; never the amount or PII |

| Metric | Labels |
|---|---|
| `payments_total` | `provider`, `kind`, `status_after`, `currency` |
| `payments_amount_minor_total` | `provider`, `kind`, `currency` |
| `payments_failures_total` | `provider`, `kind`, `failure_reason` |
| `webhook_duplicate_total` | `provider`, `event_type` (catches retry storms) |
| `reconciliation_delta_minor` | `provider`, `currency` (gauge; should be 0 after cycles) |

Metric labels are bounded and contain NO customer identifiers — see OB-007. Currency IS allowed as a label; it is bounded and useful.

---

## Anti-patterns (auto-reject in review)

- A `float` for money anywhere — column type, PHP variable, JSON field, log entry. `NUMERIC(10,2)` is also forbidden — pure integer minor units only.
- A money column without an adjacent currency column.
- A handler that calls `$psp->createCharge(...)` without an idempotency key.
- A webhook handler that parses the body before verifying the signature.
- A webhook handler that returns 200 before persisting the state change.
- A handler that updates a balance without an opposite-direction ledger entry.
- A `subscriptions` table updated by a polling cron — it MUST be webhook-driven.
- An in-place mutation of a charge's amount after it was captured — corrections are new entries.
- A hardcoded price in PHP, even "for the MVP".
- A reconciliation job that logs `WARN: small delta, ignoring` — the delta is zero or it is an incident.

---

## What the reviewer checks

Money rules are enforced during review via the backend reviewer checklist (see [`backend-review-checklist.md`](backend-review-checklist.md) → "Payments & money") and the frontend reviewer checklist (see [`frontend-review-checklist.md`](frontend-review-checklist.md) → "Payments & money"). The checklists are the authoritative surface — if a rule appears here and not in the checklist, file a minor and update the checklist in the same commit.
