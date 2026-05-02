"""Tests for stages_lib.m8_host_bootstrap_overrides_yml.

Stage: M8 | agentic | host-shared | both platforms
TDD: tests written to drive implementation.
Run: cd scripts && python3 -m pytest stages_lib/ -v

Key behaviors verified:
- 4-callable contract: all four callables present and callable
- apply_choice (5th callable): present and callable
- compute_target_state: returns prompt schema with options list + presets_selected
- target_state_predicate: accepts valid subset; rejects unknown presets and wrong type
- idempotency_check: absent (not configured) / present (configured, even with [])
- executor (agentic): returns requires_input when not configured; no-op when configured
- apply_choice: persists correctly; expands to autonomy_overrides; idempotent; rejects invalid
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
from stages_lib.m8_host_bootstrap_overrides_yml import (
    _ALL_PRESET_NAMES,
    _PRESET_CATALOG,
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
    import stages_lib.m8_host_bootstrap_overrides_yml as m
    for name in ["compute_target_state", "target_state_predicate",
                 "idempotency_check", "executor"]:
        assert callable(getattr(m, name, None)), f"{name} missing or not callable"


def test_apply_choice_present():
    import stages_lib.m8_host_bootstrap_overrides_yml as m
    assert callable(getattr(m, "apply_choice", None))


# ---------------------------------------------------------------------------
# Preset catalog
# ---------------------------------------------------------------------------


def test_preset_catalog_not_empty():
    assert len(_PRESET_CATALOG) > 0


def test_preset_catalog_has_required_fields():
    for p in _PRESET_CATALOG:
        assert "name" in p
        assert "action_id" in p
        assert "description" in p


def test_all_preset_names_consistent_with_catalog():
    catalog_names = {p["name"] for p in _PRESET_CATALOG}
    assert set(_ALL_PRESET_NAMES) == catalog_names


def test_preset_catalog_includes_known_presets():
    names = set(_ALL_PRESET_NAMES)
    assert "allow-split-card" in names
    assert "allow-close-stale-card" in names
    assert "allow-cancel-claim" in names
    assert "allow-pr-merge" in names


# ---------------------------------------------------------------------------
# compute_target_state() — prompt schema
# ---------------------------------------------------------------------------


def test_compute_target_state_returns_dict(ctx):
    state = compute_target_state(ctx)
    assert isinstance(state, dict)


def test_compute_target_state_has_presets_selected(ctx):
    state = compute_target_state(ctx)
    assert "presets_selected" in state


def test_compute_target_state_default_is_empty_list(ctx):
    """Fresh ctx → presets_selected should be []."""
    state = compute_target_state(ctx)
    assert state["presets_selected"] == []


def test_compute_target_state_has_presets_canon_known(ctx):
    state = compute_target_state(ctx)
    assert "presets_canon_known" in state
    assert isinstance(state["presets_canon_known"], list)
    assert len(state["presets_canon_known"]) > 0


def test_compute_target_state_canon_known_matches_catalog(ctx):
    state = compute_target_state(ctx)
    assert set(state["presets_canon_known"]) == set(_ALL_PRESET_NAMES)


def test_compute_target_state_reflects_persisted_selection(ctx):
    apply_choice(ctx, ["allow-pr-merge"])
    state = compute_target_state(ctx)
    assert "allow-pr-merge" in state["presets_selected"]


def test_compute_target_state_is_pure_before_write(ctx):
    s1 = compute_target_state(ctx)
    s2 = compute_target_state(ctx)
    assert s1 == s2


# ---------------------------------------------------------------------------
# target_state_predicate()
# ---------------------------------------------------------------------------


def test_target_state_predicate_valid_empty():
    """Empty selection is valid per ADR-0023."""
    assert target_state_predicate({"presets_selected": []}) is True


def test_target_state_predicate_valid_single(ctx):
    name = _ALL_PRESET_NAMES[0]
    assert target_state_predicate({"presets_selected": [name]}) is True


def test_target_state_predicate_valid_all():
    assert target_state_predicate({"presets_selected": list(_ALL_PRESET_NAMES)}) is True


def test_target_state_predicate_invalid_unknown_preset():
    assert target_state_predicate({"presets_selected": ["not-a-real-preset"]}) is False


def test_target_state_predicate_invalid_not_list():
    assert target_state_predicate({"presets_selected": "allow-pr-merge"}) is False


def test_target_state_predicate_invalid_missing_field():
    assert target_state_predicate({}) is False


def test_target_state_predicate_invalid_none_value():
    assert target_state_predicate({"presets_selected": None}) is False


def test_target_state_predicate_invalid_not_dict():
    assert target_state_predicate([]) is False


def test_target_state_predicate_invalid_list_of_non_strings():
    assert target_state_predicate({"presets_selected": [1, 2]}) is False


# ---------------------------------------------------------------------------
# idempotency_check() — not configured
# ---------------------------------------------------------------------------


def test_idempotency_check_absent(ctx):
    result = idempotency_check(ctx)
    assert result["present"] is False
    assert isinstance(result["current_state"], dict)
    assert result["current_state"]["presets_selected"] is None


# ---------------------------------------------------------------------------
# idempotency_check() — configured (even with empty selection)
# ---------------------------------------------------------------------------


def test_idempotency_check_present_after_apply_choice_empty(ctx):
    """Empty selection [] is a valid completed state per ADR-0023."""
    apply_choice(ctx, [])
    result = idempotency_check(ctx)
    assert result["present"] is True


def test_idempotency_check_present_after_apply_choice_with_preset(ctx):
    apply_choice(ctx, ["allow-split-card"])
    result = idempotency_check(ctx)
    assert result["present"] is True
    assert "allow-split-card" in result["current_state"]["presets_selected"]


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
    assert prompt.get("kind") == "multi-choice"


def test_executor_fresh_has_options(ctx):
    result = executor(ctx)
    assert "options" in result
    assert isinstance(result["options"], list)
    assert len(result["options"]) > 0


def test_executor_fresh_has_default_empty_list(ctx):
    result = executor(ctx)
    assert "default" in result
    assert result["default"] == []


def test_executor_fresh_has_message(ctx):
    result = executor(ctx)
    assert "message" in result
    assert isinstance(result["message"], str)


def test_executor_configured_no_op(ctx):
    """After apply_choice, executor should be a no-op."""
    apply_choice(ctx, [])
    result = executor(ctx)
    assert result["applied"] is False
    assert result.get("requires_input") is not True


def test_executor_configured_with_presets_no_op(ctx):
    apply_choice(ctx, ["allow-cancel-claim"])
    result = executor(ctx)
    assert result["applied"] is False
    assert result.get("requires_input") is not True


# ---------------------------------------------------------------------------
# apply_choice() — persistence
# ---------------------------------------------------------------------------


def test_apply_choice_empty_list(ctx):
    """Empty selection is valid completed state."""
    result = apply_choice(ctx, [])
    assert result["applied"] is True


def test_apply_choice_single_preset(ctx):
    result = apply_choice(ctx, ["allow-pr-merge"])
    assert result["applied"] is True


def test_apply_choice_all_presets(ctx):
    result = apply_choice(ctx, list(_ALL_PRESET_NAMES))
    assert result["applied"] is True


def test_apply_choice_persists_to_host_settings_yml(ctx):
    apply_choice(ctx, ["allow-split-card"])
    path = ctx.home / ".board-superpowers" / "settings.yml"
    assert path.exists()
    data = yaml.safe_load(path.read_text())
    m8 = data["modules"]["m8_autonomy"]
    assert "allow-split-card" in (m8.get("presets_selected") or m8.get("presets_chosen", []))


def test_apply_choice_expands_to_autonomy_overrides(ctx):
    """Chosen presets must expand to autonomy_overrides[] entries."""
    apply_choice(ctx, ["allow-pr-merge"])
    path = ctx.home / ".board-superpowers" / "settings.yml"
    data = yaml.safe_load(path.read_text())
    m8 = data["modules"]["m8_autonomy"]
    overrides = m8.get("autonomy_overrides", [])
    assert len(overrides) > 0
    # action_id 12 = auto-merge PR (from ADR-0006 §3 matrix)
    action_ids = [o["action_id"] for o in overrides]
    assert 12 in action_ids


def test_apply_choice_empty_produces_empty_overrides(ctx):
    apply_choice(ctx, [])
    path = ctx.home / ".board-superpowers" / "settings.yml"
    data = yaml.safe_load(path.read_text())
    m8 = data["modules"]["m8_autonomy"]
    assert m8.get("autonomy_overrides", []) == []


def test_apply_choice_returns_side_effects(ctx):
    result = apply_choice(ctx, [])
    assert isinstance(result["side_effects"], list)
    assert len(result["side_effects"]) > 0


def test_apply_choice_idempotent_same_selection(ctx):
    r1 = apply_choice(ctx, ["allow-split-card"])
    r2 = apply_choice(ctx, ["allow-split-card"])
    assert r1["applied"] is True
    assert r2["applied"] is False


def test_apply_choice_rejects_unknown_preset(ctx):
    with pytest.raises((ValueError, Exception)):
        apply_choice(ctx, ["not-a-real-preset"])


def test_apply_choice_rejects_non_string_in_list(ctx):
    with pytest.raises((ValueError, TypeError, Exception)):
        apply_choice(ctx, [1, 2])  # type: ignore[list-item]


def test_apply_choice_rejects_non_list(ctx):
    with pytest.raises((ValueError, TypeError, Exception)):
        apply_choice(ctx, "allow-pr-merge")  # type: ignore[arg-type]


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
        s
        for s in registry["stages"]
        if s["stage_id"] == "m8.host.bootstrap-overrides-yml"
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
        s
        for s in registry["stages"]
        if s["stage_id"] == "m8.host.bootstrap-overrides-yml"
    )
    schema = stage["target_state_schema"]
    apply_choice(ctx, ["allow-split-card", "allow-cancel-claim"])
    ts = compute_target_state(ctx)
    jsonschema.validate(instance=ts, schema=schema)
