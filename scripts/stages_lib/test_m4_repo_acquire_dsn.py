"""Tests for stages_lib.m4_repo_acquire_dsn.

Stage: M4 | agentic | repo-shared | both platforms
TDD: tests against the ADR-0014 4-callable contract + apply_choice 5th callable.
Run: cd scripts && python3 -m pytest stages_lib/ -v

Key behaviors verified:
- 4-callable contract + apply_choice (5th callable) all present
- apply_choice absent on automated stages (tested by m4 siblings)
- 6-scheme allow-list per ADR-0009: all 6 accepted; non-canonical rejected
- credentials.yml at HOST-side per-repo path (NOT under <repo>/)
- credentials.yml mode 0600
- DSN NOT written to settings.yml family (ADR-0024 § Part A separation)
- executor auto-configures sqlite default (ADR-0019 zero-config)
- executor no-op when already configured
- apply_choice persists to credentials.yml, mode 0600
- apply_choice idempotent: same DSN → no change
- idempotency_check: absent / present / invalid-scheme paths
- compute_target_state returns dsn_scheme in allowlist
- Round-trip: compute_target_state validates against registry target_state_schema
"""

from __future__ import annotations

import os
import stat
import tempfile
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml

from stages_lib.m4_repo_acquire_dsn import (
    ALLOWED_SCHEMES,
    _credentials_path,
    _default_sqlite_dsn,
    _parse_scheme,
    _read_credentials,
    _write_credentials,
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


@pytest.fixture
def ctx_with_sqlite(ctx):
    """ctx with sqlite DSN already in credentials.yml."""
    dsn = f"sqlite:////{ctx.home}/.board-superpowers/repos/test/repo/audit.db"
    apply_choice(ctx, dsn)
    return ctx, dsn


# ---------------------------------------------------------------------------
# Module-level callable contract
# ---------------------------------------------------------------------------


def test_four_callables_present():
    import stages_lib.m4_repo_acquire_dsn as m
    for name in ["compute_target_state", "target_state_predicate", "idempotency_check", "executor"]:
        assert callable(getattr(m, name, None)), f"{name} missing or not callable"


def test_apply_choice_present():
    """Agentic stage — 5th callable apply_choice MUST be present."""
    import stages_lib.m4_repo_acquire_dsn as m
    assert callable(getattr(m, "apply_choice", None)), "apply_choice missing"


# ---------------------------------------------------------------------------
# 6-scheme allow-list (ADR-0009 § Decision)
# ---------------------------------------------------------------------------


def test_predicate_accepts_all_six_schemes():
    for scheme in ALLOWED_SCHEMES:
        state = {"dsn_scheme": scheme}
        assert target_state_predicate(state) is True, f"scheme {scheme!r} should be accepted"


def test_predicate_rejects_non_canonical_scheme():
    for bad in ["foobar", "oracle", "mssql", "redis", "mongodb", ""]:
        state = {"dsn_scheme": bad}
        assert target_state_predicate(state) is False, f"scheme {bad!r} should be rejected"


def test_predicate_rejects_none_scheme():
    assert target_state_predicate({"dsn_scheme": None}) is False


def test_predicate_rejects_non_dict():
    assert target_state_predicate("sqlite") is False
    assert target_state_predicate(None) is False


# ---------------------------------------------------------------------------
# credentials.yml path + mode
# ---------------------------------------------------------------------------


def test_credentials_path_is_host_side_per_repo(ctx):
    """credentials.yml must be at ~/.board-superpowers/repos/<identity>/credentials.yml.

    NOT under <repo>/ — per ADR-0015 + ADR-0024 § Part A.
    """
    cred_path = _credentials_path(ctx)
    # Must be under home, not under repo_root
    assert str(ctx.home) in str(cred_path), "credentials.yml must be under home"
    assert str(ctx.repo_root) not in str(cred_path), "credentials.yml must NOT be under repo_root"
    assert "test" in str(cred_path)
    assert "repo" in str(cred_path)


def test_apply_choice_creates_credentials_yml_at_correct_path(ctx):
    dsn = "sqlite:///tmp/test.db"
    apply_choice(ctx, dsn)
    cred_path = ctx.home / ".board-superpowers" / "repos" / "test" / "repo" / "credentials.yml"
    assert cred_path.exists(), f"credentials.yml not at {cred_path}"


def test_apply_choice_sets_mode_0600(ctx):
    dsn = "sqlite:///tmp/test.db"
    apply_choice(ctx, dsn)
    cred_path = _credentials_path(ctx)
    mode = cred_path.stat().st_mode & 0o777
    assert mode == 0o600, f"credentials.yml mode should be 0600, got {oct(mode)}"


def test_apply_choice_persists_audit_dsn(ctx):
    dsn = "sqlite:///tmp/audit.db"
    apply_choice(ctx, dsn)
    creds = _read_credentials(ctx)
    assert creds["audit_dsn"] == dsn


def test_apply_choice_does_not_write_to_settings_yml(ctx):
    """DSN must NOT be written to settings.yml family — ADR-0024 § Part A."""
    dsn = "sqlite:///tmp/audit.db"
    apply_choice(ctx, dsn)
    # settings.yml at repo-git should NOT exist or should not have audit_dsn
    repo_settings = ctx.repo_root / ".board-superpowers" / "settings.yml"
    if repo_settings.exists():
        content = yaml.safe_load(repo_settings.read_text()) or {}
        modules = content.get("modules", {})
        # No m4_audit.audit_dsn in settings.yml
        m4 = modules.get("m4_audit", {})
        assert "audit_dsn" not in m4, "audit_dsn must NOT be in settings.yml"
    # repo-shared settings.yml should also not have audit_dsn
    repo_shared = ctx.home / ".board-superpowers" / "repos" / "test" / "repo" / "settings.yml"
    if repo_shared.exists():
        content = yaml.safe_load(repo_shared.read_text()) or {}
        modules = content.get("modules", {})
        m4 = modules.get("m4_audit", {})
        assert "audit_dsn" not in m4, "audit_dsn must NOT be in repo-shared settings.yml"


# ---------------------------------------------------------------------------
# apply_choice idempotency + validation
# ---------------------------------------------------------------------------


def test_apply_choice_idempotent_same_dsn(ctx):
    dsn = "sqlite:///tmp/audit.db"
    result1 = apply_choice(ctx, dsn)
    result2 = apply_choice(ctx, dsn)
    assert result1["applied"] is True
    assert result2["applied"] is False
    assert "no change" in result2["message"]


def test_apply_choice_updates_to_new_dsn(ctx):
    dsn1 = "sqlite:///tmp/audit1.db"
    dsn2 = "sqlite:///tmp/audit2.db"
    apply_choice(ctx, dsn1)
    result = apply_choice(ctx, dsn2)
    assert result["applied"] is True
    creds = _read_credentials(ctx)
    assert creds["audit_dsn"] == dsn2


def test_apply_choice_preserves_other_keys(ctx):
    """apply_choice must not clobber other credential keys."""
    cred_path = _credentials_path(ctx)
    cred_path.parent.mkdir(parents=True, exist_ok=True)
    initial = {"some_token": "abc123", "audit_dsn": "sqlite:///old.db"}
    _write_credentials(ctx, initial)
    apply_choice(ctx, "sqlite:///new.db")
    creds = _read_credentials(ctx)
    assert creds["some_token"] == "abc123", "other keys must be preserved"


def test_apply_choice_rejects_invalid_scheme(ctx):
    with pytest.raises(ValueError, match="not in allowlist"):
        apply_choice(ctx, "oracle://localhost/db")


def test_apply_choice_rejects_empty_string(ctx):
    with pytest.raises(ValueError):
        apply_choice(ctx, "")


def test_apply_choice_all_six_schemes_accepted(ctx):
    """All 6 canonical schemes must be accepted by apply_choice."""
    for scheme in ALLOWED_SCHEMES:
        dsn = f"{scheme}://localhost/testdb"
        result = apply_choice(ctx, dsn)
        # Either applied (first write) or no-change (same value)
        assert "applied" in result


# ---------------------------------------------------------------------------
# idempotency_check
# ---------------------------------------------------------------------------


def test_idempotency_check_absent_returns_not_present(ctx):
    result = idempotency_check(ctx)
    assert result["present"] is False
    assert result["current_state"]["dsn_scheme"] is None


def test_idempotency_check_configured_returns_present(ctx):
    dsn = "sqlite:///tmp/audit.db"
    apply_choice(ctx, dsn)
    result = idempotency_check(ctx)
    assert result["present"] is True
    assert result["current_state"]["dsn_scheme"] == "sqlite"


def test_idempotency_check_invalid_scheme_returns_not_present(ctx):
    """A credentials.yml with an invalid scheme → not present."""
    cred_path = _credentials_path(ctx)
    cred_path.parent.mkdir(parents=True, exist_ok=True)
    _write_credentials(ctx, {"audit_dsn": "oracle://x"})
    result = idempotency_check(ctx)
    assert result["present"] is False
    assert "error" in result["current_state"]


# ---------------------------------------------------------------------------
# executor (ADR-0019 zero-config sqlite default)
# ---------------------------------------------------------------------------


def test_executor_auto_configures_sqlite_default(ctx):
    """Fresh ctx with no credentials.yml → executor auto-writes sqlite default."""
    result = executor(ctx)
    assert result["applied"] is True
    assert "sqlite" in result["message"].lower()
    # credentials.yml must exist after executor
    cred_path = _credentials_path(ctx)
    assert cred_path.exists()
    creds = _read_credentials(ctx)
    assert creds["audit_dsn"].startswith("sqlite:")


def test_executor_no_op_when_already_configured(ctx_with_sqlite):
    ctx, dsn = ctx_with_sqlite
    result = executor(ctx)
    assert result["applied"] is False
    assert "no-op" in result["message"]


def test_executor_sqlite_default_uses_host_side_path(ctx):
    """Default sqlite DSN must point to host-side path, not inside repo_root."""
    executor(ctx)
    creds = _read_credentials(ctx)
    dsn = creds["audit_dsn"]
    # Must NOT be a path inside repo_root
    assert str(ctx.repo_root) not in dsn, "SQLite DSN must NOT point inside repo_root"
    assert str(ctx.home) in dsn, "SQLite DSN must point inside home"


# ---------------------------------------------------------------------------
# compute_target_state
# ---------------------------------------------------------------------------


def test_compute_target_state_returns_dict(ctx):
    ts = compute_target_state(ctx)
    assert isinstance(ts, dict)


def test_compute_target_state_dsn_scheme_in_allowlist(ctx):
    ts = compute_target_state(ctx)
    assert ts["dsn_scheme"] in ALLOWED_SCHEMES


def test_compute_target_state_defaults_sqlite(ctx):
    """Fresh ctx → compute_target_state reports sqlite default scheme."""
    ts = compute_target_state(ctx)
    assert ts["dsn_scheme"] == "sqlite"


def test_compute_target_state_reports_configured_scheme(ctx):
    dsn = "postgresql://user:pass@localhost/mydb"
    apply_choice(ctx, dsn)
    ts = compute_target_state(ctx)
    assert ts["dsn_scheme"] == "postgresql"


# ---------------------------------------------------------------------------
# Round-trip: compute_target_state validates against registry schema
# ---------------------------------------------------------------------------


def test_compute_target_state_validates_against_registry_schema(ctx):
    """Round-trip: compute_target_state output MUST validate against registry."""
    import jsonschema
    registry_path = Path(__file__).parent.parent / "stages-registry.yml"
    registry = yaml.safe_load(registry_path.read_text())
    stage = next(
        s for s in registry["stages"]
        if s["stage_id"] == "m4.repo.acquire-dsn"
    )
    schema = stage["target_state_schema"]
    ts = compute_target_state(ctx)
    jsonschema.validate(instance=ts, schema=schema)


# ---------------------------------------------------------------------------
# _default_sqlite_dsn helper
# ---------------------------------------------------------------------------


def test_default_sqlite_dsn_uses_absolute_4slash_form(ctx):
    """sqlite DSN must use 4-slash absolute form per ADR-0009 § Decision."""
    dsn = _default_sqlite_dsn(ctx)
    assert dsn.startswith("sqlite:////"), f"Must use 4-slash absolute form, got: {dsn}"


def test_default_sqlite_dsn_points_to_host_side_path(ctx):
    dsn = _default_sqlite_dsn(ctx)
    assert str(ctx.home) in dsn
    assert str(ctx.repo_root) not in dsn
