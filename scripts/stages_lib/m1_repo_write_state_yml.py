"""ADR-0014 4-callable contract for stage m1.repo.write-state-yml.

Stage: M1 | automated | repo-shared | both platforms
Purpose: Atomic write of per-repo settings.yml at HOST-side path
         ~/.board-superpowers/repos/<repo-identity>/settings.yml.
         Replaces v0.4.0 state.yml per ADR-0024 § Part A.

Locality: repo-shared (HOST-side, NOT under <repo>/). Per ADR-0017 I-13:
  repo_identity = "<owner>/<repo>" slug from git remote "origin".

target_state_schema: {path, schema_version (int ≥1), repo_identity?, stages_completed_present?, routing_blocks_present?}

ctx: home, repo_root, repo_identity (all pathlib.Path / str compatible).

Lifecycle invariant: append-merge-only. executor() MUST load-merge against
existing settings.yml content; it MUST NOT bulk-overwrite. Peer-written
modules.lifecycle.<stage_id> entries, architect-supplied module fields
(m4_audit.dsn_scheme, m7_routing.detected_form, m10_kanban.projection,
etc.), and any non-setup top-level keys MUST survive. See
SETUP_STAGES_DEVELOPMENT.md § "Lifecycle invariant: append-merge-only".
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

    Lifecycle invariant: append-merge-only. We LOAD existing settings.yml
    first, OVERWRITE only the `setup` section + ensure baseline module
    skeletons exist, then write back. Peer-written
    modules.lifecycle.<stage_id> entries, architect-supplied module fields,
    and any non-setup top-level keys are preserved verbatim. See
    SETUP_STAGES_DEVELOPMENT.md § "Lifecycle invariant: append-merge-only".
    """
    if idempotency_check(ctx)["present"]:
        return {"applied": False, "message": "repo-shared settings.yml already matches target", "side_effects": []}

    target = compute_target_state(ctx)
    now = datetime.now(timezone.utc).isoformat()

    # Load-merge: read existing content (empty dict if absent) and merge
    # only this stage's owned fields. Never bulk-overwrite.
    existing = read_settings(
        "repo-shared",
        home=Path(ctx.home), repo_root=Path(ctx.repo_root), repo_identity=ctx.repo_identity,
    )
    data: dict = dict(existing) if isinstance(existing, dict) else {}

    # 1. setup — this stage owns this section; replace it wholesale.
    data["setup"] = {
        "generated_at": now,
        "plugin_version": "",   # filled after m1.host.write-manifest
        "repo_identity": ctx.repo_identity,
        "schema_version": _SCHEMA_VERSION,
    }

    # 2. stages_completed — deprecated stub; ensure presence without
    # clobbering historical entries.
    if "stages_completed" not in data or not isinstance(data["stages_completed"], list):
        data["stages_completed"] = []

    # 3. modules — ensure top-level dict, then ensure each baseline module
    # skeleton without clobbering peer-written keys.
    modules = data.get("modules")
    if not isinstance(modules, dict):
        modules = {}
        data["modules"] = modules

    def _ensure_module(name: str, skeleton: dict) -> None:
        existing_section = modules.get(name)
        if not isinstance(existing_section, dict):
            modules[name] = dict(skeleton)
            return
        # Merge skeleton keys WITHOUT overwriting any field the architect /
        # peer stage already populated.
        for k, v in skeleton.items():
            existing_section.setdefault(k, v)

    _ensure_module("lifecycle", {"schema_version": 1})
    _ensure_module("m1_plugin_runtime", {"bootstrapped_at": now, "schema_version": 1})
    _ensure_module("m4_audit", {
        "audit_rows_landed": 0, "dsn_recorded": False, "pending_count": 0, "schema_version": 1,
    })
    _ensure_module("m7_routing", {"detected_form": "", "schema_version": 1})

    write_settings(
        "repo-shared", data,
        home=Path(ctx.home), repo_root=Path(ctx.repo_root), repo_identity=ctx.repo_identity,
    )
    return {
        "applied": True,
        "message": f"wrote repo-shared settings.yml at {target['path']} for repo {ctx.repo_identity}",
        "side_effects": [f"wrote {target['path']}"],
    }
