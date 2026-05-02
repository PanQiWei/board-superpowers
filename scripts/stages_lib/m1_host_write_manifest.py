"""ADR-0014 4-callable contract for stage m1.host.write-manifest.

Stage: M1 | automated | host-shared | both platforms
Purpose: Atomic write of host-shared settings.yml at ~/.board-superpowers/settings.yml.
         Replaces v0.4.0 manifest.yml per ADR-0024 § Part A.

target_state_schema: {path, schema_version (int ≥1), last_seen_version (str), uv_version?, host_bootstrapped_at?}
hash_excluded_fields: [host_bootstrapped_at]

ctx: home, repo_root, repo_identity (all pathlib.Path / str compatible).
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from stages_lib._partitioned_settings import read_settings, write_settings

_SCHEMA_VERSION = 1
_PLUGIN_JSON_REL = ".claude-plugin/plugin.json"


def _read_plugin_version() -> str:
    """Read version from plugin.json; normalize to v-prefixed semver."""
    plugin_json = Path(__file__).parent.parent.parent / _PLUGIN_JSON_REL
    try:
        with open(plugin_json, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        ver = data.get("version", "")
        return (ver if ver.startswith("v") else f"v{ver}") if ver else "v0.0.0"
    except (OSError, json.JSONDecodeError):
        return "v0.0.0"


def compute_target_state(ctx: Any) -> dict:
    """Pure: derive target state from ctx.

    Returns: {path, schema_version, last_seen_version}
    host_bootstrapped_at omitted — hash_excluded_field, changes on every write.
    """
    return {
        "path": str(Path(ctx.home) / ".board-superpowers" / "settings.yml"),
        "schema_version": _SCHEMA_VERSION,
        "last_seen_version": _read_plugin_version(),
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
    lsv = state.get("last_seen_version")
    if not isinstance(lsv, str) or not lsv:
        return False
    return True


def idempotency_check(ctx: Any) -> dict:
    """Read-only probe: load host-shared settings.yml; compare schema_version + last_seen_version."""
    target = compute_target_state(ctx)
    existing = read_settings(
        "host-shared",
        home=Path(ctx.home), repo_root=Path(ctx.repo_root), repo_identity=ctx.repo_identity,
    )
    if not existing:
        return {"present": False, "current_state": {}}
    setup = existing.get("setup", {})
    if not isinstance(setup, dict):
        return {"present": False, "current_state": {"setup": setup}}
    on_disk_sv = setup.get("schema_version")
    on_disk_lsv = setup.get("last_seen_version") or setup.get("plugin_version", "")
    present = on_disk_sv == target["schema_version"] and on_disk_lsv == target["last_seen_version"]
    return {"present": present, "current_state": {"schema_version": on_disk_sv, "last_seen_version": on_disk_lsv}}


def executor(ctx: Any) -> dict:
    """Write host-shared settings.yml (ADR-0021 two-section structure).

    Idempotent: no-op if schema_version + last_seen_version already match.
    Returns: {applied, message, side_effects}
    """
    if idempotency_check(ctx)["present"]:
        return {"applied": False, "message": "host-shared settings.yml already matches target", "side_effects": []}

    target = compute_target_state(ctx)
    now = datetime.now(timezone.utc).isoformat()
    lsv = target["last_seen_version"]

    data = {
        "setup": {
            "generated_at": now,
            "host_bootstrapped_at": now,
            "last_seen_version": lsv,
            "plugin_version": lsv,
            "schema_version": _SCHEMA_VERSION,
        },
        "stages_completed": [],  # deprecated stub — schema compat per ADR-0021
        "modules": {
            "lifecycle": {"schema_version": 1},
            "m1_plugin_runtime": {"schema_version": 1},
            "m2_python_runtime": {"schema_version": 1, "uv_version": ""},
            "m8_autonomy": {"autonomy_overrides": [], "presets_chosen": [], "schema_version": 1},
            "m9_hook_registration": {"codex_hooks_registered": False, "schema_version": 1},
        },
    }
    write_settings(
        "host-shared", data,
        home=Path(ctx.home), repo_root=Path(ctx.repo_root), repo_identity=ctx.repo_identity,
    )
    return {
        "applied": True,
        "message": f"wrote host-shared settings.yml at {target['path']}",
        "side_effects": [f"wrote {target['path']}"],
    }
