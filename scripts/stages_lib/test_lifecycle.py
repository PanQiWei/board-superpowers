"""TDD tests for stages_lib._lifecycle — the 5-state lifecycle engine.

ADR-0013 lifecycle states: not-applicable, pending, applied, drifted, failed, blocked.
ADR-0020: applicable_when 3-form predicate.
ADR-0027 § 2: kanban_projection_capability Form B shells out to bsp_resolve_active_projection.

Run:
    cd scripts && python3 -m pytest stages_lib/test_lifecycle.py -v --tb=short

Test IDs:
  T2.5-01  evaluate_applicability — no applicable_when → always True
  T2.5-02  evaluate_applicability — Form A setting_path/equals match
  T2.5-03  evaluate_applicability — Form A setting_path/equals mismatch
  T2.5-04  evaluate_applicability — Form A setting_path/one_of match
  T2.5-05  evaluate_applicability — Form B kanban_projection_capability (mock OK subprocess)
  T2.5-06  evaluate_applicability — Form B subprocess returns EMPTY → False
  T2.5-07  evaluate_applicability — Form C python callable → True
  T2.5-08  diff_layer1 matches (same generation) → fast-path-applied
  T2.5-09  diff_layer1 mismatch (generation bump) → fast-path-pending
  T2.5-10  diff_layer1 no persisted → fast-path-pending
  T2.5-11  diff_layer2 hash match → matched
  T2.5-12  diff_layer2 hash mismatch → drifted
  T2.5-13  diff_layer2 byte-stable across key-permutation (uses canonical)
  T2.5-14  diff_layer3 surfaces structured diff when states differ
  T2.5-15  evaluate_stage returns pending for never-run stage
  T2.5-16  evaluate_stage returns applied when fully matched
  T2.5-17  evaluate_stage returns drifted when generation matches but hash diverges
  T2.5-18  evaluate_stage returns not-applicable when predicate rules it out
  T2.5-19  evaluate_all_stages cascades not-applicable to dependent stages
  T2.5-20  evaluate_all_stages topological order (m1.host before m1.repo)
  T2.5-21  Form B shell-out pattern (source code check)
"""

from __future__ import annotations

import importlib
import inspect
import subprocess
import tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import pytest
import yaml

# ---------------------------------------------------------------------------
# Import guard
# ---------------------------------------------------------------------------
from stages_lib._lifecycle import (
    diff_layer1,
    diff_layer2,
    diff_layer3,
    evaluate_applicability,
    evaluate_all_stages,
    evaluate_stage,
)
from stages_lib._canonical import fingerprint
from stages_lib._partitioned_settings import write_settings


# ---------------------------------------------------------------------------
# Helpers / fixtures
# ---------------------------------------------------------------------------


def make_dirs():
    """Return (home_tmp, repo_tmp) as Path objects (caller must manage cleanup)."""
    home = tempfile.mkdtemp()
    repo = tempfile.mkdtemp()
    # initialise as a git repo so primary_repo_root can resolve it
    import subprocess as sp
    sp.run(["git", "init", "-q", repo], check=True)
    return Path(home), Path(repo)


@pytest.fixture()
def dirs(tmp_path):
    home = tmp_path / "home"
    repo = tmp_path / "repo"
    home.mkdir()
    repo.mkdir()
    import subprocess as sp
    sp.run(["git", "init", "-q", str(repo)], check=True)
    return home, repo


REPO_IDENTITY = "test/repo"


def make_stage(
    stage_id="m6.repo.append-gitignore",
    generation=1,
    applicable_when=None,
    depends_on=None,
    hash_excluded_fields=None,
):
    s = {
        "stage_id": stage_id,
        "generation": generation,
        "depends_on": depends_on or [],
        "hash_excluded_fields": hash_excluded_fields or [],
    }
    if applicable_when:
        s["applicable_when"] = applicable_when
    return s


