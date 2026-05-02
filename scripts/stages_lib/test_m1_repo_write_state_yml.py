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


# ---------------------------------------------------------------------------
# Round-trip: compute_target_state output validates against registry schema
# ---------------------------------------------------------------------------


def test_compute_target_state_validates_against_registry_schema(ctx):
    """Round-trip: compute_target_state output MUST validate against the
    stage's target_state_schema declared in scripts/stages-registry.yml.
    Prevents registry/impl drift from being invisible to the test suite."""
    import jsonschema
    registry_path = Path(__file__).parent.parent / "stages-registry.yml"
    registry = yaml.safe_load(registry_path.read_text())
    stage = next(s for s in registry["stages"] if s["stage_id"] == "m1.repo.write-state-yml")
    schema = stage["target_state_schema"]
    ts = compute_target_state(ctx)
    jsonschema.validate(instance=ts, schema=schema)


# ---------------------------------------------------------------------------
# Audit A3 — load-merge invariant
#
# The v0.5.0 executor() literal-constructed `data = {...}` and called
# write_settings(...), atomically replacing the file and vaporizing every
# peer-written modules.lifecycle.<stage_id> entry. Lifecycle invariant
# (SETUP_STAGES_DEVELOPMENT.md § "Lifecycle invariant: append-merge-only")
# requires load-merge, never bulk overwrite.
# ---------------------------------------------------------------------------


from stages_lib._partitioned_settings import read_settings, write_settings  # noqa: E402


def _read_back(ctx) -> dict:
    return read_settings(
        "repo-shared",
        home=Path(ctx.home), repo_root=Path(ctx.repo_root), repo_identity=ctx.repo_identity,
    )


def test_executor_preserves_existing_lifecycle_entries(ctx):
    """A3-1: peer-written modules.lifecycle.<stage_id> entries MUST survive a
    subsequent m1.repo.write-state-yml.executor() invocation that needs to
    re-write the file (idempotency_check returns present=False).

    RED before A3 fix lands: the literal-construct write clobbers the entries.
    GREEN after fix: load-merge preserves them.

    We simulate the realistic re-write trigger by pre-populating with a
    stale repo_identity. idempotency_check then returns present=False and the
    executor proceeds with the write — exercising the bulk-overwrite path.
    """
    existing = {
        "setup": {
            "generated_at": "2026-04-30T10:00:00+00:00",
            "plugin_version": "v0.4.9",
            "repo_identity": "stale/identity",  # forces re-write
            "schema_version": 1,
        },
        "stages_completed": [],
        "modules": {
            "lifecycle": {
                "schema_version": 1,
                "m3.repo.ensure-labels": {
                    "status": "applied",
                    "generation": 1,
                    "target_state_hash": "abc123",
                    "external_validated_at": "2026-05-01T12:00:00Z",
                },
                "m4.repo.apply-audit-ddl": {
                    "status": "applied",
                    "generation": 2,
                    "target_state_hash": "def456",
                },
            },
            "m1_plugin_runtime": {
                "bootstrapped_at": "2026-04-30T10:00:00+00:00",
                "schema_version": 1,
            },
            "m4_audit": {
                "audit_rows_landed": 0,
                "dsn_recorded": False,
                "pending_count": 0,
                "schema_version": 1,
            },
            "m7_routing": {"detected_form": "", "schema_version": 1},
        },
    }
    write_settings(
        "repo-shared", existing,
        home=Path(ctx.home), repo_root=Path(ctx.repo_root), repo_identity=ctx.repo_identity,
    )

    # Re-run executor — idempotency_check returns present (matching schema +
    # repo_identity), so this is the most realistic post-bootstrap path.
    executor(ctx)

    data = _read_back(ctx)
    lifecycle = data.get("modules", {}).get("lifecycle", {})

    assert "m3.repo.ensure-labels" in lifecycle, (
        "m3.repo.ensure-labels lifecycle entry vaporized — "
        "executor() bulk-overwrote modules.lifecycle"
    )
    assert lifecycle["m3.repo.ensure-labels"]["status"] == "applied"
    assert lifecycle["m3.repo.ensure-labels"]["generation"] == 1
    assert lifecycle["m3.repo.ensure-labels"]["target_state_hash"] == "abc123"
    # external_validated_at may be a string OR a datetime (PyYAML auto-parse)
    # depending on how the YAML emitter quoted the value. Either survives.
    assert "external_validated_at" in lifecycle["m3.repo.ensure-labels"]

    assert "m4.repo.apply-audit-ddl" in lifecycle, (
        "m4.repo.apply-audit-ddl lifecycle entry vaporized"
    )
    assert lifecycle["m4.repo.apply-audit-ddl"]["status"] == "applied"

    # Schema marker also intact.
    assert lifecycle.get("schema_version") == 1


