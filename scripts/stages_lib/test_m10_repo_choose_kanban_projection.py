"""Tests for stages_lib.m10_repo_choose_kanban_projection.

Stage: M10 | agentic | repo-git | both platforms
TDD: tests written against the ADR-0014 4-callable + apply_choice contract.
Run: cd scripts && python3 -m pytest stages_lib/ -v

Key behaviors verified:
- 4-callable contract: all four callables present and callable
- apply_choice (5th callable): present and callable for agentic stage
- compute_target_state: returns {kanban_projection: str} with default on fresh ctx
- target_state_predicate: accepts valid enum; rejects unknown / wrong type
- idempotency_check: absent (fresh ctx) / present (after apply_choice)
- executor (agentic): requires_input on fresh / no-op when configured
- apply_choice: persists to repo-git settings.yml; idempotent; rejects invalid
- round-trip: compute_target_state validates against registry target_state_schema
- ADR-0026 v1.0 shorthand: projection stored flat under modules.m10_kanban.projection
  (NOT nested under primary.projection — bsp_resolve_active_projection awk reads
  the 4-space-indented shorthand form, not a 6-space nested key)
- real awk round-trip: apply_choice + bash bsp_resolve_active_projection (integration)
"""

from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml

# ---------------------------------------------------------------------------
# Import guard — fails RED until module exists
# ---------------------------------------------------------------------------
from stages_lib.m10_repo_choose_kanban_projection import (
    _DEFAULT_PROJECTION,
    _VALID_PROJECTIONS,
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
    import stages_lib.m10_repo_choose_kanban_projection as m
    for name in ["compute_target_state", "target_state_predicate",
                 "idempotency_check", "executor"]:
        assert callable(getattr(m, name, None)), f"{name} missing or not callable"


def test_apply_choice_present():
    import stages_lib.m10_repo_choose_kanban_projection as m
    assert callable(getattr(m, "apply_choice", None))


# ---------------------------------------------------------------------------
# compute_target_state()
# ---------------------------------------------------------------------------


def test_compute_target_state_returns_dict(ctx):
    state = compute_target_state(ctx)
    assert isinstance(state, dict)


def test_compute_target_state_default_projection_fresh(ctx):
    state = compute_target_state(ctx)
    assert "kanban_projection" in state
    assert state["kanban_projection"] == _DEFAULT_PROJECTION


def test_compute_target_state_reflects_persisted_value(ctx):
    apply_choice(ctx, "github-project-v2")
    assert compute_target_state(ctx)["kanban_projection"] == "github-project-v2"


def test_compute_target_state_pure_before_write(ctx):
    assert compute_target_state(ctx) == compute_target_state(ctx)


# ---------------------------------------------------------------------------
# target_state_predicate()
# ---------------------------------------------------------------------------


def test_target_state_predicate_valid_github_project_v2():
    assert target_state_predicate({"kanban_projection": "github-project-v2"}) is True


@pytest.mark.parametrize("state", [
    {"kanban_projection": "linear"},
    {"kanban_projection": ""},
    {"kanban_projection": None},
    {},
    "github-project-v2",
    {"kanban_projection": 1},
])
def test_target_state_predicate_invalid(state):
    assert target_state_predicate(state) is False


# ---------------------------------------------------------------------------
# idempotency_check() — fresh ctx
# ---------------------------------------------------------------------------


def test_idempotency_check_absent_fresh_ctx(ctx):
    result = idempotency_check(ctx)
    assert result["present"] is False
    assert result["current_state"]["kanban_projection"] is None


# ---------------------------------------------------------------------------
# idempotency_check() — after apply_choice
# ---------------------------------------------------------------------------


def test_idempotency_check_present_after_apply_choice(ctx):
    apply_choice(ctx, "github-project-v2")
    result = idempotency_check(ctx)
    assert result["present"] is True
    assert result["current_state"]["kanban_projection"] == "github-project-v2"


# ---------------------------------------------------------------------------
# executor() — agentic protocol (Option A)
# ---------------------------------------------------------------------------


def test_executor_fresh_requires_input(ctx):
    result = executor(ctx)
    assert result["applied"] is False
    assert result.get("requires_input") is True


def test_executor_fresh_has_prompt(ctx):
    result = executor(ctx)
    assert "prompt" in result
    prompt = result["prompt"]
    assert isinstance(prompt, dict)
    assert prompt.get("kind") == "single-choice"


def test_executor_fresh_has_default(ctx):
    result = executor(ctx)
    assert "default" in result
    assert result["default"] == _DEFAULT_PROJECTION


def test_executor_fresh_prompt_has_options(ctx):
    result = executor(ctx)
    prompt = result["prompt"]
    assert "options" in prompt
    assert "github-project-v2" in prompt["options"]


def test_executor_fresh_has_message(ctx):
    result = executor(ctx)
    assert "message" in result
    assert isinstance(result["message"], str)


def test_executor_already_configured_no_op(ctx):
    apply_choice(ctx, "github-project-v2")
    result = executor(ctx)
    assert result["applied"] is False
    assert result.get("requires_input") is not True


# ---------------------------------------------------------------------------
# apply_choice() — persistence (ADR-0026 multi-kanban)
# ---------------------------------------------------------------------------


def test_apply_choice_returns_applied_true(ctx):
    result = apply_choice(ctx, "github-project-v2")
    assert result["applied"] is True


def test_apply_choice_persists_to_repo_git_settings_yml(ctx):
    apply_choice(ctx, "github-project-v2")
    path = ctx.repo_root / ".board-superpowers" / "settings.yml"
    assert path.exists()
    data = yaml.safe_load(path.read_text())
    # ADR-0026 v1.0 shorthand: flat key modules.m10_kanban.projection (NOT nested
    # under primary.projection — the awk parser in bsp_resolve_active_projection
    # reads /^[[:space:]]{4}projection:/ at 4-space indent under m10_kanban).
    proj = data["modules"]["m10_kanban"]["projection"]
    assert proj == "github-project-v2"


def test_apply_choice_writes_flat_not_nested(ctx):
    """Projection stored flat under modules.m10_kanban.projection per ADR-0026 v1.0.

    The key 'projection' must live directly in modules.m10_kanban (4-space
    indent in the YAML), NOT under modules.m10_kanban.primary (6-space indent).
    The awk parser in bsp_resolve_active_projection captures the 4-space form;
    the 6-space nested form is silently ignored and causes M3 to stay not-applicable.
    """
    apply_choice(ctx, "github-project-v2")
    path = ctx.repo_root / ".board-superpowers" / "settings.yml"
    data = yaml.safe_load(path.read_text())
    m10 = data["modules"]["m10_kanban"]
    # Flat key must be present
    assert "projection" in m10, f"'projection' not in m10_kanban section: {m10}"
    # The nested 'primary' subkey must NOT be used as the canonical form
    assert m10.get("projection") == "github-project-v2"


def test_apply_choice_returns_side_effects(ctx):
    result = apply_choice(ctx, "github-project-v2")
    assert isinstance(result["side_effects"], list)
    assert len(result["side_effects"]) > 0


def test_apply_choice_idempotent_same_value(ctx):
    r1 = apply_choice(ctx, "github-project-v2")
    r2 = apply_choice(ctx, "github-project-v2")
    assert r1["applied"] is True
    assert r2["applied"] is False


def test_apply_choice_rejects_unknown_projection(ctx):
    with pytest.raises(ValueError):
        apply_choice(ctx, "linear")


def test_apply_choice_rejects_empty_string(ctx):
    with pytest.raises(ValueError):
        apply_choice(ctx, "")


def test_apply_choice_rejects_non_string(ctx):
    with pytest.raises((ValueError, TypeError)):
        apply_choice(ctx, 42)  # type: ignore[arg-type]


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
        s for s in registry["stages"]
        if s["stage_id"] == "m10.repo.choose-kanban-projection"
    )
    schema = stage["target_state_schema"]
    ts = compute_target_state(ctx)
    jsonschema.validate(instance=ts, schema=schema)


