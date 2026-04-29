# board-superpowers routing block — source of truth

This file holds the canonical bytes that `scripts/bootstrap-project.sh`
step 4 injects into a consuming repo's AGENTS.md and CLAUDE.md,
between the marker pair (the literal HTML-comment opening + closing
sentinels are deliberately not shown verbatim in this header so that
the helper's marker-scan does not match against them; see
`skills/using-board-superpowers/SKILL.md` Step 1 for the verbatim
form, and `scripts/lib/common.sh:bsp_inject_routing_block` for the
matcher).

**Injection contract** (the routing-block injection step of the
per-repo bootstrap, implemented in
`scripts/lib/common.sh:bsp_inject_routing_block`):

1. The injection helper reads THIS file and locates the fence
   sentinels — `<!-- routing-block:start -->` and
   `<!-- routing-block:end -->` — to extract ONLY the bytes between
   them. The docstring header above the fence (this prose) is NOT
   injected. Anything outside the fence is treated as
   maintainer-facing notes.
2. The extracted bytes are normalized — strip UTF-8 BOM if present,
   replace CRLF / CR with LF, strip leading + trailing whitespace
   newlines so the injected block is tight.
3. SHA256 over the normalized fence-bounded bytes (with a single
   trailing newline trimmed) yields the recorded hash.
4. The helper writes the block between the target's marker pair
   (`<!-- board-superpowers:routing -->` /
   `<!-- /board-superpowers:routing -->`) into AGENTS.md and CLAUDE.md
   and records one entry per file —
   `{target_file, block_hash: "sha256:<hex>", injected_at: <iso8601>}`
   — into `~/.board-superpowers/repos/<normalized>/state.yml`'s
   `routing_blocks:` list.
5. The `board-superpowers:migrating-repo-version` skill consumes
   `state.yml:routing_blocks[]` hashes for tamper detection at plugin
   upgrade time.

LF-only line endings. No BOM. Final line of the block ends with a
single LF.

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

This project uses the `board-superpowers` plugin (v0.2.0).
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
