# board-superpowers — project instructions

This repo **is** the plugin. Sessions here are plugin-maintainer
sessions, not product-user sessions. See `README.md` for the
user-facing overview.

@SKILLS.md

## Project status — v1 catalog 10/11 shipped

> **The plugin is loadable at runtime.** `hooks/`,
> `scripts/`, and `skills/` directories exist at the repo root.
> `SessionStart` fires. The 10 v1-catalog skills auto-match.
> The plugin dogfoods itself for any new skill / script / hook.

**v1 catalog = 10 of 11 skills shipped** (11 once `migrating-repo-version` ships), per [`SKILLS.md`](./SKILLS.md):

- **Shipped**: `using-board-superpowers` (entry),
  `managing-board` + `consuming-card` + `bootstrapping-repo` +
  `decomposing-into-milestones` (molecular), `board-canon` +
  `enforcing-pr-contract` + `classifying-actions` +
  `auditing-actions` + `operating-kanban` (atomic).
- **Roadmap (pending shipment)**: `migrating-repo-version`.
  Reason lives in the SKILLS.md table.

**Remaining degraded behavior**:

- **No `migrating-repo-version` skill yet** — current plugin
  version is `v0.5.0`; the schema-aware migration runner lands
  starting from the v0.5.x → v0.6.x transition. The hook never
  injects `INVOKE: migrating-repo-version` in v0.5.0.

The single source of truth for v1 design remains
[`docs/architecture/`](./docs/architecture/) — read
`0001-positioning.md` first; the
[`docs/architecture/README.md`](./docs/architecture/README.md)
index lists everything else in canonical order. The 10 shipped
skills are the operating substrate; the 1 deferred skill is a
roadmap item, not a gate on day-to-day work.

## Subdirectory contracts

This project's per-directory rules are sharded into nested
`AGENTS.md` files. **Read the relevant contract before any
work that touches the listed directory** — including planning
/ design / discussion phases, not just file edits.

CC auto-loads the nested `CLAUDE.md` shim lazily when you Read
or Edit a file under that path; Codex CLI does **not** —
Codex sessions must Read the contract file explicitly before
editing that subtree.

When you need to consult a contract during planning, design,
or cross-directory discussion (i.e., before any file is
touched), Read the listed file directly — don't rely on lazy
loading.

| Working in / about | Contract file | CC auto-load? | Codex auto-load? |
|--------------------|---------------|---------------|------------------|
| `skills/**` (writing / editing / discussing skills) | [`skills/AGENTS.md`](./skills/AGENTS.md) | yes (lazy on Read/Edit) | no — Read explicitly |
| `hooks/**` (hook scripts, `hooks.json`) | [`hooks/AGENTS.md`](./hooks/AGENTS.md) | yes (lazy) | no — Read explicitly |
| `scripts/**` (bash tooling, `common.sh`) | [`scripts/AGENTS.md`](./scripts/AGENTS.md) | yes (lazy) | no — Read explicitly |
| `docs/architecture/**` (spec, ADRs, change-impact matrix) | [`docs/architecture/AGENTS.md`](./docs/architecture/AGENTS.md) | yes (lazy) | no — Read explicitly |

The nested `CLAUDE.md` files in each of those directories are
one-line shims that `@`-include the sibling `AGENTS.md`. Make
all edits in the `AGENTS.md`, not in the `CLAUDE.md` shim.

### Cross-cutting reference docs

The three large companion docs below are referenced by name —
**not loaded with `@`-prefix** — so they don't ride into every
session's context. Open them on demand using `Read` (or its
platform equivalent) when the work matches their scope. Each
nested `AGENTS.md` above sends you to the relevant companion
doc when its scope is touched.

