# scripts/check-web/

Playwright walker for the `/check-web` command. Two-layer architecture:

1. **`playwright-walker.mjs`** — deterministic Node script. Visits routes, captures console/network/page errors/axe violations, dumps a single JSON. Pays no LLM tokens.
2. **`check-web.sh`** — thin Bash wrapper invoked by the `/check-web` command. Validates flags, ensures `node_modules/` exists, runs the walker.

The Web Auditor agent (`agents/web-auditor-agent.md`) reads the JSON afterwards on Opus tier and produces the triaged report.

## Install

```bash
cd ai-standards/scripts/check-web
npm install
```

The `postinstall` hook installs the Chromium binary Playwright needs.

## Run directly (without the slash command)

```bash
./check-web.sh \
  --url http://localhost:3000 \
  --out /tmp/findings.json \
  --max-depth 2 \
  --max-routes 50
```

With explicit route list (skips crawl discovery):

```bash
./check-web.sh \
  --url http://localhost:3000 \
  --out /tmp/findings.json \
  --routes ./routes.txt
```

`routes.txt`: one path or absolute URL per line, `#` comments allowed.

With seed authentication:

```bash
./check-web.sh \
  --url http://localhost:3000 \
  --out /tmp/findings.json \
  --cookie session=abc123 \
  --cookie csrf=def456
```

## What it captures

Per route:
- **Document status** — final HTTP status of the navigation request.
- **Console messages** — every `console.*` call (level + text + source location).
- **Network responses** — every response (URL, method, status, content-type).
- **Page errors** — uncaught exceptions and unhandled promise rejections.
- **axe violations** — accessibility issues (id, impact, sample DOM target).
- **Discovered links** — used for crawl expansion when no `--routes` is set.
- **Safe click results** — observations from clicking tabs/accordions/pagination.

## What it does NOT do

- Submit forms.
- Click delete icons or destructive buttons.
- POST / PATCH / DELETE.
- Assert correctness against any spec — that is the agent's job.
- Test functionality — that is the Tester agent's job.

These omissions are deliberate. The walker is observational only; richer interaction is a separate command.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Walker completed (findings JSON written; the JSON itself may report failures per route) |
| 1 | Bad usage / missing required flag |
| 2 | Playwright not installed (run `npm install` here) |
| 3 | Walker crashed before producing any output |

## JSON shape

```json
{
  "walker_version": "1.0.0",
  "started_at": "...",
  "finished_at": "...",
  "base_url": "http://localhost:3000",
  "config": { "max_depth": 2, "max_routes": 50, "has_routes_file": false, "cookie_count": 0 },
  "routes": [
    {
      "url": "...",
      "document_status": 200,
      "console": [{ "level": "error", "text": "...", "location": {} }],
      "network": [{ "url": "...", "method": "GET", "status": 200, "content_type": "..." }],
      "page_errors": [{ "message": "...", "stack": "..." }],
      "axe_violations": [{ "id": "...", "impact": "serious", "help": "...", "nodes_count": 3 }],
      "discovered_links": ["..."],
      "safe_click_results": [{ "selector": "...", "index": 0, "ok": true }],
      "walker_error": null
    }
  ],
  "walker_errors": [],
  "summary": {
    "routes_with_5xx": 0,
    "routes_with_4xx_subresources": 0,
    "total_console_errors": 0,
    "total_page_errors": 0,
    "total_axe_violations": 0
  }
}
```
