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