| Doc | When it applies |
|-----|-----------------|
| [`PLUGIN_DEVELOPMENT.md`](./PLUGIN_DEVELOPMENT.md) (~440 lines) | hook scripts, bash tooling, plugin manifest, dual-platform (CC + Codex CLI) contracts. |
| [`MULTI_AGENT_DEVELOPMENT.md`](./MULTI_AGENT_DEVELOPMENT.md) (~700 lines) | subagent / agent-team / orchestration design, `Agent` tool / `SendMessage` / fan-out-fan-in. |
| [`SKILL_DEVELOPMENT.md`](./SKILL_DEVELOPMENT.md) (~1290 lines) | skill authoring — frontmatter, body skeletons, anti-patterns, testing, `.skill-meta.yaml` schema. |
| [`SETUP_STAGES_DEVELOPMENT.md`](./SETUP_STAGES_DEVELOPMENT.md) (~700 lines) | setup-stages system — `scripts/stages-registry.yml`, `scripts/stages_lib/`, `scripts/stages-registry.schema.json`, `hooks/session-start.sh` lifecycle diff, `skills/bootstrapping-repo/`, the four partitioned `settings.yml` files. Read before adding/editing/removing a stage, before changing the 5-callable contract, before introducing a new `applicable_when` form, or before any spec change touching § 1.5 (Bootstrap surface redesign). The legacy filename `BOOTSTRAP_STAGES_DEVELOPMENT.md` is a one-line shim that redirects here. |
| [`BOARD_DEVELOPMENT.md`](./BOARD_DEVELOPMENT.md) (~600 lines) | board / card / Kanban Protocol layer — `docs/architecture/0005-contracts/00-kanban-protocol.md`, ADR-0025 + ADR-0026, `skills/board-canon/`, the planned `skills/operating-kanban/`, `scripts/claim-card.sh`, the eight protocol actions, six canonical statuses, multi-kanban semantics, flat-Card hierarchy + display-only metadata, AI-native concept hygiene anchors. Read before editing the Kanban Protocol document, before authoring/changing `board-canon` or `operating-kanban`, before adding a new backend projection (Linear / Jira / others), or before touching multi-kanban schema / kanban lifecycle / branch naming / claim primitive. § 7 "Setup-stages bridge" documents how the board layer meets `SETUP_STAGES_DEVELOPMENT.md`'s M10 module. |

**Do not "fix" these references back to `@`-prefix** — that
change would force-load all five docs into every session and
is exactly the anti-pattern they themselves warn against.

### Doctrine

These three rules close the rationalization loopholes that
make per-directory contracts merely advisory:

1. **No "I already know."** If a Subdirectory contract row
   matches your work, the contract file gets read in this
   session. "I read it last week" is not a substitute — the
   doc may have changed, and your context window has long
   since dropped the relevant passages.
2. **No "this change is too small."** A one-line edit to a
   spec table, a single new field in a SKILL frontmatter, a
   one-character rename of a hook marker — each can violate a
   contract documented in one of these files. Smallness of
   diff is not smallness of blast radius.
3. **Same-PR contract update.** If your change makes a
   contract in a nested `AGENTS.md` or a cross-cutting
   companion doc stale, fix the doc in the **same PR** — not a
   follow-up. Doc lag is the primary failure mode that makes
   this pattern decay over time.
4. **No "selectively skip the entry skill."** When working
   under `skills/`, the `SKILL_DEVELOPMENT.md` read + the
   `example-skills:skill-creator` invocation specified in
   [`skills/AGENTS.md`](./skills/AGENTS.md) "Process gate"
   block are mandatory in BOTH implementation and review
   phases — even when the work feels routine (e.g., a small
   frontmatter tweak, a one-line description fix, a body
   length adjustment). The AI cadence 100x doctrine permits
   IN-SESSION skill chains (`brainstorming` → `writing-plans`
   → implementation, all in one agent); it does NOT permit
   skipping the entry skills that gate skill-authoring. The
   entry skills carry source-of-truth re-read + Skeleton
   selection + Regime 1/2 testing scaffolding that the chain
   skills assume have already happened. Skipping them
   silently turns an "AI-cadence-compressed flow" into a
   "doctrine-skipped flow" — and the gap only surfaces under
   external audit, not under self-review.

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
   (Postgres / MySQL / SQLite via the 6-scheme allowlist —
   [ADR-0006 §5](./docs/architecture/adr/0006-producer-autonomy-boundary.md)
   + [ADR-0009](./docs/architecture/adr/0009-allow-sqlite-as-byo-audit-db.md)).
   When the DB is unavailable, audit-log-write.sh degrades to
   a local jsonl trace and the entry's `mode` field records the
   degradation cause (see spec 06 § "jsonl fallback mode-field").

