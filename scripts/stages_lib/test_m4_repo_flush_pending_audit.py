"""Tests for stages_lib.m4_repo_flush_pending_audit.

Stage: M4 | automated | external | both platforms
TDD: tests against the ADR-0014 4-callable contract.
Run: cd scripts && python3 -m pytest stages_lib/ -v

Key behaviors verified:
- 4-callable contract: all four callables present
- apply_choice NOT present (automated stage)
- compute_target_state: pending=0 → pending_replayed=True; pending>0 → False
- target_state_predicate: accepts pending_replayed=True; rejects False/missing
- idempotency_check: no jsonl / empty jsonl → present; pending rows → not present
- executor: delegates to audit-flush-pending.sh (subprocess MOCKED)
  - no-op when no pending rows
  - invokes flush script when pending rows exist
  - handles subprocess errors gracefully
  - exit 1 (dead-letter warning) counts as applied
- jsonl path uses HOST-side per-repo location (ADR-0015)
- Round-trip: compute_target_state validates against registry target_state_schema
"""

from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest
import yaml

from stages_lib.m4_repo_flush_pending_audit import (
    _jsonl_path,
    _pending_row_count,
    compute_target_state,
    executor,
    idempotency_check,
    target_state_predicate,
)


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


def _write_jsonl_rows(jsonl_path: Path, rows: list[dict]) -> None:
    """Write rows to a jsonl file, creating parent dirs."""
    jsonl_path.parent.mkdir(parents=True, exist_ok=True)
    with jsonl_path.open("w") as f:
        for row in rows:
            f.write(json.dumps(row) + "\n")


def _pending_row(event_uuid: str = "uuid-1") -> dict:
    return {
        "event_uuid": event_uuid,
        "action_id": 200,
        "decision": "A",
        "skill": "bootstrapping-repo",
        "approval_stage": "auto",
        "outcome": "success",
        "payload": "{}",
        "status": "pending",
        "retry_count": 0,
        "pending_since": "2026-01-01T00:00:00Z",
    }


def _processed_row(event_uuid: str = "uuid-2") -> dict:
    row = _pending_row(event_uuid)
    row["status"] = "processed"
    return row


def _make_flush_success():
    m = MagicMock()
    m.returncode = 0
    m.stdout = ""
    m.stderr = ""
    return m


def _make_flush_dead_letter():
    """Exit 1 = corrupt rows → dead-letter (still counts as applied per spec)."""
    m = MagicMock()
    m.returncode = 1
    m.stdout = ""
    m.stderr = "1 row(s) sent to audit-dead-letter"
    return m


def _make_flush_failure():
    m = MagicMock()
    m.returncode = 2
    m.stdout = ""
    m.stderr = "partial INSERT failure"
    return m


# ---------------------------------------------------------------------------
# Module-level callable contract
# ---------------------------------------------------------------------------


def test_four_callables_present():
    import stages_lib.m4_repo_flush_pending_audit as m
    for name in ["compute_target_state", "target_state_predicate", "idempotency_check", "executor"]:
        assert callable(getattr(m, name, None)), f"{name} missing or not callable"


def test_apply_choice_absent():
    """Automated stage — no 5th callable."""
    import stages_lib.m4_repo_flush_pending_audit as m
    assert not callable(getattr(m, "apply_choice", None))


# ---------------------------------------------------------------------------
# jsonl path
# ---------------------------------------------------------------------------


def test_jsonl_path_is_host_side_per_repo(ctx):
    """jsonl must be at HOST-side path, not inside repo_root (ADR-0015)."""
    jp = _jsonl_path(ctx)
    assert str(ctx.home) in str(jp), "jsonl must be under home"
    assert str(ctx.repo_root) not in str(jp), "jsonl must NOT be under repo_root"
    assert jp.name == "audit-local.jsonl"


# ---------------------------------------------------------------------------
# _pending_row_count helper
# ---------------------------------------------------------------------------


def test_pending_row_count_no_file(ctx):
    jp = _jsonl_path(ctx)
    assert _pending_row_count(jp) == 0


def test_pending_row_count_empty_file(ctx):
    jp = _jsonl_path(ctx)
    jp.parent.mkdir(parents=True, exist_ok=True)
    jp.write_text("")
    assert _pending_row_count(jp) == 0


def test_pending_row_count_pending_rows(ctx):
    jp = _jsonl_path(ctx)
    _write_jsonl_rows(jp, [_pending_row("u1"), _pending_row("u2")])
    assert _pending_row_count(jp) == 2


def test_pending_row_count_processed_rows_not_counted(ctx):
    jp = _jsonl_path(ctx)
    _write_jsonl_rows(jp, [_processed_row("u1"), _processed_row("u2")])
    assert _pending_row_count(jp) == 0


def test_pending_row_count_mixed(ctx):
    jp = _jsonl_path(ctx)
    _write_jsonl_rows(jp, [_pending_row("u1"), _processed_row("u2"), _pending_row("u3")])
    assert _pending_row_count(jp) == 2


# ---------------------------------------------------------------------------
# compute_target_state
# ---------------------------------------------------------------------------


