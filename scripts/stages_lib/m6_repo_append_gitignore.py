"""ADR-0014 4-callable Python contract for stage m6.repo.append-gitignore.

Stage identity: M6 | automated | repo-git | both platforms
Purpose: Append three protective .gitignore entries to <repo>/.gitignore
         (idempotent, via a managed block).

The three entries (from stages-registry.yml description):
  - *.local.*     (local config files, e.g., settings.local.yml)
  - claims/       (per-clone worktree claim state)
  - .venv/        (per-repo uv venv materialized by m2.repo.sync-venv)

Managed block markers:
  # >>> board-superpowers managed >>>
  <entries>
  # <<< board-superpowers managed <<<

The markers let executor distinguish its own prior output from user content.
One block per .gitignore — multiple blocks are not supported (walking skeleton).

ctx contract: any object with attribute ``repo_root: pathlib.Path``.
Callers may use ``types.SimpleNamespace(repo_root=pathlib.Path(...))`` for
testing; the lifecycle runtime populates it at execution time.

I/O contract (ADR-0014):
  - compute_target_state: pure, no I/O
  - target_state_predicate: pure, no I/O
  - idempotency_check: read-only (.gitignore read)
  - executor: writes .gitignore (the only callable that mutates)
"""

from __future__ import annotations

import pathlib
from typing import Any

# ---------------------------------------------------------------------------
# Internal constants
# ---------------------------------------------------------------------------

_REQUIRED_ENTRIES: list[str] = ["*.local.*", "claims/", ".venv/"]

_BLOCK_OPEN = "# >>> board-superpowers managed >>>"
_BLOCK_CLOSE = "# <<< board-superpowers managed <<<"


# ---------------------------------------------------------------------------
# 4-callable ADR-0014 contract
# ---------------------------------------------------------------------------


def compute_target_state(ctx: Any) -> dict:
    """Return the expected target state for this stage.

    Pure function — no I/O. ``ctx`` is accepted for signature uniformity
    but is not read (all M6 state is statically known).

    Returns:
        {"required_entries": ["*.local.*", "claims/", ".venv/"]}
    """
    return {"required_entries": list(_REQUIRED_ENTRIES)}


def target_state_predicate(state: Any) -> bool:
    """Return True if *state* matches the expected target_state schema.

    Validates:
    - state is a dict
    - "required_entries" key is present
    - "required_entries" value is a list
    """
    if not isinstance(state, dict):
        return False
    entries = state.get("required_entries")
    if entries is None:
        return False
    if not isinstance(entries, list):
        return False
    return True


def idempotency_check(ctx: Any) -> dict:
    """Read .gitignore and report whether the managed block is present.

    Read-only — does NOT write.

    Returns a dict:
        {
            "present": bool,       # True if managed block found with matching content
            "current_state": {
                "required_entries": list[str]  # entries inside managed block (may be [])
            }
        }

    "present" is True iff the managed block exists AND its content exactly
    matches compute_target_state(ctx)["required_entries"].  This lets
    executor skip re-writing when the block already matches target.
    """
    gi_path = pathlib.Path(ctx.repo_root) / ".gitignore"
    if not gi_path.exists():
        return {"present": False, "current_state": {"required_entries": []}}

    content = gi_path.read_text(encoding="utf-8")
    entries = _parse_managed_block(content)
    if entries is None:
        # Managed block absent
        return {"present": False, "current_state": {"required_entries": []}}

    target = _REQUIRED_ENTRIES
    present = entries == target
    return {"present": present, "current_state": {"required_entries": entries}}


def executor(ctx: Any) -> dict:
    """Append / update the managed block in <repo>/.gitignore.

    Idempotent:
    - If managed block absent → append block with all target entries.
    - If managed block present and matches target → no-op (applied=False).
    - If managed block present but content drifts → replace block in-place.

    Returns:
        {
            "applied": bool,           # False if file was already correct
            "message": str,
            "side_effects": list[str]  # human-readable list of mutations
        }
    """
    gi_path = pathlib.Path(ctx.repo_root) / ".gitignore"
    target_entries = list(_REQUIRED_ENTRIES)

    if gi_path.exists():
        original = gi_path.read_text(encoding="utf-8")
    else:
        original = ""

    existing_entries = _parse_managed_block(original)

    if existing_entries == target_entries:
        # Block present and content matches — no-op
        return {
            "applied": False,
            "message": ".gitignore managed block already matches target",
            "side_effects": [],
        }

    if existing_entries is None:
        # Block absent — append
        new_content = _append_managed_block(original, target_entries)
        action = "appended managed block to .gitignore"
    else:
        # Block present but drifted — replace
        new_content = _replace_managed_block(original, target_entries)
        action = "replaced drifted managed block in .gitignore"

    gi_path.write_text(new_content, encoding="utf-8")
    return {
        "applied": True,
        "message": action,
        "side_effects": [f"wrote {gi_path}"],
    }


# ---------------------------------------------------------------------------
# Internal helpers — not part of the 4-callable public surface
# ---------------------------------------------------------------------------


def _parse_managed_block(content: str) -> list[str] | None:
    """Return the list of entries inside the managed block, or None if absent.

    Returns None when no managed block markers are found.
    Returns a list (possibly empty) of the non-empty, non-comment lines
    between the markers.
    """
    lines = content.splitlines()
    try:
        open_idx = lines.index(_BLOCK_OPEN)
        close_idx = lines.index(_BLOCK_CLOSE)
    except ValueError:
        return None

    if close_idx <= open_idx:
        return None  # malformed block (close before open)

    entries = [
        line.strip()
        for line in lines[open_idx + 1 : close_idx]
        if line.strip() and not line.strip().startswith("#")
    ]
    return entries


def _build_block_text(entries: list[str]) -> str:
    """Return the managed block as a string (including markers, no leading newline)."""
    inner = "\n".join(entries)
    return f"{_BLOCK_OPEN}\n{inner}\n{_BLOCK_CLOSE}\n"


def _append_managed_block(content: str, entries: list[str]) -> str:
    """Append the managed block to *content*, ensuring exactly one blank-line separator."""
    block = _build_block_text(entries)
    if content and not content.endswith("\n"):
        content += "\n"
    if content:
        content += "\n"
    content += block
    return content


def _replace_managed_block(content: str, entries: list[str]) -> str:
    """Replace the existing managed block in *content* with updated entries."""
    lines = content.splitlines(keepends=True)
    try:
        open_idx = next(
            i for i, l in enumerate(lines) if l.rstrip("\n") == _BLOCK_OPEN
        )
        close_idx = next(
            i for i, l in enumerate(lines) if l.rstrip("\n") == _BLOCK_CLOSE
        )
    except StopIteration:
        # Block markers not found — fall back to append
        return _append_managed_block(content, entries)

    new_block_lines = [_BLOCK_OPEN + "\n"]
    for entry in entries:
        new_block_lines.append(entry + "\n")
    new_block_lines.append(_BLOCK_CLOSE + "\n")

    new_lines = lines[:open_idx] + new_block_lines + lines[close_idx + 1 :]
    return "".join(new_lines)
