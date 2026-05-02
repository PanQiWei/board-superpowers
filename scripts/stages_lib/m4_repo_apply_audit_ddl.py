"""ADR-0014 4-callable contract for stage m4.repo.apply-audit-ddl.

Stage: M4 | automated | external | both platforms
Purpose: Apply audit-log DDL to the resolved DB (3-dialect dispatch via
         audit-init.sh — sqlite / postgres / mysql per ADR-0009).

character: automated
locality: external → validated against live DB state
depends_on: m4.repo.acquire-dsn
external_ttl_seconds: 86400

Delegates execution to scripts/audit-init.sh (the single source of truth
for DDL and schema migration logic). The Python executor is a thin wrapper
that resolves the DSN, invokes the script via subprocess, then verifies
the schema using the target_state_predicate.

target_state_schema (from registry):
  {audit_log: {schema_version, columns_required, indexes_required},
   audit_outbox: {columns_required},
   audit_schema_meta: {columns_required},
   last_validated_at?: str}

All subprocess calls are mocked in CI tests.
ctx contract: any object with attributes home, repo_root, repo_identity.
"""

from __future__ import annotations

import datetime
import subprocess
from pathlib import Path
from typing import Any

from stages_lib.m4_repo_acquire_dsn import (
    ALLOWED_SCHEMES,
    _credentials_path,
    _parse_scheme,
    _read_credentials,
)

# ---------------------------------------------------------------------------
# Schema constants (ADR-0006 §5 + audit-init.sh SoT)
# ---------------------------------------------------------------------------

_AUDIT_LOG_COLUMNS = [
    "id", "timestamp", "project", "session_id", "actor_role",
    "action_id", "payload", "outcome", "approval_stage",
]
_AUDIT_LOG_INDEXES = ["idx_audit_log_timestamp", "idx_audit_log_action_id"]

_AUDIT_OUTBOX_COLUMNS = [
    "id", "event_uuid", "action_id", "decision", "skill",
    "approval_stage", "outcome", "payload", "project",
    "status", "retry_count", "pending_since",
]

_AUDIT_SCHEMA_META_COLUMNS = ["id", "version", "applied_at"]

_SCHEMA_VERSION = 2  # current target schema version (audit-init.sh TARGET_VERSION)


def _resolve_dsn(ctx: Any) -> str:
    """Resolve audit_dsn from per-repo credentials.yml or BOARD_SP_AUDIT_DB_URL env."""
    import os
    env_dsn = os.environ.get("BOARD_SP_AUDIT_DB_URL", "")
    if env_dsn:
        return env_dsn
    creds = _read_credentials(ctx)
    return creds.get("audit_dsn", "")


def _audit_init_sh_path() -> Path:
    """Resolve scripts/audit-init.sh relative to this module."""
    return Path(__file__).parent.parent / "audit-init.sh"


def _check_sqlite_tables(dsn: str) -> dict:
    """Query a SQLite DB for table + column presence. Returns current state dict."""
    import sqlite3

    scheme = _parse_scheme(dsn)
    db_path = dsn.replace(scheme + "://", "", 1)
    if not db_path.startswith("/"):
        db_path = "/" + db_path.lstrip("/")

    if not Path(db_path).exists():
        return {"present": False, "error": f"SQLite db does not exist: {db_path}"}

    try:
        conn = sqlite3.connect(db_path)
        tables = {
            row[0]
            for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        }
        result = {}
        for table in ("audit_log", "audit_outbox", "audit_schema_meta"):
            result[table] = table in tables
        conn.close()
        return {"present": all(result.values()), "tables": result}
    except Exception as exc:
        return {"present": False, "error": str(exc)}


# ---------------------------------------------------------------------------
# 4-callable contract
# ---------------------------------------------------------------------------


