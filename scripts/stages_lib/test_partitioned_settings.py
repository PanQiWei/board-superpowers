"""Tests for stages_lib._partitioned_settings — ADR-0024 4-locality router.

TDD: these tests are written BEFORE the implementation.

Covers:
  T2.4-01  Path resolution for each of 4 localities
  T2.4-02  read returns empty dict when file absent
  T2.4-03  write creates parent dirs as needed
  T2.4-04  write is atomic (tmp file → os.replace)
  T2.4-05  get_module_section returns empty dict when module absent
  T2.4-06  update_module_section preserves sibling modules + top-level setup
  T2.4-07  update_module_section merges (not replaces) when section already exists
  T2.4-08  Round-trip: write → read produces identical data
  T2.4-09  Repo-shared path uses HOST ~/.board-superpowers/repos/<id>/
  T2.4-10  Cross-locality independence: writing host-shared does NOT affect repo-git
  T2.4-11  settings_path: host-shared ignores repo_root + repo_identity args
  T2.4-12  write ensures all 4 parent paths are distinct
  T2.4-13  update_module_section creates file if absent
  T2.4-14  get_module_section handles nested modules key missing entirely
  T2.4-15  write_settings rejects unknown locality (raises ValueError)

Run:  cd scripts && python3 -m pytest stages_lib/test_partitioned_settings.py -v
"""

from pathlib import Path

import pytest
import yaml

# ---------------------------------------------------------------------------
# Import guard — tests must fail FAST if the module is absent (TDD red phase)
# ---------------------------------------------------------------------------

