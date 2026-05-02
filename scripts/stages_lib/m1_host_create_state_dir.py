"""ADR-0014 4-callable Python contract for stage m1.host.create-state-dir.

Stage identity: M1 | automated | host-shared | both platforms
Purpose: Create `~/.board-superpowers/` (mode 0700) plus `__host__/`
         sentinel subdirectory.

Registry target_state_schema (stages-registry.yml):
  {host_state_dir: str, mode: str (pattern ^[0-7]{4}$), sentinel_subdir?: str}

ctx contract: any object with attributes:
  ctx.home: pathlib.Path  — $HOME (or test override)
  ctx.repo_root: pathlib.Path  — absolute repo root (not used by this stage)
  ctx.repo_identity: str  — owner/repo slug (not used by this stage)

Callers may use ``types.SimpleNamespace(home=..., repo_root=..., repo_identity=...)``
for testing; the lifecycle runtime populates it at execution time.

I/O contract (ADR-0014):
  - compute_target_state: pure, no I/O
  - target_state_predicate: pure, no I/O
  - idempotency_check: read-only filesystem probe
  - executor: creates directory + sets mode (the only callable that mutates)
"""

from __future__ import annotations

import os
import re
import stat
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Internal constants
# ---------------------------------------------------------------------------

_MODE_INT = 0o700
_MODE_STR = "0700"
_SENTINEL = "__host__"
_MODE_PATTERN = re.compile(r"^[0-7]{4}$")


# ---------------------------------------------------------------------------
# 4-callable ADR-0014 contract
# ---------------------------------------------------------------------------


def compute_target_state(ctx: Any) -> dict:
    """Return expected target state for m1.host.create-state-dir.

    Pure — no I/O. Derives paths from ctx.home.

    Returns:
        {
            "host_state_dir": str,    # absolute path to ~/.board-superpowers/
            "mode": "0700",
            "sentinel_subdir": str,  # absolute path to .../__host__/
        }
    """
    host_state_dir = Path(ctx.home) / ".board-superpowers"
    sentinel = host_state_dir / _SENTINEL
    return {
        "host_state_dir": str(host_state_dir),
        "mode": _MODE_STR,
        "sentinel_subdir": str(sentinel),
    }


def target_state_predicate(state: Any) -> bool:
    """Return True if state matches the target_state_schema.

    Validates:
    - state is a dict
    - "host_state_dir" is a non-empty string
    - "mode" is a string matching ^[0-7]{4}$ (4 octal digits)
    - "sentinel_subdir" is optional but must be a string if present
    """
    if not isinstance(state, dict):
        return False
    host_state_dir = state.get("host_state_dir")
    if not isinstance(host_state_dir, str) or not host_state_dir:
        return False
    mode = state.get("mode")
    if not isinstance(mode, str):
        return False
    if not _MODE_PATTERN.match(mode):
        return False
    sentinel = state.get("sentinel_subdir")
    if sentinel is not None and not isinstance(sentinel, str):
        return False
    return True


def idempotency_check(ctx: Any) -> dict:
    """Probe filesystem state for m1.host.create-state-dir.

    Read-only — does NOT write.

    Returns:
        {
            "present": bool,  # True iff dir exists AND mode == 0700
            "current_state": dict,
        }
    "present" is True iff:
    - ~/.board-superpowers/ exists AND has mode 0700
    - ~/.board-superpowers/__host__/ exists
    """
    host_state_dir = Path(ctx.home) / ".board-superpowers"
    sentinel = host_state_dir / _SENTINEL

    if not host_state_dir.is_dir():
        return {
            "present": False,
            "current_state": {"present": False},
        }

    # Check mode
    actual_mode = stat.S_IMODE(os.stat(host_state_dir).st_mode)
    mode_ok = actual_mode == _MODE_INT
    sentinel_ok = sentinel.is_dir()

    present = mode_ok and sentinel_ok
    return {
        "present": present,
        "current_state": {
            "host_state_dir": str(host_state_dir),
            "mode": oct(actual_mode)[2:].zfill(4),
            "sentinel_exists": sentinel_ok,
        },
    }


def executor(ctx: Any) -> dict:
    """Create ~/.board-superpowers/ (mode 0700) + sentinel __host__/.

    Idempotent:
    - Dir absent → create with mode 0700, create sentinel.
    - Dir present, mode correct, sentinel exists → no-op (applied=False).
    - Dir present but mode wrong → chmod, create sentinel if missing.
    - Dir present, sentinel missing → create sentinel only.

    Returns:
        {
            "applied": bool,
            "message": str,
            "side_effects": list[str],
        }
    """
    host_state_dir = Path(ctx.home) / ".board-superpowers"
    sentinel = host_state_dir / _SENTINEL
    side_effects: list[str] = []
    applied = False

    # 1. Ensure base directory exists with correct mode
    if not host_state_dir.is_dir():
        os.makedirs(str(host_state_dir), mode=_MODE_INT, exist_ok=True)
        side_effects.append(f"created {host_state_dir} (mode 0700)")
        applied = True
    else:
        # Check and repair mode
        actual_mode = stat.S_IMODE(os.stat(host_state_dir).st_mode)
        if actual_mode != _MODE_INT:
            os.chmod(str(host_state_dir), _MODE_INT)
            side_effects.append(
                f"repaired mode on {host_state_dir}: "
                f"{oct(actual_mode)} → 0700"
            )
            applied = True

    # 2. Ensure sentinel subdir exists
    if not sentinel.is_dir():
        sentinel.mkdir(mode=0o700, exist_ok=True)
        side_effects.append(f"created sentinel {sentinel}")
        applied = True

    if applied:
        message = "; ".join(side_effects) if side_effects else "created host state dir"
    else:
        message = "host state dir already exists with correct mode and sentinel"

    return {
        "applied": applied,
        "message": message,
        "side_effects": side_effects,
    }
