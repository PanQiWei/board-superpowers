"""Tests for stages_lib.m4_repo_apply_audit_ddl.

Stage: M4 | automated | external | both platforms
TDD: tests against the ADR-0014 4-callable contract.
Run: cd scripts && python3 -m pytest stages_lib/ -v

Key behaviors verified:
- 4-callable contract: all four callables present
- apply_choice NOT present (automated stage)
- compute_target_state: returns schema with audit_log.schema_version >= 1
- target_state_predicate: accepts valid DDL state; rejects invalid
- idempotency_check: absent DB → not present; real sqlite DB present → present
- executor: delegates to audit-init.sh (subprocess MOCKED)
  - no-op when tables already present
  - invokes audit-init.sh when not present
  - handles subprocess failure gracefully
- Round-trip: compute_target_state validates against registry target_state_schema
"""

from __future__ import annotations

import sqlite3
import tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest
import yaml

from stages_lib.m4_repo_apply_audit_ddl import (
    _AUDIT_LOG_COLUMNS,
    _AUDIT_OUTBOX_COLUMNS,
    _AUDIT_SCHEMA_META_COLUMNS,
    _SCHEMA_VERSION,
    compute_target_state,
    executor,
    idempotency_check,
    target_state_predicate,
)
from stages_lib.m4_repo_acquire_dsn import apply_choice as acquire_apply_choice


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
def ctx_with_sqlite_dsn(ctx, tmp_path):
    """ctx with sqlite DSN configured."""
    db_path = tmp_path / "audit.db"
    dsn = f"sqlite:////{db_path}"
    acquire_apply_choice(ctx, dsn)
    return ctx, dsn, db_path


@pytest.fixture
def ctx_with_sqlite_tables(ctx_with_sqlite_dsn):
    """ctx with sqlite DSN + real tables created."""
    ctx, dsn, db_path = ctx_with_sqlite_dsn
    # Create the audit_log, audit_outbox, audit_schema_meta tables
    conn = sqlite3.connect(str(db_path))
    conn.execute("CREATE TABLE IF NOT EXISTS audit_log (id INTEGER PRIMARY KEY)")
    conn.execute("CREATE TABLE IF NOT EXISTS audit_outbox (id INTEGER PRIMARY KEY)")
    conn.execute(
        "CREATE TABLE IF NOT EXISTS audit_schema_meta "
        "(id INTEGER PRIMARY KEY, version INTEGER, applied_at TEXT)"
    )
    conn.commit()
    conn.close()
    return ctx, dsn, db_path


# ---------------------------------------------------------------------------
# Module-level callable contract
# ---------------------------------------------------------------------------


def test_four_callables_present():
    import stages_lib.m4_repo_apply_audit_ddl as m
    for name in ["compute_target_state", "target_state_predicate", "idempotency_check", "executor"]:
        assert callable(getattr(m, name, None)), f"{name} missing or not callable"


def test_apply_choice_absent():
    """Automated stage — no 5th callable."""
    import stages_lib.m4_repo_apply_audit_ddl as m
    assert not callable(getattr(m, "apply_choice", None))


# ---------------------------------------------------------------------------
# compute_target_state
# ---------------------------------------------------------------------------


def test_compute_target_state_returns_dict(ctx):
    ts = compute_target_state(ctx)
    assert isinstance(ts, dict)


def test_compute_target_state_has_audit_log(ctx):
    ts = compute_target_state(ctx)
    assert "audit_log" in ts
    al = ts["audit_log"]
    assert al["schema_version"] >= 1
    assert isinstance(al["columns_required"], list)
    assert len(al["columns_required"]) > 0
    assert isinstance(al["indexes_required"], list)


def test_compute_target_state_schema_version_is_target(ctx):
    ts = compute_target_state(ctx)
    assert ts["audit_log"]["schema_version"] == _SCHEMA_VERSION


def test_compute_target_state_has_audit_outbox(ctx):
    ts = compute_target_state(ctx)
    assert "audit_outbox" in ts
    assert isinstance(ts["audit_outbox"]["columns_required"], list)


def test_compute_target_state_has_audit_schema_meta(ctx):
    ts = compute_target_state(ctx)
    assert "audit_schema_meta" in ts
    assert isinstance(ts["audit_schema_meta"]["columns_required"], list)


def test_compute_target_state_includes_key_columns(ctx):
    ts = compute_target_state(ctx)
    cols = ts["audit_log"]["columns_required"]
    for col in ["timestamp", "project", "session_id", "actor_role", "action_id"]:
        assert col in cols, f"required column {col!r} missing"


# ---------------------------------------------------------------------------
# target_state_predicate
# ---------------------------------------------------------------------------


def test_predicate_valid_state():
    state = {
        "audit_log": {
            "schema_version": 2,
            "columns_required": ["id", "timestamp"],
            "indexes_required": [],
        },
        "audit_outbox": {"columns_required": ["id"]},
        "audit_schema_meta": {"columns_required": ["id", "version"]},
    }
    assert target_state_predicate(state) is True


def test_predicate_invalid_missing_audit_log():
    assert target_state_predicate({"audit_outbox": {"columns_required": []}, "audit_schema_meta": {"columns_required": []}}) is False


