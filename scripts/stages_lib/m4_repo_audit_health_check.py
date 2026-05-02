"""ADR-0014 4-callable contract for stage m4.repo.audit-health-check.

Stage: M4 | automated | repo-shared | both platforms
Purpose: Print stderr summary of audit-row landing count vs jsonl pending count.
         Records that the health summary was emitted.

character: automated
locality: repo-shared → health state persisted to
          ~/.board-superpowers/repos/<repo-identity>/settings.yml
          § modules.m4_audit.last_health
depends_on: m4.repo.flush-pending-audit
external_ttl_seconds: 86400 (from registry; stage is repo-shared)

The executor emits a summary to stderr and persists a lightweight health
snapshot to repo-shared settings.yml (not to credentials.yml — health
data is not a secret).

target_state_schema (from registry):
  {health_summary_emitted: bool, db_row_count?: int,
   jsonl_pending_count?: int, last_validated_at?: str}

ctx contract: any object with attributes home, repo_root, repo_identity.
"""

from __future__ import annotations

import datetime
import sqlite3
import sys
from pathlib import Path
from typing import Any

from stages_lib._partitioned_settings import (
    get_module_section,
    update_module_section,
)
from stages_lib.m4_repo_acquire_dsn import (
    ALLOWED_SCHEMES,
    _parse_scheme,
    _read_credentials,
)
from stages_lib.m4_repo_flush_pending_audit import _jsonl_path, _pending_row_count

_MODULE_ID = "m4_audit"
_HEALTH_FIELD = "last_health"


def _resolve_dsn(ctx: Any) -> str:
    """Resolve audit_dsn from per-repo credentials.yml or env override."""
    import os

    env_dsn = os.environ.get("BOARD_SP_AUDIT_DB_URL", "")
    if env_dsn:
        return env_dsn
    creds = _read_credentials(ctx)
    return creds.get("audit_dsn", "")


def _count_db_rows_sqlite(dsn: str) -> int:
    """Count rows in audit_log for a sqlite DSN. Returns 0 on any error."""
    scheme = _parse_scheme(dsn)
    db_path = dsn.replace(scheme + "://", "", 1)
    if not db_path.startswith("/"):
        db_path = "/" + db_path.lstrip("/")
    if not Path(db_path).exists():
        return 0
    try:
        conn = sqlite3.connect(db_path)
        row = conn.execute("SELECT COUNT(*) FROM audit_log").fetchone()
        conn.close()
        return int(row[0]) if row else 0
    except Exception:
        return 0


def _load_last_health(ctx: Any) -> dict:
    """Read last health snapshot from repo-shared settings.yml."""
    section = get_module_section(
        "repo-shared",
        _MODULE_ID,
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )
    return section.get(_HEALTH_FIELD) or {}


def _save_health_snapshot(ctx: Any, snapshot: dict) -> None:
    """Persist health snapshot to repo-shared settings.yml § modules.m4_audit."""
    section = get_module_section(
        "repo-shared",
        _MODULE_ID,
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )
    section[_HEALTH_FIELD] = snapshot
    update_module_section(
        "repo-shared",
        _MODULE_ID,
        section,
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )


# ---------------------------------------------------------------------------
# 4-callable contract
# ---------------------------------------------------------------------------


def compute_target_state(ctx: Any) -> dict:
    """Return expected health state: health_summary_emitted=True.

    Probes the DB for row count (sqlite only — no subprocess for pg/mysql)
    and the jsonl for pending count.
    """
    dsn = _resolve_dsn(ctx)
    jsonl = _jsonl_path(ctx)
    pending = _pending_row_count(jsonl)

    db_row_count = 0
    if dsn:
        scheme = _parse_scheme(dsn)
        if scheme in ("sqlite", "sqlite3"):
            db_row_count = _count_db_rows_sqlite(dsn)

    return {
        "health_summary_emitted": True,
        "db_row_count": db_row_count,
        "jsonl_pending_count": pending,
        "last_validated_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def target_state_predicate(state: Any) -> bool:
    """Pure: health_summary_emitted must be True; counts non-negative."""
    if not isinstance(state, dict):
        return False
    if state.get("health_summary_emitted") is not True:
        return False
    db_count = state.get("db_row_count", 0)
    if not isinstance(db_count, int) or db_count < 0:
        return False
    jsonl_count = state.get("jsonl_pending_count", 0)
    if not isinstance(jsonl_count, int) or jsonl_count < 0:
        return False
    return True


def idempotency_check(ctx: Any) -> dict:
    """Read-only probe: check if a recent health check was persisted.

    Returns: {present: bool, current_state: {last_validated_at: str|None}}
    present=True means a health snapshot was already stored (executor no-ops
    within the external_ttl_seconds window).
    """
    snapshot = _load_last_health(ctx)
    if not snapshot or not snapshot.get("health_summary_emitted"):
        return {"present": False, "current_state": {"last_validated_at": None}}
    return {
        "present": True,
        "current_state": {"last_validated_at": snapshot.get("last_validated_at")},
    }


def executor(ctx: Any) -> dict:
    """Automated: emit stderr health summary + persist snapshot.

    Collects: DB row count (sqlite probe; 0 for pg/mysql without live DB),
    jsonl pending count. Emits a one-line summary to stderr (per registry
    description: "Print stderr summary"). Persists to repo-shared settings.yml.

    Returns: {applied: bool, message: str, side_effects: list}
    """
    check = idempotency_check(ctx)
    if check["present"]:
        return {
            "applied": False,
            "message": (
                "health check already recorded "
                f"(last_validated_at={check['current_state']['last_validated_at']}) — no-op"
            ),
            "side_effects": [],
        }

    dsn = _resolve_dsn(ctx)
    jsonl = _jsonl_path(ctx)
    pending = _pending_row_count(jsonl)

    db_row_count = 0
    scheme = ""
    if dsn:
        scheme = _parse_scheme(dsn)
        if scheme in ("sqlite", "sqlite3"):
            db_row_count = _count_db_rows_sqlite(dsn)

    now = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    snapshot = {
        "health_summary_emitted": True,
        "db_row_count": db_row_count,
        "jsonl_pending_count": pending,
        "last_validated_at": now,
    }

    # Emit to stderr per registry description.
    sys.stderr.write(
        f"[board-superpowers] audit health: db_rows={db_row_count} "
        f"jsonl_pending={pending} "
        f"scheme={scheme or 'unconfigured'} "
        f"at={now}\n"
    )

    _save_health_snapshot(ctx, snapshot)

    return {
        "applied": True,
        "message": (
            f"audit health check recorded: db_rows={db_row_count}, "
            f"jsonl_pending={pending}"
        ),
        "side_effects": [
            "emitted health summary to stderr",
            "persisted health snapshot to repo-shared settings.yml",
        ],
    }
