"""ADR-0014 4-callable contract for stage m5.repo.write-config-yml.

Stage: M5 | automated | repo-git | both platforms
Purpose: Write <repo>/.board-superpowers/settings.yml (repo-git locality).
         Replaces v0.4.0 config.yml per ADR-0024 § Part A.

target_state_schema: {path, schema_version (int ≥1), defaults_present (bool)}

locality: repo-git → <repo>/.board-superpowers/settings.yml
character: automated (no architect input required)

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

    Returns: {path, schema_version, defaults_present}
    """
    path = settings_path(
        "repo-git",
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )
    return {
        "path": str(path),
        "schema_version": _SCHEMA_VERSION,
        "defaults_present": True,
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
    """Read-only probe: load repo-git settings.yml; compare schema_version."""
    target = compute_target_state(ctx)
    existing = read_settings(
        "repo-git",
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
    """Write repo-git settings.yml (ADR-0021 two-section structure).

    Idempotent: no-op if schema_version already matches target.
    Returns: {applied, message, side_effects}
    """
    if idempotency_check(ctx)["present"]:
        return {
            "applied": False,
            "message": "repo-git settings.yml already matches target",
            "side_effects": [],
        }

    target = compute_target_state(ctx)

    data = {
        "setup": {
            "schema_version": _SCHEMA_VERSION,
        },
        "stages_completed": [],
        "modules": {
            "lifecycle": {"schema_version": 1},
            "m5_repo_configuration": {"schema_version": 1},
            "m10_kanban": {"schema_version": 1},
        },
    }
    write_settings(
        "repo-git",
        data,
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )
    return {
        "applied": True,
        "message": f"wrote repo-git settings.yml at {target['path']}",
        "side_effects": [f"wrote {target['path']}"],
    }