from stages_lib._partitioned_settings import (
    Locality,
    get_module_section,
    read_settings,
    settings_path,
    update_module_section,
    write_settings,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture()
def dirs(tmp_path):
    """Return (home, repo_root, identity) triple in a temp filesystem."""
    home = tmp_path / "HOME"
    repo = tmp_path / "REPO"
    home.mkdir()
    repo.mkdir()
    return home, repo, "PanQiWei/board-superpowers"


# ---------------------------------------------------------------------------
# T2.4-01  Path resolution for each locality
# ---------------------------------------------------------------------------


def test_host_shared_path(dirs):
    home, repo, identity = dirs
    p = settings_path("host-shared", home=home, repo_root=repo, repo_identity=identity)
    assert p == home / ".board-superpowers" / "settings.yml"


def test_repo_shared_path(dirs):
    home, repo, identity = dirs
    p = settings_path("repo-shared", home=home, repo_root=repo, repo_identity=identity)
    # Must be under HOME, not under REPO
    assert str(p).startswith(str(home))
    assert p == home / ".board-superpowers" / "repos" / identity / "settings.yml"


def test_repo_git_path(dirs):
    home, repo, identity = dirs
    p = settings_path("repo-git", home=home, repo_root=repo, repo_identity=identity)
    assert p == repo / ".board-superpowers" / "settings.yml"


def test_repo_clone_path(dirs):
    home, repo, identity = dirs
    p = settings_path("repo-clone", home=home, repo_root=repo, repo_identity=identity)
    assert p == repo / ".board-superpowers" / "settings.local.yml"


# ---------------------------------------------------------------------------
# T2.4-09  Repo-shared is HOST-side (critical ADR-0024 invariant)
# ---------------------------------------------------------------------------


def test_repo_shared_is_host_side_not_repo_side(dirs):
    """repo-shared MUST live under HOME, not under repo_root."""
    home, repo, identity = dirs
    p = settings_path("repo-shared", home=home, repo_root=repo, repo_identity=identity)
    # Verify it does NOT start with the repo path
    assert not str(p).startswith(str(repo)), (
        f"repo-shared must be under HOME, got {p}"
    )


# ---------------------------------------------------------------------------
# T2.4-11  host-shared ignores repo args
# ---------------------------------------------------------------------------


def test_host_shared_ignores_repo_root(tmp_path):
    home = tmp_path / "H"
    home.mkdir()
    p1 = settings_path("host-shared", home=home, repo_root=Path("/repo/A"), repo_identity="A/B")
    p2 = settings_path("host-shared", home=home, repo_root=Path("/repo/C"), repo_identity="C/D")
    assert p1 == p2, "host-shared path must not depend on repo_root or repo_identity"


# ---------------------------------------------------------------------------
# T2.4-02  read returns empty dict when file absent
# ---------------------------------------------------------------------------


def test_read_absent_returns_empty(dirs):
    home, repo, identity = dirs
    data = read_settings("host-shared", home=home, repo_root=repo, repo_identity=identity)
    assert data == {}


def test_read_absent_repo_git_returns_empty(dirs):
    home, repo, identity = dirs
    data = read_settings("repo-git", home=home, repo_root=repo, repo_identity=identity)
    assert data == {}


# ---------------------------------------------------------------------------
# T2.4-03  write creates parent dirs as needed
# ---------------------------------------------------------------------------


def test_write_creates_parent_dirs(dirs):
    home, repo, identity = dirs
    payload = {"setup": {"schema_version": 1}}
    write_settings("repo-shared", payload, home=home, repo_root=repo, repo_identity=identity)
    p = settings_path("repo-shared", home=home, repo_root=repo, repo_identity=identity)
    assert p.exists()


# ---------------------------------------------------------------------------
# T2.4-04  write is atomic (tmp file lifecycle)
# ---------------------------------------------------------------------------


def test_write_is_atomic(dirs, monkeypatch):
    """Verify write uses a .tmp sibling that os.replace into final path.

    We do this by monkeypatching os.replace and checking the tmp file
    existed and was handed to replace.
    """
    import os

    home, repo, identity = dirs
    p = settings_path("host-shared", home=home, repo_root=repo, repo_identity=identity)
    p.parent.mkdir(parents=True, exist_ok=True)

    replaced = []
    original_replace = os.replace

    def capture_replace(src, dst):
        replaced.append((src, dst))
        original_replace(src, dst)

    monkeypatch.setattr(os, "replace", capture_replace)
    write_settings("host-shared", {"x": 1}, home=home, repo_root=repo, repo_identity=identity)

    assert len(replaced) == 1, "os.replace must be called exactly once per write"
    tmp_src, final_dst = replaced[0]
    assert str(final_dst) == str(p), "os.replace dst must be the canonical path"
    assert tmp_src != str(p), "os.replace src must be a temp file, not the final path"
    # Final path exists; temp file is gone
    assert p.exists()
    assert not Path(tmp_src).exists()


# ---------------------------------------------------------------------------
# T2.4-08  Round-trip: write → read identical data
# ---------------------------------------------------------------------------


def test_round_trip_host_shared(dirs):
    home, repo, identity = dirs
    data = {"setup": {"schema_version": 1, "plugin_version": "v0.5.0"}, "modules": {"m1_plugin_runtime": {"schema_version": 1}}}
    write_settings("host-shared", data, home=home, repo_root=repo, repo_identity=identity)
    result = read_settings("host-shared", home=home, repo_root=repo, repo_identity=identity)
    assert result == data


def test_round_trip_repo_clone(dirs):
    home, repo, identity = dirs
    data = {"setup": {"schema_version": 1}, "modules": {"m5_repo_configuration": {"schema_version": 1, "wip_limit": 3}}}
    write_settings("repo-clone", data, home=home, repo_root=repo, repo_identity=identity)
    result = read_settings("repo-clone", home=home, repo_root=repo, repo_identity=identity)
    assert result == data


# ---------------------------------------------------------------------------
# T2.4-05  get_module_section returns empty dict when module absent
# ---------------------------------------------------------------------------


def test_get_module_section_absent_file(dirs):
    home, repo, identity = dirs
    result = get_module_section("repo-git", "m10_kanban", home=home, repo_root=repo, repo_identity=identity)
    assert result == {}


def test_get_module_section_absent_module_key(dirs):
    home, repo, identity = dirs
    write_settings("repo-git", {"setup": {"schema_version": 1}, "modules": {}}, home=home, repo_root=repo, repo_identity=identity)
    result = get_module_section("repo-git", "m5_repo_configuration", home=home, repo_root=repo, repo_identity=identity)
    assert result == {}


# ---------------------------------------------------------------------------
# T2.4-14  get_module_section handles missing modules section entirely
# ---------------------------------------------------------------------------


def test_get_module_section_no_modules_key(dirs):
    home, repo, identity = dirs
    # Write a file without a 'modules' key at all
    write_settings("repo-git", {"setup": {"schema_version": 1}}, home=home, repo_root=repo, repo_identity=identity)
    result = get_module_section("repo-git", "m5_repo_configuration", home=home, repo_root=repo, repo_identity=identity)
    assert result == {}


# ---------------------------------------------------------------------------
# T2.4-06  update_module_section preserves sibling modules + top-level setup
# ---------------------------------------------------------------------------


def test_update_preserves_siblings(dirs):
    home, repo, identity = dirs
    initial = {
        "setup": {"schema_version": 1, "plugin_version": "v0.5.0"},
        "modules": {
            "m1_plugin_runtime": {"schema_version": 1, "existing": True},
            "m8_autonomy": {"schema_version": 1, "preset": "allow-pr"},
        },
    }
    write_settings("host-shared", initial, home=home, repo_root=repo, repo_identity=identity)

    # Update m8 only
    update_module_section("host-shared", "m8_autonomy", {"schema_version": 1, "preset": "allow-pr", "extra": "new"}, home=home, repo_root=repo, repo_identity=identity)

    result = read_settings("host-shared", home=home, repo_root=repo, repo_identity=identity)
    # Sibling m1 must be intact
    assert result["modules"]["m1_plugin_runtime"] == {"schema_version": 1, "existing": True}
    # Top-level setup must be intact
    assert result["setup"] == {"schema_version": 1, "plugin_version": "v0.5.0"}
    # Updated m8 must have merged value
    assert result["modules"]["m8_autonomy"]["extra"] == "new"


# ---------------------------------------------------------------------------
# T2.4-07  update_module_section merges, not replaces, existing section
# ---------------------------------------------------------------------------


def test_update_merges_not_replaces(dirs):
    home, repo, identity = dirs
    initial = {
        "setup": {"schema_version": 1},
        "modules": {
            "m5_repo_configuration": {"schema_version": 1, "board_owner": "PanQiWei"},
        },
    }
    write_settings("repo-git", initial, home=home, repo_root=repo, repo_identity=identity)

    # Merge in wip_limit without touching board_owner
    update_module_section("repo-git", "m5_repo_configuration", {"wip_limit": 7}, home=home, repo_root=repo, repo_identity=identity)

    result = read_settings("repo-git", home=home, repo_root=repo, repo_identity=identity)
    m5 = result["modules"]["m5_repo_configuration"]
    assert m5.get("board_owner") == "PanQiWei", "pre-existing board_owner must survive merge"
    assert m5.get("wip_limit") == 7, "new wip_limit must be present after merge"


# ---------------------------------------------------------------------------
# T2.4-13  update_module_section creates file from scratch if absent
# ---------------------------------------------------------------------------


def test_update_creates_file_if_absent(dirs):
    home, repo, identity = dirs
    update_module_section("repo-clone", "m5_repo_configuration", {"schema_version": 1, "wip_limit": 5}, home=home, repo_root=repo, repo_identity=identity)
    p = settings_path("repo-clone", home=home, repo_root=repo, repo_identity=identity)
    assert p.exists()
    data = yaml.safe_load(p.read_text())
    assert data["modules"]["m5_repo_configuration"]["wip_limit"] == 5


# ---------------------------------------------------------------------------
# T2.4-10  Cross-locality independence
# ---------------------------------------------------------------------------


def test_cross_locality_independence(dirs):
    home, repo, identity = dirs
    write_settings("host-shared", {"setup": {"schema_version": 1}, "x": "host"}, home=home, repo_root=repo, repo_identity=identity)
    # repo-git was not touched — must still be absent
    data = read_settings("repo-git", home=home, repo_root=repo, repo_identity=identity)
    assert data == {}, "writing host-shared must not affect repo-git"


# ---------------------------------------------------------------------------
# T2.4-12  All 4 localities produce distinct paths
# ---------------------------------------------------------------------------


def test_all_four_paths_are_distinct(dirs):
    home, repo, identity = dirs
    paths = [
        settings_path("host-shared", home=home, repo_root=repo, repo_identity=identity),
        settings_path("repo-shared", home=home, repo_root=repo, repo_identity=identity),
        settings_path("repo-git", home=home, repo_root=repo, repo_identity=identity),
        settings_path("repo-clone", home=home, repo_root=repo, repo_identity=identity),
    ]
    assert len(set(paths)) == 4, f"Expected 4 distinct paths, got duplicates: {paths}"


# ---------------------------------------------------------------------------
# T2.4-15  settings_path raises ValueError on unknown locality
# ---------------------------------------------------------------------------


def test_settings_path_unknown_locality(dirs):
    home, repo, identity = dirs
    with pytest.raises((ValueError, KeyError)):
        settings_path("unknown-locality", home=home, repo_root=repo, repo_identity=identity)