def write_lifecycle_entry(stage_id, status, generation, target_state_hash, target_state=None,
                          *, home, repo, repo_identity=REPO_IDENTITY):
    """Helper: write a lifecycle entry into repo-shared settings."""
    data = {
        "modules": {
            "lifecycle": {
                stage_id: {
                    "status": status,
                    "generation": generation,
                    "target_state_hash": target_state_hash,
                    "target_state": target_state or {},
                }
            }
        }
    }
    write_settings("repo-shared", data, home=home, repo_root=repo, repo_identity=repo_identity)


# ---------------------------------------------------------------------------
# T2.5-01  evaluate_applicability — no applicable_when → always True
# ---------------------------------------------------------------------------

def test_evaluate_applicability_no_condition(dirs):
    home, repo = dirs
    stage = make_stage()
    assert evaluate_applicability(stage, home=home, repo_root=repo, repo_identity=REPO_IDENTITY) is True


# ---------------------------------------------------------------------------
# T2.5-02/03  Form A: setting_path + equals
# ---------------------------------------------------------------------------

def test_evaluate_applicability_form_a_match(dirs):
    """Form A: value at path matches → True."""
    home, repo = dirs
    # Write a matching setting
    data = {"modules": {"m10_kanban": {"projection": "github-project-v2"}}}
    write_settings("repo-git", data, home=home, repo_root=repo, repo_identity=REPO_IDENTITY)

    stage = make_stage(applicable_when={
        "setting_path": "modules.m10_kanban.projection",
        "equals": "github-project-v2",
    })
    assert evaluate_applicability(stage, home=home, repo_root=repo, repo_identity=REPO_IDENTITY) is True


def test_evaluate_applicability_form_a_mismatch(dirs):
    """Form A: value at path does not match → False."""
    home, repo = dirs
    data = {"modules": {"m10_kanban": {"projection": "linear"}}}
    write_settings("repo-git", data, home=home, repo_root=repo, repo_identity=REPO_IDENTITY)

    stage = make_stage(applicable_when={
        "setting_path": "modules.m10_kanban.projection",
        "equals": "github-project-v2",
    })
    assert evaluate_applicability(stage, home=home, repo_root=repo, repo_identity=REPO_IDENTITY) is False


# ---------------------------------------------------------------------------
# T2.5-04  Form A: one_of
# ---------------------------------------------------------------------------

def test_evaluate_applicability_form_a_one_of(dirs):
    """Form A: value at path is in one_of list → True."""
    home, repo = dirs
    data = {"modules": {"m10_kanban": {"projection": "github-project-v2"}}}
    write_settings("repo-git", data, home=home, repo_root=repo, repo_identity=REPO_IDENTITY)

    stage = make_stage(applicable_when={
        "setting_path": "modules.m10_kanban.projection",
        "one_of": ["github-project-v2", "linear"],
    })
    assert evaluate_applicability(stage, home=home, repo_root=repo, repo_identity=REPO_IDENTITY) is True


# ---------------------------------------------------------------------------
# T2.5-05/06  Form B: kanban_projection_capability (mocked subprocess)
# ---------------------------------------------------------------------------

def test_evaluate_applicability_form_b_ok(dirs):
    """Form B: subprocess returns OK + ref file declares capability → True."""
    home, repo = dirs

    stage = make_stage(applicable_when={"kanban_projection_capability": "ensure-labels"})

    # Mock subprocess.run to return "OK github-project-v2 owner/123"
    # Also mock the reference file lookup to avoid real filesystem dependency
    from stages_lib import _lifecycle as lc

    mock_ref_text = "## Setup capabilities\n- ensure-labels\n- validate-status-field\n"

    def fake_run(cmd, **kwargs):
        m = mock.MagicMock()
        m.stdout = "OK github-project-v2 owner/123\n"
        m.returncode = 0
        return m

    with mock.patch("stages_lib._lifecycle.subprocess.run", side_effect=fake_run):
        with mock.patch("builtins.open", mock.mock_open(read_data=mock_ref_text)):
            with mock.patch.object(Path, "exists", return_value=True):
                with mock.patch.object(Path, "read_text", return_value=mock_ref_text):
                    result = evaluate_applicability(
                        stage, home=home, repo_root=repo, repo_identity=REPO_IDENTITY
                    )
    assert result is True


