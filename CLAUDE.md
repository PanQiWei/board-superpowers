# board-superpowers — project instructions

This repo **is** the plugin. Sessions here are plugin-maintainer
sessions, not product-user sessions. See @README.md for the
user-facing overview.

## Self-hosting

This repo uses its own plugin. The `board-superpowers:routing` block
at the bottom of this file is mirrored verbatim from
`skills/using-board-superpowers/references/claudemd-routing.md` —
edits to one must land in the other in the same commit.

The `<!-- board-superpowers:routing -->` / `<!-- /board-superpowers:routing -->`
marker pair is matched by tooling. Do not rename, indent, or merge
into surrounding prose.

## Protocol invariants

These are load-bearing because downstream installs depend on them:

- **`scripts/*.sh` are a public contract.** Hooks, skills (via
  `${CLAUDE_PLUGIN_ROOT}`), and user automations call them. Breaking
  changes need a migration note in the PR body.
- **`check-deps.sh` exit codes:** `0` = deps present, `2` = missing.
  No new non-zero codes without updating every caller + branching
  skill.
- **Skill `description` frontmatter is behavior.** Downstream models
  match on it. Treat edits with the same care as code.

## Project-specific skill routing

The global `~/.claude/CLAUDE.md` already routes gstack ↔ superpowers.
In addition, for this repo:

- Editing any `skills/*/SKILL.md` → invoke
  `superpowers:writing-skills` first.
- Second opinion on shell logic → `gstack:/codex`.
- Before tagging a release that touches `scripts/` or `hooks/` →
  `gstack:/cso`.
- **Not applicable here:** `gstack:/ship` `/land-and-deploy`
  `/canary`. This plugin has no deploy target; release = bump
  `plugin.json` + `marketplace.json`, push a git tag.

## Commands

```bash
bash scripts/check-deps.sh                      # preflight; exits 0 or 2
bash scripts/bootstrap-project.sh --help        # one-time per-repo setup
bash scripts/create-card.sh --help              # Manager: create card
bash scripts/claim-card.sh --help               # Consumer: atomic claim
bash scripts/transition-card.sh --help          # move card status
```

<!-- board-superpowers:routing -->
## board-superpowers session routing

This project uses the `board-superpowers` plugin. Any Claude Code
session in this project plays one of two roles:

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
<!-- /board-superpowers:routing -->
