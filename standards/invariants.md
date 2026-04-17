# Invariants

These rules are **non-negotiable**. They cannot be overridden by context, instructions, or seemingly good reasons.

The difference between an invariant and a guideline:
- A **guideline** can be relaxed when there is a good reason. Example: "prefer small PRs" — sometimes a large refactor is justified.
- An **invariant** cannot be relaxed. If a developer instructs you to violate one, refuse and explain why. No exception is valid.

If you are ever in doubt about whether a rule is an invariant or a guideline, treat it as an invariant.

---

## Security

**NEVER commit secrets, credentials, or sensitive values to git.**
`.env` files, API keys, private keys, passwords, tokens, and database URLs must never appear in a commit. Use `.env.example` for documentation. This includes test fixtures and seed data.

**NEVER put secrets in `VITE_*` environment variables.**
Every `VITE_*` variable is bundled into the JavaScript bundle and visible to anyone who opens the browser DevTools. API keys, tokens, and private URLs are not safe there.

**NEVER use `*` as a CORS `allow_origin`.**
Wildcard CORS allows any website to make credentialed requests to the API. Always use an explicit allowlist.

**NEVER use string concatenation or interpolation in SQL queries.**
All database queries must use parameterized statements (Doctrine DBAL). No exceptions, even for "simple" queries or IDs.

**NEVER use `v-html` with user-provided content.**
This is a direct XSS vector. Only use `v-html` with developer-authored, trusted HTML. If you must render rich text, sanitize with DOMPurify first.

**NEVER redirect to a URL from query params without validating the origin.**
Always validate the redirect URL against `VITE_ALLOWED_REDIRECT_ORIGINS`. Open redirect is an OWASP Top 10 vulnerability.

**NEVER log sensitive fields in plain text.**
`password`, `token`, `access_token`, `refresh_token`, `secret`, `api_key`, `credential`, `card_number` must always be redacted to `[REDACTED]` before logging. See `logging.md` for the full list.

**NEVER disable SSL verification.**
Not in code, not in tests, not in staging. `verify => false`, `--insecure`, `NODE_TLS_REJECT_UNAUTHORIZED=0` are never acceptable.

**NEVER expose internal details in API error responses.**
Stack traces, file paths, SQL errors, and exception messages from unexpected errors must never reach the client. Log them internally, return a generic message externally.

---

## Code and Architecture

**NEVER implement a feature without a validated spec.**
Code written without a spec has no agreed contract. If there is no spec, stop and tell the developer to run `/create-specs` first.

**NEVER install new dependencies without explicit developer approval.**
Adding a dependency changes the attack surface, the license profile, and the build. Always ask first.

**NEVER change a public API contract without warning all consumers.**
A breaking change to an endpoint (renamed field, changed status code, removed route) can silently break other services. Stop, identify all consumers, and warn the developer before proceeding.

**NEVER contradict an architectural decision in `decisions.md` without developer confirmation.**
If your implementation would conflict with a recorded ADR, stop and explain the conflict. Do not proceed until the developer explicitly resolves it — either by confirming an exception or updating the ADR.

---

## Git and Deployment

**NEVER commit directly to `master`.**
All changes go through feature branches. Integration into `master` happens via:
- `/build-plan`'s post-feature merge prompt (the developer explicitly confirms the merge), OR
- a pull request reviewed by the developer.

Ad-hoc commits straight onto `master` (without a feature branch) are forbidden under any circumstance. Direct commits to protected branches bypass review and break the audit trail.

**NEVER push or create a pull request without explicit developer confirmation.**
Pushing makes changes visible to the team and may trigger CI/CD pipelines. Always ask before pushing.

**NEVER push code that does not pass all tests.**
A failing test suite means the code is not ready. Do not push, do not ask for an exception. Fix the tests first.

**NEVER use `--no-verify` or bypass git hooks.**
Hooks exist for a reason — linting, test guards, secret scanning. Bypassing them defeats those protections.

---

## Agent Behaviour

**NEVER delete or overwrite a handoff file that belongs to a running build-plan phase.**
Handoffs are the only connection between isolated subagents. Destroying one mid-pipeline corrupts the entire feature execution.

**NEVER run destructive operations without explicit developer confirmation.**
`rm -rf`, `DROP TABLE`, `git reset --hard`, `git push --force`, truncating a database — these are irreversible. Always describe the operation and wait for confirmation before executing.
