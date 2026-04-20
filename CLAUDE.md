# AI Standards

## Purpose

Global standards, conventions, and agent definitions for all projects in this workspace.
Every service must have a `CLAUDE.md` referencing this file.

- **Invariants (read first): `ai-standards/standards/invariants.md`** — rules that cannot be overridden under any circumstances
- **Agent reading protocol: `ai-standards/standards/agent-reading-protocol.md`** — canonical order every agent must follow (build-plan mode + standalone mode)
- **Tech stack: `ai-standards/standards/tech-stack.md`** — authoritative versions (all values are minimums, open to update) and upgrade procedure
- Agent definitions: `ai-standards/agents/`
- Commands: `ai-standards/commands/` (full implementations, referenced by the `.claude/commands/` stubs)
- Templates: `ai-standards/templates/`
- Scaffold files: `ai-standards/scaffolds/` — copy-verbatim PHP classes (AppController, ApiExceptionSubscriber, etc.)
- **Skills: `ai-standards/.claude/skills/`** — on-demand playbooks (CORS, Docker env reload, migrations, JWT, Vitest patterns, ...). Claude auto-loads a skill only when it matches the active task or file paths; description-only otherwise. See `USAGE.md` → Skills reference for the full catalog.
- Backend standards: `ai-standards/standards/backend.md` (rules) / `backend-reference.md` (full examples)
- Frontend standards: `ai-standards/standards/frontend.md` (rules) / `frontend-reference.md` (full examples)
- Logging standards: `ai-standards/standards/logging.md`
- Security standards: `ai-standards/standards/security.md`
- Performance standards: `ai-standards/standards/performance.md`
- Caching standards: `ai-standards/standards/caching.md`
- New service scaffold checklist: `ai-standards/standards/new-service-checklist.md`
- Reviewer checklists: `ai-standards/standards/backend-review-checklist.md` / `frontend-review-checklist.md` — closed list of verifiable rules consumed by Backend/Frontend Reviewer agents instead of the full standards. **When you add or change a rule in any standards file, update the matching checklist entry in the same commit** — otherwise reviewers will silently miss new rules.
- Project config lookup: `ai-standards/.workspace-config-path` (gitignored, one line created by `init-project`) points to the current project's docs repo — typically `../{project-name}-docs`. The real config files (`workspace.md`, `workspace.mk`, `services.md`, specs, decisions, lessons-learned) all live **inside that docs repo**, not in `ai-standards/`. To discover any project path, read `.workspace-config-path` first, then read `{docs-dir}/workspace.md`.

## Tech Stack

See [`standards/tech-stack.md`](standards/tech-stack.md) for the authoritative list of technologies, minimum versions (all values are floors — newer compatible releases are welcome), and the upgrade procedure. Do not restate versions in other files.

## General Naming Conventions

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

## AI Behavior Rules

All agents follow the canonical reading order defined in [`standards/agent-reading-protocol.md`](standards/agent-reading-protocol.md) — both the build-plan subagent mode (context bundle only) and the standalone mode (full file set). The protocol also defines role-specific additions and the handoff rules; do not restate them in agent definitions.

The reading protocol is binding. If it conflicts with an older instruction elsewhere, the protocol wins.

### Specs & Documentation

- Specs must be written before any code — never implement without a validated spec
- Specs, plans and tasks live in the path defined in `{project-docs}/workspace.md` (resolve `{project-docs}` from `ai-standards/.workspace-config-path`)
- `{project-name}-docs/specs/INDEX.md` is the quick-reference index — always read this before deep-reading full specs
- Specs are version-controlled — every spec update must be committed
- When running as a `build-plan` subagent, read the **context bundle** (`{workspace_root}/handoffs/{feature}/context-bundle.md`, path defined in `{project-docs}/workspace.md` under the `handoffs:` key) instead of individual standards files — it contains the distilled rules relevant to the current feature

### Commit convention

Every commit to `ai-standards/` master must use [Conventional Commits](https://www.conventionalcommits.org/). The release-please Action reads this history to maintain the release PR, generate `CHANGELOG.md` entries and compute the next version bump. Getting the prefix wrong means the change is either invisible in the CHANGELOG or bumps the wrong version component.

| Prefix | CHANGELOG section | Version bump (pre-1.0) |
|---|---|---|
| `feat:` | Added | minor (0.1.0 → 0.2.0) |
| `fix:` | Fixed | patch (0.1.0 → 0.1.1) |
| `refactor:` / `perf:` | Changed | patch |
| `docs:` | Documentation | patch |
| `chore:` / `ci:` / `test:` / `style:` / `build:` | hidden | no bump on its own |

Breaking changes: append `!` after the type (e.g. `refactor!: move workspace.md to docs repo`) **or** include a `BREAKING CHANGE:` trailer in the body. Pre-1.0 this promotes the bump to minor; post-1.0 it will trigger a major.

Commit scope (optional but recommended) matches the area: `feat(skill): add x`, `refactor(workspace): …`, `docs(readme): …`.

### Release process

Releases are cut by [release-please](https://github.com/googleapis/release-please) — see [`.github/workflows/release-please.yml`](.github/workflows/release-please.yml).

Flow:
1. You push commits to `master` following the convention above.
2. The `Release Please` Action opens (or updates) a PR titled `chore(master): release X.Y.Z`. The PR's diff is the CHANGELOG update plus a bump in `.release-please-manifest.json`. **Never edit `CHANGELOG.md` by hand** — release-please owns it. Manual edits get overwritten on the next push.
3. Review the PR. If the computed version or CHANGELOG section assignments are wrong, fix the offending commit message with a follow-up commit (e.g. an empty commit with a corrected `BREAKING CHANGE:` trailer).
4. Merge the release PR. release-please then creates the git tag (`v0.2.0`) and a GitHub Release with the CHANGELOG excerpt as the release notes.

The tag pointed to by the manifest is the most recent released version. `Unreleased` in `CHANGELOG.md` is populated by release-please from post-tag commits.

### Git (main conversation only — subagents do not perform git operations)

- Main branch: `master`
- Always work from `master` — every new branch is created from an up-to-date `master`
- Branch naming: `feature/{aggregate}/{description}`, `fix/{aggregate}/{description}`, `hotfix/{description}`
- `build-plan` workflow:
  1. **Pre-flight check**: before creating a feature branch in any affected repo, verify HEAD is on `master`. If not, ask the developer to merge the current branch into `master` first, continue on the existing branch, or abort — never silently branch from a non-master HEAD.
  2. Creates the feature branch from `master` and commits after the last agent.
  3. **Post-feature merge prompt**: after committing, asks the developer if the feature should be merged into `master`. If yes, merges + pushes in every affected repo and leaves all repos checked out on `master`.
- Any other command that creates branches must apply the same pre-flight master check.
- Never push or create pull requests without explicit developer confirmation (see `invariants.md`)

### Makefile

Every service must implement at minimum:
- `make up` / `make down` / `make build` / `make update`
- `make test` / `make test-unit` / `make test-integration`

The root Makefile in `ai-standards/` orchestrates all services and adds:
- `make infra-up` / `make infra-down` — start/stop shared infrastructure only (PostgreSQL, RabbitMQ, Mailpit)
- `make up` — starts infrastructure first, then all services
- `make ps` — shows status of infrastructure + all services
