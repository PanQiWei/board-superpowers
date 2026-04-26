# board-superpowers — project instructions

This repo **is** the plugin. Sessions here are plugin-maintainer
sessions, not product-user sessions. See `README.md` for the
user-facing overview.

@SKILLS.md

## Project status — v1 spec phase

> **The plugin is intentionally unloadable at runtime during this
> phase.** No `hooks/`, `scripts/`, `skills/`, or `tests/`
> directories exist at the repo root. No `SessionStart` hook
> fires. No skill auto-matches. No callable bash entry point.

The single source of truth for v1 design is
[`docs/architecture/`](./docs/architecture/) — read
`0001-positioning.md` first; the
[`docs/architecture/README.md`](./docs/architecture/README.md)
index lists everything else in canonical order.

This phase ends when v1 implementation lands at the canonical
locations (`hooks/`, `scripts/`, `skills/`, `tests/`) authored
against the spec.

## Required reading

The three documents below are large
(`PLUGIN_DEVELOPMENT.md` ~440 lines,
`MULTI_AGENT_DEVELOPMENT.md` ~700 lines,
`SKILL_DEVELOPMENT.md` ~1290 lines). They are intentionally
**referenced by name, not loaded with `@`-prefix**, so they do
not ride into every session's context. Open them on demand
using `Read` (or its platform equivalent) when the work matches
their scope. **Do not "fix" these references back to
`@`-prefix** — that change would force-load all three docs into
every session and is exactly the anti-pattern they themselves
warn against.

### Quick reference: when to read what

Use this table to decide before any code or spec change. If
multiple rows match, read all matched docs.

| Trigger (what you're about to touch / design) | Read first | Why it's load-bearing |
|-----------------------------------------------|-----------|----------------------|
| Anything under `hooks/`, `scripts/`, `.claude-plugin/`, `.codex-plugin/`, or any `marketplace.json`; editing the plugin manifest, adding / changing a hook event, modifying a script's exit-code / stdout contract | `PLUGIN_DEVELOPMENT.md` | Defines the dual-platform (Claude Code + Codex CLI) contracts every script / hook / manifest in this repo conforms to. Wrong contract change = silently broken downstream installs. |
| Designing or modifying any orchestration where one agent spawns another (Producer → Consumer subagent, agent-teams, `SendMessage`, fan-out / fan-in pipelines, session-id reachback) | `MULTI_AGENT_DEVELOPMENT.md` | Documents the experimental surfaces and the hard rules (e.g., "subagents cannot spawn subagents"). Get this wrong and Mode-2 designs assume capabilities that do not exist. |
| Writing a new `skills/<name>/SKILL.md` or revising any existing one (incl. its `references/`, `scripts/`, `agents/`, `assets/` siblings); adding a new skill type; renaming a skill; touching frontmatter `description` | `SKILL_DEVELOPMENT.md` | Canonical guide for skill design / creation / maintenance — covers the skill-graph framing (entry / molecular / atomic), frontmatter discipline, body skeletons, anti-patterns, testing regimes. Skills are this repo's product surface; sloppy authoring fails downstream invisibly. |
| **Adding, removing, renaming, or re-layering any skill** (anything that changes the topology of `skills/` or the cross-plugin edges board-superpowers depends on) | `SKILLS.md` (already always-loaded) — **edit it BEFORE editing `skills/`**, then both halves land in the same PR. Per `SKILLS.md` "Source-of-truth contract", a `skills/` change without a `SKILLS.md` change is incomplete and unmergeable. | `SKILLS.md` is the source of truth for the skills system topology. Bypassing it lets the catalog drift silently; SPOT (single-point-of-truth) consolidations decay; cross-plugin Mode-2 compatibility loses its checklist. |
| Editing any file under `docs/architecture/` | All three docs that match the affected surface | The spec leads the implementation. A spec change that violates a platform / multi-agent / skill contract is worse than a code change that does, because every future implementer trusts the spec. |
| Anything that **clearly** falls in two or three categories above | All matched docs | These docs are designed to compose. Their cross-references assume each is read when its scope is touched. |

### Doctrine

These three rules close the rationalization loopholes that make
"required reading" merely advisory:

1. **No "I already know."** If the trigger row matches, the doc
   gets read in this session. "I read it last week" is not a
   substitute — the doc may have changed, and your context
   window has long since dropped the relevant passages.
2. **No "this change is too small."** A one-line edit to a
   spec table, a single new field in a SKILL frontmatter, a
   one-character rename of a hook marker — each can violate a
   contract documented in one of these three docs. Smallness of
   diff is not smallness of blast radius.
3. **Same-PR contract update.** If your change makes a contract
   in one of these docs (or in `docs/architecture/`) stale, fix
   the doc in the **same PR** — not a follow-up. Doc lag is the
   primary failure mode that makes this pattern decay over time.

## Architecture at a glance (v1 design)

board-superpowers is a scheduling layer on top of `superpowers`
and `gstack`, packaged as a dual-platform plugin (Claude Code +
OpenAI Codex CLI). At runtime — once v1 implementation lands —
it does four things:

1. **Routes** every session into Manager (board orchestration) or
   Consumer (one-card-to-PR) based on the first user message,
   first-time / version-transition state, or a hook-injected
   intent marker. Routing details:
   [`docs/architecture/0002-product-features-and-flows/02-roles.md`](./docs/architecture/0002-product-features-and-flows/02-roles.md).
2. **Coordinates** work through GitHub. No server-side state.
   Truth lives on the user's GitHub Project (Linear / Jira /
   others via the `BoardAdapter` contract,
   [ADR-0005](./docs/architecture/adr/0005-board-adapter-contract.md)).
   Plugin state files: per-`(host, repo)` host-local
   `state.yml` (out of git) + per-repo committed `config.yml`
   (in git). See [I-13](./docs/architecture/0002-product-features-and-flows/07-cross-cutting-invariants.md).