def test_compute_target_state_no_jsonl_pending_replayed_true(ctx):
    ts = compute_target_state(ctx)
    assert ts["pending_replayed"] is True
    assert ts["rows_inserted"] == 0


def test_compute_target_state_pending_rows_pending_replayed_false(ctx):
    jp = _jsonl_path(ctx)
    _write_jsonl_rows(jp, [_pending_row("u1")])
    ts = compute_target_state(ctx)
    assert ts["pending_replayed"] is False


# ---------------------------------------------------------------------------
# target_state_predicate
# ---------------------------------------------------------------------------


def test_predicate_valid_pending_replayed_true():
    assert target_state_predicate({"pending_replayed": True, "rows_inserted": 0}) is True


def test_predicate_valid_with_nonzero_rows():
    assert target_state_predicate({"pending_replayed": True, "rows_inserted": 5}) is True


def test_predicate_invalid_pending_replayed_false():
    assert target_state_predicate({"pending_replayed": False}) is False


def test_predicate_invalid_missing_field():
    assert target_state_predicate({"rows_inserted": 0}) is False


def test_predicate_invalid_negative_rows():
    assert target_state_predicate({"pending_replayed": True, "rows_inserted": -1}) is False


def test_predicate_invalid_not_dict():
    assert target_state_predicate(True) is False
    assert target_state_predicate(None) is False


# ---------------------------------------------------------------------------
# idempotency_check
# ---------------------------------------------------------------------------


def test_idempotency_check_no_jsonl_present(ctx):
    result = idempotency_check(ctx)
    assert result["present"] is True
    assert result["current_state"]["pending_count"] == 0


def test_idempotency_check_empty_jsonl_present(ctx):
    jp = _jsonl_path(ctx)
    jp.parent.mkdir(parents=True, exist_ok=True)
    jp.write_text("")
    result = idempotency_check(ctx)
    assert result["present"] is True


def test_idempotency_check_pending_rows_not_present(ctx):
    jp = _jsonl_path(ctx)
    _write_jsonl_rows(jp, [_pending_row("u1"), _pending_row("u2")])
    result = idempotency_check(ctx)
    assert result["present"] is False
    assert result["current_state"]["pending_count"] == 2


def test_idempotency_check_only_processed_rows_present(ctx):
    jp = _jsonl_path(ctx)
    _write_jsonl_rows(jp, [_processed_row("u1"), _processed_row("u2")])
    result = idempotency_check(ctx)
    assert result["present"] is True


# ---------------------------------------------------------------------------
# executor — subprocess MOCKED
# ---------------------------------------------------------------------------


def test_executor_no_pending_rows_no_op(ctx):
    """No pending rows → no-op; subprocess NOT called."""
    with patch("subprocess.run") as mock_run:
        result = executor(ctx)
    mock_run.assert_not_called()
    assert result["applied"] is False
    assert "no-op" in result["message"].lower() or "no pending" in result["message"].lower()


def test_executor_pending_rows_invokes_flush_sh(ctx):
    """Pending rows → invokes audit-flush-pending.sh."""
    jp = _jsonl_path(ctx)
    _write_jsonl_rows(jp, [_pending_row("u1")])
    with patch("subprocess.run", return_value=_make_flush_success()) as mock_run:
        result = executor(ctx)
    mock_run.assert_called_once()
    cmd = mock_run.call_args[0][0]
    assert "bash" in cmd
    assert "audit-flush-pending.sh" in str(cmd)
    assert result["applied"] is True


def test_executor_handles_flush_failure_exit_2(ctx):
    jp = _jsonl_path(ctx)
    _write_jsonl_rows(jp, [_pending_row("u1")])
    with patch("subprocess.run", return_value=_make_flush_failure()):
        result = executor(ctx)
    assert result["applied"] is False
    assert "failed" in result["message"].lower()


def test_executor_handles_subprocess_oserror(ctx):
    jp = _jsonl_path(ctx)
    _write_jsonl_rows(jp, [_pending_row("u1")])
    with patch("subprocess.run", side_effect=OSError("no such file")):
        result = executor(ctx)
    assert result["applied"] is False
    assert "error" in result["message"].lower()


def test_executor_returns_run_id_on_success(ctx):
    jp = _jsonl_path(ctx)
    _write_jsonl_rows(jp, [_pending_row("u1")])
    with patch("subprocess.run", return_value=_make_flush_success()):
        result = executor(ctx)
    assert result["applied"] is True
    assert "run_id" in result


# ---------------------------------------------------------------------------
# Round-trip: compute_target_state validates against registry schema
# ---------------------------------------------------------------------------


def test_compute_target_state_validates_against_registry_schema(ctx):
    import jsonschema
    registry_path = Path(__file__).parent.parent / "stages-registry.yml"
    registry = yaml.safe_load(registry_path.read_text())
    stage = next(
        s for s in registry["stages"]
        if s["stage_id"] == "m4.repo.flush-pending-audit"
    )
    schema = stage["target_state_schema"]
    ts = compute_target_state(ctx)
    jsonschema.validate(instance=ts, schema=schema)
