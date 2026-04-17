# Lessons Learned

Mistakes agents have made in past features that are **not yet covered** by existing standards.
Once a lesson is promoted to a proper standard file, remove it from here.

**Keep this file short** — under 40 lines of entries. Each entry is one line. Long explanations belong in the standard file where the lesson gets promoted.

## Format

```
- [{agent}] {what went wrong} → {fix or rule to follow}
```

## Entries

<!-- Add new entries at the bottom. Remove when promoted to a standard. -->
- [Backend Developer] Skipped test execution because Docker "was not accessible" → Always run `docker compose up -d` before `docker compose exec`. Promoted to backend-developer-agent.md and build-plan-command.md.
- [DevOps] Used Vite default port (5173) for CORS instead of actual frontend port (3002) → Read `workspace.md` Service Ports table for correct port. Promoted to workspace.md and new-service-checklist.md.
- [DevOps] NelmioCorsBundle `paths` section only had `allow_origin`, missing other fields → `paths` overrides `defaults` entirely; must duplicate all fields. Promoted to new-service-checklist.md item 12.
- [Frontend Developer] Installed npm dependencies on host only, but services run in Docker with separate node_modules → After any `npm install` that adds/removes packages, also run `docker compose exec {service} npm install` and clear Vite cache (`rm -rf node_modules/.vite`). Then restart the container.
- [Tester] Tests passed locally but the app crashed in Docker because container lacked new dependencies → Tester must verify the app loads in the browser (Docker-served URL from workspace.md ports) in addition to running `npm test` locally.
- [Frontend Developer] `npx shadcn-vue@latest add <component>` silently overwrites unrelated files in the same subtree (e.g. `src/components/ui/button/index.ts`, font `@import` in `main.css`) → Always run `git diff` and the existing test suite immediately after any `shadcn-vue` CLI invocation; revert unintended changes before moving on.
- [Frontend Developer] jsdom does not implement `window.matchMedia`, so components that read `prefers-reduced-motion` crash in Vitest → Add a `window.matchMedia` shim to the test setup file (`src/test-setup.ts`) alongside other jsdom shims (e.g. the `apexchart` stub).
- [Tester] Checking that a container rebuild actually picked up new npm deps → `docker compose logs --tail=50 <service> | grep "new dependencies optimized"` is a cheap, independent signal that complements curl/test checks and catches stale-container bugs without opening a browser.
