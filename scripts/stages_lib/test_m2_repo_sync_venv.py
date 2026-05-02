"""Tests for stages_lib.m2_repo_sync_venv.

TDD: tests written first; run RED before implementation, GREEN after.
Run: cd scripts && python3 -m pytest stages_lib/ -v

Stage runs `uv sync --project <repo>/.board-superpowers/` to materialize
the .venv. subprocess is mocked — no actual uv invocations in CI.
"""

import hashlib
import subprocess
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest


# ---------------------------------------------------------------------------
# Import guard — fails RED until module exists
# ---------------------------------------------------------------------------
from stages_lib.m2_repo_sync_venv import (  # noqa: E402
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
    repo = tmp_path / "repo"
    repo.mkdir()
    bsp_dir = repo / ".board-superpowers"
    bsp_dir.mkdir()
    (bsp_dir / "uv.lock").write_text("# uv lock file\nversion = 1\n")
    (bsp_dir / "pyproject.toml").write_text("[project]\nname = 'board-superpowers-runtime'\n")
    return SimpleNamespace(
        home=tmp_path / "home",
        repo_root=repo,
        repo_identity="test/repo",
    )


def _sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _make_fake_venv(repo_root: Path):
    """Create a minimal fake .venv structure (no real uv needed)."""
    venv = repo_root / ".board-superpowers" / ".venv"
    bin_dir = venv / "bin"
    bin_dir.mkdir(parents=True)
    (bin_dir / "python3").write_text("#!/bin/sh\nexec python3 \"$@\"\n")
    (bin_dir / "python3").chmod(0o755)
    return venv


# ---------------------------------------------------------------------------
# compute_target_state()
# ---------------------------------------------------------------------------


def test_compute_target_state_returns_dict(ctx):
    state = compute_target_state(ctx)
    assert isinstance(state, dict)


def test_compute_target_state_has_venv_path(ctx):
    state = compute_target_state(ctx)
    assert "venv_path" in state
    assert isinstance(state["venv_path"], str)


def test_compute_target_state_venv_path_under_bsp_dir(ctx):
    state = compute_target_state(ctx)
    expected_prefix = str(ctx.repo_root / ".board-superpowers")
    assert state["venv_path"].startswith(expected_prefix)


def test_compute_target_state_has_uv_lock_hash(ctx):
    state = compute_target_state(ctx)
    assert "uv_lock_hash" in state
    assert isinstance(state["uv_lock_hash"], str)


def test_compute_target_state_uv_lock_hash_is_hex64(ctx):
    state = compute_target_state(ctx)
    h = state["uv_lock_hash"]
    assert len(h) == 64
    int(h, 16)  # raises ValueError if not valid hex


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


def test_target_state_predicate_missing_venv_path():
    state = {"uv_lock_hash": "a" * 64}
    assert target_state_predicate(state) is False


def test_target_state_predicate_missing_uv_lock_hash():
    state = {"venv_path": "/repo/.board-superpowers/.venv"}
    assert target_state_predicate(state) is False


def test_target_state_predicate_empty_venv_path():
    state = {"venv_path": "", "uv_lock_hash": "a" * 64}
    assert target_state_predicate(state) is False


def test_target_state_predicate_invalid_hash_length():
    # hash must be hex 64 chars
    state = {"venv_path": "/repo/.board-superpowers/.venv", "uv_lock_hash": "abc"}
    assert target_state_predicate(state) is False


def test_target_state_predicate_not_dict():
    assert target_state_predicate("string") is False


# ---------------------------------------------------------------------------
# idempotency_check() — venv absent
# ---------------------------------------------------------------------------


def test_idempotency_check_absent(ctx):
    result = idempotency_check(ctx)
    assert result["present"] is False
    assert isinstance(result["current_state"], dict)


# ---------------------------------------------------------------------------
# idempotency_check() — venv present, lock unchanged
# ---------------------------------------------------------------------------


def test_idempotency_check_present_and_matching(ctx):
    """present=True when .venv/bin/python3 exists AND stored hash matches current uv.lock."""
    _make_fake_venv(ctx.repo_root)
    # Store the current hash in settings so idempotency_check sees it
    lock_hash = _sha256_of(ctx.repo_root / ".board-superpowers" / "uv.lock")
    from stages_lib._partitioned_settings import update_module_section
    update_module_section(
        "repo-clone", "m2_python_runtime",
        {"uv_lock_hash": lock_hash, "venv_path": str(ctx.repo_root / ".board-superpowers" / ".venv")},
        home=ctx.home, repo_root=ctx.repo_root, repo_identity=ctx.repo_identity,
    )
    result = idempotency_check(ctx)
    assert result["present"] is True


# ---------------------------------------------------------------------------
# idempotency_check() — venv present but lock drifted
# ---------------------------------------------------------------------------


def test_idempotency_check_present_but_lock_drifted(ctx):
    """present=False when hash in settings doesn't match current uv.lock."""
    _make_fake_venv(ctx.repo_root)
    from stages_lib._partitioned_settings import update_module_section
    # Store a stale hash
    update_module_section(
        "repo-clone", "m2_python_runtime",
        {"uv_lock_hash": "b" * 64, "venv_path": str(ctx.repo_root / ".board-superpowers" / ".venv")},
        home=ctx.home, repo_root=ctx.repo_root, repo_identity=ctx.repo_identity,
    )
    result = idempotency_check(ctx)
    assert result["present"] is False


# ---------------------------------------------------------------------------
# executor() — uv sync succeeds
# ---------------------------------------------------------------------------


def test_executor_calls_uv_sync(ctx):
    """executor invokes uv sync --project <bsp_dir>."""
    def fake_uv_sync(cmd, **kwargs):
        # Create a minimal .venv so idempotency_check passes afterwards
        _make_fake_venv(ctx.repo_root)
        m = MagicMock()
        m.returncode = 0
        m.stdout = b""
        m.stderr = b""
        return m

    with patch("subprocess.run", side_effect=fake_uv_sync) as mock_run:
        result = executor(ctx)

    assert result["applied"] is True
    # Verify uv sync was called with the project path
    calls = mock_run.call_args_list
    assert len(calls) >= 1
    first_cmd = calls[0][0][0]
    assert "uv" in first_cmd
    assert "sync" in first_cmd


def test_executor_persists_target_state(ctx):
    """executor persists venv_path + uv_lock_hash to repo-clone settings."""
    def fake_uv_sync(cmd, **kwargs):
        _make_fake_venv(ctx.repo_root)
        m = MagicMock()
        m.returncode = 0
        m.stdout = b""
        m.stderr = b""
        return m

    with patch("subprocess.run", side_effect=fake_uv_sync):
        executor(ctx)

    from stages_lib._partitioned_settings import get_module_section
    section = get_module_section(
        "repo-clone", "m2_python_runtime",
        home=ctx.home, repo_root=ctx.repo_root, repo_identity=ctx.repo_identity,
    )
    assert "uv_lock_hash" in section
    assert len(section["uv_lock_hash"]) == 64
    assert "venv_path" in section


def test_executor_returns_side_effects(ctx):
    def fake_uv_sync(cmd, **kwargs):
        _make_fake_venv(ctx.repo_root)
        m = MagicMock()
        m.returncode = 0
        m.stdout = b""
        m.stderr = b""
        return m

    with patch("subprocess.run", side_effect=fake_uv_sync):
        result = executor(ctx)

    assert isinstance(result["side_effects"], list)
    assert len(result["side_effects"]) > 0


# ---------------------------------------------------------------------------
# executor() — idempotency (no-op on second run)
# ---------------------------------------------------------------------------


def test_executor_idempotent(ctx):
    """Second executor() call is a no-op (applied=False) when venv up-to-date."""
    def fake_uv_sync(cmd, **kwargs):
        _make_fake_venv(ctx.repo_root)
        m = MagicMock()
        m.returncode = 0
        m.stdout = b""
        m.stderr = b""
        return m

    with patch("subprocess.run", side_effect=fake_uv_sync):
        r1 = executor(ctx)

    # Second call should be a no-op (venv present + hash matches)
    with patch("subprocess.run", side_effect=fake_uv_sync) as mock_run2:
        r2 = executor(ctx)

    assert r1["applied"] is True
    assert r2["applied"] is False
    mock_run2.assert_not_called()


# ---------------------------------------------------------------------------
# executor() — uv sync failure
# ---------------------------------------------------------------------------


def test_executor_handles_uv_sync_failure(ctx):
    """executor handles uv sync CalledProcessError gracefully."""
    with patch("subprocess.run") as mock_run:
        mock_run.side_effect = subprocess.CalledProcessError(
            1, ["uv", "sync"], output=b"", stderr=b"error: lockfile out of date"
        )
        result = executor(ctx)

    assert result["applied"] is False
    assert "message" in result
    assert result["side_effects"] == []


# ---------------------------------------------------------------------------
# Round-trip: compute_target_state output validates against registry schema
# ---------------------------------------------------------------------------


def test_compute_target_state_validates_against_registry_schema(ctx):
    """Round-trip: compute_target_state output MUST validate against the
    stage's target_state_schema declared in scripts/stages-registry.yml.
    Prevents registry/impl drift from being invisible to the test suite."""
    import yaml
    import jsonschema
    registry_path = Path(__file__).parent.parent / "stages-registry.yml"
    registry = yaml.safe_load(registry_path.read_text())
    stage = next(s for s in registry["stages"] if s["stage_id"] == "m2.repo.sync-venv")
    schema = stage["target_state_schema"]
    # ctx fixture already creates uv.lock under .board-superpowers/
    ts = compute_target_state(ctx)
    jsonschema.validate(instance=ts, schema=schema)
