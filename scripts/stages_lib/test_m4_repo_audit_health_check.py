"""Tests for stages_lib.m4_repo_audit_health_check.

Stage: M4 | automated | repo-shared | both platforms
TDD: tests against the ADR-0014 4-callable contract.
Run: cd scripts && python3 -m pytest stages_lib/ -v

Key behaviors verified:
- 4-callable contract: all four callables present
- apply_choice NOT present (automated stage)
- compute_target_state: health_summary_emitted=True; counts non-negative
- target_state_predicate: accepts valid health state; rejects missing/invalid
- idempotency_check: no prior snapshot → not present; snapshot present → present
- executor:
  - no-op when health already recorded
  - emits stderr summary
  - persists snapshot to repo-shared settings.yml
  - counts sqlite rows directly (no subprocess)
  - counts jsonl pending rows
- health snapshot NOT in credentials.yml (not a secret)
- health snapshot in repo-shared settings.yml § modules.m4_audit.last_health
- Round-trip: compute_target_state validates against registry target_state_schema
"""

from __future__ import annotations

import json
import sqlite3
import sys
from io import StringIO
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml

from stages_lib.m4_repo_audit_health_check import (
    _count_db_rows_sqlite,
    _load_last_health,
    compute_target_state,
    executor,
    idempotency_check,
    target_state_predicate,
)
from stages_lib.m4_repo_acquire_dsn import apply_choice as acquire_apply_choice
from stages_lib.m4_repo_flush_pending_audit import _jsonl_path
from stages_lib._partitioned_settings import get_module_section


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def ctx(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    repo = tmp_path / "repo"
    repo.mkdir()
    return SimpleNamespace(
        home=home,
        repo_root=repo,
        repo_identity="test/repo",
    )


@pytest.fixture
def ctx_with_sqlite_db(ctx, tmp_path):
    """ctx with sqlite DSN + real DB with audit_log table."""
    db_path = tmp_path / "audit.db"
    dsn = f"sqlite:////{db_path}"
    acquire_apply_choice(ctx, dsn)
    conn = sqlite3.connect(str(db_path))
    conn.execute(
        "CREATE TABLE audit_log "
        "(id INTEGER PRIMARY KEY, timestamp TEXT, project TEXT, "
        "session_id TEXT, actor_role TEXT, action_id INTEGER, "
        "payload TEXT, outcome TEXT, approval_stage TEXT)"
    )
    conn.commit()
    conn.close()
    return ctx, dsn, db_path


def _pending_row(event_uuid: str) -> dict:
    return {"event_uuid": event_uuid, "status": "pending", "action_id": 200}


# ---------------------------------------------------------------------------
# Module-level callable contract
# ---------------------------------------------------------------------------


def test_four_callables_present():
    import stages_lib.m4_repo_audit_health_check as m
    for name in ["compute_target_state", "target_state_predicate", "idempotency_check", "executor"]:
        assert callable(getattr(m, name, None)), f"{name} missing or not callable"


def test_apply_choice_absent():
    """Automated stage — no 5th callable."""
    import stages_lib.m4_repo_audit_health_check as m
    assert not callable(getattr(m, "apply_choice", None))


# ---------------------------------------------------------------------------
# compute_target_state
# ---------------------------------------------------------------------------


def test_compute_target_state_returns_dict(ctx):
    ts = compute_target_state(ctx)
    assert isinstance(ts, dict)


def test_compute_target_state_health_summary_emitted_true(ctx):
    ts = compute_target_state(ctx)
    assert ts["health_summary_emitted"] is True


def test_compute_target_state_counts_non_negative(ctx):
    ts = compute_target_state(ctx)
    assert ts["db_row_count"] >= 0
    assert ts["jsonl_pending_count"] >= 0


def test_compute_target_state_no_db_counts_zero(ctx):
    ts = compute_target_state(ctx)
    assert ts["db_row_count"] == 0
    assert ts["jsonl_pending_count"] == 0


def test_compute_target_state_counts_sqlite_rows(ctx_with_sqlite_db, tmp_path):
    ctx, dsn, db_path = ctx_with_sqlite_db
    # Insert 3 rows
    conn = sqlite3.connect(str(db_path))
    for i in range(3):
        conn.execute(
            "INSERT INTO audit_log (timestamp, project, session_id, actor_role, "
            "action_id, payload, outcome, approval_stage) "
            "VALUES ('2026-01-01', 'p', 's', 'producer', 1, '{}', 'success', 'auto')"
        )
    conn.commit()
    conn.close()
    ts = compute_target_state(ctx)
    assert ts["db_row_count"] == 3


def test_compute_target_state_counts_jsonl_pending(ctx):
    jp = _jsonl_path(ctx)
    jp.parent.mkdir(parents=True, exist_ok=True)
    with jp.open("w") as f:
        for i in range(2):
            f.write(json.dumps(_pending_row(f"u{i}")) + "\n")
    ts = compute_target_state(ctx)
    assert ts["jsonl_pending_count"] == 2


# ---------------------------------------------------------------------------
# target_state_predicate
# ---------------------------------------------------------------------------


def test_predicate_valid_state():
    state = {
        "health_summary_emitted": True,
        "db_row_count": 10,
        "jsonl_pending_count": 0,
    }
    assert target_state_predicate(state) is True


def test_predicate_valid_minimal():
    assert target_state_predicate({"health_summary_emitted": True}) is True


def test_predicate_invalid_not_emitted():
    assert target_state_predicate({"health_summary_emitted": False}) is False


def test_predicate_invalid_missing():
    assert target_state_predicate({}) is False


def test_predicate_invalid_negative_db_count():
    assert target_state_predicate({"health_summary_emitted": True, "db_row_count": -1, "jsonl_pending_count": 0}) is False


def test_predicate_invalid_negative_jsonl_count():
    assert target_state_predicate({"health_summary_emitted": True, "db_row_count": 0, "jsonl_pending_count": -1}) is False


def test_predicate_invalid_not_dict():
    assert target_state_predicate(True) is False
    assert target_state_predicate(None) is False


# ---------------------------------------------------------------------------
# idempotency_check
# ---------------------------------------------------------------------------


def test_idempotency_check_no_snapshot_not_present(ctx):
    result = idempotency_check(ctx)
    assert result["present"] is False
    assert result["current_state"]["last_validated_at"] is None


def test_idempotency_check_snapshot_present(ctx):
    # Run executor to write snapshot
    executor(ctx)
    result = idempotency_check(ctx)
    assert result["present"] is True
    assert result["current_state"]["last_validated_at"] is not None


# ---------------------------------------------------------------------------
# executor
# ---------------------------------------------------------------------------


def test_executor_first_run_applied(ctx):
    result = executor(ctx)
    assert result["applied"] is True
    assert len(result["side_effects"]) > 0


def test_executor_emits_to_stderr(ctx, capsys):
    executor(ctx)
    captured = capsys.readouterr()
    assert "audit health" in captured.err.lower() or "board-superpowers" in captured.err


def test_executor_persists_to_repo_shared_settings_yml(ctx):
    executor(ctx)
    section = get_module_section(
        "repo-shared",
        "m4_audit",
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )
    assert "last_health" in section
    assert section["last_health"]["health_summary_emitted"] is True


def test_executor_snapshot_not_in_credentials_yml(ctx):
    """Health data must NOT be in credentials.yml — it's not a secret."""
    executor(ctx)
    from stages_lib.m4_repo_acquire_dsn import _credentials_path, _read_credentials
    cred_path = _credentials_path(ctx)
    if cred_path.exists():
        creds = _read_credentials(ctx)
        assert "last_health" not in creds
        assert "health_summary_emitted" not in creds


def test_executor_no_op_on_second_run(ctx):
    result1 = executor(ctx)
    result2 = executor(ctx)
    assert result1["applied"] is True
    assert result2["applied"] is False
    assert "no-op" in result2["message"].lower()


def test_executor_includes_row_counts_in_message(ctx):
    result = executor(ctx)
    assert "db_rows" in result["message"] or "0" in result["message"]


def test_executor_counts_sqlite_rows_in_message(ctx_with_sqlite_db):
    ctx, dsn, db_path = ctx_with_sqlite_db
    # Insert 2 rows
    conn = sqlite3.connect(str(db_path))
    conn.execute(
        "INSERT INTO audit_log (timestamp, project, session_id, actor_role, "
        "action_id, payload, outcome, approval_stage) "
        "VALUES ('2026-01-01', 'p', 's', 'producer', 1, '{}', 'success', 'auto')"
    )
    conn.execute(
        "INSERT INTO audit_log (timestamp, project, session_id, actor_role, "
        "action_id, payload, outcome, approval_stage) "
        "VALUES ('2026-01-01', 'p', 's', 'consumer', 100, '{}', 'success', 'auto')"
    )
    conn.commit()
    conn.close()
    result = executor(ctx)
    assert result["applied"] is True
    # Snapshot should report 2 rows
    snapshot = _load_last_health(ctx)
    assert snapshot["db_row_count"] == 2


# ---------------------------------------------------------------------------
# _count_db_rows_sqlite helper
# ---------------------------------------------------------------------------


def test_count_db_rows_sqlite_no_file(tmp_path):
    dsn = f"sqlite:////{tmp_path}/nonexistent.db"
    assert _count_db_rows_sqlite(dsn) == 0


def test_count_db_rows_sqlite_empty_table(tmp_path):
    db_path = tmp_path / "audit.db"
    conn = sqlite3.connect(str(db_path))
    conn.execute("CREATE TABLE audit_log (id INTEGER)")
    conn.commit()
    conn.close()
    dsn = f"sqlite:////{db_path}"
    assert _count_db_rows_sqlite(dsn) == 0


def test_count_db_rows_sqlite_with_rows(tmp_path):
    db_path = tmp_path / "audit.db"
    conn = sqlite3.connect(str(db_path))
    conn.execute("CREATE TABLE audit_log (id INTEGER)")
    conn.execute("INSERT INTO audit_log VALUES (1)")
    conn.execute("INSERT INTO audit_log VALUES (2)")
    conn.commit()
    conn.close()
    dsn = f"sqlite:////{db_path}"
    assert _count_db_rows_sqlite(dsn) == 2


# ---------------------------------------------------------------------------
# Round-trip: compute_target_state validates against registry schema
# ---------------------------------------------------------------------------


def test_compute_target_state_validates_against_registry_schema(ctx):
    import jsonschema
    registry_path = Path(__file__).parent.parent / "stages-registry.yml"
    registry = yaml.safe_load(registry_path.read_text())
    stage = next(
        s for s in registry["stages"]
        if s["stage_id"] == "m4.repo.audit-health-check"
    )
    schema = stage["target_state_schema"]
    ts = compute_target_state(ctx)
    jsonschema.validate(instance=ts, schema=schema)