def test_evaluate_applicability_form_b_empty(dirs):
    """Form B: subprocess returns EMPTY → not configured → False."""
    home, repo = dirs
    stage = make_stage(applicable_when={"kanban_projection_capability": "ensure-labels"})

    def fake_run(cmd, **kwargs):
        m = mock.MagicMock()
        m.stdout = "EMPTY\n"
        m.returncode = 0
        return m

    with mock.patch("stages_lib._lifecycle.subprocess.run", side_effect=fake_run):
        result = evaluate_applicability(
            stage, home=home, repo_root=repo, repo_identity=REPO_IDENTITY
        )
    assert result is False


# ---------------------------------------------------------------------------
# T2.5-07  Form C: python callable
# ---------------------------------------------------------------------------

def test_evaluate_applicability_form_c(dirs):
    """Form C: python escape hatch callable resolves and returns True."""
    home, repo = dirs

    # Use a module + callable we can import: stages_lib._canonical.fingerprint
    # We need a callable that accepts ctx and returns bool.
    # Let's mock importlib.import_module to return a module with our callable.
    def always_true(ctx):
        return True

    fake_mod = SimpleNamespace(always_true=always_true)

    stage = make_stage(applicable_when={"python": "fake_module.always_true"})

    with mock.patch("stages_lib._lifecycle.importlib.import_module", return_value=fake_mod):
        result = evaluate_applicability(
            stage, home=home, repo_root=repo, repo_identity=REPO_IDENTITY
        )
    assert result is True


# ---------------------------------------------------------------------------
# T2.5-08/09/10  diff_layer1
# ---------------------------------------------------------------------------

def test_diff_layer1_matches():
    """Layer 1: generation matches → fast-path-applied."""
    persisted = {"generation": 3}
    result = diff_layer1("some-stage", persisted, 3)
    assert result == "fast-path-applied"


def test_diff_layer1_mismatch():
    """Layer 1: generation mismatch → fast-path-pending."""
    persisted = {"generation": 2}
    result = diff_layer1("some-stage", persisted, 3)
    assert result == "fast-path-pending"


def test_diff_layer1_no_persisted():
    """Layer 1: no persisted entry → fast-path-pending."""
    result = diff_layer1("some-stage", {}, 1)
    assert result == "fast-path-pending"


# ---------------------------------------------------------------------------
# T2.5-11/12/13  diff_layer2
# ---------------------------------------------------------------------------

def test_diff_layer2_hash_match():
    """Layer 2: matching hashes → matched."""
    target_state = {"required_entries": ["*.local.*", "claims/", ".venv/"]}
    h = fingerprint(target_state)
    persisted = {"target_state_hash": h}
    assert diff_layer2("some-stage", persisted, h) == "matched"


def test_diff_layer2_hash_mismatch():
    """Layer 2: different hashes → drifted."""
    target_state = {"required_entries": ["*.local.*", "claims/", ".venv/"]}
    h = fingerprint(target_state)
    wrong_hash = "deadbeef" + "0" * 56
    persisted = {"target_state_hash": wrong_hash}
    assert diff_layer2("some-stage", persisted, h) == "drifted"


def test_diff_layer2_byte_stable_across_key_permutations():
    """Layer 2: canonical emit is stable regardless of dict key insertion order."""
    state_a = {"z_key": 1, "a_key": 2, "m_key": 3}
    state_b = {"a_key": 2, "m_key": 3, "z_key": 1}
    h_a = fingerprint(state_a)
    h_b = fingerprint(state_b)
    assert h_a == h_b, "Canonical fingerprint must be key-order-independent"
    persisted = {"target_state_hash": h_a}
    assert diff_layer2("some-stage", persisted, h_b) == "matched"


