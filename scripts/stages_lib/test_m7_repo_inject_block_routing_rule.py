"""Tests for stages_lib.m7_repo_inject_block_routing_rule — routing-rule injection.

TDD: covers compute_target_state, target_state_predicate, idempotency_check,
executor (append/no-op/replace/stub-skip), user content preservation,
CLAUDE.md handling, and schema round-trip.

Run:  cd scripts && python3 -m pytest stages_lib/ -v
"""

from __future__ import annotations

import tempfile
from pathlib import Path
from types import SimpleNamespace

import jsonschema
import pytest
import yaml

from stages_lib.m7_repo_inject_block_routing_rule import (
    _BLOCK_CLOSE,
    _BLOCK_NAME,
    _BLOCK_OPEN,
    _ROUTING_RULE_CONTENT,
    compute_target_state,
    executor,
    idempotency_check,
    target_state_predicate,
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def make_ctx(home_dir: str, repo_dir: str, repo_identity: str = "test/repo") -> SimpleNamespace:
    return SimpleNamespace(
        home=Path(home_dir),
        repo_root=Path(repo_dir),
        repo_identity=repo_identity,
    )


def _seed_detect_cache(ctx: SimpleNamespace, form: str) -> None:
    """Seed the detect stage's cache so inject stages can find the form."""
    import stages_lib._partitioned_settings as _ps
    kwargs = {
        "home": ctx.home,
        "repo_root": ctx.repo_root,
        "repo_identity": ctx.repo_identity,
    }
    _ps.update_module_section(
        "repo-shared",
        "m7_agent_routing",
        {"agentsmd_form": {"form": form, "agentsmd_present": True, "claudemd_present": False}},
        **kwargs,
    )


_REGISTRY_PATH = Path(__file__).parent.parent / "stages-registry.yml"


def _get_registry_schema(stage_id: str) -> dict:
    registry = yaml.safe_load(_REGISTRY_PATH.read_text())
    for stage in registry["stages"]:
        if stage["stage_id"] == stage_id:
            return stage["target_state_schema"]
    raise KeyError(f"stage {stage_id!r} not found")


# ---------------------------------------------------------------------------
# compute_target_state()
# ---------------------------------------------------------------------------


def test_compute_target_state_block_name():
    """compute_target_state must return block_name='routing-rule'."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        ctx = make_ctx(h, r)
        _seed_detect_cache(ctx, "codex-only")
        state = compute_target_state(ctx)
        assert state["block_name"] == "routing-rule"


def test_compute_target_state_block_present_empty_initially():
    """block_present_in_targets must be empty when block not yet injected."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# No managed block yet\n")
        ctx = make_ctx(h, r)
        _seed_detect_cache(ctx, "codex-only")
        state = compute_target_state(ctx)
        assert state["block_present_in_targets"] == []


def test_compute_target_state_block_present_after_inject():
    """block_present_in_targets must include file after injection."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        ctx = make_ctx(h, r)
        _seed_detect_cache(ctx, "codex-only")
        executor(ctx)
        state = compute_target_state(ctx)
        assert "AGENTS.md" in state["block_present_in_targets"]


def test_compute_target_state_has_block_bytes():
    """compute_target_state must include block_bytes."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        ctx = make_ctx(h, r)
        _seed_detect_cache(ctx, "codex-only")
        state = compute_target_state(ctx)
        assert isinstance(state["block_bytes"], int)
        assert state["block_bytes"] > 0


# ---------------------------------------------------------------------------
# target_state_predicate()
# ---------------------------------------------------------------------------


def test_predicate_accepts_valid_state():
    state = {"block_name": "routing-rule", "block_present_in_targets": ["AGENTS.md"]}
    assert target_state_predicate(state) is True


def test_predicate_accepts_empty_targets():
    state = {"block_name": "routing-rule", "block_present_in_targets": []}
    assert target_state_predicate(state) is True


def test_predicate_rejects_wrong_block_name():
    state = {"block_name": "wrong", "block_present_in_targets": []}
    assert target_state_predicate(state) is False


def test_predicate_rejects_missing_block_name():
    state = {"block_present_in_targets": []}
    assert target_state_predicate(state) is False


def test_predicate_rejects_non_list_targets():
    state = {"block_name": "routing-rule", "block_present_in_targets": "AGENTS.md"}
    assert target_state_predicate(state) is False


def test_predicate_rejects_non_dict():
    assert target_state_predicate("not-a-dict") is False


# ---------------------------------------------------------------------------
# idempotency_check()
# ---------------------------------------------------------------------------


def test_idempotency_check_absent_block():
    """When block not present, present=False."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# No block here\n")
        ctx = make_ctx(h, r)
        _seed_detect_cache(ctx, "codex-only")
        result = idempotency_check(ctx)
        assert result["present"] is False


def test_idempotency_check_present_after_inject():
    """After injection, idempotency_check must report present=True."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        ctx = make_ctx(h, r)
        _seed_detect_cache(ctx, "codex-only")
        executor(ctx)
        result = idempotency_check(ctx)
        assert result["present"] is True


