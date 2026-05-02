"""ADR-0014 4-callable contract for stage m3.repo.validate-status-field.

Stage: M3 | agentic (on-failure) | external | both platforms
character: agentic (flags: confirm-only, agentic-on-failure)
locality: external | depends_on: m10.repo.choose-kanban-projection
applicable_when: {kanban_projection_capability: validate-status-field}
external_ttl_seconds: 86400

executor(): all 6 canonical present → no-op; missing → requires_input.
apply_choice(): persists resolution to repo-git settings.yml.
ctx contract: any object with attributes home, repo_root, repo_identity.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from typing import Any

from stages_lib._partitioned_settings import (
    get_module_section,
    settings_path,
    update_module_section,
)

CANONICAL_STATUS_OPTIONS: list[str] = [
    "Backlog", "Ready", "In Progress", "In Review", "Blocked", "Done",
]
CANONICAL_STATUS_SET: set[str] = set(CANONICAL_STATUS_OPTIONS)

VALID_RESOLUTIONS: list[str] = [
    "canonical-already-present",
    "architect-added-missing",
    "architect-accepted-custom-state-folding",
]

_MODULE_ID = "m3_validate_status_field"
_M10_MODULE_ID = "m10_kanban"
_DEFAULT_KANBAN_ID = "primary"

_PROMPT = {
    "kind": "single-choice",
    "prompt": (
        "Status field missing canonical options (Backlog/Ready/In Progress/In Review/Done/Blocked). "
        "Choose resolution:"
    ),
    "options": [
        {"value": "architect-added-missing",
         "label": "I added the missing options in the projection UI — re-validate now",
         "description": "After manually adding missing Status options in GitHub Project settings."},
        {"value": "architect-accepted-custom-state-folding",
         "label": "Accept custom-state folding (extra options fold to Backlog at runtime)",
         "description": "Extra Status options treated as Backlog by board-superpowers runtime."},
    ],
    "options_source": "literal",
}


def compute_target_state(ctx: Any) -> dict:
    """Return expected target state; satisfies registry target_state_schema."""
    section = _get_section(ctx)
    resolution = section.get("resolution", "canonical-already-present")
    return {
        "status_options_canonical_present": True,
        "canonical_status_options": CANONICAL_STATUS_OPTIONS,
        "resolution": resolution if resolution in VALID_RESOLUTIONS else "canonical-already-present",
    }


def target_state_predicate(state: Any) -> bool:
    """Pure: valid if status_options_canonical_present=True OR resolution ∈ VALID_RESOLUTIONS."""
    if not isinstance(state, dict):
        return False
    if state.get("status_options_canonical_present") is True:
        return True
    res = state.get("resolution")
    return isinstance(res, str) and res in VALID_RESOLUTIONS


_GQL = (
    "query($owner:String!,$num:Int!){user(login:$owner){projectV2(number:$num){"
    "field(name:\"Status\"){... on ProjectV2SingleSelectField{options{name}}}}}}"
)


def idempotency_check(ctx: Any) -> dict:
    """Read-only probe: gh api graphql to check Status field options. Mocked in CI."""
    ref = _get_project_ref(ctx)
    _empty = {"existing_options": [], "missing": CANONICAL_STATUS_OPTIONS, "custom": []}
    if not ref:
        return {"present": False, "current_state": {**_empty, "error": "BSP_PROJECT_REF not configured"}}
    parts = ref.split("/")
    if len(parts) != 2 or not all(parts):
        return {"present": False, "current_state": {**_empty, "error": f"invalid project_ref: {ref!r}"}}
    owner, num = parts
    try:
        r = subprocess.run(
            ["gh", "api", "graphql", "-f", f"query={_GQL}", "-F", f"owner={owner}", "-F", f"num={num}"],
            capture_output=True, text=True, timeout=30,
        )
        if r.returncode != 0:
            return {"present": False, "current_state": {**_empty, "error": r.stderr.strip()}}
        opts = (json.loads(r.stdout).get("data", {}).get("user", {})
                .get("projectV2", {}).get("field", {}).get("options", []))
        existing = [o["name"] for o in opts if isinstance(o, dict)]
    except (subprocess.TimeoutExpired, json.JSONDecodeError, OSError) as exc:
        return {"present": False, "current_state": {**_empty, "error": str(exc)}}
    missing = [n for n in CANONICAL_STATUS_OPTIONS if n not in set(existing)]
    custom = [n for n in existing if n not in CANONICAL_STATUS_SET]
    return {"present": len(missing) == 0,
            "current_state": {"existing_options": existing, "missing": missing, "custom": custom}}


def executor(ctx: Any) -> dict:
    """Agentic-on-failure executor.

    All 6 canonical options present → no-op.
    Missing → requires_input with 2-option resolution prompt.
    Resolution already persisted → no-op.
    """
    section = _get_section(ctx)
    resolution = section.get("resolution")
    if isinstance(resolution, str) and resolution in VALID_RESOLUTIONS:
        return {
            "applied": False,
            "message": f"status field validation already resolved: {resolution}",
        }

    check = idempotency_check(ctx)
    if check["present"]:
        return {
            "applied": False,
            "message": "Status field has all 6 canonical options — canonical-already-present",
        }

    missing = check["current_state"].get("missing", CANONICAL_STATUS_OPTIONS)
    prompt = dict(_PROMPT)
    prompt["missing_options"] = missing
    return {
        "applied": False,
        "requires_input": True,
        "prompt": prompt,
        "missing_options": missing,
        "message": (
            f"Status field missing canonical options: {missing}. "
            "Architect resolution required."
        ),
    }


def apply_choice(ctx: Any, resolution_value: str) -> dict:
    """5th callable: persist resolution choice to repo-git settings.yml."""
    if not isinstance(resolution_value, str):
        raise ValueError(
            f"resolution_value must be str, got {type(resolution_value).__name__}"
        )
    if resolution_value not in VALID_RESOLUTIONS:
        raise ValueError(
            f"Unknown resolution {resolution_value!r}. Valid: {VALID_RESOLUTIONS}"
        )

    section = _get_section(ctx)
    if section.get("resolution") == resolution_value:
        return {
            "applied": False,
            "message": f"resolution already set to {resolution_value!r} — no change",
            "side_effects": [],
        }

    update_module_section(
        "repo-git", _MODULE_ID,
        {"resolution": resolution_value, "canonical_status_options": CANONICAL_STATUS_OPTIONS,
         "schema_version": 1},
        home=Path(ctx.home), repo_root=Path(ctx.repo_root), repo_identity=ctx.repo_identity,
    )

    path = settings_path(
        "repo-git",
        home=Path(ctx.home), repo_root=Path(ctx.repo_root), repo_identity=ctx.repo_identity,
    )
    return {
        "applied": True,
        "message": f"status field resolution set to {resolution_value!r}",
        "side_effects": [f"updated {path} modules.{_MODULE_ID}.resolution"],
    }


def _get_section(ctx: Any) -> dict:
    return get_module_section(
        "repo-git", _MODULE_ID,
        home=Path(ctx.home), repo_root=Path(ctx.repo_root), repo_identity=ctx.repo_identity,
    )


def _get_project_ref(ctx: Any) -> str:
    ref = os.environ.get("BSP_PROJECT_REF", "")
    if ref:
        return ref
    m10 = get_module_section(
        "repo-git", _M10_MODULE_ID,
        home=Path(ctx.home), repo_root=Path(ctx.repo_root), repo_identity=ctx.repo_identity,
    )
    # ADR-0026 v1.0 shorthand flat form: modules.m10_kanban.project_ref
    # (same level as modules.m10_kanban.projection, written by M10 apply_choice)
    flat_ref = m10.get("project_ref", "")
    if flat_ref and isinstance(flat_ref, str):
        return flat_ref
    # Legacy fallback: nested primary.project_ref (pre-fix format — no longer written
    # by apply_choice but kept for backwards compat with manually-edited settings files)
    primary = m10.get(_DEFAULT_KANBAN_ID, {})
    return primary.get("project_ref", "") if isinstance(primary, dict) else ""