### Skills system — the v1 catalog (11 skills, 3 layers)

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

Atomic layer (5) — single-purpose primitives, reflexive (no upward calls)
─────────────────────────────────────────────────────────────────
  board-canon                 state machine + Card schema + branch
                              naming + WIP rules (read-only contract)
  enforcing-pr-contract       PR three-section injection + validation
  classifying-actions         D-AUTONOMY-1 matrix + triage + overrides
  auditing-actions            audit log schema + two-entry rule + BYO DB
  operating-kanban            8-action protocol dispatch over the active
                              projection (backend selection + Form A/B/C)
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
REASON: Plugin version v0.5.0 detected; state.yml records
        last_seen_version_in_repo=v0.4.x.
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
- **uv** (host-level globally installed; install via `brew install uv`
  or `curl -LsSf https://astral.sh/uv/install.sh | sh`) — manages the
  per-repo Python venv at `<repo>/.board-superpowers/.venv/` for
  plugin's own runtime deps (`pyyaml + pymysql` at v0.3.0). The plugin
  ships `pyproject.toml` + `uv.lock` templates; bootstrap-project.sh
  copies them per repo. See "Why per-repo venv" below.
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

### Why per-repo venv (not host-local)

board-superpowers's Python deps live in `<repo>/.board-superpowers/.venv/` per repo, not at host-level `~/.board-superpowers/.venv/`. Trade-off:

| Dimension | host-local | **per-repo (chosen)** |
|-----------|------------|------------------------|
| Disk | 1 venv (~10 MB) | N venvs (~10 MB × N) |
| Plugin upgrade | one upgrade affects all repos at once | each repo upgrades independently on bootstrap re-run |
| Plugin version mix | impossible (one venv → one deps set) | possible (different repos pin different plugin versions via different `uv.lock`) |
| Multi-architect on shared host | shared deps version | each architect's per-repo isolation |

Per-repo wins because:

1. **Plugin version isolation**. Architect A upgrading the plugin in repo X does not break repo Y's audit governance behavior. With host-local venv, a plugin upgrade would silently change deps versions for every repo simultaneously.
2. **`uv.lock` reproducibility**. Each repo's committed `uv.lock` is the source of truth for that repo's audit governance behavior. Host-shared venv would require host-level lock coordination, breaking the "repo is the unit of coordination" principle that the rest of board-superpowers follows.
3. **Disk cost is acceptable**. ~10 MB × N repos is small relative to typical repo size + modern host disk; SSDs make the per-repo overhead negligible.
4. **Co-location with other plugin-managed scaffolding**. The venv lives next to `config.yml`, `config.local.yml`, `pyproject.toml`, `uv.lock` — all per-repo plugin-managed files.

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

## Self-hosting

The plugin **dogfoods itself** as of `v0.1.0-minimum`. Any new
skill / script / hook / spec change for board-superpowers itself
goes through the same two-role flow board-superpowers prescribes
for any consuming repo:

- **Spec architecture changes** (anything under
  `docs/architecture/`) — flow through `managing-board` (intake
  → decomposition handoff → cards on the board) →
  `consuming-card` (claim → worktree → implement → PR). Spec
  changes that don't yet have decomposition support (since
  `decomposing-into-milestones` is deferred) get hand-decomposed
  by the architect into Ready cards, then claimed normally.
