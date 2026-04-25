# DPIA — {Feature or processing purpose}

> Data Protection Impact Assessment, per GDPR Article 35.
> File this document at `{project-docs}/dpia/{YYYY-MM-DD}-{slug}.md` BEFORE implementation merges.

| Field | Value |
|---|---|
| Date | {YYYY-MM-DD} |
| Author | {name} |
| Reviewer | {DPO / privacy lead / legal counsel — required} |
| Status | proposed / approved / rejected / superseded |
| Supersedes | {previous DPIA id or `none`} |
| Linked spec | `{project-docs}/specs/{path}` |
| Linked ADR | `{project-docs}/decisions.md#ADR-NNN` (if any) |

---

## 1. Context

### 1.1 Processing purpose

One paragraph: what is the system going to do, why, and on whose behalf.

### 1.2 Why this triggers a DPIA

Mark all that apply (Art. 35 plus the local data-protection authority's published list):

- [ ] Systematic monitoring of public spaces (geolocation, biometric, video)
- [ ] Large-scale processing of GDPR special-category data (health, biometrics, ethnicity, religion, sexuality, political views, union membership, criminal records)
- [ ] Automated decisions with legal or similarly significant effect on the data subject
- [ ] Profiling that influences eligibility, pricing, or visibility
- [ ] Use of new or evolving technologies whose privacy implications are not yet established (LLM-driven personalization, federated learning, on-device inference combined with server profiles)
- [ ] Combining datasets from independent sources in a way the data subject would not expect
- [ ] Processing that prevents data subjects from exercising a right or accessing a service
- [ ] Other (specify): _________

### 1.3 Stakeholders

- **Controller:** {legal entity}
- **Processor(s):** {list — none if controller-only}
- **Sub-processors:** {names + region — see project sub-processor list}
- **Data subjects:** {who is affected — users, professionals, children, employees…}

---

## 2. Data flow

### 2.1 Personal data fields

Reference `{project-docs}/pii-inventory.md`. List the fields this processing touches:

| Field | Tier | Legal basis | Retention |
|---|---|---|---|
| `users.email` | Internal-PII | contract | account_lifetime + 6 years |
| ... | | | |

### 2.2 Flow diagram (text or link)

Describe (or link to a diagram) every hop the data takes:
1. Source — where the data enters the system
2. Storage — where it lives at rest
3. Processing — what the system does with it
4. Sub-processors — external systems that receive it
5. Output — what the data subject (or third parties) see as a result

Make explicit where the data crosses a trust boundary (network, organisation, jurisdiction).

---

## 3. Necessity and proportionality

### 3.1 Why this data, why this much

Explain why each field is necessary for the stated purpose. A field that is not necessary MUST be removed before approval — minimization is not optional.

### 3.2 Alternatives considered

Briefly list the alternatives that were rejected and why (e.g. aggregating before storing vs storing raw, on-device vs server-side, hashing vs encryption, pseudonym vs real identifier).

### 3.3 Lawful basis (Art. 6) and, if applicable, special-category basis (Art. 9)

State the basis explicitly per processing purpose. "Legitimate interest" requires a balancing test — include it here.

---

## 4. Risks to data subjects

For each risk, score likelihood (low / medium / high) and severity (low / medium / high). The score drives the mitigation requirement.

| Risk | Likelihood | Severity | Mitigation | Residual risk |
|---|---|---|---|---|
| Unauthorised access to Sensitive-PII via SQL injection | low | high | parameterised queries (SE-001), encrypted columns (GD-002), access audited (GD-004) | low |
| Re-identification of "anonymised" analytics via quasi-identifiers | medium | medium | k-anonymity ≥ 20, no rare combinations exported | low |
| Sub-processor breach (LLM provider) | medium | high | minimise PII in prompts (LL-XXX), per-call PII guard, contractual DPA | medium |
| RTBF not honoured by downstream system | low | high | privacy event bus + verification phase (Phase 3) | low |
| ... | | | | |

A residual risk of `high` blocks approval — the DPIA returns to design.

---

## 5. Mitigations and controls

List concrete technical controls and their checklist IDs (`GD-*`, `SE-*`, `AZ-*`, `SC-*`, `LL-*`):

- Encryption at rest for all Sensitive-PII fields involved → `GD-002`
- Voter-gated read of Sensitive-PII → `AZ-001`, `GD-003`
- Access audited per row → `GD-004`
- Redaction list updated for any new field → `GD-006`, `SC-010`
- DSAR export covers the new fields → `GD-009`
- RTBF action declared per field → `GD-010`
- Sub-processor inventory updated → `GD-011`
- Consent ledger queried before processing (if `consent` is the basis) → `GD-012`

---

## 6. Data subject rights — implementation

Confirm each right is honoured for the new processing:

- [ ] Access (Art. 15) — exposed via DSAR export
- [ ] Rectification (Art. 16) — UI / admin tool path documented
- [ ] Erasure (Art. 17) — `rtbf_action` declared per field; carve-outs documented
- [ ] Restriction (Art. 18) — flag suppresses processing
- [ ] Portability (Art. 20) — covered by DSAR export
- [ ] Objection (Art. 21) — opt-out path documented if `consent` or `legitimate_interest`
- [ ] Automated-decision rights (Art. 22) — when applicable, human review available

---

## 7. Cross-border transfers

If the processing involves transferring personal data outside the data subject's jurisdiction:

- Destination country/region: ___
- Transfer mechanism: SCCs / Adequacy decision / BCR / explicit consent / derogation
- Sub-processor's DPA + transfer addendum filed at: ___

If none of the above is in place, the transfer MUST NOT happen.

---

## 8. Outcome

- **Decision:** approved / approved-with-conditions / rejected
- **Conditions (if any):** {list — must be tracked to closure}
- **Approver:** {name + role}
- **Approval date:** {YYYY-MM-DD}
- **Re-assessment trigger:** {event — e.g. "new sub-processor added", "model upgrade", "schema change touching pii-inventory"}

---

## 9. Change log

| Date | Author | Change |
|---|---|---|
| {YYYY-MM-DD} | {name} | Initial draft |
| {YYYY-MM-DD} | {name} | {what changed and why} |
