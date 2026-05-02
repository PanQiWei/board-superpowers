"""ADR-0014 4-callable contract for stage m5.repo.write-config-local-yml.

Stage: M5 | automated | repo-clone | both platforms
Purpose: Write <repo>/.board-superpowers/settings.local.yml (repo-clone locality).
         Replaces v0.4.0 config.local.yml per ADR-0024 § Part A.
         This file is gitignored (*.local.* pattern per M6 stage).

target_state_schema: {path, schema_version (int ≥1)}

locality: repo-clone → <repo>/.board-superpowers/settings.local.yml
character: automated (writes empty stub; M5 set-wip-limit + M4 DSN fill fields later)

ctx contract: any object with attributes home, repo_root, repo_identity.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from stages_lib._partitioned_settings import (
    read_settings,
    settings_path,
    write_settings,
)

_SCHEMA_VERSION = 1


def compute_target_state(ctx: Any) -> dict:
    """Pure: derive target state from ctx (no I/O).

    Returns: {path, schema_version}
    """
    path = settings_path(
        "repo-clone",
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )
    return {
        "path": str(path),
        "schema_version": _SCHEMA_VERSION,
    }


def target_state_predicate(state: Any) -> bool:
    """Pure: validate state shape per target_state_schema."""
    if not isinstance(state, dict):
        return False
    if not isinstance(state.get("path"), str) or not state.get("path"):
        return False
    sv = state.get("schema_version")
    if not isinstance(sv, int) or sv < 1:
        return False
    return True


def idempotency_check(ctx: Any) -> dict:
    """Read-only probe: load repo-clone settings.local.yml; compare schema_version."""
    target = compute_target_state(ctx)
    existing = read_settings(
        "repo-clone",
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )
    if not existing:
        return {"present": False, "current_state": {}}
    setup = existing.get("setup", {})
    if not isinstance(setup, dict):
        return {"present": False, "current_state": {"setup": setup}}
    on_disk_sv = setup.get("schema_version")
    present = on_disk_sv == target["schema_version"]
    return {
        "present": present,
        "current_state": {"schema_version": on_disk_sv},
    }


def executor(ctx: Any) -> dict:
    """Write repo-clone settings.local.yml (ADR-0021 two-section structure).

    Idempotent: no-op if schema_version already matches target.
    Returns: {applied, message, side_effects}
    """
    if idempotency_check(ctx)["present"]:
        return {
            "applied": False,
            "message": "repo-clone settings.local.yml already matches target",
            "side_effects": [],
        }

    target = compute_target_state(ctx)

    # Minimal stub: M5 set-wip-limit and M4 DSN fill in fields later
    data = {
        "setup": {
            "schema_version": _SCHEMA_VERSION,
        },
        "stages_completed": [],
        "modules": {
            "lifecycle": {"schema_version": 1},
            "m4_audit": {"schema_version": 1, "dsn_scheme": ""},
            "m5_repo_configuration": {"schema_version": 1, "wip_limit": None},
            "m8_autonomy": {"schema_version": 1, "autonomy_overrides": []},
        },
    }
    write_settings(
        "repo-clone",
        data,
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )
    return {
        "applied": True,
        "message": f"wrote repo-clone settings.local.yml at {target['path']}",
        "side_effects": [f"wrote {target['path']}"],
    }