def test_compute_target_state_after_apply_choice_validates_schema(ctx):
    """After apply_choice, compute_target_state must still validate."""
    import jsonschema
    registry_path = Path(__file__).parent.parent / "stages-registry.yml"
    registry = yaml.safe_load(registry_path.read_text())
    stage = next(
        s for s in registry["stages"]
        if s["stage_id"] == "m10.repo.choose-kanban-projection"
    )
    schema = stage["target_state_schema"]
    apply_choice(ctx, "github-project-v2")
    ts = compute_target_state(ctx)
    jsonschema.validate(instance=ts, schema=schema)


# ---------------------------------------------------------------------------
# Real awk round-trip integration test (no mocks — exercises bash parser)
# ---------------------------------------------------------------------------


def test_apply_choice_resolves_via_real_awk_parser(tmp_path):
    """Round-trip: M10 apply_choice + project_ref → bsp_resolve_active_projection returns OK.

    This test does NOT mock subprocess. It:
    1. Writes settings.yml via apply_choice() (sets modules.m10_kanban.projection).
    2. Adds a test project_ref at the flat level (modules.m10_kanban.project_ref)
       since bsp_resolve_active_projection requires BOTH projection AND project_ref
       to emit "OK <projection> <ref>" — the project_ref is configured separately
       from the projection type (M10 records the type; a companion stage records the ref).
    3. Invokes the real bash bsp_resolve_active_projection awk and asserts "OK".

    Regression guard for storage-format drift:
    If apply_choice() ever reverts to writing modules.m10_kanban.primary.projection
    (6-space nested) instead of modules.m10_kanban.projection (4-space flat),
    the awk parser will see 'primary:' as an unrecognized key, t_proj will be empty,
    and the awk will emit EMPTY — this test catches the drift.
    """
    import subprocess
    import yaml
    home = tmp_path / "home"
    repo = tmp_path / "repo"
    home.mkdir()
    repo.mkdir()

    ctx = SimpleNamespace(home=home, repo_root=repo, repo_identity="test/repo")

    # Step 1: write settings.yml via the Python M10 apply_choice
    # This sets modules.m10_kanban.projection: github-project-v2 (flat, 4-space)
    apply_choice(ctx, "github-project-v2")

    # Step 2: add project_ref at the flat level (same indent as projection)
    # The awk requires BOTH projection and project_ref to return "OK".
    # project_ref is a separate concern from projection type; use a test placeholder.
    settings_file = repo / ".board-superpowers" / "settings.yml"
    data = yaml.safe_load(settings_file.read_text())
    data["modules"]["m10_kanban"]["project_ref"] = "testowner/1"
    settings_file.write_text(
        __import__("yaml").safe_dump(data, default_flow_style=False, sort_keys=True,
                                     allow_unicode=True, indent=2, width=10**9)
    )

    # Step 3: invoke the real bash bsp_resolve_active_projection awk parser
    plugin_root = Path(__file__).parent.parent.parent
    common_sh = plugin_root / "scripts" / "lib" / "common.sh"
    assert common_sh.exists(), f"common.sh not found at {common_sh}"

    result = subprocess.run(
        ["bash", "-c",
         f"source {common_sh} && bsp_resolve_active_projection {repo}"],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, (
        f"bsp_resolve_active_projection returned non-zero.\n"
        f"stdout: {result.stdout!r}\n"
        f"stderr: {result.stderr!r}\n"
        f"settings.yml content:\n{settings_file.read_text()}"
    )
    # bsp_resolve_active_projection strips the "OK " prefix before printing:
    # output format is "<projection> <project_ref>" (exit 0 = success).
    assert "github-project-v2" in result.stdout, (
        f"awk did not resolve projection.\n"
        f"stdout: {result.stdout!r}\n"
        f"stderr: {result.stderr!r}\n"
        f"settings.yml content:\n{settings_file.read_text()}"
    )
