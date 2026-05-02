"""ADR-0014 4-callable contract for stage m10.repo.choose-kanban-projection.

Stage: M10 | agentic | repo-git | both platforms
Purpose: Prompt architect to choose the kanban projection used in this repo.
         At v0.5.0 the enum has only `github-project-v2`. Persists to
         repo-git settings.yml § modules.m10_kanban.projection (shorthand
         flat form per ADR-0026 v1.0 single-kanban; awk parser in
         bsp_resolve_active_projection reads this 4-space-indented key).
         Per ADR-0027 § 4 + ADR-0024 Part B.

character: agentic (single-choice; confirm-only flag)
locality: repo-git → <repo>/.board-superpowers/settings.yml
target_state_schema: {kanban_projection: enum [github-project-v2]}
default_value: github-project-v2
validation_kind: single-choice
module_section_path: modules.m10_kanban

Agentic stage protocol (ADR-0023):
  executor() returns {applied: False, requires_input: True, prompt: <dict>, default: ...}
  when not yet configured. The SKILL surfaces the prompt to the architect,
  validates the response, then calls apply_choice(ctx, projection_value).

5th callable: apply_choice(ctx, projection_value: str) -> dict
  Persists the validated projection choice to repo-git settings.yml under
  modules.m10_kanban.projection (shorthand flat form) and returns
  {applied: True, message: ..., side_effects: [...]}.

Storage format (ADR-0026 v1.0 shorthand — matched by bsp_resolve_active_projection awk):
  modules:
    m10_kanban:
      projection: github-project-v2
      schema_version: 1

  The 'primary' kanban_id nesting form is reserved for when multi-kanban
  kanbans-list support lands in v0.6.x. Using nested primary.projection at
  v0.5.0 breaks bsp_resolve_active_projection's awk parser (which only reads
  4-space-indented projection: or 8-space-indented inside a kanbans list).

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

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_MODULE_ID = "m10_kanban"
_DEFAULT_PROJECTION = "github-project-v2"
_VALID_PROJECTIONS = ["github-project-v2"]  # v0.5.0 enum

_PROMPT = {
    "kind": "single-choice",
    "prompt": (
        "Choose the kanban projection used in this repo: [github-project-v2] (default). "
        "Future v1.x ships add Linear / Jira / others."
    ),
    "options": _VALID_PROJECTIONS,
    "options_source": "computed-from-schema-enum",
    "default": _DEFAULT_PROJECTION,
}


# ---------------------------------------------------------------------------
# 4-callable ADR-0014 contract
# ---------------------------------------------------------------------------


def compute_target_state(ctx: Any) -> dict:
    """Return the prompt schema for this agentic stage.

    For agentic stages, compute_target_state returns the PROMPT SCHEMA
    (what the SKILL needs to elicit the architect's choice). The returned dict
    also satisfies the registry target_state_schema {required: [kanban_projection]}.

    Returns: {kanban_projection: str} using persisted value if known,
    or the default if not yet configured.
    """
    section = _get_module_section_raw(ctx)
    projection = section.get("projection")
    if isinstance(projection, str) and projection in _VALID_PROJECTIONS:
        return {"kanban_projection": projection}
    return {"kanban_projection": _DEFAULT_PROJECTION}


def target_state_predicate(state: Any) -> bool:
    """Pure: validate that state has kanban_projection ∈ valid enum."""
    if not isinstance(state, dict):
        return False
    proj = state.get("kanban_projection")
    if not isinstance(proj, str):
        return False
    return proj in _VALID_PROJECTIONS


def idempotency_check(ctx: Any) -> dict:
    """Read-only probe: check if projection is already recorded in repo-git settings.yml.

    Returns: {present: bool, current_state: {kanban_projection: str|None}}
    present=True means the stage has already been configured.
    """
    section = _get_module_section_raw(ctx)
    projection = section.get("projection")
    if isinstance(projection, str) and projection in _VALID_PROJECTIONS:
        return {"present": True, "current_state": {"kanban_projection": projection}}
    return {"present": False, "current_state": {"kanban_projection": None}}


def executor(ctx: Any) -> dict:
    """Agentic executor: no-op if already configured; otherwise signal requires_input.

    Per ADR-0023 agentic stage protocol:
    - If idempotency_check says already-recorded → return {applied: False, message: '...'}
    - If absent → return {applied: False, requires_input: True, prompt: <prompt dict>,
      default: <default>, message: '...'}

    Returns: {applied, message, requires_input?, prompt?, default?}
    """
    check = idempotency_check(ctx)
    if check["present"]:
        proj = check["current_state"]["kanban_projection"]
        return {
            "applied": False,
            "message": f"kanban projection already configured: {proj}",
        }

    return {
        "applied": False,
        "requires_input": True,
        "prompt": _PROMPT,
        "default": _DEFAULT_PROJECTION,
        "message": "kanban projection not yet configured — architect input required",
    }


def apply_choice(ctx: Any, projection_value: str) -> dict:
    """5th callable: persist the architect's validated kanban projection choice.

    Writes modules.m10_kanban.projection to repo-git settings.yml using the
    ADR-0026 v1.0 shorthand flat form:

      modules:
        m10_kanban:
          projection: github-project-v2
          schema_version: 1

    This is the form that bsp_resolve_active_projection's awk parser reads
    (captures 4-space-indented 'projection:' under m10_kanban when in_kanbans==0).
    The multi-kanban kanbans-list form is reserved for v0.6.x.
    Idempotent: re-applying the same value is safe.

    Args:
        ctx: lifecycle context with home, repo_root, repo_identity
        projection_value: validated projection identifier (e.g., 'github-project-v2')

    Returns: {applied, message, side_effects}
    """
    if not isinstance(projection_value, str):
        raise ValueError(
            f"projection_value must be str, got {type(projection_value).__name__}"
        )
    if projection_value not in _VALID_PROJECTIONS:
        raise ValueError(
            f"Unknown projection {projection_value!r}. "
            f"Valid options: {_VALID_PROJECTIONS}"
        )

    # Idempotency: same value already persisted — skip
    check = idempotency_check(ctx)
    if check["present"] and check["current_state"]["kanban_projection"] == projection_value:
        return {
            "applied": False,
            "message": f"kanban projection already set to {projection_value!r} — no change",
            "side_effects": [],
        }

    # ADR-0026 v1.0 shorthand: write flat under modules.m10_kanban.
    # projection: and schema_version: both at 4-space indent (module section level).
    # The awk parser captures /^[[:space:]]{4}projection:/ under m10_kanban.
    existing_section = _get_module_section_raw(ctx)
    new_section = {**existing_section, "projection": projection_value, "schema_version": 1}

    update_module_section(
        "repo-git",
        _MODULE_ID,
        new_section,
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )

    path = settings_path(
        "repo-git",
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )
    return {
        "applied": True,
        "message": (
            f"kanban projection set to {projection_value!r} "
            f"in settings.yml § modules.{_MODULE_ID}.projection"
        ),
        "side_effects": [
            f"updated {path} modules.{_MODULE_ID}.projection"
        ],
    }


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _get_module_section_raw(ctx: Any) -> dict:
    """Return the raw m10_kanban module section dict."""
    return get_module_section(
        "repo-git",
        _MODULE_ID,
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )
