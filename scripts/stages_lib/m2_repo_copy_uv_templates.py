"""ADR-0014 4-callable contract for stage m2.repo.copy-uv-templates.

Stage: M2 | automated | repo-git | both platforms
Purpose: Copy plugin's pyproject.toml + uv.lock from
         <plugin>/scripts/templates/ into <repo>/.board-superpowers/.

Templates source: ${CLAUDE_PLUGIN_ROOT}/scripts/templates/ resolved via
  Path(__file__).parent.parent / 'templates' (same convention as m1_host_write_manifest.py
  uses .parent.parent.parent for plugin.json). Falls back to ctx._plugin_templates_dir
  for test injection.

Registry target_state_schema (stages-registry.yml):
  {pyproject_path: str, uv_lock_path: str, pyproject_sha256?: str, uv_lock_sha256?: str}

Idempotency: files present AND content byte-equal to templates → present=True.

ctx contract: any object with attributes:
  ctx.home: pathlib.Path
  ctx.repo_root: pathlib.Path
  ctx.repo_identity: str
  ctx._plugin_templates_dir: pathlib.Path  (optional, for tests only)
"""

from __future__ import annotations

import hashlib
import shutil
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_TEMPLATE_FILES = ("pyproject.toml", "uv.lock")


def _templates_dir(ctx: Any) -> Path:
    """Resolve plugin templates directory.

    Test injection: if ctx has _plugin_templates_dir, use it.
    Production: scripts/templates/ sibling of this file's parent.
    """
    override = getattr(ctx, "_plugin_templates_dir", None)
    if override is not None:
        return Path(override)
    # Production: <plugin_root>/scripts/templates/
    # __file__ is <plugin_root>/scripts/stages_lib/m2_repo_copy_uv_templates.py
    return Path(__file__).parent.parent / "templates"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _dest_dir(ctx: Any) -> Path:
    return Path(ctx.repo_root) / ".board-superpowers"


# ---------------------------------------------------------------------------
# 4-callable ADR-0014 contract
# ---------------------------------------------------------------------------


def compute_target_state(ctx: Any) -> dict:
    """Return expected target state (paths + sha256 of templates).

    Pure relative to filesystem: reads template content to compute sha256
    but does NOT write. Returns:
        {pyproject_path: str, uv_lock_path: str,
         pyproject_sha256?: str, uv_lock_sha256?: str}
    """
    dest = _dest_dir(ctx)
    state: dict = {
        "pyproject_path": str(dest / "pyproject.toml"),
        "uv_lock_path": str(dest / "uv.lock"),
    }
    # Optionally include sha256 of templates for content-aware idempotency
    tpl_dir = _templates_dir(ctx)
    for fname, key in (("pyproject.toml", "pyproject_sha256"), ("uv.lock", "uv_lock_sha256")):
        src = tpl_dir / fname
        if src.exists():
            state[key] = _sha256(src)
    return state


def target_state_predicate(state: Any) -> bool:
    """Return True if state satisfies target_state_schema.

    Validates:
    - state is a dict
    - pyproject_path is a non-empty string
    - uv_lock_path is a non-empty string
    - pyproject_sha256, uv_lock_sha256 optional but must be str if present
    """
    if not isinstance(state, dict):
        return False
    for key in ("pyproject_path", "uv_lock_path"):
        val = state.get(key)
        if not isinstance(val, str) or not val:
            return False
    for key in ("pyproject_sha256", "uv_lock_sha256"):
        val = state.get(key)
        if val is not None and not isinstance(val, str):
            return False
    return True


def idempotency_check(ctx: Any) -> dict:
    """Read-only probe: check whether both template files are already in place.

    Returns:
        {present: bool, current_state: dict}
    present=True iff BOTH files exist AND their content matches the
    plugin templates byte-for-byte.
    """
    dest = _dest_dir(ctx)
    tpl_dir = _templates_dir(ctx)
    current: dict = {}

    all_present_and_matching = True
    for fname in _TEMPLATE_FILES:
        dst = dest / fname
        src = tpl_dir / fname
        if not dst.exists():
            all_present_and_matching = False
            current[fname] = "absent"
        elif not src.exists():
            # Template missing in plugin — treat as not-applicable drift
            all_present_and_matching = False
            current[fname] = "template-missing"
        elif dst.read_bytes() != src.read_bytes():
            all_present_and_matching = False
            current[fname] = "content-drifted"
        else:
            current[fname] = "present-matching"

    return {
        "present": all_present_and_matching,
        "current_state": current,
    }


def executor(ctx: Any) -> dict:
    """Copy pyproject.toml + uv.lock from plugin templates to <repo>/.board-superpowers/.

    Idempotent: no-op if both files already match the templates.
    Creates <repo>/.board-superpowers/ if it does not exist.

    Returns:
        {applied: bool, message: str, side_effects: list[str]}
    """
    if idempotency_check(ctx)["present"]:
        return {
            "applied": False,
            "message": "uv templates already present and up-to-date",
            "side_effects": [],
        }

    dest = _dest_dir(ctx)
    tpl_dir = _templates_dir(ctx)
    dest.mkdir(parents=True, exist_ok=True)

    side_effects: list[str] = []
    for fname in _TEMPLATE_FILES:
        src = tpl_dir / fname
        dst = dest / fname
        shutil.copy2(str(src), str(dst))
        side_effects.append(f"copied {src.name} → {dst}")

    return {
        "applied": True,
        "message": f"copied {len(_TEMPLATE_FILES)} uv template(s) to {dest}",
        "side_effects": side_effects,
    }
