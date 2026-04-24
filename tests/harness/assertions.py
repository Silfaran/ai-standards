#!/usr/bin/env python3
"""
Assertion runner for the dynamic smoke harness.

Two modes:

- **fast**: reads the JSONL capture produced by
  tests/harness/hooks/capture-agent.sh and compares its first entry against
  the invariants declared in tests/expected/<fixture>.json. The orchestrator
  never ran past the first Agent spawn — cheap, deterministic.

- **full**: additionally reads the handoff snapshots captured by
  tests/harness/hooks/snapshot-handoff.sh during a real end-to-end pipeline
  run and asserts structural invariants on each produced handoff file (e.g.
  `backend-dev-handoff.md` contains `## Files Created`, reviewer handoff
  cites rule IDs, tester handoff mentions pass/fail). Costs real tokens.

Stdlib only — no pip dependencies — so `make smoke-dynamic` works on a
fresh machine.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List


# --- Assertions --------------------------------------------------------------

def _fail(msg: str, hint: str | None = None) -> None:
    print(f"   assertion failed: {msg}", file=sys.stderr)
    if hint:
        print(f"     hint: {hint}", file=sys.stderr)


def run_fast_assertions(fixture: str, capture_path: Path, expected: Dict[str, Any],
                        workdir: Path) -> List[str]:
    """Fast-mode assertions — first-spawn shape + context bundle."""
    failures: List[str] = []

    if not capture_path.exists() or capture_path.stat().st_size == 0:
        failures.append(
            "capture file is empty — the orchestrator never reached the first "
            "Agent spawn. Check claude.log for why it stalled (sign-off "
            "prompt, pre-flight branch check, missing file)."
        )
        return failures

    lines = [ln for ln in capture_path.read_text().splitlines() if ln.strip()]
    if not lines:
        failures.append("capture file has no JSONL lines")
        return failures

    try:
        first = json.loads(lines[0])
    except json.JSONDecodeError as exc:
        failures.append(f"first capture line is not valid JSON: {exc}")
        return failures

    # --- spawn.model ---------------------------------------------------------
    spawn = expected.get("expected_first_spawn", {}) or {}
    expected_model = spawn.get("model")
    if expected_model:
        actual_model = first.get("model", "")
        if actual_model != expected_model:
            failures.append(
                f"first spawn model = '{actual_model}', expected '{expected_model}'"
            )
            if not actual_model:
                _fail(
                    "first spawn model is empty",
                    "the orchestrator invoked Agent without a `model` argument. "
                    "Verify commands/build-plan-command.md Step 6 and the "
                    "workspace PreToolUse hook that enforces `model`.",
                )

    # --- spawn.prompt contains agent path -----------------------------------
    required_substrings = spawn.get("prompt_contains", []) or []
    prompt = first.get("prompt_snippet", "")
    for needle in required_substrings:
        if needle not in prompt:
            failures.append(
                f"first spawn prompt does not contain '{needle}' — got snippet: "
                f"{prompt[:200]!r}"
            )

    # --- spawn.description matches regex ------------------------------------
    desc_regex = spawn.get("description_regex")
    if desc_regex:
        if not re.search(desc_regex, first.get("description", "") or ""):
            failures.append(
                f"first spawn description does not match /{desc_regex}/ — got "
                f"{first.get('description', '')!r}"
            )

    # --- spawn.prompt follows the subagent prompt template ------------------
    # build-plan-command.md mandates a specific template for Developer/Tester/
    # DevOps prompts: "Read these files in order", "Working directory:", and
    # "write your handoff to:". Missing any of these signals that the
    # orchestrator is not following the documented prompt template. Patterns
    # are treated as regex (re.search) — use `A|B` to accept paraphrase
    # variations the LLM may produce across runs ("Working directory" vs
    # "Working dir:" etc).
    required_template = spawn.get("prompt_template_sections", []) or []
    for section in required_template:
        if not re.search(section, prompt):
            failures.append(
                f"first spawn prompt missing required template pattern: "
                f"/{section}/ — the orchestrator is not following the "
                "Developer/Tester/DevOps prompt template in "
                "commands/build-plan-command.md"
            )

    # --- handoffs: required files present at spawn time ---------------------
    required_files = expected.get("required_handoff_files", []) or []
    present = set(first.get("handoffs_at_spawn", []) or [])
    for rel in required_files:
        if rel not in present:
            failures.append(
                f"required handoff file not present at first spawn: {rel}"
            )

    # --- handoffs: context bundle sections ----------------------------------
    bundle_rules = expected.get("context_bundle", {}) or {}
    bundle_rel = bundle_rules.get("path")
    bundle_sections = bundle_rules.get("required_sections", []) or []
    if bundle_rel and bundle_sections:
        bundle_path = workdir / bundle_rel
        if not bundle_path.exists():
            failures.append(
                f"context bundle not found at {bundle_rel} — the orchestrator "
                "did not generate it before the first Agent spawn"
            )
        else:
            body = bundle_path.read_text()
            # Patterns are regex (re.search) — use `A|B` to accept paraphrase
            # variations. The orchestrator sometimes writes "## Spec digest"
            # and sometimes "## Technical Details" — both indicate the spec
            # summary section is present.
            for section in bundle_sections:
                if not re.search(section, body):
                    failures.append(
                        f"context bundle missing required section pattern: "
                        f"/{section}/"
                    )

    return failures


def run_full_assertions(fixture: str, capture_path: Path, expected: Dict[str, Any],
                        workdir: Path, snapshot_dir: Path) -> List[str]:
    """Full-mode assertions — structural invariants on produced handoff files."""
    failures: List[str] = []

    full_rules = expected.get("full_mode", {}) or {}
    if not full_rules:
        failures.append(
            "expected file has no `full_mode` section — add handoff invariants "
            "before running SMOKE_FULL=1"
        )
        return failures

    # Full mode still benefits from the fast-mode checks on the first spawn —
    # model tier, prompt template, context bundle. Re-use them verbatim.
    failures.extend(
        run_fast_assertions(fixture, capture_path, expected, workdir)
    )

    # --- handoff snapshots --------------------------------------------------
    if not snapshot_dir.exists():
        failures.append(
            f"handoffs snapshot directory not found at {snapshot_dir} — the "
            "snapshot-handoff.sh PostToolUse hook did not run or did not "
            "capture any files"
        )
        return failures

    # Collect every snapshotted handoff by basename (flatten feature subdirs).
    snapshots: Dict[str, Path] = {}
    for p in snapshot_dir.rglob("*.md"):
        snapshots[p.name] = p

    handoffs_spec = full_rules.get("handoffs", {}) or {}
    for handoff_name, rules in handoffs_spec.items():
        required = bool(rules.get("required", True))
        snapshot = snapshots.get(handoff_name)

        if snapshot is None:
            if required:
                failures.append(
                    f"required handoff file not produced: {handoff_name} — the "
                    "orchestrator did not reach this phase OR the phase agent "
                    f"did not write its handoff. Snapshot dir contains: "
                    f"{sorted(snapshots.keys()) or '[empty]'}"
                )
            continue

        body = snapshot.read_text()

        # Must-contain patterns (regex — alternation welcome).
        for pattern in rules.get("body_must_match", []) or []:
            if not re.search(pattern, body, re.IGNORECASE | re.MULTILINE):
                failures.append(
                    f"handoff '{handoff_name}' missing required pattern: "
                    f"/{pattern}/ (case-insensitive, multiline)"
                )

        # At-least-one-of: accept any one pattern from the set. Use for
        # outcomes where the agent has several legitimate phrasings
        # (e.g. "approved" vs "no violations found" vs rule-ID citations).
        any_of_groups = rules.get("body_must_match_any_of", []) or []
        for group in any_of_groups:
            if not any(re.search(p, body, re.IGNORECASE | re.MULTILINE)
                       for p in group):
                failures.append(
                    f"handoff '{handoff_name}' satisfies none of the "
                    f"patterns in any-of group: {group}"
                )

        # Non-empty body sanity check.
        if rules.get("min_length"):
            min_len = int(rules["min_length"])
            if len(body.strip()) < min_len:
                failures.append(
                    f"handoff '{handoff_name}' is too short "
                    f"({len(body.strip())} chars < {min_len}) — the agent "
                    "probably aborted early"
                )

    return failures


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fixture", required=True)
    ap.add_argument("--capture", required=True, type=Path)
    ap.add_argument("--expected", required=True, type=Path)
    ap.add_argument("--workdir", required=True, type=Path)
    ap.add_argument("--mode", choices=("fast", "full"), default="fast")
    ap.add_argument("--snapshot-dir", type=Path, default=None,
                    help="Full-mode: directory containing snapshotted handoffs")
    args = ap.parse_args()

    try:
        expected = json.loads(args.expected.read_text())
    except Exception as exc:
        print(f"   could not parse {args.expected}: {exc}", file=sys.stderr)
        return 2

    if args.mode == "full":
        if args.snapshot_dir is None:
            print("   --snapshot-dir is required in full mode", file=sys.stderr)
            return 2
        failures = run_full_assertions(
            args.fixture, args.capture, expected, args.workdir,
            args.snapshot_dir,
        )
    else:
        failures = run_fast_assertions(
            args.fixture, args.capture, expected, args.workdir,
        )

    if not failures:
        return 0

    print(f"   {len(failures)} assertion(s) failed for fixture '{args.fixture}':",
          file=sys.stderr)
    for msg in failures:
        print(f"   - {msg}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
