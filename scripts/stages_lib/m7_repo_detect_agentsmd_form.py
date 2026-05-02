"""ADR-0014 4-callable contract for stage m7.repo.detect-agentsmd-form.

Stage identity: M7 | automated | repo-shared | both platforms
Purpose: Detect repo's routing-target form by scanning AGENTS.md + CLAUDE.md
         presence; cache result in repo-shared settings.yml.

Form enum (ADR-0018 § Decision element 1):
  cc-only    — AGENTS.md absent, CLAUDE.md present
  codex-only — AGENTS.md present, CLAUDE.md absent
  dual       — AGENTS.md present AND CLAUDE.md present
  neither    — both absent

Locality: repo-shared → state stored host-side (not in git).
Each clone re-detects on bootstrap rather than inheriting another clone's
filesystem layout (per ADR-0018 § "Prerequisite form-detect stage").

target_state_schema (from registry):
  {form: enum[cc-only|codex-only|dual|neither],
   agentsmd_present?: bool,
   claudemd_present?: bool}

ctx contract: any object with attributes home, repo_root, repo_identity.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import stages_lib._partitioned_settings as _ps

# ---------------------------------------------------------------------------
# Internal constants
# ---------------------------------------------------------------------------

_VALID_FORMS = {"cc-only", "codex-only", "dual", "neither"}
_MODULE_ID = "m7_agent_routing"
_LOCALITY = "repo-shared"


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _detect_form(repo_root: Path) -> dict:
    """Detect AGENTS.md and CLAUDE.md presence; return form + booleans."""
    agents_present = (repo_root / "AGENTS.md").exists()
    claude_present = (repo_root / "CLAUDE.md").exists()

    if agents_present and claude_present:
        form = "dual"
    elif agents_present and not claude_present:
        form = "codex-only"
    elif claude_present and not agents_present:
        form = "cc-only"
    else:
        form = "neither"

    return {
        "form": form,
        "agentsmd_present": agents_present,
        "claudemd_present": claude_present,
    }


# ---------------------------------------------------------------------------
# 4-callable ADR-0014 contract
# ---------------------------------------------------------------------------


def compute_target_state(ctx: Any) -> dict:
    """Return expected target_state by probing repo_root for AGENTS.md + CLAUDE.md.

    Pure filesystem read — no mutation. Output validates against registry schema.
    """
    repo_root = Path(ctx.repo_root)
    return _detect_form(repo_root)


def target_state_predicate(state: Any) -> bool:
    """Return True if *state* satisfies the registry target_state_schema.

    Validates:
    - state is a dict
    - "form" key is present
    - form value is one of the four enum values
    """
    if not isinstance(state, dict):
        return False
    form = state.get("form")
    if form not in _VALID_FORMS:
        return False
    return True


def idempotency_check(ctx: Any) -> dict:
    """Read cached form from repo-shared settings.yml; compare with re-detected form.

    Read-only — does NOT write.

    Returns:
        {
            "present": bool,      # True if cached form == re-detected form
            "current_state": dict  # cached module section (may be {})
        }
    """
    repo_root = Path(ctx.repo_root)
    kwargs = {
        "home": Path(ctx.home),
        "repo_root": repo_root,
        "repo_identity": ctx.repo_identity,
    }

    cached = _ps.get_module_section(_LOCALITY, _MODULE_ID, **kwargs)
    if not cached or "agentsmd_form" not in cached:
        return {"present": False, "current_state": cached}

    detected = _detect_form(repo_root)
    cached_form_block = cached.get("agentsmd_form", {})
    if not isinstance(cached_form_block, dict):
        return {"present": False, "current_state": cached}

    cached_form = cached_form_block.get("form")
    match = (cached_form == detected["form"])
    return {"present": match, "current_state": cached}


def executor(ctx: Any) -> dict:
    """Detect form and persist to repo-shared settings.yml § modules.m7_agent_routing.

    Idempotent:
    - If cached form matches re-detected form → no-op (applied=False).
    - Otherwise → write form to settings.yml (applied=True).

    Returns:
        {
            "applied": bool,
            "message": str,
            "side_effects": list[str]
        }
    """
    repo_root = Path(ctx.repo_root)
    kwargs = {
        "home": Path(ctx.home),
        "repo_root": repo_root,
        "repo_identity": ctx.repo_identity,
    }

    detected = _detect_form(repo_root)

    # Check cached form
    check = idempotency_check(ctx)
    if check["present"]:
        return {
            "applied": False,
            "message": f"agentsmd_form already cached as '{detected['form']}' — no-op",
            "side_effects": [],
        }

    # Persist to repo-shared settings.yml
    _ps.update_module_section(
        _LOCALITY,
        _MODULE_ID,
        {"agentsmd_form": detected},
        **kwargs,
    )

    return {
        "applied": True,
        "message": f"detected agentsmd form: '{detected['form']}'",
        "side_effects": [
            f"wrote modules.{_MODULE_ID}.agentsmd_form to repo-shared settings.yml"
        ],
    }
