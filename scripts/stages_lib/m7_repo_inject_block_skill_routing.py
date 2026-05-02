"""ADR-0014 4-callable contract for stage m7.repo.inject-block.skill-routing.

Stage identity: M7 | automated | repo-git | both platforms
Purpose: Inject the `skill-routing` required block (Manager / Consumer dispatch
         rules — "How to compose gstack and superpowers") into target AGENTS.md
         per ADR-0018 multi-stage routing-block protocol.

Block content: skill-routing composition guidance (phase-of-work routing).
Managed block markers: <!-- board-superpowers:skill-routing --> / <!-- /board-superpowers:skill-routing -->
Block size cap: 4096 bytes (block_max_bytes from registry, per ADR-0018 § 5).
Depends on: m7.repo.detect-agentsmd-form (form cached in repo-shared settings.yml).

target_state_schema (from registry):
  {block_name: "skill-routing",
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

_BLOCK_NAME = "skill-routing"
_BLOCK_OPEN = f"<!-- board-superpowers:{_BLOCK_NAME} -->"
_BLOCK_CLOSE = f"<!-- /board-superpowers:{_BLOCK_NAME} -->"
_BLOCK_MAX_BYTES = 4096

# Manager/Consumer dispatch rules — extracted from
# skills/using-board-superpowers/references/agentsmd-routing.md fence region (second half).
_SKILL_ROUTING_CONTENT = """\
### How to compose gstack and superpowers

Both plugins are runtime dependencies of board-superpowers. They are
complementary, not alternatives — route by phase of work, not by
preference.

**Division of labor**

- **gstack owns the bookends.** Direction-setting before a card is
  claimed (is this worth building, what's the right shape) and
  delivery-side verification (code review, QA, security). CEO /
  design / QA / security-officer viewpoints.
- **superpowers owns the middle.** The coding-discipline loop:
  `brainstorming` → `writing-plans` → `test-driven-development` →
  `systematic-debugging` → `verification-before-completion` →
  `requesting-code-review`. TDD is mandatory inside this loop.
- **Conflict arbitration** follows `superpowers:using-superpowers`:
  **user instructions > skill > default behavior.** A gstack skill's
  "plan is ready, start coding" advice does not override superpowers'
  TDD discipline unless the user explicitly says so in the current
  conversation.

**Typical flow — menu, not checklist**

Pick skills that fit the card; do not run them all.

Pre-card intake (Manager's Intake routine routes here before a card
is created):

1. `gstack:/office-hours` or `/plan-ceo-review` — is this worth
   building.
2. `gstack:/plan-eng-review` — lock the architecture.
3. `superpowers:brainstorming` — sharpen requirements and design.
4. `superpowers:writing-plans` — turn the output into an executable
   plan.

Implementation (inside a Consumer session):

5. `superpowers:test-driven-development` drives Red → Green →
   Refactor.
6. Stuck? `superpowers:systematic-debugging`, or
   `gstack:/investigate` for a second angle.
7. Parallelizable subtasks:
   `superpowers:dispatching-parallel-agents` or
   `superpowers:subagent-driven-development`.

Self-check and delivery (still inside the Consumer session, before
opening the PR):

8. `superpowers:verification-before-completion` — evidence-first; do
   not claim "done" without it.
9. `gstack:/review` — production-bug viewpoint.
10. `superpowers:requesting-code-review` — independent
    second-pair-of-eyes.
11. `gstack:/qa <url>` — real-browser QA. Mandatory for any
    UI-touching card.
12. `gstack:/cso` — security / OWASP / STRIDE audit. superpowers has
    no equivalent.

Release, deploy, canary, and document-release skills
(`gstack:/ship`, `/canary`, `/land-and-deploy`,
`/document-release`) are project-specific. Enable them only if they
match this repo's deployment shape; otherwise use whatever release
flow the project already has. board-superpowers does not prescribe
a release process.

**Pitfalls**

- **Skill-name collisions.** Two large libraries have overlapping
  descriptions. Route by this block, not by letting the model guess
  from skill descriptions.
- **Browser tools — one source.** Always use `gstack:/browse`. Do
  not mix with other browser tooling.
- **TDD is not optional** inside
  `superpowers:test-driven-development`. An adjacent planning
  skill's "start coding" suggestion does not excuse skipping
  Red → Green → Refactor."""


def _build_block() -> str:
    return f"{_BLOCK_OPEN}\n{_SKILL_ROUTING_CONTENT}\n{_BLOCK_CLOSE}\n"


def _content_hash() -> str:
    return hashlib.sha256(_SKILL_ROUTING_CONTENT.encode("utf-8")).hexdigest()


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
            if parse_managed_block(text, _BLOCK_OPEN, _BLOCK_CLOSE) == _SKILL_ROUTING_CONTENT:
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
        if inner == _SKILL_ROUTING_CONTENT:
            status[t.name] = "matches"
        elif inner is None:
            all_present = False
            status[t.name] = "block-absent"
        else:
            all_present = False
            status[t.name] = "drifted"
    return {"present": all_present, "current_state": {"files": status}}


def executor(ctx: Any) -> dict:
    """Inject skill-routing block into all target files.

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
                f"skill-routing block exceeds 4 KiB cap "
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
            t, _BLOCK_OPEN, _BLOCK_CLOSE, _SKILL_ROUTING_CONTENT, prefix=".bsp-m7-sr-"
        )
        if changed:
            any_changed = True
            side_effects.append(action)

    if not any_changed:
        return {
            "applied": False,
            "message": "skill-routing block already present and matching in all target files",
            "side_effects": [],
        }

    persist_block_hash(ctx, "skill_routing_block_hash", _content_hash())
    return {
        "applied": True,
        "message": f"skill-routing block injected into {len(side_effects)} file(s)",
        "side_effects": side_effects,
    }
