"""Tests for stages_lib.m7_repo_detect_agentsmd_form — M7 form-detection stage.

TDD: tests cover compute_target_state, target_state_predicate,
idempotency_check, executor, form detection logic, and schema round-trip.

Run:  cd scripts && python3 -m pytest stages_lib/ -v
"""

from __future__ import annotations

import json
import tempfile
from pathlib import Path
from types import SimpleNamespace

import jsonschema
import pytest
import yaml

from stages_lib.m7_repo_detect_agentsmd_form import (
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


# Load registry schema for round-trip tests
_REGISTRY_PATH = Path(__file__).parent.parent / "stages-registry.yml"


def _get_registry_schema(stage_id: str) -> dict:
    registry = yaml.safe_load(_REGISTRY_PATH.read_text())
    for stage in registry["stages"]:
        if stage["stage_id"] == stage_id:
            return stage["target_state_schema"]
    raise KeyError(f"stage {stage_id!r} not found in registry")


# ---------------------------------------------------------------------------
# compute_target_state()
# ---------------------------------------------------------------------------


def test_compute_target_state_neither():
    """When neither AGENTS.md nor CLAUDE.md present, form='neither'."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        ctx = make_ctx(h, r)
        state = compute_target_state(ctx)
        assert state["form"] == "neither"
        assert state["agentsmd_present"] is False
        assert state["claudemd_present"] is False


def test_compute_target_state_codex_only():
    """When only AGENTS.md present, form='codex-only'."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        ctx = make_ctx(h, r)
        state = compute_target_state(ctx)
        assert state["form"] == "codex-only"
        assert state["agentsmd_present"] is True
        assert state["claudemd_present"] is False


def test_compute_target_state_cc_only():
    """When only CLAUDE.md present, form='cc-only'."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "CLAUDE.md").write_text("# CLAUDE\n")
        ctx = make_ctx(h, r)
        state = compute_target_state(ctx)
        assert state["form"] == "cc-only"
        assert state["agentsmd_present"] is False
        assert state["claudemd_present"] is True


def test_compute_target_state_dual():
    """When both AGENTS.md and CLAUDE.md present, form='dual'."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        (Path(r) / "CLAUDE.md").write_text("# CLAUDE\n")
        ctx = make_ctx(h, r)
        state = compute_target_state(ctx)
        assert state["form"] == "dual"
        assert state["agentsmd_present"] is True
        assert state["claudemd_present"] is True


def test_compute_target_state_is_pure():
    """compute_target_state must return same result on repeated calls."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        ctx = make_ctx(h, r)
        s1 = compute_target_state(ctx)
        s2 = compute_target_state(ctx)
        assert s1 == s2


# ---------------------------------------------------------------------------
# target_state_predicate()
# ---------------------------------------------------------------------------


def test_predicate_accepts_valid_cc_only():
    assert target_state_predicate({"form": "cc-only"}) is True


def test_predicate_accepts_valid_codex_only():
    assert target_state_predicate({"form": "codex-only"}) is True


def test_predicate_accepts_valid_dual():
    assert target_state_predicate({"form": "dual"}) is True


def test_predicate_accepts_valid_neither():
    assert target_state_predicate({"form": "neither"}) is True


def test_predicate_rejects_missing_form():
    assert target_state_predicate({}) is False


def test_predicate_rejects_invalid_form_value():
    assert target_state_predicate({"form": "unknown"}) is False


def test_predicate_rejects_non_dict():
    assert target_state_predicate("not-a-dict") is False
    assert target_state_predicate(None) is False


# ---------------------------------------------------------------------------
# idempotency_check()
# ---------------------------------------------------------------------------


def test_idempotency_check_absent_cache():
    """When no cached form, present=False."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        ctx = make_ctx(h, r)
        result = idempotency_check(ctx)
        assert result["present"] is False


def test_idempotency_check_matching_cache():
    """When cached form matches detected form, present=True."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        ctx = make_ctx(h, r)
        # First run to populate cache
        executor(ctx)
        result = idempotency_check(ctx)
        assert result["present"] is True


def test_idempotency_check_stale_cache():
    """When cached form doesn't match detected form, present=False."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        # Populate cache with codex-only
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        ctx = make_ctx(h, r)
        executor(ctx)
        # Now add CLAUDE.md to make it dual — cache is stale
        (Path(r) / "CLAUDE.md").write_text("# CLAUDE\n")
        result = idempotency_check(ctx)
        assert result["present"] is False


# ---------------------------------------------------------------------------
# executor()
# ---------------------------------------------------------------------------


def test_executor_persists_form():
    """executor must detect form and persist to settings.yml."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        ctx = make_ctx(h, r)
        result = executor(ctx)
        assert result["applied"] is True
        assert "codex-only" in result["message"]


def test_executor_noop_when_cached():
    """executor must return applied=False when cached form matches."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        ctx = make_ctx(h, r)
        executor(ctx)
        result = executor(ctx)
        assert result["applied"] is False


def test_executor_idempotent():
    """Running executor multiple times must produce same result."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        ctx = make_ctx(h, r)
        r1 = executor(ctx)
        r2 = executor(ctx)
        r3 = executor(ctx)
        assert r1["applied"] is True
        assert r2["applied"] is False
        assert r3["applied"] is False


def test_executor_detects_neither():
    """executor handles repos with no AGENTS.md or CLAUDE.md."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        ctx = make_ctx(h, r)
        result = executor(ctx)
        assert result["applied"] is True
        assert "neither" in result["message"]


def test_executor_detects_dual():
    """executor handles repos with both AGENTS.md and CLAUDE.md."""
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        (Path(r) / "CLAUDE.md").write_text("# CLAUDE\n")
        ctx = make_ctx(h, r)
        result = executor(ctx)
        assert result["applied"] is True
        assert "dual" in result["message"]


# ---------------------------------------------------------------------------
# Schema round-trip
# ---------------------------------------------------------------------------


def test_schema_roundtrip():
    """compute_target_state output must validate against registry schema."""
    schema = _get_registry_schema("m7.repo.detect-agentsmd-form")
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        (Path(r) / "AGENTS.md").write_text("# AGENTS\n")
        ctx = make_ctx(h, r)
        state = compute_target_state(ctx)
        jsonschema.validate(instance=state, schema=schema)  # raises on violation


def test_schema_roundtrip_neither():
    """Schema must also accept form='neither'."""
    schema = _get_registry_schema("m7.repo.detect-agentsmd-form")
    with tempfile.TemporaryDirectory() as h, tempfile.TemporaryDirectory() as r:
        ctx = make_ctx(h, r)
        state = compute_target_state(ctx)
        jsonschema.validate(instance=state, schema=schema)
