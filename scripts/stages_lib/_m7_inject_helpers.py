"""Shared helpers for M7 routing-block injection stages (ADR-0018).

Used by m7_repo_inject_block_routing_rule and m7_repo_inject_block_skill_routing.
Not part of the ADR-0014 4-callable public surface — internal to stages_lib.
"""

from __future__ import annotations

import os
import re
import tempfile
from pathlib import Path
from typing import Any

import stages_lib._partitioned_settings as _ps

_MODULE_ID = "m7_agent_routing"


def get_form_from_cache(ctx: Any) -> str:
    """Return the cached agentsmd form string; '' if not set."""
    cached = _ps.get_module_section(
        "repo-shared",
        _MODULE_ID,
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )
    form_data = cached.get("agentsmd_form", {}) if isinstance(cached, dict) else {}
    if isinstance(form_data, dict):
        return form_data.get("form", "")
    return ""


def is_stub_redirect(path: Path) -> bool:
    """Return True if path is a CC @-include stub-redirect (≤30 lines + @<file>.md)."""
    if not path.exists():
        return False
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    lines = text.splitlines()
    if len(lines) > 30:
        return False
    return any(re.match(r"^@[A-Za-z0-9./_-]+\.md\s*$", line) for line in lines)


def get_target_files(ctx: Any) -> list[Path]:
    """Determine which files to inject into based on cached form."""
    repo_root = Path(ctx.repo_root)
    form = get_form_from_cache(ctx)

    targets = []
    if form in ("codex-only", "dual", ""):
        agents = repo_root / "AGENTS.md"
        if agents.exists() or form in ("codex-only", "dual"):
            targets.append(agents)
    if form in ("cc-only", "dual"):
        claude = repo_root / "CLAUDE.md"
        if not is_stub_redirect(claude):
            targets.append(claude)
    if not targets:
        agents = repo_root / "AGENTS.md"
        if agents.exists():
            targets.append(agents)
    return targets


def parse_managed_block(text: str, block_open: str, block_close: str) -> str | None:
    """Extract inner content between managed block markers; None if absent."""
    try:
        open_idx = text.index(block_open)
        close_idx = text.index(block_close)
    except ValueError:
        return None
    if close_idx <= open_idx:
        return None
    inner = text[open_idx + len(block_open):close_idx]
    return inner.strip("\n")


def replace_managed_block(content: str, block_open: str, block_close: str, new_inner: str) -> str:
    """Replace existing managed block's inner content with new_inner."""
    open_idx = content.index(block_open)
    close_idx = content.index(block_close)
    before = content[:open_idx]
    after = content[close_idx + len(block_close):]
    return before + f"{block_open}\n{new_inner}\n{block_close}" + after


def apply_block_to_file(
    path: Path,
    block_open: str,
    block_close: str,
    block_inner: str,
    prefix: str = ".bsp-m7-",
) -> tuple[bool, str]:
    """Inject or update managed block in *path*. Atomic write.

    Returns (changed: bool, action_description: str).
    """
    original = path.read_text(encoding="utf-8") if path.exists() else ""
    existing_inner = parse_managed_block(original, block_open, block_close)

    if existing_inner == block_inner:
        return False, "already matches"

    if existing_inner is None:
        managed_block = f"{block_open}\n{block_inner}\n{block_close}\n"
        sep = "\n" if original and not original.endswith("\n\n") else ""
        if original and not original.endswith("\n"):
            original += "\n"
        new_content = original + ("\n" if original else "") + managed_block
        action = f"appended block to {path.name}"
    else:
        new_content = replace_managed_block(original, block_open, block_close, block_inner)
        action = f"replaced drifted block in {path.name}"

    parent = path.parent
    parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=prefix, dir=str(parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(new_content)
        os.replace(tmp_path, str(path))
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise

    return True, action


def persist_block_hash(ctx: Any, field: str, hash_hex: str) -> None:
    """Persist block hash to repo-git settings.yml § modules.m7_agent_routing."""
    _ps.update_module_section(
        "repo-git",
        _MODULE_ID,
        {field: hash_hex},
        home=Path(ctx.home),
        repo_root=Path(ctx.repo_root),
        repo_identity=ctx.repo_identity,
    )
