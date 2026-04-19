# Changelog

All notable changes to ai-standards. This file captures milestones, not every commit.

The project follows [Semantic Versioning](https://semver.org/) with pre-1.0 semantics:
while on `0.x`, minor bumps may include breaking changes (called out explicitly in the **Breaking** section).
A `1.0.0` release will signal a stable public surface.

## [0.6.0](https://github.com/Silfaran/ai-standards/compare/v0.5.3...v0.6.0) (2026-04-19)


### ⚠ BREAKING CHANGES

* **standards:** every service under src/Application/Service/ that is a pure domain rule (finders, authorizers, validators, calculators) must be relocated to src/Domain/Service/{Aggregate}/. Existing final class *Service declarations must be changed to readonly class. The updated backend-review-checklist.md enforces both rules as [critical]; non-compliant services will fail review.

### Added

* **standards:** codify Domain vs Application service placement ([7e3b02f](https://github.com/Silfaran/ai-standards/commit/7e3b02fb34800135f6a08ab2a13099374501ccc3))

## [0.5.3](https://github.com/Silfaran/ai-standards/compare/v0.5.2...v0.5.3) (2026-04-19)


### Documentation

* **lessons-learned:** note PHPUnit 13 vs final application service conflict ([f981e48](https://github.com/Silfaran/ai-standards/commit/f981e48ea9ebf3ac6160b4607c4b4869dde3de16))

## [0.5.2](https://github.com/Silfaran/ai-standards/compare/v0.5.1...v0.5.2) (2026-04-19)


### Documentation

* **commands:** refine-specs step 7b enforces one-public-method rule ([9011aac](https://github.com/Silfaran/ai-standards/commit/9011aac2655989c839130b0132cb1450d7e160d3))

## [0.5.1](https://github.com/Silfaran/ai-standards/compare/v0.5.0...v0.5.1) (2026-04-19)


### Documentation

* **standards:** reinforce one-public-method rule for services ([9eb1cea](https://github.com/Silfaran/ai-standards/commit/9eb1ceafcceba2bb39465524eb24175643318596))

## [0.5.0](https://github.com/Silfaran/ai-standards/compare/v0.4.0...v0.5.0) (2026-04-19)


### ⚠ BREAKING CHANGES

* a finder class may host only one throw-on-miss lookup (execute). Multi-method finders must split into one class per key shape.

### Changed

* one finder, one lookup, one execute() — no exceptions ([6880dae](https://github.com/Silfaran/ai-standards/commit/6880dae67cd42980298f16c6e2977145dc3af108))

## [0.4.0](https://github.com/Silfaran/ai-standards/compare/v0.3.2...v0.4.0) (2026-04-19)


### ⚠ BREAKING CHANGES

* repository interfaces must not expose throw-on-miss lookups; throw-on-miss lives in {Aggregate}FinderService.

### Changed

* repositories stay nullable; FinderService owns throw-on-miss ([d991fb4](https://github.com/Silfaran/ai-standards/commit/d991fb4ab30681b8ca4755a132b121dac5f77963))

## [0.3.2](https://github.com/Silfaran/ai-standards/compare/v0.3.1...v0.3.2) (2026-04-19)


### Fixed

* **ci:** use RELEASE_PLEASE_TOKEN for auto-merge so release-please re-runs on merge ([#6](https://github.com/Silfaran/ai-standards/issues/6)) ([41a760e](https://github.com/Silfaran/ai-standards/commit/41a760eed870ab425d39c437970e8365f189bae0))

## [0.3.1](https://github.com/Silfaran/ai-standards/compare/v0.3.0...v0.3.1) (2026-04-19)


### Fixed

* **commands:** gate context loading on argument presence ([24e134a](https://github.com/Silfaran/ai-standards/commit/24e134a5cf4b6b99c5be426ed9895ab4a487235b))

## [0.3.0](https://github.com/Silfaran/ai-standards/compare/v0.2.1...v0.3.0) (2026-04-19)


### Added

* **standards:** define service extraction criteria and naming patterns ([7184677](https://github.com/Silfaran/ai-standards/commit/71846778d0d7f1f0e57edf42087585ca4f523008))

## [0.2.1](https://github.com/Silfaran/ai-standards/compare/v0.2.0...v0.2.1) (2026-04-19)


### Changed

* **build-plan:** scope browser verification to Tester only ([56f8454](https://github.com/Silfaran/ai-standards/commit/56f8454b41d7026e9f27f1b2d313b8ef76d1ef7b))

## [0.2.0](https://github.com/Silfaran/ai-standards/compare/v0.1.0...v0.2.0) (2026-04-19)


### Added

* **commands:** retire plan/task on update-specs with as-built distillation ([041e63a](https://github.com/Silfaran/ai-standards/commit/041e63a7c138bece339c32842a7aa1ac225ef11d))


### Documentation

* **lessons-learned:** capture Playwright MCP lacks HAR export ([7467e7e](https://github.com/Silfaran/ai-standards/commit/7467e7e986ba478aa30911640ccf90c397613d82))
* **readme:** add Author section crediting the maintainer ([65ff4c4](https://github.com/Silfaran/ai-standards/commit/65ff4c4368ab4311cc6a90e36fcd65c70b5a54c2))
* **readme:** add prior-knowledge and spec-lifecycle sections ([7632621](https://github.com/Silfaran/ai-standards/commit/763262105d1b105a21c331022d7d03d452234bd8))
* **readme:** add release, CI and license badges + MIT LICENSE file ([4f430fb](https://github.com/Silfaran/ai-standards/commit/4f430fbb0e29eb084110d76c1802802f59022552))
* **readme:** use static MIT badge instead of flaky dynamic license badge ([3a7460c](https://github.com/Silfaran/ai-standards/commit/3a7460cf92817575d05b83f1caf3961f2992cc54))

## [Unreleased]

## [0.1.0] — 2026-04-18

Initial versioned release. The framework is still a work-in-progress — expect breaking changes in subsequent `0.x` releases.

### Framework capabilities

- **Seven-agent pipeline** running in isolated contexts: Spec Analyzer, Backend Developer, Frontend Developer, Backend Reviewer, Frontend Reviewer, Tester, DevOps. Backend and Frontend run in parallel; reviewers loop up to 3 iterations per side.
- **Four slash commands** covering the full feature loop: `/create-specs`, `/refine-specs`, `/build-plan`, `/update-specs`.
- **On-demand skills** (~13) for narrow playbooks — CORS, Docker env reload, safe migrations, JWT lifecycle, Messenger logging, Vitest patterns, quality-gate setup, and more. Claude Code auto-loads each only when the active task matches.
- **Architecture enforced by standards**: Hexagonal + DDD + CQRS + event-driven. Every agent validates against them; reviewer agents consume closed-list checklists extracted from the standards.
- **Token-conscious execution**: per-feature **context bundle** distills ~1,000+ lines of standards into a 200–400 line briefing. Reviewers read checklists instead of standards. Skills load only on match.
- **Spec-first discipline**: no agent writes code without a validated spec. Specs, plans and task files live in the project docs repo and are version-controlled.
- **Scaffolds and templates**: production-ready PHP classes (`AppController`, `ApiExceptionSubscriber`, `LoggingMiddleware`, `SecurityHeadersSubscriber`), GitHub Actions CI templates, pre-commit hook templates, Makefile quality snippets.
- **Playwright MCP integration**: the Tester drives a real browser to verify visual / interactive DoD items (viewport sizes, dark-mode parity, rendered error copy, form flows). Falls back to "requires human verification" only when MCP is unavailable.
- **Lessons-learned loop**: agent mistakes captured during a feature become warnings injected into future builds. Recurring patterns graduate to permanent standards.
- **Quality gates enforced**: pre-commit hook + per-service `make quality` + GitHub Actions CI. PHPStan level 9, `vue-tsc --noEmit` strict, PHP-CS-Fixer, ESLint + Prettier, full test suite, `composer audit` / `npm audit`.
- **Git workflow baked into `/build-plan`**: pre-flight master check before branching, post-feature merge prompt, consistent `feature/{aggregate}/{name}` branch naming.

### Added in the final stretch before v0.1.0

- Project-neutral layout — `workspace.md` and `workspace.mk` live in `{project-docs}/`, located via the gitignored `.workspace-config-path` pointer file inside `ai-standards/`. The public framework repo no longer stores project-specific names, ports or paths.
- Per-project `lessons-learned/` directory split by `back.md` / `front.md` / `infra.md` / `general.md`. Framework-level lessons stay in `ai-standards/standards/lessons-learned.md`.
- `/build-plan` pre-flight master branch check and post-feature merge prompt.
- `handoffs/` directory moved to the workspace root — ephemeral, never committed, shared across service repos.
- Playwright MCP install step documented in USAGE.

### Breaking (compared to unversioned history)

- **Workspace config relocation**: `workspace.md` and `workspace.mk` moved from `ai-standards/` to `{project-name}-docs/`. The `ai-standards/Makefile` and every agent now resolve the docs directory from `ai-standards/.workspace-config-path` (created by `/init-project`).
- **Lessons-learned split**: project-specific entries moved from `ai-standards/standards/lessons-learned.md` to `{project-name}-docs/lessons-learned/`. The framework file is now reserved for framework-level mistakes only.
- **Handoffs relocation**: `handoffs/` moved from `ai-standards/handoffs/` to the workspace root, so it is shared across service repos and lives outside any git tree.

Existing workspaces must re-run `/init-project` (or apply the moves manually) to pick up the new layout.
