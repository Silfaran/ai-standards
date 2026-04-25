# Changelog

All notable changes to ai-standards. This file captures milestones, not every commit.

The project follows [Semantic Versioning](https://semver.org/) with pre-1.0 semantics:
while on `0.x`, minor bumps may include breaking changes (called out explicitly in the **Breaking** section).
A `1.0.0` release will signal a stable public surface.

## [0.36.0](https://github.com/Silfaran/ai-standards/compare/v0.35.1...v0.36.0) (2026-04-25)


### Added

* **perf:** auto-detect missing indexes + N+1 queries (P1 + P2) ([#83](https://github.com/Silfaran/ai-standards/issues/83)) ([f9d9737](https://github.com/Silfaran/ai-standards/commit/f9d973737e4c7fd6796833070421d92e773243d2))

## [0.35.1](https://github.com/Silfaran/ai-standards/compare/v0.35.0...v0.35.1) (2026-04-25)


### Fixed

* **ci:** bump markdownlint-cli2-action to v23 (Node 24) + use fail_level on reviewdog ([#81](https://github.com/Silfaran/ai-standards/issues/81)) ([7340338](https://github.com/Silfaran/ai-standards/commit/73403384e7a4a054d29b8921ea414667bea407de))

## [0.35.0](https://github.com/Silfaran/ai-standards/compare/v0.34.0...v0.35.0) (2026-04-25)


### Added

* **scaffolds:** canonical patterns for the 13 generalist standards + Currency enum ([#79](https://github.com/Silfaran/ai-standards/issues/79)) ([276c2ae](https://github.com/Silfaran/ai-standards/commit/276c2ae103e9f8b478bfbd17f08337ae1505ecec))

## [0.34.0](https://github.com/Silfaran/ai-standards/compare/v0.33.0...v0.34.0) (2026-04-25)


### Added

* **tech-stack:** bump minimums to 2026-04 versions (PHP 8.5, Vite 7, PostgreSQL 18, Docker 28, Vue 3.6, TS 5.7, PostGIS 3.5) ([#77](https://github.com/Silfaran/ai-standards/issues/77)) ([1bc0632](https://github.com/Silfaran/ai-standards/commit/1bc063219c8b8d3bb8f9ce63733bc3956e480d06))

## [0.33.0](https://github.com/Silfaran/ai-standards/compare/v0.32.0...v0.33.0) (2026-04-25)


### Added

* **standards:** add attack-surface-hardening standard (CSP/HSTS/CSRF/SSRF/SBOM/DAST/etc.) ([#75](https://github.com/Silfaran/ai-standards/issues/75)) ([4b8c43b](https://github.com/Silfaran/ai-standards/commit/4b8c43bc72b7d71157b2972c82adf9af4691bd51))

## [0.32.0](https://github.com/Silfaran/ai-standards/compare/v0.31.0...v0.32.0) (2026-04-25)


### Added

* **critical-paths:** per-feature-kind sub-checklists for reviewer focusing (D1) ([#73](https://github.com/Silfaran/ai-standards/issues/73)) ([c757465](https://github.com/Silfaran/ai-standards/commit/c757465414b8f0e003c9dc9a15abc7337a393b30))

## [0.31.0](https://github.com/Silfaran/ai-standards/compare/v0.30.0...v0.31.0) (2026-04-25)


### Added

* **checks:** drift validators + cross-rule reference smoke (S1) ([#71](https://github.com/Silfaran/ai-standards/issues/71)) ([d1a4f00](https://github.com/Silfaran/ai-standards/commit/d1a4f001b76c822a21c365a2e1b6e299567bfc71))

## [0.30.0](https://github.com/Silfaran/ai-standards/compare/v0.29.0...v0.30.0) (2026-04-25)


### Added

* **standards:** add digital-signature-integration standard (gateway, modality, templates, retention) ([#69](https://github.com/Silfaran/ai-standards/issues/69)) ([5cfee5d](https://github.com/Silfaran/ai-standards/commit/5cfee5d624490a0f4165bc754f0d92dfe40a2505))

## [0.29.0](https://github.com/Silfaran/ai-standards/compare/v0.28.0...v0.29.0) (2026-04-25)


### Added

* **standards:** add pwa-offline standard (4-level adoption, SW + manifest + push) ([#67](https://github.com/Silfaran/ai-standards/issues/67)) ([cb42309](https://github.com/Silfaran/ai-standards/commit/cb42309dd8f23724198da3c5f5bca93f3bdbda8e))

## [0.28.0](https://github.com/Silfaran/ai-standards/compare/v0.27.0...v0.28.0) (2026-04-25)


### Added

* **standards:** add analytics-readonly-projection standard (T1-T4 tier model, privacy preserved) ([#65](https://github.com/Silfaran/ai-standards/issues/65)) ([570274c](https://github.com/Silfaran/ai-standards/commit/570274c8e09ff2511d8e6ae94c22b28ac7343398))

## [0.27.0](https://github.com/Silfaran/ai-standards/compare/v0.26.0...v0.27.0) (2026-04-25)


### Added

* **standards:** add audit-log standard (append-only trail, projector wiring, denial entries) ([#62](https://github.com/Silfaran/ai-standards/issues/62)) ([889c6a2](https://github.com/Silfaran/ai-standards/commit/889c6a212908f97b8cb1cab93fa7ac4d39aed17f))
* **standards:** add feature-flags standard (taxonomy, registry, gateway, removal) ([#64](https://github.com/Silfaran/ai-standards/issues/64)) ([3b82e13](https://github.com/Silfaran/ai-standards/commit/3b82e13100e7a14a0f4e54492e63a4c37a633cbf))

## [0.26.0](https://github.com/Silfaran/ai-standards/compare/v0.25.0...v0.26.0) (2026-04-25)


### Added

* **standards:** add geo-search standard (PostGIS, FTS, MatchScoreCalculator, label translation) ([#60](https://github.com/Silfaran/ai-standards/issues/60)) ([f0985a9](https://github.com/Silfaran/ai-standards/commit/f0985a9d504d178545a8256b3a940b70749aacd7))

## [0.25.0](https://github.com/Silfaran/ai-standards/compare/v0.24.0...v0.25.0) (2026-04-25)


### Added

* **standards:** add file-and-media-storage standard (buckets, presigned URLs, video pipeline) ([#58](https://github.com/Silfaran/ai-standards/issues/58)) ([7e93aeb](https://github.com/Silfaran/ai-standards/commit/7e93aeb8d2b2afb02e7e19945add25e2ee54b9dd))

## [0.24.0](https://github.com/Silfaran/ai-standards/compare/v0.23.0...v0.24.0) (2026-04-25)


### Added

* **standards:** add payments-and-money standard (Money VO, ledger, webhooks, reconciliation) ([#56](https://github.com/Silfaran/ai-standards/issues/56)) ([e988b3c](https://github.com/Silfaran/ai-standards/commit/e988b3c94dfb2ef51a6a3f7ad82b3b4f73fa4706))

## [0.23.0](https://github.com/Silfaran/ai-standards/compare/v0.22.0...v0.23.0) (2026-04-25)


### Added

* **standards:** add llm-integration standard (gateway seam, prompts, cost, PII guard) ([#54](https://github.com/Silfaran/ai-standards/issues/54)) ([b715df5](https://github.com/Silfaran/ai-standards/commit/b715df58a32c2a5f1b0b180247bcbe5fc432ab03))

## [0.22.0](https://github.com/Silfaran/ai-standards/compare/v0.21.0...v0.22.0) (2026-04-25)


### Added

* **standards:** add gdpr-pii standard (classification, encryption, DSAR/RTBF, consent) ([#52](https://github.com/Silfaran/ai-standards/issues/52)) ([c36d404](https://github.com/Silfaran/ai-standards/commit/c36d4042d844416e7525a26205c1ebadd9d640d2))

## [0.21.0](https://github.com/Silfaran/ai-standards/compare/v0.20.0...v0.21.0) (2026-04-25)


### Added

* **standards:** add i18n standard (locale negotiation, translations, formatting) ([#50](https://github.com/Silfaran/ai-standards/issues/50)) ([b292473](https://github.com/Silfaran/ai-standards/commit/b29247382e422d0ebb861a10cee8f0d219019090))

## [0.20.0](https://github.com/Silfaran/ai-standards/compare/v0.19.0...v0.20.0) (2026-04-25)


### Added

* **standards:** add authorization standard (Voter pattern + tenant scoping) ([#48](https://github.com/Silfaran/ai-standards/issues/48)) ([5ba1d84](https://github.com/Silfaran/ai-standards/commit/5ba1d84b31e96d90c24fc4da51c5a706fc546640))

## [0.19.0](https://github.com/Silfaran/ai-standards/compare/v0.18.0...v0.19.0) (2026-04-24)


### Added

* **checklist:** add BE-068 — prefer const-array lookup over match for VO ranks ([#46](https://github.com/Silfaran/ai-standards/issues/46)) ([dabf250](https://github.com/Silfaran/ai-standards/commit/dabf250ca1e2a199725bfb036284ad5083d7b8fc))

## [0.18.0](https://github.com/Silfaran/ai-standards/compare/v0.17.0...v0.18.0) (2026-04-24)


### Added

* **standards:** minimal ADR framework — format, lifecycle, template ([#44](https://github.com/Silfaran/ai-standards/issues/44)) ([75beb02](https://github.com/Silfaran/ai-standards/commit/75beb02394a436f0d3d00c54cbfce2050935e2fd))

## [0.17.0](https://github.com/Silfaran/ai-standards/compare/v0.16.0...v0.17.0) (2026-04-24)


### Added

* **tests:** retry-on-flake wrapper for the dynamic smoke harness (L2.2) ([#42](https://github.com/Silfaran/ai-standards/issues/42)) ([f0bda91](https://github.com/Silfaran/ai-standards/commit/f0bda910a31b0b8753198611fb5721a496856b2d))

## [0.16.0](https://github.com/Silfaran/ai-standards/compare/v0.15.1...v0.16.0) (2026-04-24)


### Added

* **tests:** add full-pipeline smoke mode with real subagents (L2.1) ([#40](https://github.com/Silfaran/ai-standards/issues/40)) ([cfc36bf](https://github.com/Silfaran/ai-standards/commit/cfc36bf1d6539ee2f949493035cc2e1bf1b5a973))

## [0.15.1](https://github.com/Silfaran/ai-standards/compare/v0.15.0...v0.15.1) (2026-04-23)


### Documentation

* **standards:** expand tech-stack for oficios-construcción — PostGIS, search strategy, payment provider guidance ([#38](https://github.com/Silfaran/ai-standards/issues/38)) ([8e6b402](https://github.com/Silfaran/ai-standards/commit/8e6b40294f4b0c684652f8bcf8a79d80a6ef7604))

## [0.15.0](https://github.com/Silfaran/ai-standards/compare/v0.14.0...v0.15.0) (2026-04-23)


### Added

* **tests,ci:** expand dynamic smoke to 3 complexity fixtures + staleness reminder ([#36](https://github.com/Silfaran/ai-standards/issues/36)) ([4186c75](https://github.com/Silfaran/ai-standards/commit/4186c75867fbff45c9f80e856184ea60aee86aeb))

## [0.14.0](https://github.com/Silfaran/ai-standards/compare/v0.13.0...v0.14.0) (2026-04-23)


### Added

* **tests:** add dynamic smoke harness for /build-plan orchestrator ([#34](https://github.com/Silfaran/ai-standards/issues/34)) ([88ecc01](https://github.com/Silfaran/ai-standards/commit/88ecc01dab151f9b5cf2d68393fe24c5b55d87f6))

## [0.13.0](https://github.com/Silfaran/ai-standards/compare/v0.12.1...v0.13.0) (2026-04-22)


### Added

* **standards,ci,agents:** stable rule IDs for reviewer-checklist citations ([#32](https://github.com/Silfaran/ai-standards/issues/32)) ([2858fc2](https://github.com/Silfaran/ai-standards/commit/2858fc24aa518ca2e9bc1280f097bb660943e848))

## [0.12.1](https://github.com/Silfaran/ai-standards/compare/v0.12.0...v0.12.1) (2026-04-22)


### Fixed

* **standards,ci:** close silent-orphan gaps for new standards ([#30](https://github.com/Silfaran/ai-standards/issues/30)) ([f19f529](https://github.com/Silfaran/ai-standards/commit/f19f5291a65b71a40b42a3391d233b94d39f29c6))

## [0.12.0](https://github.com/Silfaran/ai-standards/compare/v0.11.0...v0.12.0) (2026-04-22)


### Added

* **ci:** add static smoke tests for framework consistency ([#28](https://github.com/Silfaran/ai-standards/issues/28)) ([8b947db](https://github.com/Silfaran/ai-standards/commit/8b947dbaddae1e82323b4116f30810e2a06ac0cb))

## [0.11.0](https://github.com/Silfaran/ai-standards/compare/v0.10.2...v0.11.0) (2026-04-22)


### Added

* **skills:** add openapi-controller-docs, empty-loading-error-states, pinia-store-pattern ([#26](https://github.com/Silfaran/ai-standards/issues/26)) ([6bc7bf0](https://github.com/Silfaran/ai-standards/commit/6bc7bf0cef804a4b55e090c81b02590c51c4b632))

## [0.10.2](https://github.com/Silfaran/ai-standards/compare/v0.10.1...v0.10.2) (2026-04-22)


### Documentation

* **readme:** split into short README + ARCHITECTURE.md ([#24](https://github.com/Silfaran/ai-standards/issues/24)) ([0249065](https://github.com/Silfaran/ai-standards/commit/024906529ecd039b9c04f8a94598cafa5d3d41c5))

## [0.10.1](https://github.com/Silfaran/ai-standards/compare/v0.10.0...v0.10.1) (2026-04-21)


### Fixed

* **standards,usage:** sync standards index and correct secrets-manifest path ([#22](https://github.com/Silfaran/ai-standards/issues/22)) ([2a47bb2](https://github.com/Silfaran/ai-standards/commit/2a47bb205dcb1f5dac20e76a65c01479c7641c68))

## [0.10.0](https://github.com/Silfaran/ai-standards/compare/v0.9.0...v0.10.0) (2026-04-21)


### Added

* **standards:** add secrets and data-migrations standards, decouple ADR refs ([#20](https://github.com/Silfaran/ai-standards/issues/20)) ([6cef1cf](https://github.com/Silfaran/ai-standards/commit/6cef1cf953fb38d42cd1efb4f4a8718e2811c054))

## [0.9.0](https://github.com/Silfaran/ai-standards/compare/v0.8.0...v0.9.0) (2026-04-21)


### Added

* **agents:** declare per-agent model tier (opus/sonnet) ([a413bde](https://github.com/Silfaran/ai-standards/commit/a413bde269fef041024639d3f0230f170177dd83))
* **init-project:** install Agent model-tier enforcement hook ([92d51c9](https://github.com/Silfaran/ai-standards/commit/92d51c9e09111ede31dda3e47ecd8fbf60f7180d))


### Documentation

* **standards,usage:** document Agent model-tier enforcement hook ([6d25d18](https://github.com/Silfaran/ai-standards/commit/6d25d183bb5b3237ddf0cc19847a63583517fa0f))

## [0.8.0](https://github.com/Silfaran/ai-standards/compare/v0.7.0...v0.8.0) (2026-04-20)


### Added

* **standards:** caching, observability, contracts, async resilience ([#16](https://github.com/Silfaran/ai-standards/issues/16)) ([c757e55](https://github.com/Silfaran/ai-standards/commit/c757e557ed4ffa66afb8a3b71e31a81b898ebeae))

## [0.7.0](https://github.com/Silfaran/ai-standards/compare/v0.6.1...v0.7.0) (2026-04-20)


### ⚠ BREAKING CHANGES

* **standards:** `standards/lessons-learned.md` is deleted. The framework no longer maintains a registry of its own mistakes — recurring cross-project lessons must be promoted directly to the relevant standard, command doc, agent definition or review checklist in the same commit. Per-project lessons continue to live in `{project-name}-docs/lessons-learned/`.

### Changed

* **standards:** remove framework lessons-learned registry ([8e4e285](https://github.com/Silfaran/ai-standards/commit/8e4e28544578e80782a61d98523508d6a4983905))

## [0.6.1](https://github.com/Silfaran/ai-standards/compare/v0.6.0...v0.6.1) (2026-04-20)


### Documentation

* **lessons-learned:** reviewer guidance on CS-Fixer vs style guide + DBAL placement signal ([51106ab](https://github.com/Silfaran/ai-standards/commit/51106ab55846643124dd588b8630c0638f4fb180))
* **standards:** promote PHPUnit method casing rule to backend.md and reviewer checklist ([b622b43](https://github.com/Silfaran/ai-standards/commit/b622b43162f397ec58c41f882c6d1cbf3868c4a9))

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