def test_predicate_invalid_schema_version_zero():
    state = {
        "audit_log": {"schema_version": 0, "columns_required": ["id"], "indexes_required": []},
        "audit_outbox": {"columns_required": []},
        "audit_schema_meta": {"columns_required": []},
    }
    assert target_state_predicate(state) is False


def test_predicate_invalid_empty_columns():
    state = {
        "audit_log": {"schema_version": 1, "columns_required": [], "indexes_required": []},
        "audit_outbox": {"columns_required": []},
        "audit_schema_meta": {"columns_required": []},
    }
    assert target_state_predicate(state) is False


def test_predicate_invalid_not_dict():
    assert target_state_predicate(True) is False
    assert target_state_predicate(None) is False


# ---------------------------------------------------------------------------
# idempotency_check
# ---------------------------------------------------------------------------


def test_idempotency_check_no_dsn_configured(ctx):
    result = idempotency_check(ctx)
    assert result["present"] is False
    assert "error" in result["current_state"]


def test_idempotency_check_dsn_configured_but_no_db(ctx_with_sqlite_dsn):
    ctx, dsn, db_path = ctx_with_sqlite_dsn
    # DB file doesn't exist yet
    result = idempotency_check(ctx)
    assert result["present"] is False


def test_idempotency_check_sqlite_tables_present(ctx_with_sqlite_tables):
    ctx, dsn, db_path = ctx_with_sqlite_tables
    result = idempotency_check(ctx)
    assert result["present"] is True
    assert result["current_state"]["dsn_scheme"] == "sqlite"


def test_idempotency_check_sqlite_partial_tables(ctx_with_sqlite_dsn):
    """Only audit_log present, not all three → not present."""
    ctx, dsn, db_path = ctx_with_sqlite_dsn
    conn = sqlite3.connect(str(db_path))
    conn.execute("CREATE TABLE audit_log (id INTEGER)")
    conn.commit()
    conn.close()
    result = idempotency_check(ctx)
    # audit_outbox and audit_schema_meta missing → not present
    assert result["present"] is False


def test_idempotency_check_pg_scheme_returns_not_present(ctx):
    """For pg DSN, probe is deferred to executor → returns not present."""
    acquire_apply_choice(ctx, "postgresql://user:pass@localhost/db")
    result = idempotency_check(ctx)
    assert result["present"] is False
    assert result["current_state"]["dsn_scheme"] == "postgresql"


# ---------------------------------------------------------------------------
# executor — subprocess MOCKED
# ---------------------------------------------------------------------------


def _make_success_result():
    m = MagicMock()
    m.returncode = 0
    m.stdout = ""
    m.stderr = ""
    return m


def _make_failure_result(rc=1, stderr="error"):
    m = MagicMock()
    m.returncode = rc
    m.stdout = ""
    m.stderr = stderr
    return m


def test_executor_no_dsn_returns_not_applied(ctx):
    result = executor(ctx)
    assert result["applied"] is False
    assert "acquire-dsn" in result["message"].lower() or "not configured" in result["message"].lower()


def test_executor_tables_already_present_no_op(ctx_with_sqlite_tables):
    """All tables present → no-op; subprocess NOT called."""
    ctx, dsn, db_path = ctx_with_sqlite_tables
    with patch("subprocess.run") as mock_run:
        result = executor(ctx)
    mock_run.assert_not_called()
    assert result["applied"] is False
    assert "no-op" in result["message"].lower()


def test_executor_invokes_audit_init_sh_when_needed(ctx_with_sqlite_dsn):
    """Tables absent → invokes audit-init.sh via subprocess."""
    ctx, dsn, db_path = ctx_with_sqlite_dsn
    with patch("subprocess.run", return_value=_make_success_result()) as mock_run:
        result = executor(ctx)
    mock_run.assert_called_once()
    cmd = mock_run.call_args[0][0]
    assert "bash" in cmd
    assert "audit-init.sh" in str(cmd)
    assert result["applied"] is True


def test_executor_handles_audit_init_sh_failure(ctx_with_sqlite_dsn):
    ctx, dsn, db_path = ctx_with_sqlite_dsn
    with patch("subprocess.run", return_value=_make_failure_result(rc=1, stderr="db error")):
        result = executor(ctx)
    assert result["applied"] is False
    assert "failed" in result["message"].lower()


def test_executor_handles_subprocess_oserror(ctx_with_sqlite_dsn):
    ctx, dsn, db_path = ctx_with_sqlite_dsn
    with patch("subprocess.run", side_effect=OSError("no such file")):
        result = executor(ctx)
    assert result["applied"] is False
    assert "error" in result["message"].lower()


# ---------------------------------------------------------------------------
# Round-trip: compute_target_state validates against registry schema
# ---------------------------------------------------------------------------


def test_compute_target_state_validates_against_registry_schema(ctx):
    import jsonschema
    registry_path = Path(__file__).parent.parent / "stages-registry.yml"
    registry = yaml.safe_load(registry_path.read_text())
    stage = next(
        s for s in registry["stages"]
        if s["stage_id"] == "m4.repo.apply-audit-ddl"
    )
    schema = stage["target_state_schema"]
    ts = compute_target_state(ctx)
    jsonschema.validate(instance=ts, schema=schema)