3. **Delegates** real work — brainstorming, TDD, debugging, QA,
   review, security audit — to `superpowers:*` and `gstack:/*`.
   Composition is permanent
   ([P4b](./docs/architecture/0001-positioning.md), ADR-0004);
   we never reimplement upstream disciplines.
4. **Records** every mutating action to a BYO RDBMS audit log
   (Postgres / MySQL only —
   [ADR-0006 §5](./docs/architecture/adr/0006-producer-autonomy-boundary.md)).
   When the DB is unavailable, every A-class action degrades to
   R-class (architect prompt required).

### Skills system — the v1 catalog (10 skills, 3 layers)

The `skills/` directory **is** the agent's action system. It is
designed as a graph of nodes (skills) and edges (cross-skill
references), per
[`SKILL_DEVELOPMENT.md`](./SKILL_DEVELOPMENT.md) "Skill graph"
section.

```
Entry layer (1) — first-touch router, routes only, never works
─────────────────────────────────────────────────────────────────
  using-board-superpowers     reliable dep gate + role routing
                              (consumes hook-injected INVOKE: markers)

Molecular layer (5) — business workflows, state-machine-shaped
─────────────────────────────────────────────────────────────────
  managing-board              Producer (F-01..F-08, F-10..F-15)
  consuming-card              Consumer (F-C0..F-C14 lifecycle)
  decomposing-into-milestones F-09 + INVEST + vertical slicing
  bootstrapping-repo          F-B1 + F-B2 (first-time setup)
  migrating-repo-version      F-B3 + F-B4 (upgrade migration)

Atomic layer (4) — single-purpose primitives, reflexive (no upward calls)
─────────────────────────────────────────────────────────────────
  board-canon                 state machine + Card schema + branch
                              naming + WIP rules (read-only contract)
  enforcing-pr-contract       PR three-section injection + validation
  classifying-actions         D-AUTONOMY-1 matrix + triage + overrides
  auditing-actions            audit log schema + two-entry rule + BYO DB
```

Dependency direction is **strictly downward**: Entry → Molecular
→ Atomic. Atomic skills MUST NOT call same-plugin skills (they
are reflexes, not orchestrators). Cross-plugin references
(`superpowers:*`, `gstack:/*`) always carry the namespace prefix.

**Full topology** — per-skill descriptions, call graph, SPOT
derivation, bounded-context mapping, cross-plugin edges, and
the maintenance contract — lives in [`SKILLS.md`](./SKILLS.md),
which is `@`-included from this file's top and rides into every
session as standing context. Any change to `skills/` MUST start
with an edit to `SKILLS.md` (per its Source-of-truth contract).

