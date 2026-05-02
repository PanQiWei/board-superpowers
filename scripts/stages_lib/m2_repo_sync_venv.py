"""ADR-0014 4-callable contract for stage m2.repo.sync-venv.

Stage: M2 | automated | repo-clone | both platforms
Purpose: Run `uv sync --project <repo>/.board-superpowers/` to materialize
         <repo>/.board-superpowers/.venv/ from the committed uv.lock.

Registry target_state_schema (stages-registry.yml):
  {venv_path: str, uv_lock_hash: str}

Idempotency: .venv/bin/python3 exists AND stored uv_lock_hash matches
  the current uv.lock sha256 → present=True (no re-sync needed).

Persisted state: uv_lock_hash + venv_path written to
  repo-clone settings.local.yml § modules.m2_python_runtime
  after a successful sync.

ctx contract: any object with attributes:
  ctx.home: pathlib.Path
  ctx.repo_root: pathlib.Path
  ctx.repo_identity: str
"""

from __future__ import annotations

import hashlib
import subprocess
from pathlib import Path
from typing import Any

from stages_lib._partitioned_settings import get_module_section, update_module_section

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_MODULE_ID = "m2_python_runtime"
_LOCK_FILENAME = "uv.lock"


def _bsp_dir(ctx: Any) -> Path:
    return Path(ctx.repo_root) / ".board-superpowers"


def _lock_path(ctx: Any) -> Path:
    return _bsp_dir(ctx) / _LOCK_FILENAME


def _venv_path(ctx: Any) -> Path:
    return _bsp_dir(ctx) / ".venv"


def _python_bin(ctx: Any) -> Path:
    return _venv_path(ctx) / "bin" / "python3"


def _sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ---------------------------------------------------------------------------
# 4-callable ADR-0014 contract
# ---------------------------------------------------------------------------


def compute_target_state(ctx: Any) -> dict:
    """Return expected target state derived from ctx.

    Reads uv.lock to compute hash. Not purely functional (reads file) but
    does NOT write. Returns:
        {venv_path: str, uv_lock_hash: str}
    python_version omitted (only known after sync runs).
    """
    lock = _lock_path(ctx)
    uv_lock_hash = _sha256_of(lock) if lock.exists() else "0" * 64
    return {
        "venv_path": str(_venv_path(ctx)),
        "uv_lock_hash": uv_lock_hash,
    }


def target_state_predicate(state: Any) -> bool:
    """Return True if state satisfies target_state_schema.

    Validates:
    - state is a dict
    - venv_path is a non-empty string
    - uv_lock_hash is a 64-char hex string (SHA-256)
    """
    if not isinstance(state, dict):
        return False
    venv_path = state.get("venv_path")
    if not isinstance(venv_path, str) or not venv_path:
        return False
    uv_lock_hash = state.get("uv_lock_hash")
    if not isinstance(uv_lock_hash, str):
        return False
    if len(uv_lock_hash) != 64:
        return False
    try:
        int(uv_lock_hash, 16)
    except ValueError:
        return False
    return True


def idempotency_check(ctx: Any) -> dict:
    """Read-only probe: venv/bin/python3 exists AND stored hash matches current uv.lock.

    Returns:
        {present: bool, current_state: dict}
    present=True iff both conditions hold.
    """
    python_bin = _python_bin(ctx)
    lock = _lock_path(ctx)

    if not python_bin.exists():
        return {
            "present": False,
            "current_state": {"python_bin_exists": False},
        }

    # Compare stored hash vs current lock
    stored = get_module_section(
        "repo-clone", _MODULE_ID,
        home=Path(ctx.home), repo_root=Path(ctx.repo_root), repo_identity=ctx.repo_identity,
    )
    stored_hash = stored.get("uv_lock_hash", "")
    current_hash = _sha256_of(lock) if lock.exists() else ""
    hash_matches = bool(stored_hash) and stored_hash == current_hash

    return {
        "present": hash_matches,
        "current_state": {
            "python_bin_exists": True,
            "stored_hash": stored_hash,
            "current_hash": current_hash,
            "hash_matches": hash_matches,
        },
    }


def executor(ctx: Any) -> dict:
    """Run `uv sync --project <bsp_dir>/` to create/update .venv.

    Idempotent: no-op if venv present and uv.lock unchanged.
    Persists uv_lock_hash + venv_path to repo-clone settings after sync.

    Returns:
        {applied: bool, message: str, side_effects: list[str]}
    """
    if idempotency_check(ctx)["present"]:
        return {
            "applied": False,
            "message": "venv already up-to-date (uv.lock unchanged)",
            "side_effects": [],
        }

    bsp_dir = _bsp_dir(ctx)
    venv = _venv_path(ctx)

    try:
        subprocess.run(
            ["uv", "sync", "--project", str(bsp_dir)],
            check=True,
            capture_output=True,
        )
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.decode("utf-8", errors="replace") if exc.stderr else ""
        return {
            "applied": False,
            "message": f"uv sync failed: {stderr.strip() or str(exc)}",
            "side_effects": [],
        }
    except (FileNotFoundError, OSError) as exc:
        return {
            "applied": False,
            "message": f"uv not found or not executable: {exc}",
            "side_effects": [],
        }

    # Persist state to repo-clone settings
    lock = _lock_path(ctx)
    uv_lock_hash = _sha256_of(lock) if lock.exists() else "0" * 64
    update_module_section(
        "repo-clone", _MODULE_ID,
        {
            "venv_path": str(venv),
            "uv_lock_hash": uv_lock_hash,
            "schema_version": 1,
        },
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )

    return {
        "applied": True,
        "message": f"uv sync complete; venv at {venv}",
        "side_effects": [f"created/updated {venv}", f"persisted uv_lock_hash to repo-clone settings"],
    }
