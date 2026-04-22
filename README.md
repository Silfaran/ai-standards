# AI Standards

[![Latest release](https://img.shields.io/github/v/release/Silfaran/ai-standards?display_name=tag&sort=semver&label=release)](https://github.com/Silfaran/ai-standards/releases)
[![Latest tag](https://img.shields.io/github/v/tag/Silfaran/ai-standards?sort=semver&label=tag)](https://github.com/Silfaran/ai-standards/tags)
[![CI](https://img.shields.io/github/actions/workflow/status/Silfaran/ai-standards/validate.yml?branch=master&label=CI)](https://github.com/Silfaran/ai-standards/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> **Status: work in progress.** This is an active, evolving framework — not a stable release. Breaking changes to standards, agent prompts, commands and repo layout land between `0.x` releases as the design matures. If you adopt it today, pin a tag (the latest is shown in the badge above; details in [`CHANGELOG.md`](CHANGELOG.md)) and expect to re-read that file before every upgrade. Feedback and issues are welcome.

An orchestration framework for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that builds full-stack web applications — PHP/Symfony backend and Vue 3 frontend — using isolated AI agents that spec, implement, review, and test each feature.

You describe a feature in plain language. The framework splits the work across seven specialized agents, each with its own context window, strict standards, and a single role. The result is implemented, reviewed, and tested code following Hexagonal Architecture, DDD, CQRS, and Event-Driven design.

---

## Quickstart

```bash
mkdir my-workspace && cd my-workspace
git clone https://github.com/Silfaran/ai-standards.git
cp -r ai-standards/.claude/commands .claude/commands
cp -r ai-standards/.claude/skills   .claude/skills
```

Open Claude Code in `my-workspace/` and run `/init-project`. It asks for a project name and list of services, scaffolds `{project-name}-docs/`, and installs the agent model-tier hook. From there, `/create-specs` starts your first feature.

Full setup (Playwright MCP, upgrading an existing workspace, skills reference) → **[USAGE.md](USAGE.md)**.

---

## Learn more

- **[USAGE.md](USAGE.md)** — setup guide, step-by-step workflow, skills catalog
- **[ARCHITECTURE.md](ARCHITECTURE.md)** — tech stack, spec lifecycle, agent pipeline, repo layout, design rationale
- **[CHANGELOG.md](CHANGELOG.md)** — releases and breaking changes

---

## Honest limitations

- **Single stack.** This builds PHP/Symfony + Vue 3 applications. A different stack requires rewriting the standards, scaffolds, and reference files. The orchestration patterns (agents, handoffs, spec-first) are portable; the implementation details are not.
- **Claude Code only.** Agent orchestration relies on Claude Code's subagent system. It won't work with other AI tools without significant adaptation.
- **Developer in the loop.** This does not replace the developer. You describe features, approve specs, confirm git operations, and make decisions the AI can't make alone. The framework structures the AI's work — it doesn't eliminate yours.
- **Opinionated architecture.** Hexagonal + DDD + CQRS is enforced, not suggested. If your project doesn't follow these patterns, the standards will fight your codebase.

---

## Ethical use

This project is released under the MIT License. You are free to use, modify, and distribute it for any purpose, including commercial use.

However, the author does not endorse and explicitly discourages use of this work in any context that:

- Develops, supports, or facilitates weapons systems or military targeting
- Enables mass surveillance, tracking, or profiling of individuals without consent
- Powers systems designed to discriminate based on race, gender, religion, nationality, or any protected characteristic
- Generates or distributes disinformation, propaganda, or deceptive content at scale
- Facilitates fraud, scams, or platforms designed to deceive or defraud users
- Develops malware, cyberweapons, or software intended to attack systems without authorization
- Violates applicable human rights law or international humanitarian law

This notice is not a legal restriction — it is a statement of values.

---

## Author

Built and maintained by **Mario Marco Esteve** — [@Silfaran](https://github.com/Silfaran) on GitHub.

Issues, questions and pull requests are welcome in [the repository tracker](https://github.com/Silfaran/ai-standards/issues).
