"""Tests for stages_lib.m3_repo_validate_status_field.

Stage: M3 | agentic (on-failure) | external | both platforms
TDD: tests against the ADR-0014 4-callable + apply_choice contract.
Run: cd scripts && python3 -m pytest stages_lib/ -v

Key behaviors verified:
- 4-callable contract: all four callables present and callable
- apply_choice (5th callable): present for agentic stage
- compute_target_state: schema-valid, returns canonical options + resolution
- target_state_predicate: accepts present=True or valid resolution
- idempotency_check: all options present / missing (subprocess MOCKED)
- executor: no-op when canonical present; requires_input when missing;
            no-op when resolution already persisted
- apply_choice: persists; idempotent; rejects invalid
- subprocess MOCKED — no real gh calls in CI
- round-trip: compute_target_state validates against registry schema
"""

from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest
import yaml

from stages_lib.m3_repo_validate_status_field import (
    CANONICAL_STATUS_OPTIONS,
    VALID_RESOLUTIONS,
    apply_choice,
    compute_target_state,
    executor,
    idempotency_check,
    target_state_predicate,
)


@pytest.fixture
def ctx(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    repo = tmp_path / "repo"
    repo.mkdir()
    return SimpleNamespace(home=home, repo_root=repo, repo_identity="test/repo")


def _graphql_result(option_names: list[str]) -> MagicMock:
    payload = json.dumps({
        "data": {"user": {"projectV2": {"field": {
            "options": [{"name": n} for n in option_names]
        }}}}
    })
    m = MagicMock()
    m.returncode = 0
    m.stdout = payload
    m.stderr = ""
    return m


def _graphql_error() -> MagicMock:
    m = MagicMock()
    m.returncode = 1
    m.stdout = ""
    m.stderr = "gh: authentication error"
    return m


# ---------------------------------------------------------------------------
# Callable contract
# ---------------------------------------------------------------------------

def test_four_callables_present():
    import stages_lib.m3_repo_validate_status_field as m
    for name in ["compute_target_state", "target_state_predicate",
                 "idempotency_check", "executor"]:
        assert callable(getattr(m, name, None)), f"{name} missing"


def test_apply_choice_present():
    import stages_lib.m3_repo_validate_status_field as m
    assert callable(getattr(m, "apply_choice", None))


# ---------------------------------------------------------------------------
# compute_target_state()
# ---------------------------------------------------------------------------

def test_compute_target_state_shape(ctx):
    ts = compute_target_state(ctx)
    assert ts["status_options_canonical_present"] is True
    assert len(ts["canonical_status_options"]) == 6
    assert ts["resolution"] in VALID_RESOLUTIONS
    for opt in CANONICAL_STATUS_OPTIONS:
        assert opt in ts["canonical_status_options"]


def test_compute_target_state_reflects_persisted_resolution(ctx):
    apply_choice(ctx, "architect-added-missing")
    assert compute_target_state(ctx)["resolution"] == "architect-added-missing"


# ---------------------------------------------------------------------------
# target_state_predicate()
# ---------------------------------------------------------------------------

def test_predicate_status_present_true():
    assert target_state_predicate({"status_options_canonical_present": True}) is True


@pytest.mark.parametrize("resolution", VALID_RESOLUTIONS)
def test_predicate_valid_resolution(resolution):
    assert target_state_predicate({
        "status_options_canonical_present": False, "resolution": resolution,
    }) is True


@pytest.mark.parametrize("state", [
    {"status_options_canonical_present": False},
    {"status_options_canonical_present": False, "resolution": "invalid"},
    True, {},
])
def test_predicate_invalid(state):
    assert target_state_predicate(state) is False


# ---------------------------------------------------------------------------
# idempotency_check() — subprocess MOCKED
# ---------------------------------------------------------------------------

def test_idempotency_check_all_canonical_present(ctx):
    with patch("subprocess.run") as mr, \
         patch.dict("os.environ", {"BSP_PROJECT_REF": "owner/42"}):
        mr.return_value = _graphql_result(CANONICAL_STATUS_OPTIONS)
        result = idempotency_check(ctx)
    assert result["present"] is True
    assert result["current_state"]["missing"] == []


def test_idempotency_check_missing_some(ctx):
    partial = CANONICAL_STATUS_OPTIONS[:4]
    with patch("subprocess.run") as mr, \
         patch.dict("os.environ", {"BSP_PROJECT_REF": "owner/42"}):
        mr.return_value = _graphql_result(partial)
        result = idempotency_check(ctx)
    assert result["present"] is False
    assert len(result["current_state"]["missing"]) == 2


def test_idempotency_check_custom_options_tracked(ctx):
    opts = CANONICAL_STATUS_OPTIONS + ["Custom-State"]
    with patch("subprocess.run") as mr, \
         patch.dict("os.environ", {"BSP_PROJECT_REF": "owner/42"}):
        mr.return_value = _graphql_result(opts)
        result = idempotency_check(ctx)
    assert result["present"] is True
    assert "Custom-State" in result["current_state"]["custom"]


def test_idempotency_check_gh_error(ctx):
    with patch("subprocess.run") as mr, \
         patch.dict("os.environ", {"BSP_PROJECT_REF": "owner/42"}):
        mr.return_value = _graphql_error()
        result = idempotency_check(ctx)
    assert result["present"] is False
    assert "error" in result["current_state"]


def test_idempotency_check_no_project_ref(ctx):
    with patch.dict("os.environ", {}, clear=True):
        result = idempotency_check(ctx)
    assert result["present"] is False


# ---------------------------------------------------------------------------
# executor() — agentic-on-failure protocol
# ---------------------------------------------------------------------------

def test_executor_canonical_present_no_op(ctx):
    with patch("subprocess.run") as mr, \
         patch.dict("os.environ", {"BSP_PROJECT_REF": "owner/42"}):
        mr.return_value = _graphql_result(CANONICAL_STATUS_OPTIONS)
        result = executor(ctx)
    assert result["applied"] is False
    assert result.get("requires_input") is not True
    assert "canonical-already-present" in result["message"]


def test_executor_missing_requires_input(ctx):
    with patch("subprocess.run") as mr, \
         patch.dict("os.environ", {"BSP_PROJECT_REF": "owner/42"}):
        mr.return_value = _graphql_result([])
        result = executor(ctx)
    assert result.get("requires_input") is True


def test_executor_missing_has_two_option_prompt(ctx):
    with patch("subprocess.run") as mr, \
         patch.dict("os.environ", {"BSP_PROJECT_REF": "owner/42"}):
        mr.return_value = _graphql_result([])
        result = executor(ctx)
    prompt = result.get("prompt", {})
    assert prompt.get("kind") == "single-choice"
    assert len(prompt.get("options", [])) == 2


def test_executor_missing_has_missing_options_list(ctx):
    partial = CANONICAL_STATUS_OPTIONS[:3]
    with patch("subprocess.run") as mr, \
         patch.dict("os.environ", {"BSP_PROJECT_REF": "owner/42"}):
        mr.return_value = _graphql_result(partial)
        result = executor(ctx)
    assert len(result.get("missing_options", [])) == 3


def test_executor_resolution_persisted_no_op(ctx):
    apply_choice(ctx, "architect-added-missing")
    with patch("subprocess.run") as mr, \
         patch.dict("os.environ", {"BSP_PROJECT_REF": "owner/42"}):
        mr.return_value = _graphql_result([])
        result = executor(ctx)
    assert result.get("requires_input") is not True


# ---------------------------------------------------------------------------
# apply_choice() — persistence
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("resolution", [
    "architect-added-missing",
    "architect-accepted-custom-state-folding",
    "canonical-already-present",
])
def test_apply_choice_valid_resolutions(ctx, resolution):
    assert apply_choice(ctx, resolution)["applied"] is True


def test_apply_choice_persists_to_settings_yml(ctx):
    apply_choice(ctx, "architect-added-missing")
    path = ctx.repo_root / ".board-superpowers" / "settings.yml"
    data = yaml.safe_load(path.read_text())
    assert data["modules"]["m3_validate_status_field"]["resolution"] == "architect-added-missing"


def test_apply_choice_idempotent(ctx):
    r1 = apply_choice(ctx, "architect-added-missing")
    r2 = apply_choice(ctx, "architect-added-missing")
    assert r1["applied"] is True and r2["applied"] is False


def test_apply_choice_can_change_resolution(ctx):
    apply_choice(ctx, "architect-added-missing")
    apply_choice(ctx, "architect-accepted-custom-state-folding")
    path = ctx.repo_root / ".board-superpowers" / "settings.yml"
    data = yaml.safe_load(path.read_text())
    assert data["modules"]["m3_validate_status_field"]["resolution"] == \
        "architect-accepted-custom-state-folding"


def test_apply_choice_rejects_invalid(ctx):
    with pytest.raises(ValueError):
        apply_choice(ctx, "invalid-resolution")


def test_apply_choice_rejects_non_string(ctx):
    with pytest.raises((ValueError, TypeError)):
        apply_choice(ctx, 42)  # type: ignore[arg-type]


# ---------------------------------------------------------------------------
# Round-trip schema validation
# ---------------------------------------------------------------------------

def test_compute_target_state_validates_against_registry_schema(ctx):
    import jsonschema
    registry_path = Path(__file__).parent.parent / "stages-registry.yml"
    registry = yaml.safe_load(registry_path.read_text())
    stage = next(
        s for s in registry["stages"]
        if s["stage_id"] == "m3.repo.validate-status-field"
    )
    schema = stage["target_state_schema"]
    jsonschema.validate(instance=compute_target_state(ctx), schema=schema)


def test_compute_target_state_after_apply_choice_validates_schema(ctx):
    import jsonschema
    registry_path = Path(__file__).parent.parent / "stages-registry.yml"
    registry = yaml.safe_load(registry_path.read_text())
    stage = next(
        s for s in registry["stages"]
        if s["stage_id"] == "m3.repo.validate-status-field"
    )
    schema = stage["target_state_schema"]
    apply_choice(ctx, "architect-added-missing")
    jsonschema.validate(instance=compute_target_state(ctx), schema=schema)
