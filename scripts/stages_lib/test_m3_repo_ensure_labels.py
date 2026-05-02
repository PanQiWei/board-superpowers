"""Tests for stages_lib.m3_repo_ensure_labels.

Stage: M3 | automated | external | both platforms
TDD: tests against the ADR-0014 4-callable contract.
Run: cd scripts && python3 -m pytest stages_lib/ -v

Key behaviors verified:
- 4-callable contract: all four callables present and callable
- apply_choice NOT present (automated stage — no 5th callable)
- compute_target_state: returns {canonical_labels_present: True, labels_canon: [...]}
  with exactly 13 labels (4 ops + 5 type + 4 size) matching scripts/setup-labels.sh
- target_state_predicate: accepts present=True with valid labels; rejects otherwise
- idempotency_check: all labels present / some missing (subprocess MOCKED)
- executor: delegates to setup-labels.sh / no-op when all present (subprocess MOCKED)
- subprocess MOCKED — no real gh calls in CI
- round-trip: compute_target_state validates against registry target_state_schema
- Status field options (Backlog, Ready, …) are NOT in the label set —
  they are GitHub Project field options, managed by m3.repo.validate-status-field
"""

from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest
import yaml

# ---------------------------------------------------------------------------
# Import guard — fails RED until module exists
# ---------------------------------------------------------------------------
from stages_lib.m3_repo_ensure_labels import (
    CANONICAL_LABEL_NAMES,
    CANONICAL_LABELS,
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
        repo_identity="test/testrepo",
    )


def _make_gh_label_list_result(names: list[str]) -> MagicMock:
    """Build a mocked subprocess.run result for gh label list --json name."""
    payload = json.dumps([{"name": n} for n in names])
    m = MagicMock()
    m.returncode = 0
    m.stdout = payload
    m.stderr = ""
    return m


def _make_gh_label_create_result(success: bool = True) -> MagicMock:
    m = MagicMock()
    m.returncode = 0 if success else 1
    m.stdout = ""
    m.stderr = "" if success else "some error"
    return m


# ---------------------------------------------------------------------------
# Module-level callable contract
# ---------------------------------------------------------------------------


def test_four_callables_present():
    import stages_lib.m3_repo_ensure_labels as m
    for name in ["compute_target_state", "target_state_predicate",
                 "idempotency_check", "executor"]:
        assert callable(getattr(m, name, None)), f"{name} missing or not callable"


def test_apply_choice_absent():
    """Automated stage — no 5th callable."""
    import stages_lib.m3_repo_ensure_labels as m
    assert not callable(getattr(m, "apply_choice", None))


# ---------------------------------------------------------------------------
# compute_target_state()
# ---------------------------------------------------------------------------


def test_compute_target_state_returns_dict(ctx):
    ts = compute_target_state(ctx)
    assert isinstance(ts, dict)


def test_compute_target_state_canonical_labels_present_true(ctx):
    ts = compute_target_state(ctx)
    assert ts.get("canonical_labels_present") is True


def test_compute_target_state_has_labels_canon(ctx):
    ts = compute_target_state(ctx)
    assert "labels_canon" in ts
    assert isinstance(ts["labels_canon"], list)


def test_compute_target_state_thirteen_labels(ctx):
    """Canonical set is 13 labels: 4 ops + 5 type + 4 size (from setup-labels.sh SoT)."""
    ts = compute_target_state(ctx)
    assert len(ts["labels_canon"]) == 13


def test_compute_target_state_label_names_match_canonical(ctx):
    ts = compute_target_state(ctx)
    names = [lb["name"] for lb in ts["labels_canon"]]
    for canon_name in CANONICAL_LABEL_NAMES:
        assert canon_name in names


# ---------------------------------------------------------------------------
# target_state_predicate()
# ---------------------------------------------------------------------------


def test_predicate_valid_present_true():
    assert target_state_predicate({"canonical_labels_present": True}) is True


def test_predicate_valid_with_labels_canon():
    state = {
        "canonical_labels_present": True,
        "labels_canon": CANONICAL_LABELS,
    }
    assert target_state_predicate(state) is True


def test_predicate_invalid_present_false():
    assert target_state_predicate({"canonical_labels_present": False}) is False


def test_predicate_invalid_missing_field():
    assert target_state_predicate({}) is False


def test_predicate_invalid_not_dict():
    assert target_state_predicate(True) is False


def test_predicate_invalid_labels_canon_missing_label():
    """labels_canon missing one entry should fail."""
    partial = [lb for lb in CANONICAL_LABELS if lb["name"] != "size:L"]
    state = {
        "canonical_labels_present": True,
        "labels_canon": partial,
    }
    assert target_state_predicate(state) is False


# ---------------------------------------------------------------------------
# idempotency_check() — subprocess MOCKED
# ---------------------------------------------------------------------------


def test_idempotency_check_all_labels_present(ctx):
    """All 13 canonical labels present → present=True."""
    with patch("subprocess.run") as mock_run:
        mock_run.return_value = _make_gh_label_list_result(CANONICAL_LABEL_NAMES)
        result = idempotency_check(ctx)
    assert result["present"] is True
    assert result["current_state"]["missing"] == []


