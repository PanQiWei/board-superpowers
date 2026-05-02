"""Tests for stages_lib.m1_repo_write_state_yml.

TDD: tests written first; run RED before implementation, GREEN after.
Run: cd scripts && python3 -m pytest stages_lib/ -v
"""

from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml


# ---------------------------------------------------------------------------
# Import guard — fails RED until module exists
# ---------------------------------------------------------------------------
from stages_lib.m1_repo_write_state_yml import (  # noqa: E402
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


def test_compute_target_state_has_path(ctx):
    state = compute_target_state(ctx)
    assert "path" in state
    assert isinstance(state["path"], str)


def test_compute_target_state_path_value(ctx):
    state = compute_target_state(ctx)
    expected = str(
        ctx.home / ".board-superpowers" / "repos" / ctx.repo_identity / "settings.yml"
    )
    assert state["path"] == expected


def test_compute_target_state_has_schema_version(ctx):
    state = compute_target_state(ctx)
    assert "schema_version" in state
    assert isinstance(state["schema_version"], int)
    assert state["schema_version"] >= 1


def test_compute_target_state_has_repo_identity(ctx):
    state = compute_target_state(ctx)
    assert "repo_identity" in state
    assert state["repo_identity"] == ctx.repo_identity


def test_compute_target_state_is_pure(ctx):
    s1 = compute_target_state(ctx)
    s2 = compute_target_state(ctx)
    assert s1 == s2


def test_compute_target_state_uses_ctx_repo_identity(ctx):
    ctx.repo_identity = "owner/my-repo"
    state = compute_target_state(ctx)
    assert state["repo_identity"] == "owner/my-repo"


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


def test_target_state_predicate_invalid_not_dict():
    assert target_state_predicate("string") is False


def test_target_state_predicate_accepts_optional_fields():
    state = {
        "path": "/tmp/x.yml",
        "schema_version": 1,
        "repo_identity": "owner/repo",
        "stages_completed_present": True,
        "routing_blocks_present": False,
    }
    assert target_state_predicate(state) is True


# ---------------------------------------------------------------------------
# idempotency_check() — file absent
# ---------------------------------------------------------------------------


def test_idempotency_check_absent(ctx):
    result = idempotency_check(ctx)
    assert result["present"] is False
    assert isinstance(result["current_state"], dict)


# ---------------------------------------------------------------------------
# idempotency_check() — file present with matching state
# ---------------------------------------------------------------------------


def test_idempotency_check_present_matching(ctx):
    executor(ctx)
    result = idempotency_check(ctx)
    assert result["present"] is True


# ---------------------------------------------------------------------------
# idempotency_check() — file present but wrong repo_identity
# ---------------------------------------------------------------------------


def test_idempotency_check_present_wrong_repo_identity(ctx):
    settings_dir = ctx.home / ".board-superpowers" / "repos" / ctx.repo_identity
    settings_dir.mkdir(parents=True)
    settings_path = settings_dir / "settings.yml"
    data = {
        "setup": {
            "schema_version": 1,
            "repo_identity": "wrong/repo",
        },
        "modules": {},
    }
    settings_path.write_text(yaml.safe_dump(data))
    result = idempotency_check(ctx)
    assert result["present"] is False


# ---------------------------------------------------------------------------
# executor() — creates settings.yml
# ---------------------------------------------------------------------------


def test_executor_creates_file(ctx):
    result = executor(ctx)
    assert result["applied"] is True
    settings_path = (
        ctx.home / ".board-superpowers" / "repos" / ctx.repo_identity / "settings.yml"
    )
    assert settings_path.exists()


def test_executor_creates_parent_dir_if_needed(ctx):
    # No parent dir exists; executor must create it
    result = executor(ctx)
    assert result["applied"] is True
    settings_path = (
        ctx.home / ".board-superpowers" / "repos" / ctx.repo_identity / "settings.yml"
    )
    assert settings_path.exists()


def test_executor_writes_valid_yaml(ctx):
    executor(ctx)
    settings_path = (
        ctx.home / ".board-superpowers" / "repos" / ctx.repo_identity / "settings.yml"
    )
    data = yaml.safe_load(settings_path.read_text())
    assert isinstance(data, dict)


def test_executor_writes_setup_section_with_repo_identity(ctx):
    executor(ctx)
    settings_path = (
        ctx.home / ".board-superpowers" / "repos" / ctx.repo_identity / "settings.yml"
    )
    data = yaml.safe_load(settings_path.read_text())
    assert "setup" in data
    assert data["setup"]["repo_identity"] == ctx.repo_identity


def test_executor_writes_modules_section(ctx):
    executor(ctx)
    settings_path = (
        ctx.home / ".board-superpowers" / "repos" / ctx.repo_identity / "settings.yml"
    )
    data = yaml.safe_load(settings_path.read_text())
    assert "modules" in data


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


def test_executor_second_run_preserves_content(ctx):
    executor(ctx)
    settings_path = (
        ctx.home / ".board-superpowers" / "repos" / ctx.repo_identity / "settings.yml"
    )
    content_1 = settings_path.read_text()
    executor(ctx)
    content_2 = settings_path.read_text()
    assert content_1 == content_2


# ---------------------------------------------------------------------------
# executor() — different repo identities are isolated
# ---------------------------------------------------------------------------


def test_executor_isolates_repo_identities(ctx):
    ctx2 = SimpleNamespace(
        home=ctx.home,
        repo_root=ctx.repo_root,
        repo_identity="owner/other-repo",
    )
    executor(ctx)
    executor(ctx2)
    path1 = ctx.home / ".board-superpowers" / "repos" / "test/repo" / "settings.yml"
    path2 = ctx.home / ".board-superpowers" / "repos" / "owner/other-repo" / "settings.yml"
    assert path1.exists()
    assert path2.exists()
    data1 = yaml.safe_load(path1.read_text())
    data2 = yaml.safe_load(path2.read_text())
    assert data1["setup"]["repo_identity"] == "test/repo"
    assert data2["setup"]["repo_identity"] == "owner/other-repo"
