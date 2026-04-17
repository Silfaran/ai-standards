---
name: shadcn-vue-component-add
description: Use before running `npx shadcn-vue add <component>` to install a shadcn/ui component, or immediately after the CLI has run and you suspect it silently overwrote unrelated files (button index, main.css imports, component utilities).
paths: "**/components.json, **/src/components/ui/**"
---

# Adding shadcn-vue components safely

The `npx shadcn-vue@latest add <component>` CLI silently overwrites unrelated files in the same subtree when it re-generates shared utilities. Common collateral damage:

- `src/components/ui/button/index.ts` — barrel export rewritten even when `add`-ing a non-button component.
- `src/assets/main.css` — font `@import` and theme CSS variables replaced.
- `src/lib/utils.ts` — cn() helper overwritten.
- `components.json` — alias paths reset to defaults.

Because the CLI prints a success message regardless, the overwrite goes unnoticed until a test fails or a button looks wrong in production.

## Rule — verify every shadcn-vue CLI run with `git diff`

```bash
# 1. Commit or stash all unrelated changes first — start from a clean tree
git status

# 2. Run the CLI
npx shadcn-vue@latest add <component>

# 3. Immediately diff EVERY file it touched — not just the expected ones
git diff

# 4. Run the full frontend test suite before doing anything else
npm test

# 5. Revert any unintended changes before moving on
git checkout -- <unintended-file>
```

Do not commit the shadcn-vue output without steps 3 and 4. If a test suddenly breaks after step 2, the CLI is the most likely culprit — check the diff, not the test.

## Why this matters more than usual

Most codegen tools are additive. shadcn-vue is **not** — it re-runs template generation for shared files every time, using the current `components.json` as the source. If `components.json` has drifted from defaults, the regenerated files may not match what your codebase actually uses.

## Rule — treat `components.json` as a protected file

- Never edit aliases or paths in `components.json` casually. They control where the CLI writes.
- Before running `add`, open `components.json` and confirm the aliases match the project (e.g. `@/components`, `@/lib/utils`).
- If a teammate modified `components.json` in a way you didn't expect, resolve that before `add`-ing anything new.

## When the CLI overwrites theme / main.css

If `src/assets/main.css` got rewritten:

1. Restore your custom theme and font imports from git: `git checkout HEAD -- src/assets/main.css`.
2. Re-merge only the new CSS variables that the component actually needs (usually 2-3 lines at the top of the `:root {}` block).
3. Do not keep the full overwritten file just because the CLI wrote it.

## See also

- [standards/lessons-learned.md](../../../standards/lessons-learned.md) — Frontend Developer entry on this trap.
- [standards/frontend.md](../../../standards/frontend.md) — shadcn-vue is the standard UI library; use it, but verify every install.