### Hook intent injection — the v1 dispatch optimization

`hooks/session-start.sh` is **intent-injecting**, not just
advisory. On every session start it reads on-disk state and may
emit one of:

```
INVOKE: bootstrapping-repo
REASON: First time using board-superpowers on this (host, repo)
        — manifest.yml absent.
```

```
INVOKE: migrating-repo-version
REASON: Plugin version v0.2.0 detected; state.yml records
        last_seen_version_in_repo=v0.1.0.
```

The marker fast-paths the entry skill's routing decision. The
entry skill ALSO does the same state check itself (CC
`SessionStart` delivery is unreliable) so the marker is an
optimization, not a correctness requirement. Marker grammar
contract:
[`docs/architecture/0005-contracts/02-hook-contracts.md`](./docs/architecture/0005-contracts/02-hook-contracts.md)
§ "Intent-injection markers". Pattern rationale:
[`docs/architecture/0004-component-architecture.md`](./docs/architecture/0004-component-architecture.md)
§ "Hook intent injection pattern".

The pattern generalizes — future hook events
(`PreToolUse`, `PostToolUse`, `Stop`) can use the same
`INVOKE: <skill> / REASON: <line>` payload to broadcast intent.
v1 wires only `SessionStart`.

## Tech stack (v1 target)

- **bash 3.2+** with strict mode for `scripts/`. Callers
  `set -euo pipefail` before sourcing `scripts/lib/common.sh`.
- **gh CLI** with `project` scope (plus `issue` / `pr`
  implicitly).
- **python3** for JSON parsing (gh output → field / option IDs).
- **shellcheck** — the style + correctness gate for every
  script and test.
- **Postgres or MySQL** for the BYO audit log
  ([ADR-0006](./docs/architecture/adr/0006-producer-autonomy-boundary.md)).
- **Claude Code plugin protocol** —
  `${CLAUDE_PLUGIN_ROOT}` env, `hooks/hooks.json` schema,
  `SKILL.md` YAML frontmatter,
  `hookSpecificOutput.additionalContext` payload shape.
- **Codex CLI plugin protocol** — `.codex-plugin/plugin.json`,
  `~/.codex/hooks.json` or `[hooks]` in `~/.codex/config.toml`,
  same `SKILL.md` shape.
- No runtime dependencies beyond the above. No node, no go, no
  compiled artifacts.

## Directory layout

```
board-superpowers/
├── .claude-plugin/
│   ├── plugin.json                 # plugin manifest (kept at root)
│   └── marketplace.json            # local-marketplace manifest (dogfood)
├── docs/
│   └── architecture/               # v1 spec — single source of truth
│       ├── 0001-positioning.md
│       ├── 0002-product-features-and-flows/
│       ├── 0003-domain-model/
│       ├── 0004-component-architecture.md
│       ├── 0005-contracts/
│       ├── 0006-failure-modes.md   (stub)
│       ├── 0007-observability.md   (stub)
│       ├── 0008-test-architecture.md (stub)
│       └── adr/                    # decision records 0001..0008
├── AGENTS.md                       # this file — developer guide
├── CLAUDE.md                       # redirects to AGENTS.md
├── README.md                       # end-user overview (English)
├── README.zh-CN.md                 # end-user overview (Chinese)
├── PLUGIN_DEVELOPMENT.md           # platform contracts (CC + Codex)
├── MULTI_AGENT_DEVELOPMENT.md      # subagent / agent-team contracts
├── SKILL_DEVELOPMENT.md            # skill-authoring guide
└── LICENSE
```

When v1 implementation lands, four new top-level directories
appear (`hooks/`, `scripts/`, `skills/`, optionally `tests/`)
authored against the spec.

## Self-hosting (during spec phase)

The plugin currently does **not** dogfood itself — v1
implementation does not yet exist. Non-trivial spec changes
still get routed to the same two roles conceptually:

- **Spec architecture changes** (anything under
  `docs/architecture/`) — direct edits on a feature branch + PR;
  spec is small enough that ceremony costs more than it gains
  during the spec phase.
- **v1 implementation** (when it begins) — once the first SKILL
  lands, dogfood resumes: every new skill / script / hook lands
  through a Manager → Consumer flow against the plugin's own
  GitHub Project.

## Working tree discipline