# ---------------------------------------------------------------------------
# T2.5-14  diff_layer3
# ---------------------------------------------------------------------------

def test_diff_layer3_surfaces_diff():
    """Layer 3: structured diff when states differ."""
    persisted = {
        "target_state": {"wip_limit": 3, "schema_version": 1},
    }
    target = {"wip_limit": 5, "schema_version": 1}
    matches, diff = diff_layer3("some-stage", persisted, target)
    assert not matches
    assert "wip_limit" in diff
    assert diff["wip_limit"] == {"recorded": 3, "target": 5}


def test_diff_layer3_matches_when_equal():
    """Layer 3: no diff when states are equal."""
    state = {"wip_limit": 5, "schema_version": 1}
    persisted = {"target_state": state}
    matches, diff = diff_layer3("some-stage", persisted, state)
    assert matches
    assert diff == {}


# ---------------------------------------------------------------------------
# T2.5-15  evaluate_stage returns pending for never-run stage
# ---------------------------------------------------------------------------

def test_evaluate_stage_pending_never_run(dirs):
    """evaluate_stage returns pending for a stage with no persisted entry."""
    home, repo = dirs
    stage = make_stage()
    helper = SimpleNamespace(
        compute_target_state=lambda ctx: {"required_entries": ["*.local.*"]}
    )
    result = evaluate_stage(
        stage, home=home, repo_root=repo, repo_identity=REPO_IDENTITY,
        helper_module=helper,
    )
    assert result["state"] == "pending"
    assert result["stage_id"] == "m6.repo.append-gitignore"


# ---------------------------------------------------------------------------
# T2.5-16  evaluate_stage returns applied when fully matched
# ---------------------------------------------------------------------------

def test_evaluate_stage_applied_when_matched(dirs):
    """evaluate_stage returns applied when generation and hash both match."""
    home, repo = dirs
    target_state = {"required_entries": ["*.local.*", "claims/", ".venv/"]}
    h = fingerprint(target_state)

    write_lifecycle_entry(
        "m6.repo.append-gitignore", "applied", 1, h, target_state,
        home=home, repo=repo,
    )

    stage = make_stage(generation=1)
    helper = SimpleNamespace(compute_target_state=lambda ctx: target_state)

    result = evaluate_stage(
        stage, home=home, repo_root=repo, repo_identity=REPO_IDENTITY,
        helper_module=helper,
    )
    assert result["state"] == "applied"


# ---------------------------------------------------------------------------
# T2.5-17  evaluate_stage returns drifted when generation matches but hash diverges
# ---------------------------------------------------------------------------

def test_evaluate_stage_drifted_on_hash_mismatch(dirs):
    """evaluate_stage returns drifted when hash diverges without generation bump."""
    home, repo = dirs
    old_state = {"required_entries": ["*.local.*"]}  # old target
    old_hash = fingerprint(old_state)

    write_lifecycle_entry(
        "m6.repo.append-gitignore", "applied", 1, old_hash, old_state,
        home=home, repo=repo,
    )

    new_target = {"required_entries": ["*.local.*", "claims/", ".venv/"]}

    stage = make_stage(generation=1)  # same generation → should catch via layer-2
    helper = SimpleNamespace(compute_target_state=lambda ctx: new_target)

    result = evaluate_stage(
        stage, home=home, repo_root=repo, repo_identity=REPO_IDENTITY,
        helper_module=helper,
    )
    assert result["state"] == "drifted"


# ---------------------------------------------------------------------------
# T2.5-18  evaluate_stage returns not-applicable when predicate rules it out
# ---------------------------------------------------------------------------

