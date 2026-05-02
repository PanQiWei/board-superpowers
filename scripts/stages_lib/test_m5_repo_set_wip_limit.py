"""Tests for stages_lib.m5_repo_set_wip_limit.

Stage: M5 | agentic | repo-clone | both platforms
TDD: tests written to drive implementation.
Run: cd scripts && python3 -m pytest stages_lib/ -v

Key behaviors verified:
- 4-callable contract: all four callables present and callable
- apply_choice (5th callable): present and callable
- compute_target_state: returns prompt schema with default wip_limit
- target_state_predicate: accepts int in 1..20; rejects out-of-range and wrong type
- idempotency_check: absent (not configured) / present (already configured)
- executor (agentic): returns requires_input when not configured; no-op when configured
- apply_choice: persists correctly; idempotent; rejects invalid values
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
from stages_lib.m5_repo_set_wip_limit import (
    apply_choice,
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
# Module-level callable contract
# ---------------------------------------------------------------------------


def test_four_callables_present():
    """All four ADR-0014 callables must exist."""
    import stages_lib.m5_repo_set_wip_limit as m
    for name in ["compute_target_state", "target_state_predicate",
                 "idempotency_check", "executor"]:
        assert callable(getattr(m, name, None)), f"{name} missing or not callable"


def test_apply_choice_present():
    """5th callable apply_choice must be present for agentic stages."""
    import stages_lib.m5_repo_set_wip_limit as m
    assert callable(getattr(m, "apply_choice", None))


# ---------------------------------------------------------------------------
# compute_target_state() — prompt schema
# ---------------------------------------------------------------------------


def test_compute_target_state_returns_dict(ctx):
    state = compute_target_state(ctx)
    assert isinstance(state, dict)


def test_compute_target_state_has_wip_limit(ctx):
    state = compute_target_state(ctx)
    assert "wip_limit" in state


def test_compute_target_state_default_wip_limit(ctx):
    """Fresh ctx should return default wip_limit=5."""
    state = compute_target_state(ctx)
    assert state["wip_limit"] == 5


def test_compute_target_state_returns_persisted_value(ctx):
    """Once apply_choice has run, compute_target_state reflects the persisted value."""
    apply_choice(ctx, 10)
    state = compute_target_state(ctx)
    assert state["wip_limit"] == 10


def test_compute_target_state_is_pure_before_write(ctx):
    s1 = compute_target_state(ctx)
    s2 = compute_target_state(ctx)
    assert s1 == s2


# ---------------------------------------------------------------------------
# target_state_predicate()
# ---------------------------------------------------------------------------


def test_target_state_predicate_valid_default():
    assert target_state_predicate({"wip_limit": 5}) is True


def test_target_state_predicate_valid_min():
    assert target_state_predicate({"wip_limit": 1}) is True


def test_target_state_predicate_valid_max():
    assert target_state_predicate({"wip_limit": 20}) is True


def test_target_state_predicate_invalid_zero():
    assert target_state_predicate({"wip_limit": 0}) is False


def test_target_state_predicate_invalid_21():
    assert target_state_predicate({"wip_limit": 21}) is False


def test_target_state_predicate_invalid_negative():
    assert target_state_predicate({"wip_limit": -1}) is False


def test_target_state_predicate_invalid_float():
    assert target_state_predicate({"wip_limit": 5.0}) is False


def test_target_state_predicate_invalid_string():
    assert target_state_predicate({"wip_limit": "5"}) is False


def test_target_state_predicate_invalid_missing():
    assert target_state_predicate({}) is False


def test_target_state_predicate_invalid_not_dict():
    assert target_state_predicate(5) is False


# ---------------------------------------------------------------------------
# idempotency_check() — not configured
# ---------------------------------------------------------------------------


def test_idempotency_check_absent(ctx):
    result = idempotency_check(ctx)
    assert result["present"] is False
    assert isinstance(result["current_state"], dict)
    assert result["current_state"]["wip_limit"] is None


# ---------------------------------------------------------------------------
# idempotency_check() — after apply_choice
# ---------------------------------------------------------------------------


def test_idempotency_check_present_after_apply_choice(ctx):
    apply_choice(ctx, 7)
    result = idempotency_check(ctx)
    assert result["present"] is True
    assert result["current_state"]["wip_limit"] == 7


def test_idempotency_check_reflects_updated_value(ctx):
    apply_choice(ctx, 3)
    apply_choice(ctx, 12)
    result = idempotency_check(ctx)
    assert result["current_state"]["wip_limit"] == 12


# ---------------------------------------------------------------------------
# executor() — agentic protocol
# ---------------------------------------------------------------------------


def test_executor_fresh_requires_input(ctx):
    """Fresh (not configured) → requires_input=True."""
    result = executor(ctx)
    assert result["applied"] is False
    assert result.get("requires_input") is True


def test_executor_fresh_has_prompt(ctx):
    result = executor(ctx)
    assert "prompt" in result
    prompt = result["prompt"]
    assert isinstance(prompt, dict)
    assert prompt.get("kind") == "numeric-range"


def test_executor_fresh_has_default(ctx):
    result = executor(ctx)
    assert "default" in result
    assert result["default"] == 5


def test_executor_fresh_has_message(ctx):
    result = executor(ctx)
    assert "message" in result
    assert isinstance(result["message"], str)


def test_executor_already_configured_no_op(ctx):
    """After apply_choice, executor should be a no-op."""
    apply_choice(ctx, 8)
    result = executor(ctx)
    assert result["applied"] is False
    assert result.get("requires_input") is not True


def test_executor_idempotent_no_side_effects_after_configure(ctx):
    apply_choice(ctx, 5)
    r1 = executor(ctx)
    r2 = executor(ctx)
    assert r1["applied"] is False
    assert r2["applied"] is False


# ---------------------------------------------------------------------------
# apply_choice() — persistence
# ---------------------------------------------------------------------------


def test_apply_choice_applies_value(ctx):
    result = apply_choice(ctx, 5)
    assert result["applied"] is True


def test_apply_choice_persists_to_settings_local_yml(ctx):
    apply_choice(ctx, 7)
    path = ctx.repo_root / ".board-superpowers" / "settings.local.yml"
    assert path.exists()
    data = yaml.safe_load(path.read_text())
    wip = data["modules"]["m5_repo_configuration"]["wip_limit"]
    assert wip == 7


def test_apply_choice_returns_side_effects(ctx):
    result = apply_choice(ctx, 5)
    assert isinstance(result["side_effects"], list)
    assert len(result["side_effects"]) > 0


def test_apply_choice_idempotent_same_value(ctx):
    r1 = apply_choice(ctx, 5)
    r2 = apply_choice(ctx, 5)
    assert r1["applied"] is True
    assert r2["applied"] is False


def test_apply_choice_updates_to_new_value(ctx):
    apply_choice(ctx, 5)
    r = apply_choice(ctx, 15)
    assert r["applied"] is True
    path = ctx.repo_root / ".board-superpowers" / "settings.local.yml"
    data = yaml.safe_load(path.read_text())
    assert data["modules"]["m5_repo_configuration"]["wip_limit"] == 15


def test_apply_choice_rejects_zero(ctx):
    with pytest.raises((ValueError, Exception)):
        apply_choice(ctx, 0)


def test_apply_choice_rejects_21(ctx):
    with pytest.raises((ValueError, Exception)):
        apply_choice(ctx, 21)


def test_apply_choice_rejects_string(ctx):
    with pytest.raises((ValueError, TypeError, Exception)):
        apply_choice(ctx, "5")  # type: ignore[arg-type]


def test_apply_choice_min_value(ctx):
    result = apply_choice(ctx, 1)
    assert result["applied"] is True


def test_apply_choice_max_value(ctx):
    result = apply_choice(ctx, 20)
    assert result["applied"] is True


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
        s for s in registry["stages"] if s["stage_id"] == "m5.repo.set-wip-limit"
    )
    schema = stage["target_state_schema"]
    ts = compute_target_state(ctx)
    jsonschema.validate(instance=ts, schema=schema)


def test_apply_choice_output_validates_against_registry_schema(ctx):
    """After apply_choice, compute_target_state must still validate."""
    import jsonschema
    registry_path = Path(__file__).parent.parent / "stages-registry.yml"
    registry = yaml.safe_load(registry_path.read_text())
    stage = next(
        s for s in registry["stages"] if s["stage_id"] == "m5.repo.set-wip-limit"
    )
    schema = stage["target_state_schema"]
    apply_choice(ctx, 10)
    ts = compute_target_state(ctx)
    jsonschema.validate(instance=ts, schema=schema)
