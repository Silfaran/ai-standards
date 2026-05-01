# {Feature Name} — Handoff from {Agent Role}

## Iteration

`iter 1` for the first handoff. Increment on every re-spawn (`iter 2`, `iter 3`, …). The Tester reads this to decide whether to re-run from scratch or trust prior pass results — see `agents/tester-agent.md` § "Quality-gate re-execution policy".

## Files Created

## Files Modified

## Quality-Gate Results

One line per gate with the tool's verbatim summary (PHPStan / PHP-CS-Fixer / PHPUnit / vue-tsc / ESLint / Prettier / npm test, as applicable). Mandatory for Developer / Dev+Tester / DevOps handoffs. Required by `agents/{backend,frontend}-developer-agent.md` § "Definition-of-Done verification gate" and validated downstream by the Tester's re-execution policy.

## DoD coverage

Verbatim copy of the task DoD with each row marked `✓` (passed), `✗` (failed), or `⚠️` (partial / blocked). Mandatory for Developer / Dev+Tester / DevOps handoffs. The DoD-checker agent re-verifies every `✓` row by spot-check; iteration ≥ 2 must re-mark every row instead of carrying marks forward.

## Key Decisions

## For the Next Agent

## Open Questions
