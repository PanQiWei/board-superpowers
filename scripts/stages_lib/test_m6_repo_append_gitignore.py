"""Tests for stages_lib.m6_repo_append_gitignore — the M6 walking-skeleton stage.

TDD: these tests are written before the implementation.
Run:  cd scripts && python3 -m pytest stages_lib/ -v
"""

import pathlib
import tempfile
from types import SimpleNamespace

import pytest


# ---------------------------------------------------------------------------
# Import guard — will fail (RED) until the module exists.
# ---------------------------------------------------------------------------
from stages_lib.m6_repo_append_gitignore import (  # noqa: E402
    compute_target_state,
    executor,
    idempotency_check,
    target_state_predicate,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

MANAGED_OPEN = "# >>> board-superpowers managed >>>"
MANAGED_CLOSE = "# <<< board-superpowers managed <<<"


def make_ctx(tmpdir: str) -> SimpleNamespace:
    return SimpleNamespace(repo_root=pathlib.Path(tmpdir))


# ---------------------------------------------------------------------------
# compute_target_state()
# ---------------------------------------------------------------------------


def test_compute_target_state_returns_dict():
    """compute_target_state must return a dict."""
    with tempfile.TemporaryDirectory() as td:
        ctx = make_ctx(td)
        state = compute_target_state(ctx)
        assert isinstance(state, dict)


def test_compute_target_state_has_required_entries_key():
    """compute_target_state must return a dict with 'required_entries' key."""
    with tempfile.TemporaryDirectory() as td:
        ctx = make_ctx(td)
        state = compute_target_state(ctx)
        assert "required_entries" in state


def test_compute_target_state_entries_are_expected():
    """compute_target_state must include *.local.*, claims/, and .venv/."""
    with tempfile.TemporaryDirectory() as td:
        ctx = make_ctx(td)
        state = compute_target_state(ctx)
        entries = state["required_entries"]
        assert "*.local.*" in entries
        assert "claims/" in entries
        assert ".venv/" in entries


def test_compute_target_state_is_pure():
    """compute_target_state must return the same result on repeated calls."""
    with tempfile.TemporaryDirectory() as td:
        ctx = make_ctx(td)
        s1 = compute_target_state(ctx)
        s2 = compute_target_state(ctx)
        assert s1 == s2


# ---------------------------------------------------------------------------
# target_state_predicate()
# ---------------------------------------------------------------------------


def test_target_state_predicate_accepts_valid_state():
    """target_state_predicate must return True for a valid state dict."""
    state = {"required_entries": ["*.local.*", "claims/", ".venv/"]}
    assert target_state_predicate(state) is True


def test_target_state_predicate_rejects_missing_key():
    """target_state_predicate must return False when required_entries key is absent."""
    assert target_state_predicate({}) is False


def test_target_state_predicate_rejects_wrong_type():
    """target_state_predicate must return False when required_entries is not a list."""
    assert target_state_predicate({"required_entries": "not-a-list"}) is False


def test_target_state_predicate_accepts_empty_entries():
    """target_state_predicate must accept an empty list (schema allows it structurally)."""
    assert target_state_predicate({"required_entries": []}) is True


# ---------------------------------------------------------------------------
# idempotency_check() — file-absent case
# ---------------------------------------------------------------------------


def test_idempotency_check_absent_returns_not_present():
    """When .gitignore is absent, idempotency_check must report present=False."""
    with tempfile.TemporaryDirectory() as td:
        ctx = make_ctx(td)
        result = idempotency_check(ctx)
        assert result["present"] is False
        assert result["current_state"]["required_entries"] == []


# ---------------------------------------------------------------------------
# idempotency_check() — managed block absent
# ---------------------------------------------------------------------------


def test_idempotency_check_no_managed_block():
    """When .gitignore has no managed block, idempotency_check reports present=False."""
    with tempfile.TemporaryDirectory() as td:
        ctx = make_ctx(td)
        gi = pathlib.Path(td) / ".gitignore"
        gi.write_text("# some existing entries\n__pycache__/\n")
        result = idempotency_check(ctx)
        assert result["present"] is False


# ---------------------------------------------------------------------------
# executor() — fresh repo (no .gitignore)
# ---------------------------------------------------------------------------


def test_executor_creates_gitignore_when_absent():
    """executor must create .gitignore with managed block when file is absent."""
    with tempfile.TemporaryDirectory() as td:
        ctx = make_ctx(td)
        result = executor(ctx)
        assert result["applied"] is True
        gi = pathlib.Path(td) / ".gitignore"
        assert gi.exists()
        content = gi.read_text()
        assert MANAGED_OPEN in content
        assert MANAGED_CLOSE in content


def test_executor_injects_all_three_entries():
    """executor must inject all three required entries into the managed block."""
    with tempfile.TemporaryDirectory() as td:
        ctx = make_ctx(td)
        executor(ctx)
        content = (pathlib.Path(td) / ".gitignore").read_text()
        assert "*.local.*" in content
        assert "claims/" in content
        assert ".venv/" in content


# ---------------------------------------------------------------------------
# executor() — managed block already matches (no-op)
# ---------------------------------------------------------------------------


def test_executor_noop_when_block_matches():
    """executor must return applied=False when managed block already matches target."""
    with tempfile.TemporaryDirectory() as td:
        ctx = make_ctx(td)
        # First run
        executor(ctx)
        before = (pathlib.Path(td) / ".gitignore").read_text()
        # Second run
        result = executor(ctx)
        after = (pathlib.Path(td) / ".gitignore").read_text()
        assert result["applied"] is False
        assert before == after


# ---------------------------------------------------------------------------
# executor() — idempotency (run N times = run once)
# ---------------------------------------------------------------------------


def test_executor_idempotent():
    """Running executor multiple times must produce identical .gitignore content."""
    with tempfile.TemporaryDirectory() as td:
        ctx = make_ctx(td)
        executor(ctx)
        content_after_1 = (pathlib.Path(td) / ".gitignore").read_text()
        executor(ctx)
        executor(ctx)
        content_after_3 = (pathlib.Path(td) / ".gitignore").read_text()
        assert content_after_1 == content_after_3


# ---------------------------------------------------------------------------
# executor() — managed block drifts (replacement)
# ---------------------------------------------------------------------------


def test_executor_replaces_drifted_block():
    """executor must replace a managed block whose content no longer matches target."""
    with tempfile.TemporaryDirectory() as td:
        ctx = make_ctx(td)
        gi = pathlib.Path(td) / ".gitignore"
        # Write a managed block with stale content
        stale = (
            "# pre-existing\n"
            + MANAGED_OPEN
            + "\n"
            + "old-entry/\n"
            + MANAGED_CLOSE
            + "\n"
            + "# post-existing\n"
        )
        gi.write_text(stale)
        result = executor(ctx)
        assert result["applied"] is True
        content = gi.read_text()
        assert "old-entry/" not in content
        assert "*.local.*" in content
        assert "# pre-existing" in content
        assert "# post-existing" in content


# ---------------------------------------------------------------------------
# executor() — preserves pre-existing non-managed content
# ---------------------------------------------------------------------------


def test_executor_preserves_existing_content():
    """executor must not remove non-managed .gitignore entries."""
    with tempfile.TemporaryDirectory() as td:
        ctx = make_ctx(td)
        gi = pathlib.Path(td) / ".gitignore"
        gi.write_text("__pycache__/\nnode_modules/\n")
        executor(ctx)
        content = gi.read_text()
        assert "__pycache__/" in content
        assert "node_modules/" in content
