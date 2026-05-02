---
title: Quickstart
description: Set up ai-standards in your workspace in five minutes — clone, install slash commands, run /init-project.
---

Five minutes from "I cloned the repo" to "I can run `/build-plan` on a feature".

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and signed in.
- Docker + docker compose (every service runs in a container).
- Git, Node.js ≥ 20, npm.
- A workspace directory where you can create new repositories.

## 1. Clone the framework

Open a terminal and create a new workspace folder:

```bash
mkdir my-workspace && cd my-workspace
git clone https://github.com/Silfaran/ai-standards.git
```

## 2. Install the slash commands and skills

Copy the slash-command stubs and skills into the workspace's `.claude/` directory so Claude Code picks them up:

```bash
cp -r ai-standards/.claude/commands .claude/commands
cp -r ai-standards/.claude/skills   .claude/skills
```

The framework ships 6 slash commands (`/init-project`, `/create-specs`, `/refine-specs`, `/build-plan`, `/update-specs`, `/check-web`) and ~16 on-demand skills.

## 3. Run `/init-project`

Open Claude Code in `my-workspace/` and run:

```
/init-project
```

You will be asked for:

- The project name (e.g. `red-profesionales`).
- The list of services that make up the project (e.g. `identity-service`, `api-gateway`, `web-front`).
- Whether to enable Playwright MCP (for the `/check-web` audit command).

The command scaffolds `{project-name}-docs/` (your project's docs repo, where specs / decisions / lessons-learned live), installs the agent model-tier `PreToolUse` hook into `.claude/settings.json`, and writes the `.workspace-config-path` pointer that lets every agent locate the project docs.

## 4. Your first feature

Once `/init-project` finishes, create a spec and run the pipeline:

```
/create-specs
```

You describe the feature in natural language; the Spec Analyzer writes a business spec under `{project-name}-docs/specs/{Aggregate}/{feature-name}-specs.md`. Review it, edit if needed, then run:

```
/refine-specs
```

This reads your codebase and turns the business spec into a technical spec + execution plan + task checklist. Review again, then run:

```
/build-plan
```

This is the orchestrator. It generates per-phase bundles, spawns the agents in sequence (DevOps if needed, then Backend Developer ‖ Frontend Developer in parallel, then DoD-checker, then Reviewer loop, then Tester), reports the per-phase token cost, and asks you to confirm the merge into `master`.

See the [your-first-feature walkthrough](/ai-standards/guides/your-first-feature/) for the full narrative with example outputs.

## 5. (Optional) Install Playwright MCP for `/check-web`

If you want manual browser audits of your running UI, set up Playwright MCP per the [USAGE guide](/ai-standards/project/usage/#playwright-mcp). The `/check-web` command then walks your deployed UI, captures findings, and produces paste-ready `/create-specs` prompts.

## What's next

- [Pipeline overview](/ai-standards/concepts/pipeline/) — the four-phase agent flow with diagrams.
- [Token economics](/ai-standards/concepts/token-economics/) — real cost numbers per `/build-plan` run.
- [Architecture deep dive](/ai-standards/project/architecture/) — tech stack, spec lifecycle, full repo layout.