def test_idempotency_check_drifted_block():
    """When block marker present but content differs, present=False."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        agents = Path(r) / "AGENTS.md"
        agents.write_text(
            f"# AGENTS\n\n{_BLOCK_OPEN}\nold content\n{_BLOCK_CLOSE}\n"
        )
        ctx = make_ctx(h, r)
        _seed_detect_cache(ctx, "codex-only")
        result = idempotency_check(ctx)
        assert result["present"] is False


# ---------------------------------------------------------------------------
# executor() — core injection behavior
# ---------------------------------------------------------------------------


def test_executor_appends_block_when_absent():
    """executor must append managed block when AGENTS.md has no block."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# My Project\n\nUser content here.\n")
        ctx = make_ctx(h, r)
        _seed_detect_cache(ctx, "codex-only")
        result = executor(ctx)
        assert result["applied"] is True
        text = (Path(r) / "AGENTS.md").read_text()
        assert _BLOCK_OPEN in text
        assert _BLOCK_CLOSE in text
        assert _ROUTING_RULE_CONTENT in text


def test_executor_preserves_user_content():
    """executor must not remove content outside the managed block."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# My Project\n\nUser content here.\n")
        ctx = make_ctx(h, r)
        _seed_detect_cache(ctx, "codex-only")
        executor(ctx)
        text = (Path(r) / "AGENTS.md").read_text()
        assert "# My Project" in text
        assert "User content here." in text


def test_executor_noop_when_block_matches():
    """executor must return applied=False when block already matches."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        ctx = make_ctx(h, r)
        _seed_detect_cache(ctx, "codex-only")
        executor(ctx)
        before = (Path(r) / "AGENTS.md").read_text()
        result = executor(ctx)
        after = (Path(r) / "AGENTS.md").read_text()
        assert result["applied"] is False
        assert before == after


def test_executor_idempotent():
    """Running executor multiple times must produce identical file content."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        ctx = make_ctx(h, r)
        _seed_detect_cache(ctx, "codex-only")
        executor(ctx)
        content1 = (Path(r) / "AGENTS.md").read_text()
        executor(ctx)
        executor(ctx)
        content3 = (Path(r) / "AGENTS.md").read_text()
        assert content1 == content3


def test_executor_replaces_drifted_block():
    """executor must replace a managed block whose content no longer matches."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        agents = Path(r) / "AGENTS.md"
        agents.write_text(
            f"# AGENTS\n\n{_BLOCK_OPEN}\nold stale content\n{_BLOCK_CLOSE}\n\n# After section\n"
        )
        ctx = make_ctx(h, r)
        _seed_detect_cache(ctx, "codex-only")
        result = executor(ctx)
        assert result["applied"] is True
        text = agents.read_text()
        assert "old stale content" not in text
        assert _ROUTING_RULE_CONTENT in text
        assert "# After section" in text


def test_executor_preserves_content_around_replaced_block():
    """Replacement must preserve content before and after managed block."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        agents = Path(r) / "AGENTS.md"
        agents.write_text(
            f"# Pre-existing\n\n{_BLOCK_OPEN}\nold\n{_BLOCK_CLOSE}\n\n# Post-existing\n"
        )
        ctx = make_ctx(h, r)
        _seed_detect_cache(ctx, "codex-only")
        executor(ctx)
        text = agents.read_text()
        assert "# Pre-existing" in text
        assert "# Post-existing" in text


# ---------------------------------------------------------------------------
# CLAUDE.md stub-redirect handling
# ---------------------------------------------------------------------------


def test_executor_skips_stub_redirect_claude_md():
    """executor must skip CLAUDE.md when it is a stub-redirect (@-include file)."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        (Path(r) / "CLAUDE.md").write_text("@AGENTS.md\n")  # stub-redirect
        ctx = make_ctx(h, r)
        # Seed dual form so both files are targeted
        import stages_lib._partitioned_settings as _ps
        _ps.update_module_section(
            "repo-shared",
            "m7_agent_routing",
            {"agentsmd_form": {"form": "dual", "agentsmd_present": True, "claudemd_present": True}},
            home=ctx.home,
            repo_root=ctx.repo_root,
            repo_identity=ctx.repo_identity,
        )
        executor(ctx)
        claude_text = (Path(r) / "CLAUDE.md").read_text()
        assert _BLOCK_OPEN not in claude_text
        assert claude_text.strip() == "@AGENTS.md"


def test_executor_injects_into_non_stub_claude_md():
    """executor must inject into CLAUDE.md when it is NOT a stub-redirect."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        (Path(r) / "CLAUDE.md").write_text("# Full CLAUDE.md\n\nReal content here.\n")
        ctx = make_ctx(h, r)
        import stages_lib._partitioned_settings as _ps
        _ps.update_module_section(
            "repo-shared",
            "m7_agent_routing",
            {"agentsmd_form": {"form": "dual", "agentsmd_present": True, "claudemd_present": True}},
            home=ctx.home,
            repo_root=ctx.repo_root,
            repo_identity=ctx.repo_identity,
        )
        executor(ctx)
        claude_text = (Path(r) / "CLAUDE.md").read_text()
        assert _BLOCK_OPEN in claude_text


# ---------------------------------------------------------------------------
# Schema round-trip
# ---------------------------------------------------------------------------


def test_schema_roundtrip():
    """compute_target_state output must validate against registry schema."""
    schema = _get_registry_schema("m7.repo.inject-block.routing-rule")
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        ctx = make_ctx(h, r)
        _seed_detect_cache(ctx, "codex-only")
        state = compute_target_state(ctx)
        jsonschema.validate(instance=state, schema=schema)


def test_schema_roundtrip_after_inject():
    """compute_target_state output must validate after block injection."""
    schema = _get_registry_schema("m7.repo.inject-block.routing-rule")
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        ctx = make_ctx(h, r)
        _seed_detect_cache(ctx, "codex-only")
        executor(ctx)
        state = compute_target_state(ctx)
        jsonschema.validate(instance=state, schema=schema)
