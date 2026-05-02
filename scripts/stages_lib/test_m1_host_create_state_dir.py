"""Tests for stages_lib.m1_host_create_state_dir.

TDD: tests written first; run RED before implementation, GREEN after.
Run: cd scripts && python3 -m pytest stages_lib/ -v
"""

import os
import stat
from pathlib import Path
from types import SimpleNamespace

import pytest


# ---------------------------------------------------------------------------
# Import guard — fails RED until module exists
# ---------------------------------------------------------------------------
from stages_lib.m1_host_create_state_dir import (  # noqa: E402
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


# ---------------------------------------------------------------------------
# compute_target_state()
# ---------------------------------------------------------------------------


def test_compute_target_state_returns_dict(ctx):
    state = compute_target_state(ctx)
    assert isinstance(state, dict)


def test_compute_target_state_has_host_state_dir(ctx):
    state = compute_target_state(ctx)
    assert "host_state_dir" in state


def test_compute_target_state_host_state_dir_path(ctx):
    state = compute_target_state(ctx)
    expected = str(ctx.home / ".board-superpowers")
    assert state["host_state_dir"] == expected


def test_compute_target_state_has_mode(ctx):
    state = compute_target_state(ctx)
    assert "mode" in state
    # mode must be a 4-char octal string matching ^[0-7]{4}$
    assert len(state["mode"]) == 4


def test_compute_target_state_mode_value(ctx):
    state = compute_target_state(ctx)
    assert state["mode"] == "0700"


def test_compute_target_state_has_sentinel_subdir(ctx):
    state = compute_target_state(ctx)
    assert "sentinel_subdir" in state


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


def test_target_state_predicate_invalid_missing_host_state_dir():
    assert target_state_predicate({"mode": "0700"}) is False


def test_target_state_predicate_invalid_missing_mode():
    assert target_state_predicate({"host_state_dir": "/tmp/foo"}) is False


def test_target_state_predicate_invalid_mode_pattern():
    # mode must be 4 octal digits
    assert target_state_predicate({"host_state_dir": "/tmp/foo", "mode": "700"}) is False


def test_target_state_predicate_invalid_not_dict():
    assert target_state_predicate("string") is False


def test_target_state_predicate_accepts_optional_sentinel_subdir():
    state = {
        "host_state_dir": "/tmp/foo",
        "mode": "0700",
        "sentinel_subdir": "/tmp/foo/__host__",
    }
    assert target_state_predicate(state) is True


# ---------------------------------------------------------------------------
# idempotency_check() — directory absent
# ---------------------------------------------------------------------------


def test_idempotency_check_absent(ctx):
    result = idempotency_check(ctx)
    assert result["present"] is False
    assert isinstance(result["current_state"], dict)


def test_idempotency_check_absent_current_state(ctx):
    result = idempotency_check(ctx)
    cs = result["current_state"]
    # dir absent → no host_state_dir info
    assert cs.get("present") is False or "host_state_dir" not in cs or not cs.get("host_state_dir")


# ---------------------------------------------------------------------------
# idempotency_check() — directory present
# ---------------------------------------------------------------------------


def test_idempotency_check_present_correct(ctx):
    target = ctx.home / ".board-superpowers"
    target.mkdir(parents=True, mode=0o700)
    # Also create sentinel — both required for idempotency_check to return present=True
    (target / "__host__").mkdir(mode=0o700)
    result = idempotency_check(ctx)
    assert result["present"] is True


def test_idempotency_check_present_wrong_mode(ctx):
    target = ctx.home / ".board-superpowers"
    target.mkdir(parents=True, mode=0o755)
    result = idempotency_check(ctx)
    # Wrong mode → not present (needs repair)
    assert result["present"] is False


# ---------------------------------------------------------------------------
# executor() — creates directory
# ---------------------------------------------------------------------------


def test_executor_creates_dir(ctx):
    result = executor(ctx)
    assert result["applied"] is True
    target = ctx.home / ".board-superpowers"
    assert target.is_dir()


def test_executor_creates_sentinel_subdir(ctx):
    executor(ctx)
    sentinel = ctx.home / ".board-superpowers" / "__host__"
    assert sentinel.is_dir()


def test_executor_sets_mode_0700(ctx):
    executor(ctx)
    target = ctx.home / ".board-superpowers"
    mode = stat.S_IMODE(os.stat(target).st_mode)
    assert mode == 0o700


def test_executor_returns_side_effects(ctx):
    result = executor(ctx)
    assert isinstance(result["side_effects"], list)
    assert len(result["side_effects"]) > 0


# ---------------------------------------------------------------------------
# executor() — idempotency (no-op on second run)
# ---------------------------------------------------------------------------


def test_executor_idempotent(ctx):
    r1 = executor(ctx)
    r2 = executor(ctx)
    assert r1["applied"] is True
    assert r2["applied"] is False


def test_executor_second_run_no_extra_change(ctx):
    executor(ctx)
    target = ctx.home / ".board-superpowers"
    mtime_before = os.stat(target).st_mtime
    executor(ctx)
    # Directory contents unchanged; the dir should still be the same
    assert target.is_dir()
    sentinel = target / "__host__"
    assert sentinel.is_dir()


# ---------------------------------------------------------------------------
# executor() — repairs wrong mode
# ---------------------------------------------------------------------------


def test_executor_repairs_wrong_mode(ctx):
    target = ctx.home / ".board-superpowers"
    target.mkdir(parents=True, mode=0o755)
    result = executor(ctx)
    assert result["applied"] is True
    mode = stat.S_IMODE(os.stat(target).st_mode)
    assert mode == 0o700
