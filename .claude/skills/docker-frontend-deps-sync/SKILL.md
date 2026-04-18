---
name: docker-frontend-deps-sync
description: Use when running npm install, adding or removing npm packages, editing package.json or package-lock.json, or when a Vue/Vite frontend runs inside a Docker container and new dependencies appear missing at runtime despite being installed locally.
paths: "**/package.json, **/package-lock.json"
---

# Frontend npm installs — host vs Docker container

Host `npm install` updates only `./node_modules/` on the host. A frontend service running in a Docker container has its **own** `node_modules/` inside the container. Host installs do not reach it.

Symptoms of the desync:
- `npm test` on the host passes, but the app crashes in the browser when served by the Docker container.
- `Cannot find module '<package>'` errors in the Docker logs after adding a dependency.
- Vite returns a 200 but the page is blank — optimized deps are stale.

## Rule — four-step sync

Every time you add or remove an npm package in a Dockerized frontend, run all four steps from the service directory:

```bash
cd {frontend-service}

# 1. Host install — keeps IDE, TypeScript, and local Vitest working
npm install

# 2. Container install — updates the container's own node_modules
docker compose exec {service} npm install

# 3. Clear Vite's optimized deps cache — stale cache will keep the old modules
docker compose exec {service} rm -rf node_modules/.vite

# 4. Restart the container so Vite re-optimizes on next boot
docker compose restart {service}
```

If the service does not have a `docker-compose.yml` of its own (rare — pure host-run frontend), skip steps 2–4.

## Verifying the install reached the container

```bash
docker compose logs --tail=50 {service} | grep "new dependencies optimized"
```

If this line is present after the restart, Vite picked up the new deps. If it's missing, step 3 (clear `.vite`) was skipped or the restart didn't happen.

Alternative cheap signal:

```bash
docker compose exec {service} node -e "console.log(require('<package>/package.json').version)"
```

## Why step 3 matters

Vite caches pre-bundled dependencies in `node_modules/.vite/deps/`. After a new `npm install`, those entries still point at old module metadata. Without clearing the cache, Vite keeps serving the previous build of dependencies and your new package is invisible even though it's on disk.

## Why step 1 is still needed on the host

Without host `node_modules/`:
- Your IDE shows "Cannot find module" on imports.
- Type checking (`vue-tsc`) fails on the host.
- Local `npm test` fails with missing deps.

Skipping host install creates a different desync (host vs container) that breaks tooling rather than runtime.

## See also

- Your project's per-project lessons-learned directory (path in `{project-docs}/workspace.md` under the `lessons-learned:` key — typically `{project-name}-docs/lessons-learned/`; resolve `{project-docs}` from `ai-standards/.workspace-config-path`). Relevant entries for this trap live in `front.md` (Frontend Developer npm-in-Docker desync) and `infra.md` (Tester Docker-vs-local desync, container-rebuild log grep).
- `docker-env-reload` skill — related category of "why my change didn't apply" in Docker.
