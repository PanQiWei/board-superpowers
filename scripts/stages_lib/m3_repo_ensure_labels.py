"""ADR-0014 4-callable contract for stage m3.repo.ensure-labels.

Stage: M3 | automated | external | both platforms
character: automated
locality: external → validated against live GitHub repo state
depends_on: m10.repo.choose-kanban-projection
applicable_when: {kanban_projection_capability: ensure-labels}
external_ttl_seconds: 86400

Ensures the 13 canonical board-superpowers labels exist on the GitHub repo.
Delegates execution to scripts/setup-labels.sh (the single source of truth for
the label set) per github-project-v2.md § ensure-labels.

Label set (from scripts/setup-labels.sh — SoT):
  Ops (4):
    wip-override, suspended, security, pr-contract-override
  Type (5):
    type:feature, type:bug, type:chore, type:refactor, type:epic
  Size (4):
    size:XS, size:S, size:M, size:L

These are GitHub repo labels (created via gh label create).
Status field options (Backlog, Ready, In Progress, In Review, Blocked, Done)
are GitHub Project FIELD OPTIONS — not repo labels — and are managed by the
separate m3.repo.validate-status-field stage.

All subprocess calls are mocked in CI tests.
ctx contract: any object with attributes home, repo_root, repo_identity.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Canonical label set — mirrors scripts/setup-labels.sh (SoT).
# Update both files in the same PR when the label set changes.
# ---------------------------------------------------------------------------

CANONICAL_LABELS: list[dict] = [
    # Ops (4)
    {"name": "wip-override",         "color": "FBCA04", "description": "Allows Consumer to claim past WIP cap"},
    {"name": "suspended",            "color": "D4C5F9", "description": "Card paused mid-work; still counts toward WIP"},
    {"name": "security",             "color": "B60205", "description": "Triggers gstack:/cso security review on PR submit"},
    {"name": "pr-contract-override", "color": "C5DEF5", "description": "Bypass PR three-section validation"},
    # Type (5)
    {"name": "type:feature",         "color": "0e8a16", "description": "A new user-visible capability"},
    {"name": "type:bug",             "color": "d73a4a", "description": "A defect in existing behavior"},
    {"name": "type:chore",           "color": "c5def5", "description": "Non-code or infra work (deps, rename, config)"},
    {"name": "type:refactor",        "color": "fbca04", "description": "Internal restructuring with no behavior change"},
    {"name": "type:epic",            "color": "5319e7", "description": "A container for several vertical-slice cards"},
    # Size (4)
    {"name": "size:XS",              "color": "cccccc", "description": "Under 50 LOC / 1-2 files"},
    {"name": "size:S",               "color": "b0bec5", "description": "50-200 LOC / 2-5 files"},
    {"name": "size:M",               "color": "607d8b", "description": "200-400 LOC / 5-10 files"},
    {"name": "size:L",               "color": "455a64", "description": "400-500 LOC / up to 10 files (ceiling)"},
]

CANONICAL_LABEL_NAMES: list[str] = [lb["name"] for lb in CANONICAL_LABELS]


def compute_target_state(ctx: Any) -> dict:
    """Return target state: canonical labels should be present."""
    return {
        "canonical_labels_present": True,
        "labels_canon": CANONICAL_LABELS,
    }


def target_state_predicate(state: Any) -> bool:
    """Pure: canonical_labels_present=True AND labels_canon ⊇ all 13 names (if provided)."""
    if not isinstance(state, dict):
        return False
    if state.get("canonical_labels_present") is not True:
        return False
    labels_canon = state.get("labels_canon")
    if labels_canon is not None:
        if not isinstance(labels_canon, list):
            return False
        canon_names = {lb["name"] for lb in CANONICAL_LABELS}
        provided = {lb["name"] if isinstance(lb, dict) else lb for lb in labels_canon}
        if not canon_names.issubset(provided):
            return False
    return True


def idempotency_check(ctx: Any) -> dict:
    """Read-only probe via `gh label list`. All subprocess calls mocked in CI.

    Checks whether all 13 canonical labels are present on the repo.
    """
    repo = _get_bsp_repo(ctx)
    if not repo:
        return {"present": False, "current_state": {"existing_names": [], "missing": CANONICAL_LABEL_NAMES}}
    try:
        result = subprocess.run(
            ["gh", "label", "list", "--repo", repo, "--json", "name", "--limit", "500"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            return {"present": False, "current_state": {
                "existing_names": [], "missing": CANONICAL_LABEL_NAMES, "error": result.stderr.strip()}}
        existing = [lb["name"] for lb in json.loads(result.stdout) if isinstance(lb, dict)]
    except (subprocess.TimeoutExpired, json.JSONDecodeError, OSError) as exc:
        return {"present": False, "current_state": {
            "existing_names": [], "missing": CANONICAL_LABEL_NAMES, "error": str(exc)}}
    missing = [n for n in CANONICAL_LABEL_NAMES if n not in set(existing)]
    return {"present": len(missing) == 0, "current_state": {"existing_names": existing, "missing": missing}}


def executor(ctx: Any) -> dict:
    """Automated: delegate to scripts/setup-labels.sh per github-project-v2.md § ensure-labels.

    setup-labels.sh is the SoT for the canonical label set. This executor is a
    thin wrapper that invokes it via subprocess. Idempotent — setup-labels.sh
    skips labels that already exist.
    """
    repo = _get_bsp_repo(ctx)
    if not repo:
        return {"applied": False, "message": "BSP_REPO not configured", "side_effects": []}

    check = idempotency_check(ctx)
    if check["present"]:
        return {"applied": False, "message": "all 13 canonical labels already present — no-op", "side_effects": []}

    # Delegate to setup-labels.sh — the SoT for label definitions.
    # Resolve script path relative to this file: stages_lib/ → scripts/ → setup-labels.sh
    setup_labels_sh = Path(__file__).parent.parent / "setup-labels.sh"
    try:
        result = subprocess.run(
            ["bash", str(setup_labels_sh), "--repo", repo],
            capture_output=True, text=True, timeout=120,
        )
    except (subprocess.TimeoutExpired, OSError) as exc:
        return {"applied": False, "message": f"setup-labels.sh subprocess error: {exc}", "side_effects": []}

    if result.returncode != 0:
        return {
            "applied": False,
            "message": f"setup-labels.sh failed (exit {result.returncode}): {result.stderr.strip()}",
            "side_effects": [],
        }

    missing_count = len(check["current_state"].get("missing", CANONICAL_LABEL_NAMES))
    return {
        "applied": True,
        "message": f"setup-labels.sh: {missing_count} labels created on {repo}",
        "side_effects": [f"invoked setup-labels.sh --repo {repo}"],
    }


def _get_bsp_repo(ctx: Any) -> str:
    """Derive BSP_REPO from env or repo_identity."""
    repo = os.environ.get("BSP_REPO", "")
    if repo:
        return repo
    identity = getattr(ctx, "repo_identity", "")
    return identity if isinstance(identity, str) else ""
