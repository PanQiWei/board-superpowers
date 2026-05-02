"""ADR-0014 4-callable contract for stage m9.host.register-codex-hooks.

Stage: M9 | automated | host-shared | codex-only
Purpose: Register board-superpowers SessionStart hook into ~/.codex/hooks.json.
         CC auto-discovers hooks/hooks.json; Codex CLI does NOT (ADR-0016).

target_state_schema: {registered: bool, config_toml_path?: str, hook_target?: str}
  config_toml_path = ~/.codex/hooks.json path (registry field name per spec).
  hook_target = absolute path to hooks/session-start.sh.

Merge semantics: user hooks preserved; bsp SessionStart replaced (idempotent);
stale bsp PreToolUse/PostToolUse entries removed (Codex parity gap cleanup).

ctx: home, repo_root, repo_identity (repo_root + repo_identity unused but
     required by lifecycle engine contract).
"""

from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any

_HOOK_NAME = "board-superpowers"
_HOOK_TIMEOUT = 10
_STALE_EVENTS = ("PreToolUse", "PostToolUse")


def _hooks_json_path(ctx: Any) -> Path:
    """Return ~/.codex/hooks.json path derived from ctx.home."""
    return Path(ctx.home) / ".codex" / "hooks.json"


def _resolve_plugin_root() -> Path | None:
    """CLAUDE_PLUGIN_ROOT env first; path-walk fallback (stages_lib→scripts→root)."""
    env_root = os.environ.get("CLAUDE_PLUGIN_ROOT", "")
    if env_root:
        p = Path(env_root)
        if p.is_dir():
            return p

    here = Path(__file__).resolve()
    candidate = here.parent.parent.parent  # stages_lib → scripts → plugin-root
    if (candidate / "hooks" / "session-start.sh").is_file():
        return candidate
    return None


def _hook_script_path() -> str | None:
    """Return absolute path to hooks/session-start.sh, or None if not found."""
    root = _resolve_plugin_root()
    if root is None:
        return None
    hook = root / "hooks" / "session-start.sh"
    if hook.is_file():
        return str(hook)
    return None


def _load_hooks_json(path: Path) -> dict:
    """Load hooks.json; return empty dict on missing or invalid JSON."""
    if not path.is_file():
        return {}
    try:
        with path.open("r", encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except (json.JSONDecodeError, OSError):
        return {}


def _bsp_entry_present(data: dict, hook_script: str) -> bool:
    """Return True iff a board-superpowers SessionStart entry is present and up to date."""
    entries = data.get("hooks", {}).get("SessionStart", [])
    for entry in entries:
        if entry.get("name") == _HOOK_NAME:
            return entry.get("command") == f"bash {hook_script}"
    return False


def _merge_hook(data: dict, hook_script: str) -> dict:
    """Deep-copy data; replace/add bsp SessionStart; remove stale bsp PreToolUse/PostToolUse."""
    import copy
    data = copy.deepcopy(data)
    data.setdefault("hooks", {})
    data["hooks"].setdefault("SessionStart", [])

    data["hooks"]["SessionStart"] = [
        h for h in data["hooks"]["SessionStart"] if h.get("name") != _HOOK_NAME
    ]

    data["hooks"]["SessionStart"].append({
        "type": "command",
        "command": f"bash {hook_script}",
        "timeout": _HOOK_TIMEOUT,
        "name": _HOOK_NAME,
    })

    for stale_event in _STALE_EVENTS:
        if stale_event in data["hooks"]:
            kept = [h for h in data["hooks"][stale_event] if h.get("name") != _HOOK_NAME]
            if kept:
                data["hooks"][stale_event] = kept
            else:
                del data["hooks"][stale_event]

    return data


def compute_target_state(ctx: Any) -> dict:
    """Return {registered, config_toml_path, hook_target} derived from ctx.home + plugin root."""
    hooks_path = _hooks_json_path(ctx)
    hook_script = _hook_script_path()
    return {
        "registered": hook_script is not None,
        "config_toml_path": str(hooks_path),
        "hook_target": hook_script,
    }


def target_state_predicate(state: Any) -> bool:
    """Return True iff state is a dict with registered=True and valid optional fields."""
    if not isinstance(state, dict):
        return False
    if state.get("registered") is not True:
        return False
    config_toml_path = state.get("config_toml_path")
    if config_toml_path is not None and (
        not isinstance(config_toml_path, str) or not config_toml_path
    ):
        return False
    hook_target = state.get("hook_target")
    if hook_target is not None and not isinstance(hook_target, str):
        return False
    return True


def idempotency_check(ctx: Any) -> dict:
    """Read-only: return {present, current_state}. present=True iff bsp SessionStart entry exists."""
    hooks_path = _hooks_json_path(ctx)
    if not hooks_path.is_file():
        return {"present": False, "current_state": {}}

    data = _load_hooks_json(hooks_path)
    if not data:
        return {"present": False, "current_state": {"hooks_json_valid": False}}

    hook_script = _hook_script_path()
    if hook_script is None:
        return {"present": False, "current_state": {"hook_script_resolvable": False}}

    already_registered = _bsp_entry_present(data, hook_script)
    entries = data.get("hooks", {}).get("SessionStart", [])
    bsp_entries = [e for e in entries if e.get("name") == _HOOK_NAME]

    return {
        "present": already_registered,
        "current_state": {
            "hooks_json_path": str(hooks_path),
            "session_start_bsp_entries": len(bsp_entries),
        },
    }


def executor(ctx: Any) -> dict:
    """Merge bsp SessionStart into ~/.codex/hooks.json; return {applied, message, side_effects}."""
    hooks_path = _hooks_json_path(ctx)
    hook_script = _hook_script_path()

    if hook_script is None:
        return {
            "applied": False,
            "message": "hooks/session-start.sh not found; cannot register Codex hook",
            "side_effects": [],
        }

    if idempotency_check(ctx)["present"]:
        return {
            "applied": False,
            "message": f"board-superpowers SessionStart hook already registered in {hooks_path}",
            "side_effects": [],
        }

    existing = _load_hooks_json(hooks_path)
    merged = _merge_hook(existing, hook_script)
    hooks_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_fd, tmp_path = tempfile.mkstemp(
        dir=hooks_path.parent, prefix=".hooks_tmp_", suffix=".json"
    )
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as fh:
            json.dump(merged, fh, indent=2)
        os.replace(tmp_path, str(hooks_path))
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise

    side_effects = [f"wrote {hooks_path}"]
    was_new = not existing
    action = "created" if was_new else "merged into"
    return {
        "applied": True,
        "message": (
            f"{action} {hooks_path} — registered board-superpowers SessionStart hook "
            f"(bash {hook_script})"
        ),
        "side_effects": side_effects,
    }
