# Command: check-web

## Description
Manual on-demand audit of a deployed UI. Walks the site with Playwright, captures runtime symptoms (5xx, 4xx, console errors, axe violations, deprecations, broken images), classifies them via the Web Auditor agent, and produces paste-ready `/create-specs` prompts grouped by inferred root cause.

Read-only and observational. Does not run tests, does not fix bugs, does not submit forms or trigger destructive actions.

## Invoked by
Developer, manually. Never run in CI, never scheduled. The output is human-reviewed before any action is taken.

## Agent
Web Auditor

## Input
A base URL to audit. Optional flags:

```
/check-web <base_url> [--routes <file>] [--cookie <key=value>] [--max-depth N] [--max-routes N]
```

| Flag | Default | Purpose |
|---|---|---|
| `<base_url>` | — | Required. e.g. `http://localhost:3000` or a staging URL. |
| `--routes <file>` | — | Path to a text file with one URL or path per line. When provided, overrides crawler discovery. |
| `--cookie <key=value>` | — | Repeatable. Seed cookies for authenticated walks. v1 supports plain key=value; do not pass long-lived secrets through here. |
| `--max-depth N` | 2 | Crawl depth from the base URL. Ignored when `--routes` is provided. |
| `--max-routes N` | 50 | Hard cap on total routes visited. |

If invoked with no `<base_url>`, STOP and respond with:

> `/check-web` needs a base URL to audit. Re-run with the URL, for example:
> `/check-web http://localhost:3000`
>
> Optional flags: `--routes <file>` (explicit list), `--cookie key=value` (seed auth), `--max-depth N` (default 2), `--max-routes N` (default 50).

Do not read any file before the developer provides the URL — context is not needed yet.

## Steps

### 1. Resolve workspace + project paths

Read `ai-standards/.workspace-config-path` to find `{project-docs}`. Read `{project-docs}/workspace.md` to resolve `{workspace_root}` and the `handoffs/` directory.

If either file is missing, stop and tell the developer to run `/init-project` first — without these, the auditor cannot locate `web-flows.md` or write its handoff.

### 2. Run the Playwright walker (no agent yet)

Execute the walker script:

```bash
ai-standards/scripts/check-web/check-web.sh \
  --url "{base_url}" \
  --out "{workspace_root}/handoffs/check-web-{timestamp}/raw-findings.json" \
  [--routes "{routes_file}"] \
  [--cookie "{key=value}" ...] \
  [--max-depth N] [--max-routes N]
```

The walker is deterministic. It captures, per route:
- Final HTTP status of the document request.
- All console messages (level + text + source location).
- All network responses (URL, method, status, content-type, timing).
- All page errors (uncaught exceptions, unhandled promise rejections).
- axe-core accessibility violations.
- Deprecation warnings emitted to console.

Output is a single JSON file. The walker does NOT submit forms, click destructive elements, or perform any POST/DELETE. It performs GET navigation + safe clicks (links, tabs, accordions, pagination, filter dropdowns).

If the walker fails to start (missing `node_modules`, port unreachable), report the error to the developer and abort — do not spawn the agent on empty data.

### 3. Spawn the Web Auditor agent

Spawn `agents/web-auditor-agent.md` on the Opus tier (per its `## Model` declaration). Pass these inputs:

```
You are the Web Auditor agent.

Read these files in order before doing anything else:
1. agents/web-auditor-agent.md                                  ← role definition
2. {workspace_root}/handoffs/check-web-{timestamp}/raw-findings.json  ← walker output
3. {project-docs}/web-flows.md (if it exists)                   ← your own append-only memo
4. {project-docs}/specs/INDEX.md                                ← feature topology

Triage every finding into one of: real bug, expected (per spec), auditor misinterpreted.
Group real bugs by inferred root cause + feature.
For each group, emit a paste-ready /create-specs block.

Write outputs to:
- {workspace_root}/handoffs/check-web-{timestamp}/triaged-report.md
- {project-docs}/web-flows.md (append-only; only entries confirmed via spec read)

When done, return a 5-line summary: groups found, severities, false positives discarded, web-flows entries appended, next suggested action.
```

### 4. Surface the report to the developer

Print the path to `triaged-report.md` and the agent's 5-line summary. Do not auto-execute any of the `/create-specs` prompts — they are paste-ready, not auto-run. The developer reviews and copies the ones worth fixing.

## Output

| Artifact | Owner | Lifecycle |
|---|---|---|
| `{workspace_root}/handoffs/check-web-{timestamp}/raw-findings.json` | Walker script | Ephemeral — overwritten next run with same timestamp |
| `{workspace_root}/handoffs/check-web-{timestamp}/triaged-report.md` | Web Auditor | Ephemeral — kept for the developer's review session, deleted manually |
| `{project-docs}/web-flows.md` | Web Auditor (append-only) | Persistent — committed to the project docs repo |

### Token Usage Report
After completing, list the files the agent read and display: `Estimated input tokens: ~{lines_read × 8} (walker JSON tokens not counted — they are paid by the script, not the agent).`

## Output structure of `triaged-report.md`

```markdown
# Web audit — {base_url} — {timestamp}

Walker visited {N} routes in {M} seconds. {X} findings before triage.

## Summary
- {G} groups produced
- {R} real bugs, {E} expected (discarded), {M} misinterpreted (web-flows.md updated)
- Severities: {critical} critical, {major} major, {minor} minor

---

## Group 1 — {short title} (severity: {tier})

**Findings ({N})**
- {file:line} {short description}
- {url} {http_status} {method}
- ...

**Why this is one group:** {one-line rationale}

**Paste-ready prompt:**
```
/create-specs {feature-area-name}: {short bug description}. Observed: {symptom 1}; {symptom 2}; ...
{Optional: spec reference if a feature exists in INDEX.md}
```

---

## Group 2 ...
```

## Output structure of `web-flows.md` (created if absent)

```markdown
# Web flows — confirmed behaviors

Append-only memory of the web-auditor agent. Each entry cites the spec section + commit SHA that confirmed it.
On read, the agent uses this BEFORE individual specs. On miss, it consults specs and may append a new entry.

Drift policy: an entry whose cited spec has changed since the cited SHA is treated as needs-revalidation. The next session that touches the same area re-confirms or supersedes the entry.

## Auth & routing
- Observed: 403 on `/admin/*` for non-admin users. Confirmed expected per: admin-management.md §authorization (a3f9b21).

## Expected console output
- Observed: `[vue-i18n] Not found 'X' key`. Confirmed expected per: i18n.md §fallback-chain (a3f9b21).

## Known third-party noise
- ...

## Auditor pitfalls (lessons from prior sessions)
- ...
```

## Context Checkpoint

After completing this command, do NOT suggest opening a new session unless context is heavy. The auditor runs fully isolated as a subagent — its context does not leak into the parent conversation.

If the developer is about to act on one of the prompts, recommend: "Open a new session and run `/create-specs ...`" — fresh session per spec keeps each one focused.
