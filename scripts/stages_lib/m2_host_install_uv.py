"""ADR-0014 4-callable contract for stage m2.host.install-uv.

Stage: M2 | automated | host-shared | both platforms
Purpose: Detect whether `uv` is installed host-wide. Surface install
         instructions if absent. MUST NOT auto-install per ADR-0006
         host-action boundary.

Registry target_state_schema (stages-registry.yml):
  {uv_present: bool, uv_version: str|null, uv_path?: str}

ADR-0006 host-action boundary:
  Executor MUST NOT run any install script (brew install uv, curl | sh, etc.).
  When uv is absent, executor returns applied=False with a human-readable
  install instruction in the message field — the lifecycle engine surfaces
  this as a blocker for the architect.

ctx contract: any object with attributes:
  ctx.home: pathlib.Path
  ctx.repo_root: pathlib.Path
  ctx.repo_identity: str
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path
from typing import Any

from stages_lib._partitioned_settings import update_module_section

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_VERSION_RE = re.compile(r"uv\s+([0-9]+\.[0-9]+\.[0-9]+[^\s]*)")
_INSTALL_INSTRUCTION = (
    "uv not installed; please install manually: "
    "brew install uv (macOS) "
    "or curl -LsSf https://astral.sh/uv/install.sh | sh"
)


def _detect_uv() -> tuple[bool, str | None, str | None]:
    """Return (present, version_str, abs_path) by probing subprocess.

    Shells out to `uv --version` and `which uv` (or `uv` directly).
    No exception is raised — returns (False, None, None) on any failure.
    """
    try:
        result = subprocess.run(
            ["uv", "--version"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        output = result.stdout.strip()
        m = _VERSION_RE.search(output)
        version = m.group(1) if m else (output.split()[-1] if output else None)
    except (FileNotFoundError, OSError, subprocess.TimeoutExpired):
        return False, None, None

    # Resolve absolute path
    uv_path: str | None = None
    try:
        which_result = subprocess.run(
            ["which", "uv"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        candidate = which_result.stdout.strip()
        if candidate:
            uv_path = candidate
    except (FileNotFoundError, OSError, subprocess.TimeoutExpired):
        uv_path = None

    return True, version, uv_path


# ---------------------------------------------------------------------------
# 4-callable ADR-0014 contract
# ---------------------------------------------------------------------------


def compute_target_state(ctx: Any) -> dict:
    """Return expected target state by probing for uv at runtime.

    Not purely functional — shells out to detect uv. Returns:
        {uv_present: bool, uv_version: str|null, uv_path?: str}
    """
    present, version, uv_path = _detect_uv()
    state: dict = {
        "uv_present": present,
        "uv_version": version,
    }
    if uv_path is not None:
        state["uv_path"] = uv_path
    return state


def target_state_predicate(state: Any) -> bool:
    """Return True if state represents a valid, installed uv.

    Validates:
    - state is a dict
    - uv_present is True (uv must be installed for the stage to be satisfied)
    - uv_version is a non-empty string
    - uv_path, if present, is a string
    """
    if not isinstance(state, dict):
        return False
    uv_present = state.get("uv_present")
    if uv_present is not True:
        return False
    uv_version = state.get("uv_version")
    if not isinstance(uv_version, str) or not uv_version:
        return False
    uv_path = state.get("uv_path")
    if uv_path is not None and not isinstance(uv_path, str):
        return False
    return True


def idempotency_check(ctx: Any) -> dict:
    """Read-only probe: detect uv and return present/current_state.

    Returns:
        {present: bool, current_state: dict}
    present=True iff uv is installed and detectable.
    """
    present, version, uv_path = _detect_uv()
    current_state: dict = {
        "uv_present": present,
        "uv_version": version,
    }
    if uv_path:
        current_state["uv_path"] = uv_path
    return {
        "present": present and bool(version),
        "current_state": current_state,
    }


def executor(ctx: Any) -> dict:
    """Detect uv; persist to host-shared settings if found.

    ADR-0006 host-action boundary:
    - If uv present: persist uv_version + uv_path to host-shared settings.
    - If uv absent: return applied=False with install instruction.
      MUST NOT run any install script.

    Returns:
        {applied: bool, message: str, side_effects: list[str]}
    """
    present, version, uv_path = _detect_uv()

    if not present or not version:
        return {
            "applied": False,
            "message": _INSTALL_INSTRUCTION,
            "side_effects": [],
        }

    # Persist uv_version to host-shared settings.yml § modules.m2_python_runtime
    update_module_section(
        "host-shared",
        "m2_python_runtime",
        {
            "uv_version": version,
            "uv_path": uv_path or "",
            "schema_version": 1,
        },
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )

    side_effects = [f"persisted uv_version={version} to host-shared settings.yml"]
    return {
        "applied": True,
        "message": f"uv {version} detected at {uv_path or 'PATH'}; recorded in host-shared settings.yml",
        "side_effects": side_effects,
    }