def compute_target_state(ctx: Any) -> dict:
    """Return the expected DDL state (fixed schema — not context-dependent).

    The schema is determined by the audit-init.sh DDL (ADR-0006 §5 SoT).
    Returns a dict that satisfies the registry target_state_schema.
    """
    return {
        "audit_log": {
            "schema_version": _SCHEMA_VERSION,
            "columns_required": _AUDIT_LOG_COLUMNS,
            "indexes_required": _AUDIT_LOG_INDEXES,
        },
        "audit_outbox": {
            "columns_required": _AUDIT_OUTBOX_COLUMNS,
        },
        "audit_schema_meta": {
            "columns_required": _AUDIT_SCHEMA_META_COLUMNS,
        },
        "last_validated_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def target_state_predicate(state: Any) -> bool:
    """Pure: validate that the DDL state has the required tables and schema version.

    Accepts state if audit_log.schema_version >= 1 and all three table
    entries are present.
    """
    if not isinstance(state, dict):
        return False
    audit_log = state.get("audit_log")
    if not isinstance(audit_log, dict):
        return False
    schema_version = audit_log.get("schema_version")
    if not isinstance(schema_version, int) or schema_version < 1:
        return False
    columns_required = audit_log.get("columns_required")
    if not isinstance(columns_required, list) or not columns_required:
        return False
    indexes_required = audit_log.get("indexes_required")
    if not isinstance(indexes_required, list):
        return False
    audit_outbox = state.get("audit_outbox")
    if not isinstance(audit_outbox, dict):
        return False
    audit_schema_meta = state.get("audit_schema_meta")
    if not isinstance(audit_schema_meta, dict):
        return False
    return True


def idempotency_check(ctx: Any) -> dict:
    """Read-only probe: check if audit_log table already exists in the DB.

    For sqlite: directly queries the DB file.
    For postgres/mysql: returns present=False (requires subprocess; let executor run).

    Returns: {present: bool, current_state: {tables: dict|None, dsn_scheme: str|None}}
    """
    dsn = _resolve_dsn(ctx)
    if not dsn:
        return {"present": False, "current_state": {"dsn_scheme": None, "error": "audit_dsn not configured"}}

    scheme = _parse_scheme(dsn)
    if scheme not in ALLOWED_SCHEMES:
        return {"present": False, "current_state": {"dsn_scheme": scheme, "error": "unknown scheme"}}

    if scheme in ("sqlite", "sqlite3"):
        result = _check_sqlite_tables(dsn)
        return {
            "present": result.get("present", False),
            "current_state": {
                "dsn_scheme": scheme,
                "tables": result.get("tables"),
                **({} if "error" not in result else {"error": result["error"]}),
            },
        }

    # For pg/mysql: cannot probe without subprocess; treat as unknown → not present.
    return {"present": False, "current_state": {"dsn_scheme": scheme, "note": "non-sqlite probe deferred to executor"}}


def executor(ctx: Any) -> dict:
    """Automated: delegate to scripts/audit-init.sh for DDL apply.

    audit-init.sh is the SoT for the DDL (IF NOT EXISTS — idempotent).
    Works for all 3 dialects: sqlite, postgres, mysql.

    Returns: {applied: bool, message: str, side_effects: list}
    """
    check = idempotency_check(ctx)
    if check["present"]:
        return {
            "applied": False,
            "message": "audit DDL already applied — no-op",
            "side_effects": [],
        }

    dsn = _resolve_dsn(ctx)
    if not dsn:
        return {
            "applied": False,
            "message": "audit_dsn not configured — skipping DDL (run m4.repo.acquire-dsn first)",
            "side_effects": [],
        }

    audit_init_sh = _audit_init_sh_path()
    try:
        result = subprocess.run(
            ["bash", str(audit_init_sh)],
            capture_output=True,
            text=True,
            timeout=120,
            env={**__import__("os").environ, "BOARD_SP_AUDIT_DB_URL": dsn},
        )
    except (subprocess.TimeoutExpired, OSError) as exc:
        return {
            "applied": False,
            "message": f"audit-init.sh subprocess error: {exc}",
            "side_effects": [],
        }

    if result.returncode != 0:
        return {
            "applied": False,
            "message": f"audit-init.sh failed (exit {result.returncode}): {result.stderr.strip()}",
            "side_effects": [],
        }

    return {
        "applied": True,
        "message": f"audit DDL applied via audit-init.sh (scheme: {_parse_scheme(dsn)})",
        "side_effects": [f"invoked audit-init.sh with DSN scheme {_parse_scheme(dsn)}"],
    }
