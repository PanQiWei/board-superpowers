"""Tests for stages_lib.m9_host_register_codex_hooks.

TDD: tests written to drive implementation.
Run: cd scripts && python3 -m pytest stages_lib/ -v

ADR-0016: this stage is codex-only; CC skips it at lifecycle engine level.
The Python module is platform-agnostic — tests run on both platforms.

Key behaviors verified:
- 4-callable contract: all four callables present and callable
- compute_target_state: returns expected shape; registered reflects hook reachability
- target_state_predicate: accepts/rejects per schema
- idempotency_check: absent / present-no-bsp / present-with-bsp
- executor: fresh (creates) / merge (preserves user hooks) / idempotent (twice = no change)
- round-trip: compute_target_state output validates against registry target_state_schema
"""

from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import pytest

# ---------------------------------------------------------------------------
# Import guard — fails RED until module exists
# ---------------------------------------------------------------------------
from stages_lib.m9_host_register_codex_hooks import (  # noqa: E402
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


@pytest.fixture
def fake_plugin_root(tmp_path):
    """Create a minimal fake plugin root with hooks/session-start.sh."""
    root = tmp_path / "plugin"
    hooks_dir = root / "hooks"
    hooks_dir.mkdir(parents=True)
    hook_script = hooks_dir / "session-start.sh"
    hook_script.write_text("#!/usr/bin/env bash\necho hi\n")
    return root


@pytest.fixture
def ctx_with_plugin(ctx, fake_plugin_root):
    """ctx with CLAUDE_PLUGIN_ROOT pointing at a fake plugin root."""
    return ctx, fake_plugin_root


# ---------------------------------------------------------------------------
# 4-callable contract check
# ---------------------------------------------------------------------------


def test_four_callables_present():
    """ADR-0014: module must export exactly the four named callables."""
    import stages_lib.m9_host_register_codex_hooks as mod
    for name in ("compute_target_state", "target_state_predicate",
                 "idempotency_check", "executor"):
        assert callable(getattr(mod, name, None)), f"{name} missing or not callable"


# ---------------------------------------------------------------------------
# compute_target_state()
# ---------------------------------------------------------------------------


def test_compute_target_state_returns_dict(ctx, fake_plugin_root):
    with patch.dict("os.environ", {"CLAUDE_PLUGIN_ROOT": str(fake_plugin_root)}):
        state = compute_target_state(ctx)
    assert isinstance(state, dict)


def test_compute_target_state_required_keys(ctx, fake_plugin_root):
    with patch.dict("os.environ", {"CLAUDE_PLUGIN_ROOT": str(fake_plugin_root)}):
        state = compute_target_state(ctx)
    assert "registered" in state
    assert "config_toml_path" in state


def test_compute_target_state_registered_true_when_hook_found(ctx, fake_plugin_root):
    with patch.dict("os.environ", {"CLAUDE_PLUGIN_ROOT": str(fake_plugin_root)}):
        state = compute_target_state(ctx)
    assert state["registered"] is True


def test_compute_target_state_config_toml_path_contains_hooks_json(ctx, fake_plugin_root):
    with patch.dict("os.environ", {"CLAUDE_PLUGIN_ROOT": str(fake_plugin_root)}):
        state = compute_target_state(ctx)
    assert state["config_toml_path"].endswith("hooks.json")


def test_compute_target_state_hook_target_points_to_session_start(ctx, fake_plugin_root):
    with patch.dict("os.environ", {"CLAUDE_PLUGIN_ROOT": str(fake_plugin_root)}):
        state = compute_target_state(ctx)
    assert state.get("hook_target") is not None
    assert "session-start.sh" in state["hook_target"]


def test_compute_target_state_registered_false_when_plugin_root_missing(ctx):
    """When plugin root cannot be resolved (neither env var nor path-walk), registered=False."""
    with patch("stages_lib.m9_host_register_codex_hooks._resolve_plugin_root", return_value=None):
        state = compute_target_state(ctx)
    assert state["registered"] is False
    assert state.get("hook_target") is None


# ---------------------------------------------------------------------------
# target_state_predicate()
# ---------------------------------------------------------------------------


def test_target_state_predicate_valid_registered():
    state = {"registered": True, "config_toml_path": "/home/user/.codex/hooks.json"}
    assert target_state_predicate(state) is True


def test_target_state_predicate_registered_false_fails():
    state = {"registered": False, "config_toml_path": "/home/user/.codex/hooks.json"}
    assert target_state_predicate(state) is False


def test_target_state_predicate_missing_registered_fails():
    state = {"config_toml_path": "/home/user/.codex/hooks.json"}
    assert target_state_predicate(state) is False


def test_target_state_predicate_not_dict_fails():
    assert target_state_predicate("string") is False
    assert target_state_predicate(None) is False


def test_target_state_predicate_empty_config_toml_path_fails():
    state = {"registered": True, "config_toml_path": ""}
    assert target_state_predicate(state) is False


def test_target_state_predicate_minimal_registered_only():
    """registered: True alone is sufficient — other fields are optional."""
    assert target_state_predicate({"registered": True}) is True


# ---------------------------------------------------------------------------
# idempotency_check()
# ---------------------------------------------------------------------------


def test_idempotency_check_absent_hooks_json(ctx):
    """hooks.json absent → present=False."""
    result = idempotency_check(ctx)
    assert result["present"] is False
    assert isinstance(result["current_state"], dict)


def test_idempotency_check_hooks_json_exists_no_bsp(ctx):
    """hooks.json present but no board-superpowers entry → present=False."""
    hooks_json = ctx.home / ".codex" / "hooks.json"
    hooks_json.parent.mkdir(parents=True)
    hooks_json.write_text(json.dumps({
        "hooks": {
            "PreToolUse": [{"type": "command", "command": "echo other", "name": "other-plugin"}]
        }
    }))
    result = idempotency_check(ctx)
    assert result["present"] is False


def test_idempotency_check_hooks_json_exists_with_bsp(ctx, fake_plugin_root):
    """hooks.json present with correct board-superpowers entry → present=True."""
    hook_script = str(fake_plugin_root / "hooks" / "session-start.sh")
    hooks_json = ctx.home / ".codex" / "hooks.json"
    hooks_json.parent.mkdir(parents=True)
    hooks_json.write_text(json.dumps({
        "hooks": {
            "SessionStart": [{
                "type": "command",
                "command": f"bash {hook_script}",
                "timeout": 10,
                "name": "board-superpowers",
            }]
        }
    }))
    with patch.dict("os.environ", {"CLAUDE_PLUGIN_ROOT": str(fake_plugin_root)}):
        result = idempotency_check(ctx)
    assert result["present"] is True


# ---------------------------------------------------------------------------
# executor() — creates fresh hooks.json
# ---------------------------------------------------------------------------


def test_executor_creates_hooks_json_when_absent(ctx, fake_plugin_root):
    with patch.dict("os.environ", {"CLAUDE_PLUGIN_ROOT": str(fake_plugin_root)}):
        result = executor(ctx)
    assert result["applied"] is True
    hooks_json = ctx.home / ".codex" / "hooks.json"
    assert hooks_json.is_file()


def test_executor_registers_session_start_hook(ctx, fake_plugin_root):
    with patch.dict("os.environ", {"CLAUDE_PLUGIN_ROOT": str(fake_plugin_root)}):
        executor(ctx)
    hooks_json = ctx.home / ".codex" / "hooks.json"
    data = json.loads(hooks_json.read_text())
    session_start = data.get("hooks", {}).get("SessionStart", [])
    bsp = [e for e in session_start if e.get("name") == "board-superpowers"]
    assert len(bsp) == 1
    assert "session-start.sh" in bsp[0]["command"]


# ---------------------------------------------------------------------------
# executor() — merges into existing hooks.json, preserves user hooks
# ---------------------------------------------------------------------------


def test_executor_preserves_user_defined_hooks(ctx, fake_plugin_root):
    """Existing unrelated hooks must survive the merge."""
    hooks_json = ctx.home / ".codex" / "hooks.json"
    hooks_json.parent.mkdir(parents=True)
    hooks_json.write_text(json.dumps({
        "hooks": {
            "PreToolUse": [{"type": "command", "command": "echo user_hook", "name": "user-plugin"}]
        }
    }))
    with patch.dict("os.environ", {"CLAUDE_PLUGIN_ROOT": str(fake_plugin_root)}):
        result = executor(ctx)
    assert result["applied"] is True
    after = json.loads(hooks_json.read_text())
    pre_hooks = after.get("hooks", {}).get("PreToolUse", [])
    user_hooks = [h for h in pre_hooks if h.get("name") == "user-plugin"]
    assert len(user_hooks) == 1, "user hook was lost during merge"


def test_executor_does_not_duplicate_session_start(ctx, fake_plugin_root):
    """Running executor twice must not create duplicate SessionStart entries."""
    with patch.dict("os.environ", {"CLAUDE_PLUGIN_ROOT": str(fake_plugin_root)}):
        executor(ctx)
        executor(ctx)
    hooks_json = ctx.home / ".codex" / "hooks.json"
    data = json.loads(hooks_json.read_text())
    bsp = [e for e in data["hooks"]["SessionStart"] if e.get("name") == "board-superpowers"]
    assert len(bsp) == 1, f"expected 1 bsp entry, got {len(bsp)}"


# ---------------------------------------------------------------------------
# executor() — idempotency: second run returns applied=False
# ---------------------------------------------------------------------------


def test_executor_idempotent_second_run_returns_applied_false(ctx, fake_plugin_root):
    """Second executor call → applied=False (idempotency invariant)."""
    with patch.dict("os.environ", {"CLAUDE_PLUGIN_ROOT": str(fake_plugin_root)}):
        r1 = executor(ctx)
        r2 = executor(ctx)
    assert r1["applied"] is True
    assert r2["applied"] is False, f"IDEMPOTENCY VIOLATION: second run returned applied=True: {r2}"


# ---------------------------------------------------------------------------
# Round-trip: compute_target_state validates against registry schema
# ---------------------------------------------------------------------------


def test_compute_target_state_validates_against_registry_schema(ctx, fake_plugin_root):
    """Round-trip: compute_target_state output MUST validate against
    m9.host.register-codex-hooks target_state_schema in stages-registry.yml.
    Prevents registry/impl drift from being invisible to the test suite."""
    import yaml
    import jsonschema

    registry_path = Path(__file__).parent.parent / "stages-registry.yml"
    registry = yaml.safe_load(registry_path.read_text())
    stage = next(
        s for s in registry["stages"]
        if s["stage_id"] == "m9.host.register-codex-hooks"
    )
    schema = stage["target_state_schema"]

    with patch.dict("os.environ", {"CLAUDE_PLUGIN_ROOT": str(fake_plugin_root)}):
        ts = compute_target_state(ctx)

    jsonschema.validate(instance=ts, schema=schema)