- **Skill / script / hook implementation** — full Manager →
  Consumer flow against the plugin's own GitHub Project
  ([PanQiWei/board-superpowers](https://github.com/PanQiWei/board-superpowers)
  Project, F-08 intake routine).

The only exception: changes to **the dogfood loop itself**
(this Self-hosting section, the working tree discipline, the
routing block, this file's own conventions) may bypass the
loop. Use direct PRs for those — circular dependency.

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

## Implementation-facing plans (`docs/plans/`)

This project separates three kinds of "documents" with
different lifecycles, scope, and storage. Knowing which goes
where is a prerequisite to all Producer-side intake / Consumer-
side claim work — putting the wrong artifact in the wrong place
either pollutes `main` with churn, or hides durable decisions in
gitignored scratch.

| Path | Purpose | Scope | Lifetime | Tracked in git? | Language |
|------|---------|-------|----------|-----------------|----------|
| `docs/architecture/` | Authoritative spec — design docs, ADRs, contracts, invariants. | Permanent project knowledge. | Durable; outlives any single PR. | committed | English (per [`SKILL_DEVELOPMENT.md`](./SKILL_DEVELOPMENT.md) anti-pattern A5). |
| `docs/plans/<feature>/` | **Producer-side** implementation-facing scaffolding — brainstorming output, plan-eng-review notes, decomposition working drafts, per-card body drafts before `gh issue create`. | One feature, spans one Manager → Consumer cycle (a "Manager session that intakes a feature → multiple Consumer sessions delivering its cards → final card lands"). | Pruned after the feature's last card merges. | gitignored | Either; Chinese is encouraged for brainstorming notes. |
| `docs/board-superpowers/plans/` | **Consumer-side** per-card plan brief — a reformat of one card's GitHub body, handed by `consuming-card` to `subagent-driven-development` as that skill's input. | One card, one Consumer session. | Deleted after the card's PR lands. | gitignored | Either. |

### Why three, not two

`docs/plans/` (new) and `docs/board-superpowers/plans/` (existing
since v0.1.0-minimum) both look like "plan files" — but they
serve different consumers and have different lifetimes:

- `docs/plans/<feature>/` is **Producer-side**, **multi-card**,
  and **multi-session**. Example artifacts: a brainstorming
  transcript covering the full bootstrap mechanism, the resulting
  6–8 card body drafts, plan-eng-review notes, dependency-graph
  diagrams. These survive across multiple Consumer sessions
  delivering the feature's cards.
- `docs/board-superpowers/plans/` is **Consumer-side**,
  **single-card**, **single-session**. Example artifact: the
  reformatted plan brief that `consuming-card` hands to
  `subagent-driven-development` for one specific card. Lives
  about as long as one PR.

Co-existing keeps each clean. Merging them would force one
consumer to read past the other's noise.

### Discipline

- **One subdirectory per feature.** A new feature gets its own
  `docs/plans/<feature>/` (e.g., `docs/plans/bootstrap/`,
  `docs/plans/audit-log-byo-rdbms/`). One flat dump invites
  stale crossover and makes pruning hard.
- **Spec is the source of truth, plans are scaffolding.** If a
  decision in `docs/plans/<feature>/` is durable architecture,
  promote it to `docs/architecture/` in the same PR that lands
  the card making the decision. Don't let `docs/plans/`
  accumulate shadow specs.
- **Prune on completion.** When the feature's last card lands,
  the architect deletes `docs/plans/<feature>/`. Stale plans
  decay silently and mislead future readers. The feature's
  PRs preserve the durable record; plans were scaffolding.
- **Chinese is allowed in `docs/plans/`, NOT in spec.**
  `docs/plans/` is the right place for Chinese discussion,
  brainstorming notes, decomposition rationale. The spec body
  stays English per the existing anti-pattern A5 in
  [`SKILL_DEVELOPMENT.md`](./SKILL_DEVELOPMENT.md).
- **No CI / hook reads from `docs/plans/`.** Anything CI or a
  hook needs as input is part of the spec or the script
  contract — promote it. `docs/plans/` is human-readable
  scaffolding only.

## Maintaining v1 implementation

Per-directory operational checklists live in nested `AGENTS.md`
files — see "Subdirectory contracts" above. The
[`docs/architecture/AGENTS.md`](./docs/architecture/AGENTS.md)
file owns spec governance (ADR discipline, citation rules,
Spec change-impact matrix). This section captures only the
cross-cutting checks that span multiple subdirectories.

### Tests / smoke checks (cross-cutting)

- `scripts/verify-skill-metadata.sh` — yaml ↔ `SKILLS.md`
  catalog consistency.
- `scripts/verify-skill-frontmatter.sh` — Tier 1 + Tier 2 +
  no-Tier-3 compliance per SKILL.md.
- `shellcheck -x scripts/**/*.sh hooks/*.sh` — full pass.
- `bash tests/e2e/test-bootstrap-audit-e2e.sh` — fresh-repo
  bootstrap audit end-to-end (#43 AC6); covers outbox emit →
  jsonl → fast-path flush → DB transition; SQLite only
  (PG/MySQL container deferred).
- Manual smoke: open a fresh CC session, type each of the 8
  shipped skills' trigger phrases, verify auto-trigger.

### Release flow

- Bump `.claude-plugin/plugin.json` + `.codex-plugin/plugin.json`
  `version` field per semver (e.g., `v0.1.0-minimum` →
  `v0.1.1` is a patch; `v0.1.x` → `v0.2.0` is a minor).
- For deferred-atomic landings, also bump per-skill
  `.skill-meta.yaml` `version` (per
  [`SKILL_DEVELOPMENT.md`](./SKILL_DEVELOPMENT.md) §
  "board-superpowers metadata convention").

<!-- board-superpowers:routing -->
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

**Manager-mode mirror**: this section's composition rules are
mirrored for the Producer's intake routine in
[`skills/managing-board/references/skill-routing.md`](./skills/managing-board/references/skill-routing.md).
The two files MUST stay in sync — see the change-impact-matrix
row "AGENTS.md compose section ↔ skill-routing.md /
scope-shape-judgment.md" in
[`docs/architecture/AGENTS.md`](./docs/architecture/AGENTS.md).
If you edit one without the other, the PR is incomplete.
The shape-level companion ([`scope-shape-judgment.md`](./skills/managing-board/references/scope-shape-judgment.md))
and the spec-first companion ([`spec-first-checklist.md`](./skills/managing-board/references/spec-first-checklist.md))
are the manager-mode SoT for shape decisions and spec
preconditions; this section provides the cross-plugin wiring
they consume.
<!-- /board-superpowers:routing -->

## Do Not

High-frequency footguns. Items here are documented in detail
elsewhere; this list is a quick scan before submitting a PR.

- **Do not edit at the repo root on a feature branch.** Repo
  root stays on `main`; all feature work happens in a
  `git worktree`. See "Working tree discipline" above.
- **Do not put worktrees inside the repo tree** (e.g.,
  `<repo>/.worktrees/<branch>`). IDEs and file watchers scan
  them and the visual confusion is real.
- **Do not edit `skills/` before `SKILLS.md`.** Per its
  Source-of-truth contract, a `skills/` change without a
  paired `SKILLS.md` change is unmergeable.
- **Do not "fix" `PLUGIN_DEVELOPMENT.md` /
  `MULTI_AGENT_DEVELOPMENT.md` / `SKILL_DEVELOPMENT.md`
  references back to `@`-prefix.** That force-loads all three
  into every session and is the exact anti-pattern they warn
  against.
- **Do not skip pre-commit hooks** (`--no-verify`,
  `--no-gpg-sign`) unless explicitly authorized. Investigate
  and fix the underlying issue.
- **Do not amend a commit when a hook failed** — the commit
  did not happen. Fix the issue, re-stage, and create a NEW
  commit.
- **Do not commit changes to `~/.board-superpowers/`** — that
  directory is host-local state, not project state, and is
  outside the repo tree.
- **Do not auto-reach for `gstack:/ship` / `/canary` /
  `/land-and-deploy`** — board-superpowers does not prescribe
  a release process. Enable these skills only if they match
  this repo's deployment shape; otherwise use whatever release
  flow the consuming repo already has.