def test_executor_preserves_other_module_sections(ctx):
    """A3-2: peer-written modules.<other_module> sections (m4_audit DSN choice,
    m7_routing form selection, m10_kanban projection) MUST survive when the
    executor re-writes the file.

    RED before fix: hardcoded skeleton overwrites architect-supplied fields.
    GREEN after fix: load-merge preserves them.
    """
    existing = {
        "setup": {
            "generated_at": "2026-04-30T10:00:00+00:00",
            "plugin_version": "v0.4.9",
            "repo_identity": "stale/identity",  # forces re-write
            "schema_version": 1,
        },
        "stages_completed": [],
        "modules": {
            "lifecycle": {"schema_version": 1},
            "m1_plugin_runtime": {
                "bootstrapped_at": "2026-04-30T10:00:00+00:00", "schema_version": 1,
            },
            "m4_audit": {
                "audit_rows_landed": 42,
                "dsn_recorded": True,
                "dsn_scheme": "sqlite",
                "pending_count": 3,
                "schema_version": 1,
            },
            "m7_routing": {"detected_form": "form-a", "schema_version": 1},
            "m10_kanban": {
                "projection": "github-project-v2",
                "project_ref": "PanQiWei/board-superpowers",
                "schema_version": 1,
            },
        },
    }
    write_settings(
        "repo-shared", existing,
        home=Path(ctx.home), repo_root=Path(ctx.repo_root), repo_identity=ctx.repo_identity,
    )

    executor(ctx)
    data = _read_back(ctx)
    modules = data.get("modules", {})

    assert modules["m4_audit"]["audit_rows_landed"] == 42, (
        "m4_audit.audit_rows_landed reset by bulk overwrite"
    )
    assert modules["m4_audit"]["dsn_recorded"] is True
    assert modules["m4_audit"].get("dsn_scheme") == "sqlite"
    assert modules["m4_audit"]["pending_count"] == 3

    assert modules["m7_routing"]["detected_form"] == "form-a"

    # m10_kanban — not pre-created by the v0.5.0 skeleton, must survive.
    assert "m10_kanban" in modules, (
        "m10_kanban module section vaporized — executor() did not "
        "load-merge non-skeleton modules"
    )
    assert modules["m10_kanban"]["projection"] == "github-project-v2"


def test_executor_preserves_non_setup_top_level_keys(ctx):
    """A3-3: top-level keys beyond setup/modules/stages_completed must survive
    a re-write.

    Belt-and-suspenders: future-version metadata or peer-stage opt-ins should
    not be silently dropped on the next executor() tick.
    """
    existing = {
        "setup": {
            "generated_at": "2026-04-30T10:00:00+00:00",
            "plugin_version": "v0.4.9",
            "repo_identity": "stale/identity",  # forces re-write
            "schema_version": 1,
        },
        "stages_completed": [{"stage_id": "m0.host.dep-check", "status": "applied"}],
        "modules": {"lifecycle": {"schema_version": 1}},
        "experimental_telemetry": {"opt_in": True, "endpoint": "https://example/x"},
    }
    write_settings(
        "repo-shared", existing,
        home=Path(ctx.home), repo_root=Path(ctx.repo_root), repo_identity=ctx.repo_identity,
    )

    executor(ctx)
    data = _read_back(ctx)

    assert "experimental_telemetry" in data, (
        "Unknown top-level key vaporized — executor() did not preserve "
        "non-setup top-level keys"
    )
    assert data["experimental_telemetry"]["opt_in"] is True
    assert any(
        e.get("stage_id") == "m0.host.dep-check"
        for e in data.get("stages_completed", [])
    ), "stages_completed history vaporized"