This project enforces a strict branch + worktree discipline for
every maintainer session. Two rules:

1. **The repo's checked-out branch at the repo root MUST always
   be `main`.** Never leave the working tree at the repo root
   parked on a feature branch.
2. **Every PR — design spec or implementation — MUST be authored
   in a `git worktree`.** Branch is cut from `main`, work happens
   in the worktree, PR is opened from the worktree's branch. The
   repo root never moves off `main`.

### Why

Multiple parallel maintainer sessions (which is exactly the
working pattern this plugin's product enables) cannot share a
HEAD. If session A is editing on `feat/foo` at the repo root and
session B needs to read `main` to verify a cross-reference, B
either has to stash A's state or wait. Worktrees give every
session its own HEAD without contention.

This is the same physical constraint that drives the product's
**I-7 (one-card-one-worktree)** invariant for Consumer sessions
(see
[`docs/architecture/0002-product-features-and-flows/07-cross-cutting-invariants.md`](./docs/architecture/0002-product-features-and-flows/07-cross-cutting-invariants.md)
I-7). Plugin maintainers eat the same dog food.

### Default worktree path

```
$HOME/.config/superpowers/worktrees/<repo>/<branch>
```

(Overridable via `$BOARD_SP_WORKTREE_DIR`.) This is the same
default location the v1 `claim-card.sh` will use for Consumer
worktrees — maintainer worktrees and Consumer worktrees share
the convention so there is one path to learn, not two.

**Do not** put worktrees inside the repo tree
(`<repo>/.worktrees/<branch>`). Repo-internal worktrees get
scanned by IDEs and file watchers and create visual confusion
about which `main` is the canonical one.

### How to use it

Starting a new piece of work:

```bash
# from the repo root, which is on main
git fetch origin
git switch main && git pull --ff-only

# create a branch + a worktree in one shot
git worktree add "$HOME/.config/superpowers/worktrees/board-superpowers/<branch>" \
  -b <branch> origin/main

# do all work inside that path; never `cd` back to the repo root
# to make changes
cd "$HOME/.config/superpowers/worktrees/board-superpowers/<branch>"
```

If you find yourself with the repo root checked out on a
non-main branch, recover by moving the branch into a worktree:

```bash
# at the repo root, currently on <branch>
git worktree add "$HOME/.config/superpowers/worktrees/board-superpowers/<branch>" <branch>
git switch main
```

The branch's tree state is preserved in the new worktree; the
repo root returns to `main`.

### What this does NOT preclude

- **Reading at the repo root.** `git log`, `git diff`,
  `git show`, file reads — all fine; they don't move HEAD.
- **One-line typo fixes** that genuinely don't warrant a PR can
  be edited at the repo root on `main` and pushed directly. The
  rule is about feature work, not about every keystroke.
- **Switching the repo root to a tag** for release inspection
  (e.g., `git switch --detach v0.2.0` to look at a tagged
  release) — this is a read operation, not work-in-progress.
  Switch back to `main` when done.

## Spec change-impact matrix

The v1 spec is a graph of cross-references. Touching one node
often forces companion edits. Use this matrix during PR
preparation:

| If you change… | You must also update… |
|----------------|----------------------|
| `0001-positioning.md` premise (P1..P8) or non-goal | Every spec doc that cites the changed premise (grep `docs/architecture/` for `P<N>`). Promote to a new ADR if the premise materially shifts. |
| ADR-0005 BoardAdapter contract surface | `0003-domain-model/03-aggregates-and-entities.md` § 3.6.3 (Anti-Corruption Layer); spec for any v1 script that calls the adapter (`board-canon` skill, future scripts). Per ADR-0005 Consequences, the GitHubProjectAdapter wrapper port has a 60-day landing deadline. |
| ADR-0006 D-AUTONOMY-1 matrix (rows or A/R/N classification) | `0002-product-features-and-flows/03-producer-surface.md` + `04-consumer-surface.md` (every feature row that cites the matrix); `classifying-actions` skill spec; `auditing-actions` skill spec (`action_id` catalog); `0005-contracts/06-audit-log-schema.md`. |
| ADR-0007 plugin-runtime constraint set (C-PLUGIN-1/-2/-3) | Every Producer / Consumer feature with verbs like *monitor*, *detect*, *trigger automatically*. The preflight-piggyback idiom citation. |
| ADR-0008 plugin-to-plugin SKILL invocation | `0005-contracts/04-skill-contracts.md` (sibling-skill classification table); `consuming-card` skill spec (F-C4 fallback rule). |
| `0002-product-features-and-flows/05-bootstrap-surface.md` (state file path / schema) | `0003-domain-model/02-bounded-contexts.md` § 3.2.3; `0003-domain-model/03-aggregates-and-entities.md` § RepoBootstrap / HostBootstrap; `0005-contracts/03-config-schemas.md` + `07-path-conventions.md`; `bootstrapping-repo` + `migrating-repo-version` skill specs. |
| `0002-product-features-and-flows/08-pr-contract.md` (three-section shape) | `consuming-card` skill spec (F-C12); `enforcing-pr-contract` skill spec; `managing-board` Review Queue routine spec (F-02 violation flagging). |
| Skill catalog (add / rename / split / merge any of the 10 v1 skills) | **`SKILLS.md` FIRST** (per its Source-of-truth contract — do not touch `skills/` until SKILLS.md is updated); then `0004-component-architecture.md` Decision 2 (capability → slot table); `0005-contracts/04-skill-contracts.md` (sibling-skill classification; v1 catalog table); the trigger row above; `README.md` and `README.zh-CN.md` if user-facing trigger phrases change. |
| Hook intent-injection marker grammar (`INVOKE:` / `REASON:`) | `0004-component-architecture.md` § "Hook intent injection pattern"; `0005-contracts/02-hook-contracts.md` § "Intent-injection markers"; `using-board-superpowers` entry-skill spec. |
| `~/.board-superpowers/` path layout (host-local state) | `0002-product-features-and-flows/05-bootstrap-surface.md`; `0003-domain-model/02-bounded-contexts.md` § 3.2.3; `0005-contracts/03-config-schemas.md` + `07-path-conventions.md`; `0002-product-features-and-flows/07-cross-cutting-invariants.md` I-13. |

When v1 implementation lands, this matrix grows additional rows
mapping spec → code (e.g., "if `0005-contracts/04-skill-contracts.md`
description discipline changes → re-read every `skills/*/SKILL.md`
frontmatter").

## Maintaining the spec

1. **Read the relevant Required-reading docs first.** The
   trigger table above tells you which.
2. **One ADR per architectural decision.** ADRs are immutable
   once accepted. Superseding an ADR creates a new one; the old
   one's status field gets `superseded by ADR-N`.
3. **Cite sources.** When a spec page makes a claim about the
   platform, link the canonical doc URL (CC docs, Codex docs,
   agentskills.io). When it makes a claim about academic
   methodology, link the primary source. The Required-reading
   docs maintain a "URL freshness" check — adopt the same
   discipline for new pages.
4. **Same-PR contract update.** If a spec change makes a
   companion doc stale, fix the companion in the same PR.
5. **Spec body stays in English** for shareability across
   collaborators and locales (per
   [`SKILL_DEVELOPMENT.md`](./SKILL_DEVELOPMENT.md) Anti-pattern
   A5). Chinese discussion belongs in commit messages, PR
   bodies, or `notes-zh.md` files outside the spec tree.

## Maintaining v1 implementation (placeholder)

> When the first v1 SKILL / script / hook lands, this section
> grows into the operational checklist for skills, scripts,
> hooks, testing, and release flow.

## Commands (v1 target)

```bash
# Spec review
ls docs/architecture/                          # what's specced
ls docs/architecture/adr/                      # what's decided

# v1 implementation (when it begins)
# bash scripts/check-deps.sh                   (not yet implemented)
# for t in tests/*.sh; do bash "$t" || exit 1; done
# (cd scripts && shellcheck -x ./*.sh)
```

<!-- board-superpowers:routing -->
## board-superpowers session routing

> **v1 spec phase note (2026-04-26):** the routing block below
> describes the **intended v1 routing**. The named skills
> (`consuming-card`, `managing-board`, `using-board-superpowers`)
> do not yet exist at runtime. Until v1 SKILL.md files land at
> the canonical path `skills/<name>/SKILL.md`, this block is
> **declarative, not behavior-bearing**. It will become
> behavior-bearing the moment the first v1 entry skill ships.

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
