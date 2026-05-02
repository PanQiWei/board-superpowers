"""Tests for stages_lib.m2_host_install_uv.

TDD: tests written first; run RED before implementation, GREEN after.
Run: cd scripts && python3 -m pytest stages_lib/ -v

ADR-0006 host-action boundary: executor MUST NOT auto-install uv.
When uv is absent, executor returns {applied: False, message: '<install instruction>'}.
"""

from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest


# ---------------------------------------------------------------------------
# Import guard — fails RED until module exists
# ---------------------------------------------------------------------------
from stages_lib.m2_host_install_uv import (  # noqa: E402
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
    return SimpleNamespace(
        home=tmp_path / "home",
        repo_root=tmp_path / "repo",
        repo_identity="test/repo",
    )


def _mock_uv_present(version="0.4.18", path="/usr/local/bin/uv"):
    """Return side_effect callable for subprocess.run that simulates uv present."""
    def _run(cmd, **kwargs):
        if "uv" in cmd and "--version" in cmd:
            m = MagicMock()
            m.stdout = f"uv {version}\n"
            m.returncode = 0
            return m
        if "which" in cmd or ("uv" in cmd and len(cmd) == 1):
            m = MagicMock()
            m.stdout = f"{path}\n"
            m.returncode = 0
            return m
        raise FileNotFoundError(f"Unexpected command: {cmd}")
    return _run


def _mock_uv_absent():
    """Return side_effect callable for subprocess.run that simulates uv absent."""
    def _run(cmd, **kwargs):
        raise FileNotFoundError("uv not found")
    return _run


# ---------------------------------------------------------------------------
# compute_target_state()
# ---------------------------------------------------------------------------


def test_compute_target_state_returns_dict_uv_present(ctx):
    with patch("subprocess.run") as mock_run:
        mock_run.side_effect = _mock_uv_present()
        state = compute_target_state(ctx)
    assert isinstance(state, dict)


def test_compute_target_state_has_required_keys_uv_present(ctx):
    with patch("subprocess.run") as mock_run:
        mock_run.side_effect = _mock_uv_present()
        state = compute_target_state(ctx)
    assert "uv_present" in state
    assert "uv_version" in state


def test_compute_target_state_uv_present_true(ctx):
    with patch("subprocess.run") as mock_run:
        mock_run.side_effect = _mock_uv_present(version="0.4.18")
        state = compute_target_state(ctx)
    assert state["uv_present"] is True
    assert state["uv_version"] == "0.4.18"


def test_compute_target_state_uv_absent_returns_false(ctx):
    with patch("subprocess.run") as mock_run:
        mock_run.side_effect = _mock_uv_absent()
        state = compute_target_state(ctx)
    assert state["uv_present"] is False
    assert state["uv_version"] is None


def test_compute_target_state_uv_path_present_when_uv_installed(ctx):
    with patch("subprocess.run") as mock_run:
        mock_run.side_effect = _mock_uv_present(path="/usr/local/bin/uv")
        state = compute_target_state(ctx)
    assert "uv_path" in state
    assert state["uv_path"] is not None


# ---------------------------------------------------------------------------
# target_state_predicate()
# ---------------------------------------------------------------------------


def test_target_state_predicate_valid_present():
    state = {"uv_present": True, "uv_version": "0.4.18", "uv_path": "/usr/local/bin/uv"}
    assert target_state_predicate(state) is True


def test_target_state_predicate_absent_version_none():
    # When uv absent, uv_version is None — predicate should return False
    state = {"uv_present": False, "uv_version": None}
    assert target_state_predicate(state) is False


def test_target_state_predicate_missing_uv_present():
    state = {"uv_version": "0.4.18"}
    assert target_state_predicate(state) is False


def test_target_state_predicate_missing_uv_version():
    state = {"uv_present": True}
    assert target_state_predicate(state) is False


def test_target_state_predicate_not_dict():
    assert target_state_predicate("string") is False


def test_target_state_predicate_uv_version_empty_string_invalid():
    state = {"uv_present": True, "uv_version": ""}
    assert target_state_predicate(state) is False


# ---------------------------------------------------------------------------
# idempotency_check()
# ---------------------------------------------------------------------------


def test_idempotency_check_uv_present(ctx):
    with patch("subprocess.run") as mock_run:
        mock_run.side_effect = _mock_uv_present()
        result = idempotency_check(ctx)
    assert result["present"] is True
    assert isinstance(result["current_state"], dict)


def test_idempotency_check_uv_absent(ctx):
    with patch("subprocess.run") as mock_run:
        mock_run.side_effect = _mock_uv_absent()
        result = idempotency_check(ctx)
    assert result["present"] is False


def test_idempotency_check_returns_current_state_dict(ctx):
    with patch("subprocess.run") as mock_run:
        mock_run.side_effect = _mock_uv_present()
        result = idempotency_check(ctx)
    assert "current_state" in result
    assert isinstance(result["current_state"], dict)


# ---------------------------------------------------------------------------
# executor() — uv present
# ---------------------------------------------------------------------------


def test_executor_uv_present_applies(ctx):
    with patch("subprocess.run") as mock_run:
        mock_run.side_effect = _mock_uv_present()
        result = executor(ctx)
    # When uv present, executor persists state and returns applied=True
    assert result["applied"] is True
    assert isinstance(result["side_effects"], list)


def test_executor_uv_present_message_not_empty(ctx):
    with patch("subprocess.run") as mock_run:
        mock_run.side_effect = _mock_uv_present()
        result = executor(ctx)
    assert "message" in result
    assert result["message"]


# ---------------------------------------------------------------------------
# executor() — uv absent (ADR-0006: MUST NOT auto-install)
# ---------------------------------------------------------------------------


def test_executor_uv_absent_does_not_install(ctx):
    """ADR-0006: executor MUST NOT auto-install uv when absent."""
    with patch("subprocess.run") as mock_run:
        mock_run.side_effect = _mock_uv_absent()
        result = executor(ctx)
    # Must NOT attempt to install (no 'install.sh' or 'brew install' in side_effects)
    for effect in result.get("side_effects", []):
        assert "install.sh" not in effect
        assert "brew install" not in effect


def test_executor_uv_absent_applied_false(ctx):
    """When uv absent, executor surfaces blocker (applied=False) rather than auto-installing."""
    with patch("subprocess.run") as mock_run:
        mock_run.side_effect = _mock_uv_absent()
        result = executor(ctx)
    assert result["applied"] is False


def test_executor_uv_absent_message_contains_install_instruction(ctx):
    """Message must guide architect on how to install uv manually."""
    with patch("subprocess.run") as mock_run:
        mock_run.side_effect = _mock_uv_absent()
        result = executor(ctx)
    # Must reference at least one install method
    msg = result["message"].lower()
    assert "brew" in msg or "astral" in msg or "curl" in msg or "uv" in msg


def test_executor_uv_absent_side_effects_empty(ctx):
    """When uv absent, no filesystem side effects."""
    with patch("subprocess.run") as mock_run:
        mock_run.side_effect = _mock_uv_absent()
        result = executor(ctx)
    assert result["side_effects"] == []


# ---------------------------------------------------------------------------
# Round-trip: compute_target_state output validates against registry schema
# ---------------------------------------------------------------------------


def test_compute_target_state_validates_against_registry_schema_uv_present(ctx):
    """Round-trip: compute_target_state (uv-present) MUST validate against the
    stage's target_state_schema declared in scripts/stages-registry.yml.
    Prevents registry/impl drift from being invisible to the test suite."""
    import json
    import yaml
    import jsonschema
    registry_path = Path(__file__).parent.parent / "stages-registry.yml"
    registry = yaml.safe_load(registry_path.read_text())
    stage = next(s for s in registry["stages"] if s["stage_id"] == "m2.host.install-uv")
    schema = stage["target_state_schema"]
    with patch("subprocess.run") as mock_run:
        mock_run.side_effect = _mock_uv_present(version="0.4.18", path="/usr/local/bin/uv")
        ts = compute_target_state(ctx)
    jsonschema.validate(instance=ts, schema=schema)


def test_compute_target_state_validates_against_registry_schema_uv_absent(ctx):
    """Round-trip: compute_target_state (uv-absent) MUST validate against the
    stage's target_state_schema declared in scripts/stages-registry.yml.
    uv_version=None must be allowed by the schema (type: ["string", "null"])."""
    import yaml
    import jsonschema
    registry_path = Path(__file__).parent.parent / "stages-registry.yml"
    registry = yaml.safe_load(registry_path.read_text())
    stage = next(s for s in registry["stages"] if s["stage_id"] == "m2.host.install-uv")
    schema = stage["target_state_schema"]
    with patch("subprocess.run") as mock_run:
        mock_run.side_effect = _mock_uv_absent()
        ts = compute_target_state(ctx)
    jsonschema.validate(instance=ts, schema=schema)
