"""ADR-0014 4-callable contract for stage m5.repo.set-wip-limit.

Stage: M5 | agentic | repo-clone | both platforms
Purpose: Prompt architect for wip_limit (concurrent active Consumer cap);
         default 5; persist into settings.local.yml § modules.m5_repo_configuration.wip_limit.
         Per ADR-0024 § Part B + ADR-0023 5-element config item protocol.

character: agentic (numeric-range; confirm-only flag means architect may accept default)
locality: repo-clone → <repo>/.board-superpowers/settings.local.yml
target_state_schema: {wip_limit: int (1..20)}
default_value: 5
validation_kind: numeric-range
module_section_path: modules.m5_repo_configuration

Agentic stage protocol (ADR-0023):
  executor() returns {applied: False, requires_input: True, prompt: <dict>, default: 5}
  when the stage has not been configured. The SKILL surfaces the prompt to the
  architect, validates the response, then calls apply_choice(ctx, chosen_value)
  to persist and mark the stage completed.

5th callable: apply_choice(ctx, chosen_value: int) -> dict
  Persists the validated wip_limit to repo-clone settings.local.yml and
  returns {applied: True, message: ..., side_effects: [...]}.

ctx contract: any object with attributes home, repo_root, repo_identity.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from stages_lib._partitioned_settings import (
    get_module_section,
    update_module_section,
)

_DEFAULT_WIP_LIMIT = 5
_MIN_WIP_LIMIT = 1
_MAX_WIP_LIMIT = 20
_MODULE_ID = "m5_repo_configuration"
_FIELD = "wip_limit"

# Prompt shape as declared in registry interactive_prompt
_PROMPT = {
    "kind": "numeric-range",
    "prompt": (
        "Set the WIP limit (concurrent active Consumer cap) for this repo. "
        f"Default: {_DEFAULT_WIP_LIMIT}. Range: {_MIN_WIP_LIMIT}..{_MAX_WIP_LIMIT}."
    ),
    "min": _MIN_WIP_LIMIT,
    "max": _MAX_WIP_LIMIT,
    "default": _DEFAULT_WIP_LIMIT,
}


def compute_target_state(ctx: Any) -> dict:
    """Pure: return the prompt schema for this agentic stage.

    For agentic stages compute_target_state returns the PROMPT SCHEMA
    (what the SKILL needs to elicit the architect's choice), not a
    persisted value. This satisfies the registry target_state_schema
    via the 'kind' + numeric bounds fields.

    Returns: {wip_limit: int} using the current persisted value if known,
    or the default if not yet configured. This validates against the registry
    target_state_schema {required: [wip_limit]}.
    """
    section = get_module_section(
        "repo-clone",
        _MODULE_ID,
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )
    wip = section.get(_FIELD)
    if isinstance(wip, int) and _MIN_WIP_LIMIT <= wip <= _MAX_WIP_LIMIT:
        return {"wip_limit": wip}
    return {"wip_limit": _DEFAULT_WIP_LIMIT}


def target_state_predicate(state: Any) -> bool:
    """Pure: validate that a chosen value is a valid wip_limit (int in 1..20)."""
    if not isinstance(state, dict):
        return False
    wip = state.get(_FIELD)
    if not isinstance(wip, int):
        return False
    return _MIN_WIP_LIMIT <= wip <= _MAX_WIP_LIMIT


def idempotency_check(ctx: Any) -> dict:
    """Read-only probe: check if wip_limit is already recorded in settings.local.yml.

    Returns: {present: bool, current_state: {wip_limit: int|None}}
    present=True means the stage has already been configured and the executor
    should be a no-op.
    """
    section = get_module_section(
        "repo-clone",
        _MODULE_ID,
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )
    wip = section.get(_FIELD)
    if isinstance(wip, int) and _MIN_WIP_LIMIT <= wip <= _MAX_WIP_LIMIT:
        return {"present": True, "current_state": {_FIELD: wip}}
    return {"present": False, "current_state": {_FIELD: None}}


def executor(ctx: Any) -> dict:
    """Agentic executor: no-op if already configured; otherwise signal requires_input.

    Per ADR-0023 agentic stage protocol:
    - If idempotency_check says already-recorded → return {applied: False, message: '...'}
    - If absent → return {applied: False, requires_input: True, prompt: <prompt dict>,
      default: <default>, message: '...'}
      The SKILL reads requires_input=True and surfaces the prompt to the architect.
      After architect responds, the SKILL calls apply_choice(ctx, chosen_value).

    Returns: {applied, message, requires_input?, prompt?, default?}
    """
    check = idempotency_check(ctx)
    if check["present"]:
        wip = check["current_state"][_FIELD]
        return {
            "applied": False,
            "message": f"wip_limit already configured: {wip}",
        }

    return {
        "applied": False,
        "requires_input": True,
        "prompt": _PROMPT,
        "default": _DEFAULT_WIP_LIMIT,
        "message": "wip_limit not yet configured — architect input required",
    }


def apply_choice(ctx: Any, chosen_value: int) -> dict:
    """5th callable: persist the architect's validated wip_limit choice.

    Writes modules.m5_repo_configuration.wip_limit to repo-clone settings.local.yml.
    Called by the SKILL after the architect confirms or enters a value.
    Idempotent: re-applying the same value is safe.

    Args:
        ctx: lifecycle context with home, repo_root, repo_identity
        chosen_value: validated integer in [1, 20]

    Returns: {applied, message, side_effects}
    """
    if not isinstance(chosen_value, int):
        raise ValueError(
            f"chosen_value must be int, got {type(chosen_value).__name__}"
        )
    if not (_MIN_WIP_LIMIT <= chosen_value <= _MAX_WIP_LIMIT):
        raise ValueError(
            f"chosen_value {chosen_value} out of range [{_MIN_WIP_LIMIT}, {_MAX_WIP_LIMIT}]"
        )

    # Check idempotency — if already set to the same value, skip
    check = idempotency_check(ctx)
    if check["present"] and check["current_state"][_FIELD] == chosen_value:
        return {
            "applied": False,
            "message": f"wip_limit already set to {chosen_value} — no change",
            "side_effects": [],
        }

    update_module_section(
        "repo-clone",
        _MODULE_ID,
        {_FIELD: chosen_value, "schema_version": 1},
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )

    from stages_lib._partitioned_settings import settings_path
    path = settings_path(
        "repo-clone",
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )
    return {
        "applied": True,
        "message": f"wip_limit set to {chosen_value} in settings.local.yml",
        "side_effects": [f"updated {path} modules.{_MODULE_ID}.{_FIELD}"],
    }
