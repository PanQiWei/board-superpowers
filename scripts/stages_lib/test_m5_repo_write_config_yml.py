"""Tests for stages_lib.m5_repo_write_config_yml.

Stage: M5 | automated | repo-git | both platforms
TDD: tests written to drive implementation.
Run: cd scripts && python3 -m pytest stages_lib/ -v

Key behaviors verified:
- 4-callable contract: all four callables present and callable
- compute_target_state: returns expected shape with path + schema_version
- target_state_predicate: accepts/rejects per schema
- idempotency_check: absent / present
- executor: creates file / idempotent second run
- round-trip: compute_target_state output validates against registry target_state_schema
"""

from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml

# ---------------------------------------------------------------------------
# Import guard — fails RED until module exists
# ---------------------------------------------------------------------------
from stages_lib.m5_repo_write_config_yml import (
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


# ---------------------------------------------------------------------------
# compute_target_state()
# ---------------------------------------------------------------------------


def test_compute_target_state_returns_dict(ctx):
    state = compute_target_state(ctx)
    assert isinstance(state, dict)


def test_compute_target_state_has_path(ctx):
    state = compute_target_state(ctx)
    assert "path" in state
    assert isinstance(state["path"], str)
    assert len(state["path"]) > 0


def test_compute_target_state_path_value(ctx):
    state = compute_target_state(ctx)
    expected = str(ctx.repo_root / ".board-superpowers" / "settings.yml")
    assert state["path"] == expected


def test_compute_target_state_has_schema_version(ctx):
    state = compute_target_state(ctx)
    assert "schema_version" in state
    assert isinstance(state["schema_version"], int)
    assert state["schema_version"] >= 1


def test_compute_target_state_has_defaults_present(ctx):
    state = compute_target_state(ctx)
    assert "defaults_present" in state
    assert state["defaults_present"] is True


def test_compute_target_state_is_pure(ctx):
    s1 = compute_target_state(ctx)
    s2 = compute_target_state(ctx)
    assert s1 == s2


# ---------------------------------------------------------------------------
# target_state_predicate()
# ---------------------------------------------------------------------------


def test_target_state_predicate_valid(ctx):
    state = compute_target_state(ctx)
    assert target_state_predicate(state) is True


def test_target_state_predicate_invalid_missing_path():
    assert target_state_predicate({"schema_version": 1}) is False


def test_target_state_predicate_invalid_missing_schema_version():
    assert target_state_predicate({"path": "/tmp/x.yml"}) is False


def test_target_state_predicate_invalid_schema_version_zero():
    assert target_state_predicate({"path": "/tmp/x.yml", "schema_version": 0}) is False


def test_target_state_predicate_invalid_schema_version_negative():
    assert target_state_predicate({"path": "/tmp/x.yml", "schema_version": -1}) is False


def test_target_state_predicate_invalid_empty_path():
    assert target_state_predicate({"path": "", "schema_version": 1}) is False


def test_target_state_predicate_invalid_not_dict():
    assert target_state_predicate("string") is False


def test_target_state_predicate_invalid_none():
    assert target_state_predicate(None) is False


# ---------------------------------------------------------------------------
# idempotency_check() — file absent
# ---------------------------------------------------------------------------


def test_idempotency_check_absent(ctx):
    result = idempotency_check(ctx)
    assert result["present"] is False
    assert isinstance(result["current_state"], dict)


# ---------------------------------------------------------------------------
# idempotency_check() — file present after executor runs
# ---------------------------------------------------------------------------


def test_idempotency_check_present_after_executor(ctx):
    executor(ctx)
    result = idempotency_check(ctx)
    assert result["present"] is True


def test_idempotency_check_present_current_state_has_schema_version(ctx):
    executor(ctx)
    result = idempotency_check(ctx)
    assert "schema_version" in result["current_state"]
    assert result["current_state"]["schema_version"] >= 1


# ---------------------------------------------------------------------------
# idempotency_check() — file present with wrong schema_version
# ---------------------------------------------------------------------------


def test_idempotency_check_wrong_schema_version(ctx):
    bsp_dir = ctx.repo_root / ".board-superpowers"
    bsp_dir.mkdir(parents=True)
    path = bsp_dir / "settings.yml"
    data = {"setup": {"schema_version": 99}, "modules": {}}
    path.write_text(yaml.safe_dump(data))
    result = idempotency_check(ctx)
    # schema_version 99 ≠ 1 → present=False
    assert result["present"] is False


# ---------------------------------------------------------------------------
# executor() — creates settings.yml
# ---------------------------------------------------------------------------


def test_executor_creates_file(ctx):
    result = executor(ctx)
    assert result["applied"] is True
    path = ctx.repo_root / ".board-superpowers" / "settings.yml"
    assert path.exists()


def test_executor_creates_parent_dir(ctx):
    # Parent dir NOT pre-created; executor must create it
    result = executor(ctx)
    assert result["applied"] is True
    path = ctx.repo_root / ".board-superpowers" / "settings.yml"
    assert path.exists()


def test_executor_writes_valid_yaml(ctx):
    executor(ctx)
    path = ctx.repo_root / ".board-superpowers" / "settings.yml"
    data = yaml.safe_load(path.read_text())
    assert isinstance(data, dict)


def test_executor_writes_setup_section(ctx):
    executor(ctx)
    path = ctx.repo_root / ".board-superpowers" / "settings.yml"
    data = yaml.safe_load(path.read_text())
    assert "setup" in data
    assert data["setup"]["schema_version"] >= 1


def test_executor_writes_modules_section(ctx):
    executor(ctx)
    path = ctx.repo_root / ".board-superpowers" / "settings.yml"
    data = yaml.safe_load(path.read_text())
    assert "modules" in data


def test_executor_returns_side_effects(ctx):
    result = executor(ctx)
    assert isinstance(result["side_effects"], list)
    assert len(result["side_effects"]) > 0


def test_executor_message_contains_path(ctx):
    result = executor(ctx)
    assert "settings.yml" in result["message"]


# ---------------------------------------------------------------------------
# executor() — idempotency
# ---------------------------------------------------------------------------


def test_executor_idempotent(ctx):
    r1 = executor(ctx)
    r2 = executor(ctx)
    assert r1["applied"] is True
    assert r2["applied"] is False


def test_executor_second_run_preserves_content(ctx):
    executor(ctx)
    path = ctx.repo_root / ".board-superpowers" / "settings.yml"
    content_1 = path.read_text()
    executor(ctx)
    content_2 = path.read_text()
    assert content_1 == content_2


# ---------------------------------------------------------------------------
# Round-trip: compute_target_state validates against registry schema
# ---------------------------------------------------------------------------


def test_compute_target_state_validates_against_registry_schema(ctx):
    """Round-trip: compute_target_state output MUST validate against the
    stage's target_state_schema declared in scripts/stages-registry.yml."""
    import jsonschema
    registry_path = Path(__file__).parent.parent / "stages-registry.yml"
    registry = yaml.safe_load(registry_path.read_text())
    stage = next(
        s for s in registry["stages"] if s["stage_id"] == "m5.repo.write-config-yml"
    )
    schema = stage["target_state_schema"]
    ts = compute_target_state(ctx)
    jsonschema.validate(instance=ts, schema=schema)
