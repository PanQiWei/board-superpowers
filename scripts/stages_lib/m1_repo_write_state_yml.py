"""ADR-0014 4-callable contract for stage m1.repo.write-state-yml.

Stage: M1 | automated | repo-shared | both platforms
Purpose: Atomic write of per-repo settings.yml at HOST-side path
         ~/.board-superpowers/repos/<repo-identity>/settings.yml.
         Replaces v0.4.0 state.yml per ADR-0024 § Part A.

Locality: repo-shared (HOST-side, NOT under <repo>/). Per ADR-0017 I-13:
  repo_identity = "<owner>/<repo>" slug from git remote "origin".

target_state_schema: {path, schema_version (int ≥1), repo_identity?, stages_completed_present?, routing_blocks_present?}

ctx: home, repo_root, repo_identity (all pathlib.Path / str compatible).
"""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from stages_lib._partitioned_settings import read_settings, settings_path, write_settings

_SCHEMA_VERSION = 1


def compute_target_state(ctx: Any) -> dict:
    """Pure: derive target state from ctx (no I/O)."""
    path = settings_path(
        "repo-shared",
        home=Path(ctx.home), repo_root=Path(ctx.repo_root), repo_identity=ctx.repo_identity,
    )
    return {
        "path": str(path),
        "schema_version": _SCHEMA_VERSION,
        "repo_identity": ctx.repo_identity,
        "stages_completed_present": True,
        "routing_blocks_present": False,
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
    """Read-only probe: load repo-shared settings.yml; compare schema_version + repo_identity."""
    target = compute_target_state(ctx)
    existing = read_settings(
        "repo-shared",
        home=Path(ctx.home), repo_root=Path(ctx.repo_root), repo_identity=ctx.repo_identity,
    )
    if not existing:
        return {"present": False, "current_state": {}}
    setup = existing.get("setup", {})
    if not isinstance(setup, dict):
        return {"present": False, "current_state": {"setup": setup}}
    on_disk_sv = setup.get("schema_version")
    on_disk_ri = setup.get("repo_identity", "")
    present = on_disk_sv == target["schema_version"] and on_disk_ri == target["repo_identity"]
    return {"present": present, "current_state": {"schema_version": on_disk_sv, "repo_identity": on_disk_ri}}


def executor(ctx: Any) -> dict:
    """Write repo-shared settings.yml (ADR-0021 two-section structure).

    Idempotent: no-op if schema_version + repo_identity already match.
    Parent dir created by write_settings (os.makedirs exist_ok=True).
    Returns: {applied, message, side_effects}
    """
    if idempotency_check(ctx)["present"]:
        return {"applied": False, "message": "repo-shared settings.yml already matches target", "side_effects": []}

    target = compute_target_state(ctx)
    now = datetime.now(timezone.utc).isoformat()

    data = {
        "setup": {
            "generated_at": now,
            "plugin_version": "",   # filled after m1.host.write-manifest
            "repo_identity": ctx.repo_identity,
            "schema_version": _SCHEMA_VERSION,
        },
        "stages_completed": [],  # deprecated stub — schema compat per ADR-0021
        "modules": {
            "lifecycle": {"schema_version": 1},
            "m1_plugin_runtime": {"bootstrapped_at": now, "schema_version": 1},
            "m4_audit": {"audit_rows_landed": 0, "dsn_recorded": False, "pending_count": 0, "schema_version": 1},
            "m7_routing": {"detected_form": "", "schema_version": 1},
        },
    }
    write_settings(
        "repo-shared", data,
        home=Path(ctx.home), repo_root=Path(ctx.repo_root), repo_identity=ctx.repo_identity,
    )
    return {
        "applied": True,
        "message": f"wrote repo-shared settings.yml at {target['path']} for repo {ctx.repo_identity}",
        "side_effects": [f"wrote {target['path']}"],
    }
