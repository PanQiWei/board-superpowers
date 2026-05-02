"""ADR-0014 4-callable contract for stage m8.host.bootstrap-overrides-yml.

Stage: M8 | agentic | host-shared | both platforms
Purpose: Prompt architect with curated autonomy-override presets; persist selected
         subset into host-shared settings.yml § modules.m8_autonomy (per ADR-0024
         § Part A — overrides.yml folded into host-shared settings.yml).
         Empty selection is a valid completed state.

character: agentic (multi-choice, runtime-derived options_source)
locality: host-shared → ~/.board-superpowers/settings.yml
target_state_schema: {presets_selected: list, presets_canon_known?: list}
default_value: []
validation_kind: multi-choice
module_section_path: modules.m8_autonomy

Agentic stage protocol (ADR-0023):
  executor() returns {applied: False, requires_input: True, prompt: <dict>,
    default: [], options: [...], message: '...'} when the stage has not been
  configured. The SKILL surfaces the prompt, validates the response, then
  calls apply_choice(ctx, chosen_presets) to persist.

5th callable: apply_choice(ctx, chosen_presets: list[str]) -> dict
  Persists the validated preset selection to host-shared settings.yml and
  returns {applied: True, message: ..., side_effects: [...]}.

Runtime-derived options: The preset catalog is defined in this module (not in
the registry) because ADR-0023 options_source=runtime-derived means the
SKILL reads the helper's compute_target_state() to get the prompt options.
The catalog is anchored to the ADR-0006 D-AUTONOMY-1 matrix R-class rows
that architects most commonly want to promote to A (v1 curated subset).

Preset catalog (v1 — derived from ADR-0006 §3 R-class rows):
  allow-split-card          → action_id=3  (R→A: auto-split cards)
  allow-close-stale-card    → action_id=7  (R→A: auto-close stale cards)
  allow-cancel-claim        → action_id=8  (R→A: auto-cancel stale claims)
  allow-pr-merge            → action_id=12 (R→A: auto-merge PRs)

ctx contract: any object with attributes home, repo_root, repo_identity.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from stages_lib._partitioned_settings import (
    get_module_section,
    settings_path,
    update_module_section,
)

_MODULE_ID = "m8_autonomy"
_FIELD_SELECTED = "presets_selected"
_FIELD_CANON = "presets_canon_known"
_FIELD_CHOSEN = "presets_chosen"  # legacy alias used in host-shared template

# Curated preset catalog — runtime-derived from ADR-0006 R-class rows.
# Each entry: (preset_name, action_id, description)
# Anchored to ADR-0006 §3 initial permission matrix.
_PRESET_CATALOG: list[dict] = [
    {
        "name": "allow-split-card",
        "action_id": 3,
        "description": (
            "Promote action #3 (Split card) from R to A. "
            "Producer will auto-split cards without waiting for architect approval."
        ),
        "introduced_in_version": "v0.5.0",
    },
    {
        "name": "allow-close-stale-card",
        "action_id": 7,
        "description": (
            "Promote action #7 (Close stale card) from R to A. "
            "Producer will auto-close stale cards without asking."
        ),
        "introduced_in_version": "v0.5.0",
    },
    {
        "name": "allow-cancel-claim",
        "action_id": 8,
        "description": (
            "Promote action #8 (Cancel claim) from R to A. "
            "Producer will auto-cancel stale claims without asking."
        ),
        "introduced_in_version": "v0.5.0",
    },
    {
        "name": "allow-pr-merge",
        "action_id": 12,
        "description": (
            "Promote action #12 (Auto-merge PR) from R to A. "
            "Producer will auto-merge PRs that pass CI without architect approval."
        ),
        "introduced_in_version": "v0.5.0",
    },
]

_ALL_PRESET_NAMES: list[str] = [p["name"] for p in _PRESET_CATALOG]

_PROMPT = {
    "kind": "multi-choice",
    "prompt": (
        "Select autonomy-override presets to apply to this host. "
        "Empty selection is valid (no host-level overrides). Per ADR-0006 + ADR-0023."
    ),
    "options": _ALL_PRESET_NAMES,
    "options_catalog": _PRESET_CATALOG,
    "options_source": "runtime-derived",
    "default": [],
}


def _derive_preset_options() -> list[str]:
    """Return the runtime-derived list of valid preset names.

    This is what 'options_source: runtime-derived' means for M8: the SKILL
    calls compute_target_state() to get the prompt dict which includes the
    options list derived at runtime from the module's _PRESET_CATALOG.
    """
    return list(_ALL_PRESET_NAMES)


def compute_target_state(ctx: Any) -> dict:
    """Pure: return the prompt schema for this agentic stage.

    For agentic stages compute_target_state returns the PROMPT SCHEMA
    with the runtime-derived options list. The returned dict also satisfies
    the registry target_state_schema {required: [presets_selected]}.

    Returns: {presets_selected: list, presets_canon_known: list}
    Uses existing persisted value if already configured, otherwise [].
    """
    section = get_module_section(
        "host-shared",
        _MODULE_ID,
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )
    # Check both field names (presets_selected = canonical; presets_chosen = legacy alias)
    selected = section.get(_FIELD_SELECTED, section.get(_FIELD_CHOSEN, None))
    if selected is None:
        selected = []

    canon = _derive_preset_options()
    return {
        "presets_selected": selected if isinstance(selected, list) else [],
        "presets_canon_known": canon,
    }


def target_state_predicate(state: Any) -> bool:
    """Pure: validate that the chosen presets list is a subset of valid options.

    An empty list [] is valid (no presets chosen = valid completed state per ADR-0023).
    """
    if not isinstance(state, dict):
        return False
    selected = state.get(_FIELD_SELECTED)
    if selected is None:
        return False
    if not isinstance(selected, list):
        return False
    valid_names = set(_ALL_PRESET_NAMES)
    for item in selected:
        if not isinstance(item, str):
            return False
        if item not in valid_names:
            return False
    return True


def idempotency_check(ctx: Any) -> dict:
    """Read-only probe: check if presets_selected is already recorded in host-shared settings.yml.

    Returns: {present: bool, current_state: {presets_selected: list|None}}
    present=True means the stage has been configured (even if empty list was chosen).
    We detect 'configured' by checking if the field key exists (None = absent vs [] = configured).
    """
    section = get_module_section(
        "host-shared",
        _MODULE_ID,
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )

    # Field present means stage has been configured (even empty list = configured)
    if _FIELD_SELECTED in section:
        selected = section[_FIELD_SELECTED]
        return {
            "present": True,
            "current_state": {_FIELD_SELECTED: selected},
        }
    # Also check legacy alias
    if _FIELD_CHOSEN in section:
        selected = section[_FIELD_CHOSEN]
        return {
            "present": True,
            "current_state": {_FIELD_SELECTED: selected},
        }

    return {"present": False, "current_state": {_FIELD_SELECTED: None}}


def executor(ctx: Any) -> dict:
    """Agentic executor: no-op if already configured; otherwise signal requires_input.

    Per ADR-0023 agentic stage protocol:
    - If idempotency_check says already-recorded → return {applied: False, message: '...'}
    - If absent → return {applied: False, requires_input: True, prompt: <prompt dict>,
      options: [...], default: [], message: '...'}
      The SKILL reads requires_input=True, surfaces the multi-choice prompt to the architect.
      After architect responds, the SKILL calls apply_choice(ctx, chosen_presets).

    Returns: {applied, message, requires_input?, prompt?, options?, default?}
    """
    check = idempotency_check(ctx)
    if check["present"]:
        selected = check["current_state"][_FIELD_SELECTED]
        count = len(selected) if isinstance(selected, list) else 0
        return {
            "applied": False,
            "message": f"autonomy presets already configured: {count} preset(s) selected",
        }

    prompt = dict(_PROMPT)
    prompt["options"] = _derive_preset_options()

    return {
        "applied": False,
        "requires_input": True,
        "prompt": prompt,
        "options": _derive_preset_options(),
        "default": [],
        "message": "autonomy presets not yet configured — architect input required",
    }


def apply_choice(ctx: Any, chosen_presets: list) -> dict:
    """5th callable: persist the architect's validated preset selection.

    Writes modules.m8_autonomy.presets_selected + autonomy_overrides to
    host-shared settings.yml. Empty list is a valid input (no overrides).
    Idempotent: re-applying the same selection is safe.

    Also expands chosen preset names to autonomy_overrides[] entries per
    ADR-0006 §3 matrix (action_id + class: A).

    Args:
        ctx: lifecycle context with home, repo_root, repo_identity
        chosen_presets: validated list of preset names (subset of _ALL_PRESET_NAMES)

    Returns: {applied, message, side_effects}
    """
    if not isinstance(chosen_presets, list):
        raise ValueError(
            f"chosen_presets must be list, got {type(chosen_presets).__name__}"
        )
    valid_names = set(_ALL_PRESET_NAMES)
    for item in chosen_presets:
        if not isinstance(item, str) or item not in valid_names:
            raise ValueError(
                f"Invalid preset {item!r}. Valid presets: {sorted(valid_names)}"
            )

    # Check idempotency — if already set to the same selection, skip
    check = idempotency_check(ctx)
    if check["present"]:
        existing = check["current_state"].get(_FIELD_SELECTED, [])
        if sorted(existing or []) == sorted(chosen_presets):
            return {
                "applied": False,
                "message": (
                    f"autonomy presets already set to {chosen_presets!r} — no change"
                ),
                "side_effects": [],
            }

    # Expand preset names to autonomy_overrides[] entries
    autonomy_overrides = []
    preset_map = {p["name"]: p for p in _PRESET_CATALOG}
    for name in chosen_presets:
        preset = preset_map[name]
        autonomy_overrides.append({
            "action_id": preset["action_id"],
            "class": "A",
            "source": f"preset:{name}",
        })

    update_module_section(
        "host-shared",
        _MODULE_ID,
        {
            _FIELD_SELECTED: chosen_presets,
            _FIELD_CHOSEN: chosen_presets,  # legacy alias for compat
            "autonomy_overrides": autonomy_overrides,
            "presets_canon_known": _derive_preset_options(),
            "schema_version": 1,
        },
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )

    path = settings_path(
        "host-shared",
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )
    count = len(chosen_presets)
    return {
        "applied": True,
        "message": (
            f"autonomy presets configured: {count} preset(s) selected "
            f"({chosen_presets!r})"
        ),
        "side_effects": [f"updated {path} modules.{_MODULE_ID}.{_FIELD_SELECTED}"],
    }
