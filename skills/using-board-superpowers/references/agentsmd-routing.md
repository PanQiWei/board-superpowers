# board-superpowers routing block — source of truth

This file holds the canonical bytes that the M7 setup-stages inject
into a consuming repo's AGENTS.md and CLAUDE.md, between the marker
pair (the literal HTML-comment opening + closing sentinels are
deliberately not shown verbatim in this header so that the helpers'
marker-scan does not match against them; see
`skills/using-board-superpowers/SKILL.md` Step 1 for the verbatim
form).

**Injection contract** (per ADR-0018, multi-stage routing-block
protocol):

1. Two M7 setup-stages own the injection — `m7.repo.inject-block-
   routing-rule` (writes the routing-rule block) and
   `m7.repo.inject-block-skill-routing` (writes the skill-routing
   block). Helpers live in
   `scripts/stages_lib/m7_repo_inject_block_routing_rule.py` and
   `scripts/stages_lib/m7_repo_inject_block_skill_routing.py`.
2. Each M7 stage hard-codes its half of the canonical bytes inline
   as a Python module-level constant — `_ROUTING_RULE_CONTENT` and
   `_SKILL_ROUTING_CONTENT` respectively — for atomic-stage purity
   (no runtime file IO inside a deterministic stage). The bytes
   between this file's `<!-- routing-block:start -->` and
   `<!-- routing-block:end -->` fence are the maintainer-facing
   source-of-truth; the inline constants and the fence are kept in
   strict byte-equality by
   `scripts/stages_lib/test_m7_routing_block_parity.py` (any
   maintainer edit to one location MUST be paired with an edit to the
   other or CI fails loudly).
3. The fence content is split into two halves at the H3 marker
   `### How to compose gstack and superpowers`:
   - First half (everything before the H3 line) → `_ROUTING_RULE_CONTENT`.
   - Second half (the H3 line and everything after) → `_SKILL_ROUTING_CONTENT`.
4. Each stage's `executor()` writes its block between the target's
   marker pair (`<!-- board-superpowers:routing -->` /
   `<!-- /board-superpowers:routing -->` for the routing-rule stage;
   `<!-- board-superpowers:skill-routing -->` /
   `<!-- /board-superpowers:skill-routing -->` for the skill-routing
   stage) into AGENTS.md and CLAUDE.md. Each stage records a SHA256
   hash of its inline constant into `modules.lifecycle.<stage_id>`
   inside the repo-shared `settings.yml` per ADR-0013 (lifecycle
   schema) + ADR-0024 (settings.yml file family).
5. The `board-superpowers:bootstrapping-repo` skill consumes the M7
   stages' lifecycle entries for tamper detection on subsequent
   sessions — including plugin-upgrade reconvergence, per ADR-0012's
   absorption of version-transition migrations into the unified
   setup-stages flow.

LF-only line endings. No BOM. Final line of the block ends with a
single LF.

**Editing the canonical bytes.** Edit the bytes between the fence
sentinels in this file, then update the matching inline constant in
the M7 stage helper. The CI parity test will fail if either half
drifts. The two-location authoring discipline is intentional: inline
constants give M7 stages atomic-stage purity, and the parity test
prevents drift.

**Why the fence sentinels differ from the target marker pair.** The
fence keywords (`routing-block:start` / `routing-block:end`) are
distinct from the target file marker keywords
(`board-superpowers:routing` / `/board-superpowers:routing`) so a
naive `find()` for the target marker pair against the source file
returns nothing. This guards against the helper accidentally treating
this docstring as a target file. A sanity check inside the helper
also rejects source content with literal target markers nested inside
the fence.

<!-- routing-block:start -->
## board-superpowers session routing

This project uses the `board-superpowers` plugin (v0.5.0).
Any Claude Code session in this project plays one of two roles:

- **Board Consumer** — if the first message contains `[board-card:#N]`,
  or the user asks to work on / claim / implement card N, invoke the
  `consuming-card` skill immediately. That skill owns the full
  lifecycle: claim → implement → PR → update board.
- **Board Manager** — if the user asks about planning today's work,
  reviewing the board, decomposing a requirement, triaging blocked
  cards, or running a retro, invoke the appropriate Producer routine skill (`briefing-daily`, `intaking-requirement`, `reviewing-pr-queue`, or `triaging-board`).
- When unsure, invoke `using-board-superpowers` first.

board-superpowers depends on the `superpowers` and `gstack` plugins
and will delegate design and execution work to them. Do not
reimplement what they already do.

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
  Red → Green → Refactor.
<!-- routing-block:end -->

## Maintainer notes (NOT injected)

Anything below the closing fence sentinel is for plugin maintainers
only and stays in this file — the helper extracts strictly between
the fence sentinels and discards everything outside.

When updating the routing block content above, remember:

- The fence sentinels (`<!-- routing-block:start -->` and
  `<!-- routing-block:end -->`) must remain on lines by themselves.
- Do NOT place a literal `<!-- board-superpowers:routing -->` or
  `<!-- /board-superpowers:routing -->` between the fence sentinels —
  the helper's sanity check rejects nested target markers.
- The hash recorded in user repos' `state.yml:routing_blocks[]`
  changes whenever the bytes between the fences change. The
  per-repo version-transition migration routine's tamper detection
  treats a hash mismatch as plausible user edit; document the
  change in the v0.x release notes.
- The block intentionally opens with a `## board-superpowers session
  routing` H2 heading so consumer repos' AGENTS.md / CLAUDE.md get a
  visible section title where the block lands. Removing the heading
  changes the hash and breaks visual structure in long target files.
- The injection helper recognises *stub-redirect* target files (≤ 30
  lines AND containing `^@<file>.md$`, e.g. `@AGENTS.md`) and skips
  them silently — `routing_blocks[]` for that target is omitted. This
  is what lets the "AGENTS.md is the SoT, CLAUDE.md is `@AGENTS.md`"
  pattern coexist with dual-file injection. See
  `scripts/lib/common.sh:bsp_inject_routing_block` (the Stub-redirect
  early-out section) for the precise matcher rules.
