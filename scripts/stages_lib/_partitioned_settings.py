"""Locality-aware settings.yml router — ADR-0024 § Part A four-path table.

Public API
----------
settings_path(locality, *, home, repo_root, repo_identity) -> Path
    Return the absolute filesystem path for the given locality.

read_settings(locality, **kwargs) -> dict
    Load and parse YAML at settings_path(); empty dict if file absent.

write_settings(locality, data, **kwargs) -> None
    Atomic write (write to .tmp + os.replace) of yaml.safe_dump(data).

get_module_section(locality, module_id, **kwargs) -> dict
    Read file, return data['modules'][module_id], empty dict if missing.

update_module_section(locality, module_id, section, **kwargs) -> None
    Read-modify-write; merge section into data['modules'][module_id];
    preserve other modules and top-level setup.

ADR-0024 § Part A four-path table:
  host-shared:  home / '.board-superpowers' / 'settings.yml'
  repo-shared:  home / '.board-superpowers' / 'repos' / repo_identity / 'settings.yml'
                  NOTE: HOST-side, NOT under <repo>/
  repo-git:     repo_root / '.board-superpowers' / 'settings.yml'
  repo-clone:   repo_root / '.board-superpowers' / 'settings.local.yml'

ADR-0021: each settings.yml carries two top-level sections:
  - stages_completed[] (machine view, lifecycle source-of-truth)
  - modules.<id>       (architect-facing config-items projection)

Write strategy: atomic mktemp + os.replace to guarantee no partial writes.
YAML emit: yaml.safe_dump with sort_keys=True for deterministic output.
"""

from __future__ import annotations

import os
import tempfile
from pathlib import Path
from typing import Literal

import yaml

# Locality type alias — exactly the four ADR-0024 localities
Locality = Literal["host-shared", "repo-shared", "repo-git", "repo-clone"]

# ---------------------------------------------------------------------------
# Path resolution
# ---------------------------------------------------------------------------

_LOCALITY_HINT = (
    "locality must be one of: 'host-shared', 'repo-shared', 'repo-git', 'repo-clone'"
)


def settings_path(
    locality: Locality,
    *,
    home: Path,
    repo_root: Path,
    repo_identity: str,
) -> Path:
    """Return the absolute filesystem path for the given locality.

    Per ADR-0024 § Part A:
      host-shared:  home / '.board-superpowers' / 'settings.yml'
      repo-shared:  home / '.board-superpowers' / 'repos' / repo_identity / 'settings.yml'
                    (HOST-side, NOT under <repo>/)
      repo-git:     repo_root / '.board-superpowers' / 'settings.yml'
      repo-clone:   repo_root / '.board-superpowers' / 'settings.local.yml'
    """
    home = Path(home)
    repo_root = Path(repo_root)

    if locality == "host-shared":
        return home / ".board-superpowers" / "settings.yml"
    elif locality == "repo-shared":
        # HOST-side path: ~/.board-superpowers/repos/<owner>/<repo>/settings.yml
        # repo_identity is e.g. "PanQiWei/board-superpowers"
        return home / ".board-superpowers" / "repos" / repo_identity / "settings.yml"
    elif locality == "repo-git":
        return repo_root / ".board-superpowers" / "settings.yml"
    elif locality == "repo-clone":
        return repo_root / ".board-superpowers" / "settings.local.yml"
    else:
        raise ValueError(f"Unknown locality: {locality!r}. {_LOCALITY_HINT}")


# ---------------------------------------------------------------------------
# Read / Write
# ---------------------------------------------------------------------------


def read_settings(locality: Locality, **kwargs) -> dict:
    """Load and parse YAML at settings_path(); empty dict if file absent."""
    path = settings_path(locality, **kwargs)
    if not path.exists():
        return {}
    with open(path, "r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    return data if isinstance(data, dict) else {}


def write_settings(
    locality: Locality,
    data: dict,
    **kwargs,
) -> None:
    """Atomic write (write to .tmp + os.replace) of yaml.safe_dump(data).

    Creates parent directories as needed.
    Uses mktemp in the same directory as the final path so os.replace
    is always a same-filesystem rename (atomic on POSIX).
    """
    path = settings_path(locality, **kwargs)
    path.parent.mkdir(parents=True, exist_ok=True)

    content = yaml.safe_dump(
        data,
        default_flow_style=False,
        sort_keys=True,
        allow_unicode=True,
        indent=2,
        width=10**9,
    )

    # Atomic write: tmp in same dir → os.replace
    fd, tmp_path = tempfile.mkstemp(
        prefix=".bsp-settings-",
        dir=str(path.parent),
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(content)
        os.replace(tmp_path, str(path))
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


# ---------------------------------------------------------------------------
# Module section helpers
# ---------------------------------------------------------------------------


def get_module_section(
    locality: Locality,
    module_id: str,
    **kwargs,
) -> dict:
    """Read file, return data['modules'][module_id]; empty dict if missing."""
    data = read_settings(locality, **kwargs)
    modules = data.get("modules", {})
    if not isinstance(modules, dict):
        return {}
    section = modules.get(module_id, {})
    return section if isinstance(section, dict) else {}


def update_module_section(
    locality: Locality,
    module_id: str,
    section: dict,
    **kwargs,
) -> None:
    """Read-modify-write; merge section into data['modules'][module_id].

    Merge semantics: section keys WIN over existing keys (shallow merge).
    Pre-existing keys in modules[module_id] that are NOT in section are preserved.
    All other top-level keys (setup, stages_completed, etc.) and sibling
    modules sections are preserved unchanged.
    """
    data = read_settings(locality, **kwargs)

    # Ensure modules dict exists
    if "modules" not in data or not isinstance(data["modules"], dict):
        data["modules"] = {}

    # Merge: existing values first, new section values win
    existing = data["modules"].get(module_id, {})
    if not isinstance(existing, dict):
        existing = {}
    merged = {**existing, **section}
    data["modules"][module_id] = merged

    write_settings(locality, data, **kwargs)
