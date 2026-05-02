"""ADR-0014 4-callable contract for stage m7.repo.inject-block.routing-rule.

Stage identity: M7 | automated | repo-git | both platforms
Purpose: Inject the `routing-rule` required block (session routing trigger prose)
         into target AGENTS.md (and CLAUDE.md if applicable) per ADR-0018
         multi-stage routing-block protocol.

Block content: declares this repo uses board-superpowers and routes sessions.
Managed block markers (ADR-0018 § Decision element 2):
  <!-- board-superpowers:routing-rule -->
  <!-- /board-superpowers:routing-rule -->

Block size cap: 4096 bytes (block_max_bytes from registry, per ADR-0018 § 5).
Depends on: m7.repo.detect-agentsmd-form (form cached in repo-shared settings.yml).

Stub-redirect handling: CLAUDE.md that is ≤30 lines AND contains `@<file>.md`
is skipped (same rule as bsp_inject_routing_block in common.sh).

target_state_schema (from registry):
  {block_name: "routing-rule",
   block_present_in_targets: list[str],
   block_bytes?: int}

ctx contract: any object with attributes home, repo_root, repo_identity.
"""

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any

from stages_lib._m7_inject_helpers import (
    apply_block_to_file,
    get_target_files,
    is_stub_redirect,
    parse_managed_block,
    persist_block_hash,
)

# ---------------------------------------------------------------------------
# Block markers and content
# ---------------------------------------------------------------------------

_BLOCK_NAME = "routing-rule"
_BLOCK_OPEN = f"<!-- board-superpowers:{_BLOCK_NAME} -->"
_BLOCK_CLOSE = f"<!-- /board-superpowers:{_BLOCK_NAME} -->"
_BLOCK_MAX_BYTES = 4096

# Session routing section — extracted from
# skills/using-board-superpowers/references/agentsmd-routing.md fence region (first half).
_ROUTING_RULE_CONTENT = """\
## board-superpowers session routing

This project uses the `board-superpowers` plugin (v0.5.0).
Any Claude Code session in this project plays one of two roles:

- **Board Consumer** — if the first message contains `[board-card:#N]`,
  or the user asks to work on / claim / implement card N, invoke the
  `consuming-card` skill immediately. That skill owns the full
  lifecycle: claim → implement → PR → update board.
- **Board Manager** — if the user asks about planning today's work,
  reviewing the board, decomposing a requirement, triaging blocked
  cards, or running a retro, invoke the `managing-board` skill.
- When unsure, invoke `using-board-superpowers` first.

board-superpowers depends on the `superpowers` and `gstack` plugins
and will delegate design and execution work to them. Do not
reimplement what they already do."""


def _build_block() -> str:
    return f"{_BLOCK_OPEN}\n{_ROUTING_RULE_CONTENT}\n{_BLOCK_CLOSE}\n"


def _content_hash() -> str:
    return hashlib.sha256(_ROUTING_RULE_CONTENT.encode("utf-8")).hexdigest()


# ---------------------------------------------------------------------------
# 4-callable ADR-0014 contract
# ---------------------------------------------------------------------------


def compute_target_state(ctx: Any) -> dict:
    """Return expected target_state: which files currently contain the block."""
    repo_root = Path(ctx.repo_root)
    block_bytes = len(_build_block().encode("utf-8"))
    targets = get_target_files(ctx)
    present_in = []
    for t in targets:
        if t.exists():
            text = t.read_text(encoding="utf-8")
            if parse_managed_block(text, _BLOCK_OPEN, _BLOCK_CLOSE) == _ROUTING_RULE_CONTENT:
                present_in.append(str(t.relative_to(repo_root)))
    return {
        "block_name": _BLOCK_NAME,
        "block_present_in_targets": present_in,
        "block_bytes": block_bytes,
    }


def target_state_predicate(state: Any) -> bool:
    """Return True if *state* satisfies the registry target_state_schema."""
    if not isinstance(state, dict):
        return False
    if state.get("block_name") != _BLOCK_NAME:
        return False
    bpit = state.get("block_present_in_targets")
    if not isinstance(bpit, list):
        return False
    return True


def idempotency_check(ctx: Any) -> dict:
    """Read-only: check if all target files have the managed block with matching content."""
    targets = get_target_files(ctx)
    if not targets:
        return {"present": False, "current_state": {"target_files": []}}

    all_present = True
    status = {}
    for t in targets:
        if not t.exists():
            all_present = False
            status[t.name] = "file-absent"
            continue
        text = t.read_text(encoding="utf-8")
        inner = parse_managed_block(text, _BLOCK_OPEN, _BLOCK_CLOSE)
        if inner == _ROUTING_RULE_CONTENT:
            status[t.name] = "matches"
        elif inner is None:
            all_present = False
            status[t.name] = "block-absent"
        else:
            all_present = False
            status[t.name] = "drifted"
    return {"present": all_present, "current_state": {"files": status}}


def executor(ctx: Any) -> dict:
    """Inject routing-rule block into all target files.

    - Block absent → append.
    - Block present, content matches → no-op.
    - Block present, content drifted → replace in-place.
    - Enforces 4 KiB cap per ADR-0018 § 5.

    Returns: {applied: bool, message: str, side_effects: list[str]}
    """
    block_bytes = len(_build_block().encode("utf-8"))
    if block_bytes > _BLOCK_MAX_BYTES:
        return {
            "applied": False,
            "message": (
                f"routing-rule block exceeds 4 KiB cap "
                f"({block_bytes} > {_BLOCK_MAX_BYTES} bytes) — refusing to inject"
            ),
            "side_effects": [],
        }

    targets = get_target_files(ctx)
    if not targets:
        return {
            "applied": False,
            "message": "no target files to inject (no AGENTS.md or CLAUDE.md found)",
            "side_effects": [],
        }

    side_effects = []
    any_changed = False
    for t in targets:
        if is_stub_redirect(t):
            continue
        changed, action = apply_block_to_file(
            t, _BLOCK_OPEN, _BLOCK_CLOSE, _ROUTING_RULE_CONTENT, prefix=".bsp-m7-rr-"
        )
        if changed:
            any_changed = True
            side_effects.append(action)

    if not any_changed:
        return {
            "applied": False,
            "message": "routing-rule block already present and matching in all target files",
            "side_effects": [],
        }

    persist_block_hash(ctx, "routing_rule_block_hash", _content_hash())
    return {
        "applied": True,
        "message": f"routing-rule block injected into {len(side_effects)} file(s)",
        "side_effects": side_effects,
    }
