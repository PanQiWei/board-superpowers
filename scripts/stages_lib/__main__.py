"""stages_lib CLI entry point — python3 -m stages_lib <subcommand>.

Subcommands
-----------
lifecycle-probe
    Evaluate all stages for the current repo and emit a single line to stdout:

      INVOKE: bootstrapping-repo
      REASON: <stage_id> is <state> - <reason>

    ...or nothing (blank stdout) if all stages are applied/not-applicable.

    Exit codes: 0 always (hook contract — never block session start).

Usage (from hooks/session-start.sh):
    python3 -m stages_lib lifecycle-probe \\
        --plugin-root <plugin_root> \\
        --home <home> \\
        --repo-root <repo_root> \\
        --repo-identity <repo_identity>

Design choice: __main__.py rather than heredoc inside the hook.
Rationale: keeps bash side simple (one python3 -m invocation); logic is
  testable in isolation; error handling / exit-code guarantees are easier
  to enforce in Python than in heredoc bash.  The hook calls this module
  and reads its stdout (INVOKE / REASON lines), mirroring the existing
  pattern used by the JSON-emit block at the end of session-start.sh.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


# Priority order for non-applied states (lower index = higher priority)
_PRIORITY: list[str] = ["failed", "blocked", "drifted", "pending"]

# Module groups that route to bootstrapping-repo regardless
_BOOTSTRAP_MODULES = {"m1", "m2", "m9"}


def lifecycle_probe(
    plugin_root: Path,
    home: Path,
    repo_root: Path,
    repo_identity: str,
) -> str:
    """Run full lifecycle diff and return the INVOKE/REASON payload (or '').

    Returns:
        A two-line string "INVOKE: bootstrapping-repo\\nREASON: ..." if any
        stage needs attention, or '' if everything is applied/not-applicable.
    """
    import yaml

    # Load registry
    registry_path = plugin_root / "scripts" / "stages-registry.yml"
    if not registry_path.exists():
        return ""

    with open(registry_path, "r", encoding="utf-8") as fh:
        registry = yaml.safe_load(fh)

    if not isinstance(registry, dict):
        return ""

    # Add stages_lib to sys.path so _lifecycle can import correctly
    scripts_dir = str(plugin_root / "scripts")
    if scripts_dir not in sys.path:
        sys.path.insert(0, scripts_dir)

    from stages_lib._lifecycle import evaluate_all_stages

    try:
        results = evaluate_all_stages(
            registry,
            home=home,
            repo_root=repo_root,
            repo_identity=repo_identity,
        )
    except Exception as exc:
        # Evaluation failure — don't block session, but surface nothing
        sys.stderr.write(f"[board-superpowers] lifecycle-probe error: {exc}\n")
        return ""

    # Find the highest-priority non-applied stage
    chosen = None
    chosen_priority = len(_PRIORITY) + 1

    for result in results:
        state = result.get("state", "")
        if state not in _PRIORITY:
            continue  # applied or not-applicable — skip
        try:
            priority = _PRIORITY.index(state)
        except ValueError:
            continue
        if priority < chosen_priority:
            chosen_priority = priority
            chosen = result

    if chosen is None:
        return ""  # all stages applied/not-applicable

    stage_id: str = chosen["stage_id"]
    state: str = chosen["state"]
    reason_detail: str = chosen.get("reason", "")

    # Sanitize reason (per 02-hook-contracts.md: plain ASCII, ≤120 chars,
    # allowed punctuation only `. , ; : - ( )`.  No newlines, no markup.)
    raw_reason = f"stage {stage_id} is {state}: {reason_detail}"
    sanitized = _sanitize_reason(raw_reason)

    return f"INVOKE: bootstrapping-repo\nREASON: {sanitized}"


def _sanitize_reason(raw: str) -> str:
    """Sanitize REASON line per 02-hook-contracts.md grammar.

    Allowed: a-zA-Z0-9 space .,;:-()
    Truncate to 120 chars.
    """
    import re
    cleaned = re.sub(r"[^a-zA-Z0-9 .,;:()\-]", "", raw)
    return cleaned[:120]


def main(argv: list[str] | None = None) -> int:
    """Entry point. Returns exit code (always 0 per hook contract)."""
    parser = argparse.ArgumentParser(
        description="board-superpowers stages_lib CLI",
        prog="python3 -m stages_lib",
    )
    subparsers = parser.add_subparsers(dest="subcommand")

    probe_parser = subparsers.add_parser(
        "lifecycle-probe",
        help="Evaluate all stages and emit INVOKE marker if needed",
    )
    probe_parser.add_argument("--plugin-root", required=True)
    probe_parser.add_argument("--home", required=True)
    probe_parser.add_argument("--repo-root", required=True)
    probe_parser.add_argument("--repo-identity", required=True)

    args = parser.parse_args(argv)

    if args.subcommand == "lifecycle-probe":
        try:
            payload = lifecycle_probe(
                plugin_root=Path(args.plugin_root),
                home=Path(args.home),
                repo_root=Path(args.repo_root),
                repo_identity=args.repo_identity,
            )
            if payload:
                sys.stdout.write(payload + "\n")
        except Exception as exc:
            # Always exit 0 — never block session start
            sys.stderr.write(f"[board-superpowers] lifecycle-probe fatal: {exc}\n")
        return 0

    parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