def test_evaluate_stage_not_applicable(dirs):
    """evaluate_stage returns not-applicable when applicable_when form A is false."""
    home, repo = dirs
    # No settings file written → path is missing → form A returns False
    stage = make_stage(applicable_when={
        "setting_path": "modules.m10_kanban.projection",
        "equals": "github-project-v2",
    })
    helper = SimpleNamespace(compute_target_state=lambda ctx: {})
    result = evaluate_stage(
        stage, home=home, repo_root=repo, repo_identity=REPO_IDENTITY,
        helper_module=helper,
    )
    assert result["state"] == "not-applicable"


# ---------------------------------------------------------------------------
# T2.5-19  evaluate_all_stages cascades not-applicable to dependent stages
# ---------------------------------------------------------------------------

def test_evaluate_all_stages_cascades_not_applicable(dirs):
    """Dependent stages cascade to not-applicable when dependency is pending."""
    home, repo = dirs

    registry = {
        "stages": [
            {
                "stage_id": "m1.host.create-state-dir",
                "generation": 1,
                "depends_on": [],
                "hash_excluded_fields": [],
                # No applicable_when
            },
            {
                "stage_id": "m1.repo.write-state-yml",
                "generation": 1,
                "depends_on": ["m1.host.create-state-dir"],
                "hash_excluded_fields": [],
            },
        ]
    }
    # Neither stage has persisted entries → m1.host is pending → m1.repo cascades
    results = evaluate_all_stages(
        registry, home=home, repo_root=repo, repo_identity=REPO_IDENTITY
    )
    by_id = {r["stage_id"]: r["state"] for r in results}
    assert by_id["m1.host.create-state-dir"] == "pending"
    assert by_id["m1.repo.write-state-yml"] == "not-applicable"


# ---------------------------------------------------------------------------
# T2.5-20  evaluate_all_stages topological order
# ---------------------------------------------------------------------------

def test_evaluate_all_stages_topo_order(dirs):
    """m1.host stages come before m1.repo in topological evaluation order."""
    home, repo = dirs

    registry_path = Path(__file__).parent.parent / "stages-registry.yml"
    if not registry_path.exists():
        pytest.skip("stages-registry.yml not found")

    registry = yaml.safe_load(registry_path.read_text(encoding="utf-8"))
    results = evaluate_all_stages(
        registry, home=home, repo_root=repo, repo_identity=REPO_IDENTITY
    )
    ids = [r["stage_id"] for r in results]
    assert "m1.host.create-state-dir" in ids
    assert "m1.repo.write-state-yml" in ids
    assert ids.index("m1.host.create-state-dir") < ids.index("m1.repo.write-state-yml"), (
        "m1.host.create-state-dir must be evaluated before m1.repo.write-state-yml"
    )


# ---------------------------------------------------------------------------
# T2.5-21  Form B uses subprocess (shell-out), not Python re-implementation
# ---------------------------------------------------------------------------

def test_form_b_uses_subprocess_not_reimplemented():
    """Form B should shell out to bsp_resolve_active_projection, not re-implement."""
    from stages_lib import _lifecycle
    # Check the Form B evaluator specifically
    src_b = inspect.getsource(_lifecycle._eval_form_b)
    # Must reference subprocess (for shell-out)
    assert "subprocess" in src_b or "bsp_resolve_active_projection" in src_b, (
        "Form B must shell out to bsp_resolve_active_projection via subprocess"
    )
    # Must NOT call awk subprocess — the awk logic lives in common.sh, not Python.
    # All awk references in _eval_form_b must be in docstrings/comments, not code.
    import ast
    try:
        tree = ast.parse(inspect.getsource(_lifecycle._eval_form_b))
        # If awk appears in actual Call nodes or string literals used as code
        # (not docstrings), that's a violation.  We check that no subprocess
        # command list contains the string 'awk'.
        for node in ast.walk(tree):
            if isinstance(node, ast.List):
                for elt in node.elts:
                    if isinstance(elt, ast.Constant) and isinstance(elt.value, str):
                        assert "awk" not in elt.value, (
                            "Form B must not call awk directly; use bsp_resolve_active_projection"
                        )
    except SyntaxError:
        pass  # If we can't parse, fall through
