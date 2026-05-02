"""ADR-0014 4-callable contract for stage m4.repo.flush-pending-audit.

Stage: M4 | automated | external | both platforms
Purpose: Replay mode=bootstrap-pending rows from jsonl into DB
         (idempotent via UNIQUE event_uuid).

character: automated
locality: external
depends_on: m4.repo.apply-audit-ddl
external_ttl_seconds: 86400

Delegates execution to scripts/audit-flush-pending.sh, which drains
all per-repo audit-local.jsonl files. The executor is a thin wrapper.

jsonl fallback path per ADR-0015 + ADR-0006:
  ~/.board-superpowers/repos/<repo-identity>/audit-local.jsonl

target_state_schema (from registry):
  {pending_replayed: bool, rows_inserted?: int,
   rows_skipped_duplicate?: int, last_run_id?: str,
   last_validated_at?: str}

All subprocess calls are mocked in CI tests.
ctx contract: any object with attributes home, repo_root, repo_identity.
"""

from __future__ import annotations

import datetime
import subprocess
import uuid
from pathlib import Path
from typing import Any

from stages_lib.m4_repo_acquire_dsn import _credentials_path


def _jsonl_path(ctx: Any) -> Path:
    """Per-repo audit-local.jsonl path.

    Per ADR-0015 + path conventions: sibling to credentials.yml under
    ~/.board-superpowers/repos/<repo-identity>/audit-local.jsonl
    """
    return _credentials_path(ctx).parent / "audit-local.jsonl"


def _pending_row_count(jsonl: Path) -> int:
    """Count status=pending rows in a jsonl file without subprocess."""
    if not jsonl.exists():
        return 0
    count = 0
    try:
        for line in jsonl.read_text().splitlines():
            if '"status"' in line and '"pending"' in line:
                count += 1
    except Exception:
        pass
    return count


def _audit_flush_sh_path() -> Path:
    """Resolve scripts/audit-flush-pending.sh relative to this module."""
    return Path(__file__).parent.parent / "audit-flush-pending.sh"


# ---------------------------------------------------------------------------
# 4-callable contract
# ---------------------------------------------------------------------------


def compute_target_state(ctx: Any) -> dict:
    """Return expected flush state.

    If jsonl has no pending rows → already flushed (pending_replayed=True,
    rows_inserted=0).
    If rows exist → pending_replayed=False (needs flush).
    last_validated_at is always fresh.
    """
    jsonl = _jsonl_path(ctx)
    pending = _pending_row_count(jsonl)
    ts: dict = {
        "pending_replayed": pending == 0,
        "rows_inserted": 0,
        "rows_skipped_duplicate": 0,
        "last_validated_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    # Omit last_run_id when not yet set — registry schema type is string
    # (non-nullable); only include when a run has occurred.
    return ts


def target_state_predicate(state: Any) -> bool:
    """Pure: pending_replayed must be True and rows_inserted must be non-negative."""
    if not isinstance(state, dict):
        return False
    pending_replayed = state.get("pending_replayed")
    if pending_replayed is not True:
        return False
    rows_inserted = state.get("rows_inserted", 0)
    if not isinstance(rows_inserted, int) or rows_inserted < 0:
        return False
    return True


def idempotency_check(ctx: Any) -> dict:
    """Read-only probe: jsonl absent or empty → already flushed.

    Returns: {present: bool, current_state: {pending_count: int}}
    present=True means no pending rows (flush is a no-op).
    """
    jsonl = _jsonl_path(ctx)
    pending = _pending_row_count(jsonl)
    return {
        "present": pending == 0,
        "current_state": {"pending_count": pending},
    }


def executor(ctx: Any) -> dict:
    """Automated: delegate to scripts/audit-flush-pending.sh.

    audit-flush-pending.sh scans all per-repo audit-local.jsonl files
    and replays status=pending rows into the DB (idempotent via event_uuid).

    Returns: {applied: bool, message: str, side_effects: list}
    """
    check = idempotency_check(ctx)
    if check["present"]:
        return {
            "applied": False,
            "message": "no pending audit rows to flush — no-op",
            "side_effects": [],
        }

    flush_sh = _audit_flush_sh_path()
    run_id = str(uuid.uuid4())
    try:
        result = subprocess.run(
            ["bash", str(flush_sh)],
            capture_output=True,
            text=True,
            timeout=120,
        )
    except (subprocess.TimeoutExpired, OSError) as exc:
        return {
            "applied": False,
            "message": f"audit-flush-pending.sh subprocess error: {exc}",
            "side_effects": [],
        }

    if result.returncode not in (0, 1):
        # Exit 1 = corrupt rows sent to dead-letter (recoverable warning).
        # Exit 2+ = partial failure. Let 0 and 1 both count as "applied".
        return {
            "applied": False,
            "message": (
                f"audit-flush-pending.sh failed (exit {result.returncode}): "
                f"{result.stderr.strip()}"
            ),
            "side_effects": [],
        }

    return {
        "applied": True,
        "message": "pending audit rows flushed via audit-flush-pending.sh",
        "side_effects": [
            f"invoked audit-flush-pending.sh (run_id={run_id})",
        ],
        "run_id": run_id,
    }
