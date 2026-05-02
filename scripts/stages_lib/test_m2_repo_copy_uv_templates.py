"""Tests for stages_lib.m2_repo_copy_uv_templates.

TDD: tests written first; run RED before implementation, GREEN after.
Run: cd scripts && python3 -m pytest stages_lib/ -v

Stage copies pyproject.toml + uv.lock from plugin's scripts/templates/
into <repo>/.board-superpowers/.
"""

import hashlib
from pathlib import Path
from types import SimpleNamespace

import pytest


# ---------------------------------------------------------------------------
# Import guard — fails RED until module exists
# ---------------------------------------------------------------------------
from stages_lib.m2_repo_copy_uv_templates import (  # noqa: E402
    compute_target_state,
    executor,
    idempotency_check,
    target_state_predicate,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def plugin_templates(tmp_path):
    """Fake plugin templates directory with pyproject.toml + uv.lock."""
    tpl = tmp_path / "plugin" / "scripts" / "templates"
    tpl.mkdir(parents=True)
    (tpl / "pyproject.toml").write_text("[project]\nname = 'board-superpowers-runtime'\n")
    (tpl / "uv.lock").write_text("# uv lock file\nversion = 1\n")
    return tpl


@pytest.fixture
def ctx(tmp_path, plugin_templates):
    repo = tmp_path / "repo"
    repo.mkdir()
    ns = SimpleNamespace(
        home=tmp_path / "home",
        repo_root=repo,
        repo_identity="test/repo",
        _plugin_templates_dir=plugin_templates,  # test-only override
    )
    return ns


# ---------------------------------------------------------------------------
# compute_target_state()
# ---------------------------------------------------------------------------


def test_compute_target_state_returns_dict(ctx):
    state = compute_target_state(ctx)
    assert isinstance(state, dict)


def test_compute_target_state_has_pyproject_path(ctx):
    state = compute_target_state(ctx)
    assert "pyproject_path" in state
    assert isinstance(state["pyproject_path"], str)


def test_compute_target_state_has_uv_lock_path(ctx):
    state = compute_target_state(ctx)
    assert "uv_lock_path" in state
    assert isinstance(state["uv_lock_path"], str)


def test_compute_target_state_paths_under_repo_board_superpowers(ctx):
    state = compute_target_state(ctx)
    bsp_dir = str(ctx.repo_root / ".board-superpowers")
    assert state["pyproject_path"].startswith(bsp_dir)
    assert state["uv_lock_path"].startswith(bsp_dir)


def test_compute_target_state_includes_sha256s(ctx):
    state = compute_target_state(ctx)
    # sha256 fields optional in schema but must be strings if present
    if "pyproject_sha256" in state:
        assert isinstance(state["pyproject_sha256"], str)
    if "uv_lock_sha256" in state:
        assert isinstance(state["uv_lock_sha256"], str)


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


def test_target_state_predicate_missing_pyproject_path():
    assert target_state_predicate({"uv_lock_path": "/repo/.board-superpowers/uv.lock"}) is False


def test_target_state_predicate_missing_uv_lock_path():
    assert target_state_predicate({"pyproject_path": "/repo/.board-superpowers/pyproject.toml"}) is False


def test_target_state_predicate_empty_pyproject_path():
    state = {"pyproject_path": "", "uv_lock_path": "/repo/.board-superpowers/uv.lock"}
    assert target_state_predicate(state) is False


def test_target_state_predicate_empty_uv_lock_path():
    state = {"pyproject_path": "/repo/.board-superpowers/pyproject.toml", "uv_lock_path": ""}
    assert target_state_predicate(state) is False


def test_target_state_predicate_not_dict():
    assert target_state_predicate("string") is False


# ---------------------------------------------------------------------------
# idempotency_check() — files absent
# ---------------------------------------------------------------------------


def test_idempotency_check_absent(ctx):
    result = idempotency_check(ctx)
    assert result["present"] is False
    assert isinstance(result["current_state"], dict)


# ---------------------------------------------------------------------------
# idempotency_check() — files present and matching
# ---------------------------------------------------------------------------


def test_idempotency_check_present_matching(ctx):
    # Copy templates to repo dir first
    executor(ctx)
    result = idempotency_check(ctx)
    assert result["present"] is True


# ---------------------------------------------------------------------------
# idempotency_check() — files present but drifted
# ---------------------------------------------------------------------------


def test_idempotency_check_present_but_drifted(ctx):
    """If files exist but content differs from templates, present=False."""
    executor(ctx)
    # Modify one file to simulate drift
    bsp_dir = ctx.repo_root / ".board-superpowers"
    (bsp_dir / "pyproject.toml").write_text("[project]\nname = 'something-else'\n")
    result = idempotency_check(ctx)
    assert result["present"] is False


# ---------------------------------------------------------------------------
# executor() — copies files
# ---------------------------------------------------------------------------


def test_executor_creates_bsp_dir(ctx):
    result = executor(ctx)
    assert result["applied"] is True
    bsp_dir = ctx.repo_root / ".board-superpowers"
    assert bsp_dir.is_dir()


def test_executor_copies_pyproject_toml(ctx):
    executor(ctx)
    dest = ctx.repo_root / ".board-superpowers" / "pyproject.toml"
    assert dest.exists()


def test_executor_copies_uv_lock(ctx):
    executor(ctx)
    dest = ctx.repo_root / ".board-superpowers" / "uv.lock"
    assert dest.exists()


def test_executor_content_matches_template(ctx):
    executor(ctx)
    src_py = ctx._plugin_templates_dir / "pyproject.toml"
    dst_py = ctx.repo_root / ".board-superpowers" / "pyproject.toml"
    assert dst_py.read_bytes() == src_py.read_bytes()


def test_executor_returns_side_effects(ctx):
    result = executor(ctx)
    assert isinstance(result["side_effects"], list)
    assert len(result["side_effects"]) > 0


# ---------------------------------------------------------------------------
# executor() — idempotency
# ---------------------------------------------------------------------------


def test_executor_idempotent(ctx):
    r1 = executor(ctx)
    r2 = executor(ctx)
    assert r1["applied"] is True
    assert r2["applied"] is False


def test_executor_second_run_preserves_content(ctx):
    executor(ctx)
    dst_py = ctx.repo_root / ".board-superpowers" / "pyproject.toml"
    content_before = dst_py.read_bytes()
    executor(ctx)
    content_after = dst_py.read_bytes()
    assert content_before == content_after


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
    stage = next(s for s in registry["stages"] if s["stage_id"] == "m2.repo.copy-uv-templates")
    schema = stage["target_state_schema"]
    # ctx fixture provides _plugin_templates_dir override for compute_target_state
    ts = compute_target_state(ctx)
    jsonschema.validate(instance=ts, schema=schema)