def test_idempotency_check_some_labels_missing(ctx):
    """Only 3 labels present → present=False."""
    existing = CANONICAL_LABEL_NAMES[:3]
    with patch("subprocess.run") as mock_run:
        mock_run.return_value = _make_gh_label_list_result(existing)
        result = idempotency_check(ctx)
    assert result["present"] is False
    assert len(result["current_state"]["missing"]) == 10


def test_idempotency_check_no_labels_present(ctx):
    """No labels → all 13 in missing."""
    with patch("subprocess.run") as mock_run:
        mock_run.return_value = _make_gh_label_list_result([])
        result = idempotency_check(ctx)
    assert result["present"] is False
    assert len(result["current_state"]["missing"]) == 13


def test_idempotency_check_gh_error(ctx):
    """gh command fails → present=False with error."""
    err_result = MagicMock()
    err_result.returncode = 1
    err_result.stdout = ""
    err_result.stderr = "gh: authentication error"
    with patch("subprocess.run") as mock_run:
        mock_run.return_value = err_result
        result = idempotency_check(ctx)
    assert result["present"] is False
    assert "error" in result["current_state"]


# ---------------------------------------------------------------------------
# executor() — subprocess MOCKED
# ---------------------------------------------------------------------------


def test_executor_all_labels_present_no_op(ctx):
    """All 13 labels present → applied=False (no-op); setup-labels.sh NOT called."""
    with patch("subprocess.run") as mock_run:
        mock_run.return_value = _make_gh_label_list_result(CANONICAL_LABEL_NAMES)
        result = executor(ctx)
    assert result["applied"] is False
    assert "no-op" in result["message"].lower() or "already present" in result["message"].lower()


def test_executor_labels_missing_delegates_to_setup_labels_sh(ctx):
    """Labels missing → delegates to setup-labels.sh; applied=True."""
    setup_sh_call = []

    def side_effect(cmd, **kwargs):
        # idempotency_check calls gh label list
        if len(cmd) > 1 and cmd[0] == "gh" and "list" in cmd:
            return _make_gh_label_list_result([])
        # executor calls bash setup-labels.sh
        if len(cmd) > 0 and cmd[0] == "bash" and "setup-labels.sh" in str(cmd):
            setup_sh_call.append(cmd)
            m = MagicMock()
            m.returncode = 0
            m.stdout = ""
            m.stderr = ""
            return m
        return _make_gh_label_create_result(success=True)

    with patch("subprocess.run", side_effect=side_effect):
        result = executor(ctx)

    assert result["applied"] is True
    assert len(setup_sh_call) == 1, "executor must call setup-labels.sh exactly once"
    assert len(result["side_effects"]) > 0


def test_executor_setup_labels_sh_failure_returns_applied_false(ctx):
    """setup-labels.sh non-zero exit → applied=False with error message."""
    def side_effect(cmd, **kwargs):
        if len(cmd) > 0 and cmd[0] == "gh" and "list" in cmd:
            return _make_gh_label_list_result([])
        # setup-labels.sh fails
        m = MagicMock()
        m.returncode = 1
        m.stdout = ""
        m.stderr = "gh: authentication error"
        return m

    with patch("subprocess.run", side_effect=side_effect):
        result = executor(ctx)

    assert result["applied"] is False
    assert "failed" in result["message"].lower() or "error" in result["message"].lower()


def test_executor_some_labels_missing_delegates_to_setup_labels_sh(ctx):
    """Partial label presence → still delegates to setup-labels.sh."""
    # 4 labels present, 9 missing
    existing = CANONICAL_LABEL_NAMES[:4]
    setup_sh_call = []

    def side_effect(cmd, **kwargs):
        if len(cmd) > 0 and cmd[0] == "gh" and "list" in cmd:
            return _make_gh_label_list_result(existing)
        if len(cmd) > 0 and cmd[0] == "bash" and "setup-labels.sh" in str(cmd):
            setup_sh_call.append(cmd)
            m = MagicMock()
            m.returncode = 0
            m.stdout = ""
            m.stderr = ""
            return m
        return _make_gh_label_create_result(success=True)

    with patch("subprocess.run", side_effect=side_effect):
        result = executor(ctx)

    assert result["applied"] is True
    assert len(setup_sh_call) == 1


# ---------------------------------------------------------------------------
# Round-trip: compute_target_state validates against registry schema
# ---------------------------------------------------------------------------


def test_compute_target_state_validates_against_registry_schema(ctx):
    """Round-trip: compute_target_state output MUST validate against the
    stage's target_state_schema in stages-registry.yml."""
    import jsonschema
    registry_path = Path(__file__).parent.parent / "stages-registry.yml"
    registry = yaml.safe_load(registry_path.read_text())
    stage = next(
        s for s in registry["stages"]
        if s["stage_id"] == "m3.repo.ensure-labels"
    )
    schema = stage["target_state_schema"]
    ts = compute_target_state(ctx)
    jsonschema.validate(instance=ts, schema=schema)
