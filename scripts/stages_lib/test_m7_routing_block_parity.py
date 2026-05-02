"""Byte-parity test: agentsmd-routing.md fence content vs M7 inline constants.

Per ADR-0018 (multi-stage routing-block protocol), the M7 routing-block
injection stages hard-code the canonical bytes inline (`_ROUTING_RULE_CONTENT`
and `_SKILL_ROUTING_CONTENT`) for atomic-stage purity — no runtime file IO
inside a deterministic stage. The maintainer-facing source-of-truth is
`skills/using-board-superpowers/references/agentsmd-routing.md`, between
the `<!-- routing-block:start -->` and `<!-- routing-block:end -->` fence
sentinels.

This test enforces byte equality between the two:

  * fence first half  (everything before the H3 split marker) ==
    `_ROUTING_RULE_CONTENT`
  * fence second half (the H3 split marker line and everything after) ==
    `_SKILL_ROUTING_CONTENT`

Any maintainer edit to one location MUST be paired with an edit to the
other, or CI fails loudly here. Without this test the two locations could
silently drift, producing routing-block injections that don't match the
documented SoT.

Audit reference: PR #75 audit synthesis comment, finding B3 (m7 inline
block content drift hazard).
"""

from __future__ import annotations

from pathlib import Path

from stages_lib.m7_repo_inject_block_routing_rule import _ROUTING_RULE_CONTENT
from stages_lib.m7_repo_inject_block_skill_routing import _SKILL_ROUTING_CONTENT


# Path resolution: this test file lives at scripts/stages_lib/<name>.py.
# parents[0] = stages_lib/, parents[1] = scripts/, parents[2] = worktree root.
_WORKTREE_ROOT = Path(__file__).resolve().parents[2]
_REFERENCE_DOC = (
    _WORKTREE_ROOT
    / "skills"
    / "using-board-superpowers"
    / "references"
    / "agentsmd-routing.md"
)

_FENCE_START = "<!-- routing-block:start -->"
_FENCE_END = "<!-- routing-block:end -->"
_SPLIT_MARKER = "\n\n### How to compose gstack and superpowers"


def _extract_fence_content() -> str:
    """Return normalized bytes between the fence sentinels.

    Mirrors the historical bsp_inject_routing_block normalization recipe
    (LF-only line endings, leading/trailing newlines stripped) so the
    extracted bytes are directly comparable to the M7 stages' inline
    constants.

    Sentinel matching is line-anchored: only lines whose content is
    exactly `<!-- routing-block:start -->` (or `:end`) count as fence
    delimiters. The reference doc's prose preamble and epilogue mention
    the sentinels inline (inside backticks) when describing the
    contract; those inline mentions MUST NOT be matched as actual
    fence delimiters or extraction returns 4 bytes from between two
    backtick-wrapped sentinel-name strings on adjacent prose lines.
    """
    text = _REFERENCE_DOC.read_text(encoding="utf-8")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    lines = text.split("\n")
    try:
        start_idx = lines.index(_FENCE_START)
        end_idx = lines.index(_FENCE_END, start_idx + 1)
    except ValueError as exc:
        raise AssertionError(
            f"line-anchored fence sentinels missing in {_REFERENCE_DOC}: "
            f"{exc}"
        )
    inner = "\n".join(lines[start_idx + 1 : end_idx]).strip("\n")
    return inner


def _split_at_h3_marker(content: str) -> tuple[str, str]:
    """Split fence content at the H3 marker.

    The first half is everything before `\\n\\n### How to compose ...`;
    the second half starts at `### How to compose ...` (the two-newline
    separator is consumed, NOT included in either half — it is the
    boundary).
    """
    idx = content.find(_SPLIT_MARKER)
    assert idx >= 0, (
        f"split marker {_SPLIT_MARKER!r} not found in fence content; "
        "fence-content / inline-constant structure assumption broken"
    )
    first = content[:idx]
    second = content[idx + 2 :]  # skip the leading "\n\n"
    return first, second


def test_routing_rule_content_byte_identical_with_reference():
    """_ROUTING_RULE_CONTENT == fence first half (before H3 marker)."""
    fence = _extract_fence_content()
    first, _ = _split_at_h3_marker(fence)
    assert first == _ROUTING_RULE_CONTENT, (
        f"_ROUTING_RULE_CONTENT (len={len(_ROUTING_RULE_CONTENT)}) drifted "
        f"from agentsmd-routing.md fence first half (len={len(first)}). "
        "Edit one location and forget the other? Update both. See ADR-0018."
    )


def test_skill_routing_content_byte_identical_with_reference():
    """_SKILL_ROUTING_CONTENT == fence second half (H3 marker onward)."""
    fence = _extract_fence_content()
    _, second = _split_at_h3_marker(fence)
    assert second == _SKILL_ROUTING_CONTENT, (
        f"_SKILL_ROUTING_CONTENT (len={len(_SKILL_ROUTING_CONTENT)}) drifted "
        f"from agentsmd-routing.md fence second half (len={len(second)}). "
        "Edit one location and forget the other? Update both. See ADR-0018."
    )


def test_split_marker_appears_exactly_once_in_fence():
    """Sanity: the H3 split marker is unambiguous (no false splits)."""
    fence = _extract_fence_content()
    occurrences = fence.count(_SPLIT_MARKER)
    assert occurrences == 1, (
        f"H3 split marker should appear exactly once in fence content; "
        f"found {occurrences}. Test logic depends on a unique split point."
    )
