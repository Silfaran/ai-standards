---
name: docker-env-reload
description: Use after editing any .env, .env.local, or env_file referenced in docker-compose.yml, when environment variable changes are not taking effect in a running container, or when you're about to "restart" a service to apply a config change.
paths: "**/.env, **/.env.*, **/docker-compose.yml, **/docker-compose.*.yml"
---

# Docker env var reload — `restart` does NOT re-read `.env`

`docker restart <service>` keeps the container's **original** environment from when it was first created. It does NOT re-read `.env`, `env_file`, or `environment:` entries from `docker-compose.yml`.

To pick up env-var changes you must **recreate** the container.

## Rule

| Command | Re-reads env_file / .env |
|---|---|
| `docker restart <service>` | No |
| `docker compose restart <service>` | No |
| `docker compose up -d <service>` | Yes — recreates the container |

**Always use `docker compose up -d`** from the service directory after changing any `.env` variable, any `environment:` entry, or any `env_file:` target.

```bash
cd {service_directory}
docker compose up -d {service_name}
```

## Verify the change was applied

```bash
docker exec <container-name> printenv VARIABLE_NAME
```

If the value is old, the container was not recreated — rerun `docker compose up -d <service>` and check the output for "Recreated" rather than "Started".

## Common symptoms of this trap

- New `CORS_ALLOW_ORIGIN` value ignored — CORS still fails.
- New `DATABASE_URL` ignored — still connects to the old database.
- JWT secret rotated but old tokens still accepted (worker not recreated).
- Any `%env(FOO)%` placeholder in a Symfony config file still resolves to the old value.

If any of these appear after you "restarted", run `docker compose up -d` instead.

## Why `restart` keeps lying

`docker restart` is a kernel-level container action — it only sends SIGTERM/SIGKILL and re-executes the same container's init. The container's environment is immutable after creation. `docker compose up -d` is different: if any of the inputs that went into creating the container have changed (env, image, ports, volumes), it tears down the old container and creates a new one from the current config.

## See also

- [standards/new-service-checklist.md](../../../standards/new-service-checklist.md) item 11 — same rule with command cheat-sheet.
- `cors-nelmio-configuration` skill — common scenario where this trap bites.
