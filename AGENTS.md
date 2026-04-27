# board-superpowers — project instructions

This repo **is** the plugin. Sessions here are plugin-maintainer
sessions, not product-user sessions. See `README.md` for the
user-facing overview.

@SKILLS.md

## Project status — v1-minimum self-hosting active

> **The plugin is now loadable at runtime.** `hooks/`,
> `scripts/`, and `skills/` directories exist at the repo root.
> `SessionStart` fires. The 6 v1-minimum skills auto-match.
> The plugin dogfoods itself for any new skill / script / hook.

**v1-minimum = 6 of 10 skills shipped** (per
[`SKILLS.md`](./SKILLS.md) § "v1 minimum vs v1 complete"):

- **Shipped**: `using-board-superpowers` (entry),
  `managing-board` + `consuming-card` + `bootstrapping-repo`
  (molecular), `board-canon` + `enforcing-pr-contract` (atomic).
- **Deferred to v1-complete**: `decomposing-into-milestones`,
  `migrating-repo-version`, `classifying-actions`,
  `auditing-actions`. Reasons live in the SKILLS.md table.

**v1-minimum degraded behaviors** (designed-in, removed when
deferred atomics ship):

- All mutating actions run as **R-class default** (propose →
  ask architect → ack → act). The full D-AUTONOMY-1 matrix
  triage from `classifying-actions` is inlined as one block per
  v1-minimum molecular SKILL.md.
- All audit entries write to a **local jsonl trace file** at
  `~/.board-superpowers/repos/<normalized>/audit-local.jsonl`. The
  full BYO RDBMS schema from `auditing-actions` is deferred.
- **No `migrating-repo-version` skill yet** — current plugin
  version is `v0.2.0`; the schema-aware migration runner lands
  starting from the v0.2.x → v0.3.x transition. The hook never
  injects `INVOKE: migrating-repo-version` in v0.2.0.

The single source of truth for v1 design remains
[`docs/architecture/`](./docs/architecture/) — read
`0001-positioning.md` first; the
[`docs/architecture/README.md`](./docs/architecture/README.md)
index lists everything else in canonical order. v1-minimum
implementation is the **current state**, not the **target
state** — v1-complete is the target.

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
| Writing a new `skills/<name>/SKILL.md` or revising any existing one (incl. its `references/`, `scripts/`, `agents/`, `assets/`, `evals/` siblings); adding a new skill type; renaming a skill; touching frontmatter `description`, `argument-hint`, `arguments`, `when_to_use`, or any other Tier 2 field | `SKILL_DEVELOPMENT.md` | Canonical guide for skill design / creation / maintenance — covers the skill-graph framing (entry / molecular / atomic), three-tier frontmatter discipline, body skeletons, anti-patterns, testing regimes. Skills are this repo's product surface; sloppy authoring fails downstream invisibly. |
| Creating or modifying a `<skill-dir>/.skill-meta.yaml` (the version + 4-dim metadata file) | `SKILL_DEVELOPMENT.md` § "board-superpowers metadata convention" | Defines the schema: `version` (semver) + `layer` (entry/molecular/atomic) + `type` (technique/pattern/reference/discipline) + `mode` (claude-code-only/codex-only/both) + `bounded-context` (board/session/bootstrap/audit/spec). CI gate `scripts/verify-skill-metadata.sh` enforces consistency between yaml and `SKILLS.md` catalog. Drift here causes silent topology rot. |
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

## Self-hosting (v1-minimum onwards)

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

## Maintaining v1 implementation

The v1-minimum plugin is loadable. The operational checklist:

### Skills (`skills/<name>/`)

- Frontmatter: Tier 1 portable subset (`name` + `description`)
  is mandatory; Tier 2 fields per the recommendation table in
  [`SKILLS.md`](./SKILLS.md) catalog. Tier 3 (custom non-spec
  fields like `version: ...`) is forbidden — those go in
  `.skill-meta.yaml`.
- Every skill directory must contain `SKILL.md` AND
  `.skill-meta.yaml`. CI gate `scripts/verify-skill-metadata.sh`
  enforces.
- New skills: edit `SKILLS.md` catalog FIRST (per its
  Source-of-truth contract), then create the directory.
- Body length: ≤200 lines for entry, 250-450 for molecular,
  200-300 for atomic. References move to `references/<topic>.md`
  past 100 lines.

### Scripts (`scripts/`)

- Strict-mode bash: callers `set -euo pipefail` before sourcing
  `scripts/lib/common.sh`.
- Header comment + shellcheck `-x` clean (CI gate).
- AI-callable tools live under `scripts/`; user-facing CLIs do
  NOT exist in this plugin (the plugin is consumed via skills /
  slash commands, not a dedicated CLI).

### Hooks (`hooks/`)

- v1-minimum wires only `SessionStart`. Future hook events use
  the same `INVOKE: <skill> / REASON: <line>` payload pattern
  per [`docs/architecture/0005-contracts/02-hook-contracts.md`](./docs/architecture/0005-contracts/02-hook-contracts.md).
- Every hook script must declare a 10s timeout in `hooks.json`.
- **Dual-platform registration**: CC auto-discovers
  `hooks/hooks.json` at plugin load. Codex CLI does NOT — users
  run `scripts/register-codex-hooks.sh --install-user` (or
  `--install-repo`) once per Codex install to wire the same
  `SessionStart` script into `~/.codex/hooks.json` (or
  `<repo>/.codex/hooks.json`). The script is idempotent and
  backs up the target file before merging. When adding a new
  hook event, update BOTH `hooks/hooks.json` AND the snippet
  generator inside `register-codex-hooks.sh`.

### Tests / smoke checks

- `scripts/verify-skill-metadata.sh` — yaml ↔ SKILLS.md catalog
  consistency.
- `scripts/verify-skill-frontmatter.sh` — Tier 1 + Tier 2 +
  no-Tier-3 compliance per SKILL.md.
- `shellcheck -x scripts/**/*.sh hooks/*.sh` — full pass.
- Manual smoke: open a fresh CC session, type each of the 6
  v1-minimum skills' trigger phrases, verify auto-trigger.

### Release flow

- Bump `.claude-plugin/plugin.json` + `.codex-plugin/plugin.json`
  `version` field per semver (e.g., `v0.1.0-minimum` → `v0.1.1`
  is a patch; `v0.1.x` → `v0.2.0` is a minor).
- For deferred-atomic landings, also bump per-skill
  `.skill-meta.yaml` `version` (per
  [`SKILL_DEVELOPMENT.md`](./SKILL_DEVELOPMENT.md) § "
  board-superpowers metadata convention").

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
<!-- /board-superpowers:routing -->
