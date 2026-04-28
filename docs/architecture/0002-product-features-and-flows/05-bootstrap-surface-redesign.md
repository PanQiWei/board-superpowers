### 1.5 Bootstrap surface — redesign

> **Status — design draft.** This file captures the in-progress
> systematic redesign of the bootstrap mechanism. It is **not**
> the source of truth yet. The currently-shipped contract still
> lives in [`05-bootstrap-surface.md`](./05-bootstrap-surface.md).
>
> **Terminal state.** Once this draft is approved and the
> companion ADR(s) are recorded, this file's content **replaces**
> `05-bootstrap-surface.md`. The replacement happens in a single
> PR that also fans out the spec change-impact matrix updates
> listed in [`../AGENTS.md`](../AGENTS.md) § "Spec
> change-impact matrix" (the row keyed on `05-bootstrap-surface.md`).
> At that point this `-redesign` file is removed (or
> `git mv`'d to `05-bootstrap-surface.md`, overwriting the old
> body).
>
> **Read order.** Read this file in pair with the existing
> `05-bootstrap-surface.md`. Where this draft contradicts the
> existing surface, this draft expresses **future intent** and
> the existing surface expresses **shipped behavior**. The gap
> between the two is exactly the redesign work.

---

## Why a redesign

Today's bootstrap mechanism (per
[`05-bootstrap-surface.md`](./05-bootstrap-surface.md)) has
four structural weaknesses that v0.4.0 makes acutely visible:

1. **Implicit completion state** — "is bootstrapped" is
   inferred from "file exists with valid `schema_version`".
   No record of which sub-step ran, when, or under which
   plugin version. Mid-bootstrap interruption recovers only
   via each step's hand-rolled idempotency.
2. **Bootstrap and migration are separate skills** — F-B1/F-B2
   (first-time) and F-B3/F-B4 (version transition) are two
   parallel families today; the deferred `migrating-repo-version`
   skill duplicates the dispatch logic that bootstrap already
   needs. The two collapse into one mechanism: "current state
   vs target state diff, run the missing steps."
3. **Automated and agentic execution are not separated** — the
   `bootstrapping-repo` SKILL today runs ~11 steps in one
   undifferentiated flow, including ~8 that need no architect
   input. The skill is forced to mediate work that a
   non-interactive script could finish before session start.
4. **Cross-platform parity is ad-hoc** — Claude Code
   auto-discovers `hooks/hooks.json`; Codex CLI requires the
   architect to manually run `scripts/register-codex-hooks.sh`
   per the README. The asymmetry is documented in prose, not
   modeled as a stage in the bootstrap mechanism. Any new
   capability that needs platform-specific registration repeats
   the same out-of-band-instruction pattern.
5. **Audit-log host-vs-repo bucket drift** — `credentials.yml`
   today is host-shared (one DSN serves every repo on the
   host); audit rows from multiple repos land in one DB. The
   architect intent is per-repo isolation (each repo carries
   its own audit credentials + DB), but the shipped contract
   has not caught up. See § "Functional modules" M4 below
   and the spec change-impact matrix entries it triggers.

## Goals

The redesign pursues four architect-stated goals:

**G1 — hook-driven unified check script (bootstrap + migration
collapsed into one mechanism).** Every session start runs a
single `check` script. The script knows the target state for
every stage at the current plugin version, compares against
on-disk declared state, computes the diff, and triggers the
missing or stale stages. The script is itself versioned and
maintained across plugin releases — adding a new stage in a
future plugin version causes existing bootstrapped repos to
auto-detect and run the new stage on next session start. The
deferred `migrating-repo-version` skill is **absorbed** into
this mechanism (migration = current state vs target state
diff). See § "Trigger model" below.

**G2 — efficient execution along two orthogonal axes.**

- **Axis A — execution character**: each stage is either
  *automated* (deterministic, no architect attention required —
  agent or script may execute, the architect is not interrupted)
  or *agentic* (requires architect decision, input, confirmation,
  or remote-side repair guidance — only an agent in a SKILL
  flow can mediate). The boundary is "does this stage need the
  architect's attention?" not "does this stage enter an agent
  session?" — automated stages may pass through a SKILL flow
  unobserved by the architect.
- **Axis B — locality**: each stage's writes land in one of
  five buckets — `host-shared` (entire host shares one copy),
  `repo-shared` (per-repo host-local but cross-clone-shared
  via GitHub identity), `repo-git` (committed into the repo's
  git history), `repo-clone` (per-clone physical copy in repo
  but git-ignored), or `external` (side-effect outside local
  filesystem — GitHub state or external RDBMS — whose
  completion cannot be inferred from local files alone). See
  § "Axis B — Locality" for the full definitions.

The 2D classification governs *where the stage's progress is
recorded* and *who runs it*. See § "Stage taxonomy" below.

**G3 — declarative state recording independent of repo path.**
Bootstrap progress is recorded as explicit
`{stage_id, status, completed_at, completed_by_version}`
entries in declarative state files, not inferred from file
existence. `status` is a 4-state enum (see § "Stage lifecycle
states"). State files live under `~/.board-superpowers/`,
keyed in a way that does not bind to the absolute on-disk path
of the repo (the exact identity scheme is open — see
§ "Repo identity"). A new architect session on the same
(host, repo) pair sees a consistent snapshot regardless of
where the repo is checked out.

**G4 — cross-platform capability parity (Claude Code ↔ Codex
CLI).** Every bootstrap stage that has a CC-side surface has
a parity Codex-side surface, and the parity is modeled
explicitly in the stage registry's `platforms` field — not
delegated to README prose. Where a stage is intrinsically
platform-specific (e.g., Codex hook registration via
`register-codex-hooks.sh`, vs. CC's auto-discovery of
`hooks/hooks.json`), the registry expresses that asymmetry as
a `platforms: [codex]` constraint on the stage rather than
silently shipping a CC-only flow. Dual-platform support is a
first-class design constraint, not an afterthought.

## The three axes

A stage's complete identity is a 3-tuple `(module, character,
locality)`. Each axis answers a distinct question about a
stage; together they pin down where the stage's progress is
recorded, who runs it, and what subsystem it configures.

### Axis A — Execution character

What kind of execution does this stage need?

- **`automated`** — purely deterministic; runs without
  architect input. Script-owned. Includes file writes,
  idempotent CLI calls, atomic state updates, schema
  migrations. Sub-flag `heavy` may apply (significant
  network or IO cost — installer downloads, venv syncs)
  which the trigger model treats differently from light
  automated.
- **`agentic`** — requires architect interaction at
  execution time: decision (pick a DSN scheme), input
  (enter a credential), confirmation (accept an optional
  content block), or remote-side repair guidance (fix
  Status field in GitHub UI). Routes through a SKILL
  because only an agent can mediate the human-in-the-loop
  turn. Sub-flag `confirm-only` distinguishes "agent must
  confirm before proceeding" from "agent must elicit free
  input."

**Why two values, not three?** Earlier drafts considered an
"automated-but-architect-confirms" middle tier; collapsed
into `agentic + flag=confirm-only` because the routing path
(skill required) is the same.

### Axis B — Locality

Where does this stage's outcome land? **Five values** —
the locality axis distinguishes by both *which subject the
outcome belongs to* (host vs repo) and *how the outcome is
shared across machines / clones / architects*:

- **`host-shared`** — written at the host root
  (`~/.board-superpowers/<files>` or `~/.codex/config.toml`);
  one copy per host, **shared across every repo** on this
  host. Examples: plugin's host manifest, host-wide tool
  installation (uv binary), Codex hook registration in
  Codex's own config.
- **`repo-shared`** (per-repo, host-local, **cross-clone
  shared**) — written under
  `~/.board-superpowers/repos/<repo-identity>/`; one copy
  per `(host, GitHub repo)` pair, **shared across every
  local clone** of the same GitHub repo on this host.
  Examples: `state.yml`, per-repo `credentials.yml`, audit
  `jsonl` + `sqlite` DB. (See § "Repo identity" for the
  identity scheme — `<repo-identity>` is `<owner>-<repo>`
  derived from the GitHub remote URL.)
- **`repo-git`** (per-repo, **git-tracked**) — written
  under `<repo>/.board-superpowers/<file>` and
  **committed to the repo's git history**; shared with
  every collaborator of that repo via git. Examples:
  `config.yml`, `pyproject.toml`, `uv.lock`, routing
  blocks injected into `AGENTS.md` / `CLAUDE.md`,
  `.gitignore` append entries.
- **`repo-clone`** (per-repo, **per-clone physical
  copy**) — written under `<repo>/.board-superpowers/<file>`
  but **git-ignored**; each clone of the same repo on the
  same host has its own physical copy. Examples:
  `config.local.yml` (per-architect override), `.venv/`
  (per-clone Python venv).
- **`external`** (side-effect outside the local
  filesystem) — outcome lives in GitHub state (labels,
  Project field schema) or external RDBMS (audit DDL,
  audit row inserts). Completion **cannot be inferred
  from local files alone** — the stage's
  `target_state_predicate` performs an external query.
  External-locality stages typically cache their last
  validation timestamp + outcome hash in `repo-shared`
  state to avoid hammering the external system every
  hook tick (TTL-based re-validation).

**Why the cross-clone vs per-clone split matters.** Two
clones of the same repo at `~/Dev/repos/foo` and
`~/Sandbox/foo` on the same host: their `repo-shared`
files (state.yml, credentials.yml) are the **same physical
file** (one source of truth); their `repo-clone` files
(config.local.yml, .venv/) are **independent copies**.
This matches the architect's intent that bootstrap progress
+ audit credentials follow the GitHub repo identity, while
per-clone tooling state (which the architect may diverge
between clones for testing) follows physical path.

### Axis C — Functional module

Which subsystem does this stage configure? Nine values
(M1..M9):

- **`M1` — plugin-runtime infra.** The plugin's own
  bookkeeping state files and directory skeleton
  (`manifest.yml`, `state.yml`, host state dir). The
  "plumbing" the plugin needs to record its own progress.
  Without M1 stages no other module can record completion.
- **`M2` — Python runtime.** The execution environment
  for the plugin's own Python dependencies (`uv` tool
  host-side + per-repo venv with `pyproject.toml` /
  `uv.lock` / `.venv/`). Cross-locality: M2 stages span
  `host-shared` (uv binary), `repo-git`
  (`pyproject.toml` + `uv.lock`), and `repo-clone`
  (`.venv/`).
- **`M3` — GitHub Project integration.** The
  BoardAdapter's contract with the GitHub Project (13
  standard Issue labels, 6-option Status field schema).
  All M3 stages have `external` locality. (BoardAdapter
  is the abstraction that makes future Linear / Jira
  adapters possible per ADR-0005.)
- **`M4` — Audit logging.** BYO RDBMS / SQLite audit-log
  subsystem (per-repo credentials + schema + flush +
  health reporting). **All M4 stages are per-repo** —
  each repo carries its own audit credentials + DB. The
  shipped v0.4.0 contract has `credentials.yml`
  host-shared; this redesign moves it to per-repo to
  match architect intent and resolve the cross-repo
  audit pollution surfaced in #43.
- **`M5` — Repo configuration.** The plugin's user-facing
  knobs (`config.yml` git-shared defaults +
  `config.local.yml` per-architect overrides). The only
  module today with both git-shared and host-local
  stages.
- **`M6` — Gitignore hygiene.** Prevent plugin files
  from polluting git (protect `*.local.*`, `claims/`,
  `.venv/`). Single git-shared stage; idempotent append.
- **`M7` — Agent routing.** Inject the plugin's
  skill-routing metadata into the user's `AGENTS.md` +
  `CLAUDE.md` so the agent (CC / Codex) knows the plugin
  is active. **Per-block multi-stage architecture** (per
  architect direction):
  - `m7.repo.detect-agentsmd-form` is a prerequisite stage
    that detects which routing-target file(s) exist
    (`cc-only` = only CLAUDE.md; `codex-only` = only
    AGENTS.md; `dual` = both; `neither` = no target file).
    The detected `form` is cached in repo-shared
    `state.yml` and propagated through the `target_state`
    of every downstream `m7.repo.inject-block.*` stage,
    so any later change to the repo's file structure (user
    adds AGENTS.md to a previously CC-only repo, etc.)
    flips every M7 inject stage to `stale` and triggers
    a full re-injection.
  - Each routing block (`routing-rule`, `skill-routing`,
    plus future blocks) is a separate stage with shape
    `m7.repo.inject-block.<name>`. Each block has a
    `kind: required | optional` flag — required blocks
    are auto-injected by script; optional blocks
    (recommended-but-not-load-bearing prompt hints that
    improve agent effectiveness) are injected only after
    the agent surfaces them and the architect explicitly
    accepts. Per-block marker pair, content hash, and
    version make M7 stages re-evaluate independently when
    the plugin upgrades.
  - "User has modified the block" detection operates
    per-block via marker-pair content hash, not on the
    file as a whole.
  - **Codex `project_doc_max_bytes` constraint**: Codex
    CLI reads AGENTS.md (and walks root-to-cwd
    concatenating multiple AGENTS.md files) up to
    32 KiB total before truncating
    (PLUGIN_DEVELOPMENT.md § "Codex AGENTS.md lookup").
    M7 must honor this hard limit:
    - **single-block size cap**: ≤ 4 KiB per block
    - **plugin total budget on AGENTS.md**: ≤ 8 KiB across
      all M7 blocks plus all sub-directory AGENTS.md
      contributions (leaves ≥ 24 KiB headroom for
      architect content)
    - The `m7.repo.detect-agentsmd-form` stage measures
      total AGENTS.md size after concat-walk and refuses
      to inject if it would push total over budget — it
      surfaces a warning marker for architect attention
      instead.
  - **Optional-block list is currently empty in
    v0.4.0+redesign** but the SKILL flow MUST contain a
    `for each optional block in registry → prompt
    architect` loop (a no-op when list is empty) so
    future optional blocks can be added by registry edit
    alone, with no SKILL code change.
- **`M8` — Autonomy overrides.**
  `~/.board-superpowers/overrides.yml` +
  `config.local.yml:autonomy_overrides[]` (D-AUTONOMY-1
  user / project-layer override of the autonomy class
  matrix). **Currently outside bootstrap** — architect
  hand-edits. Whether to add a guided agentic stage at
  first-run is an open question (§ "Open design
  choices").
- **`M9` — Hook registration.** Platform-specific hook
  event registration (Codex CLI:
  `register-codex-hooks.sh`; Claude Code: auto-discover
  via `hooks/hooks.json`). Codex-only stage in the
  registry; brought into bootstrap per G4
  (cross-platform parity) — see the `platforms` column
  in the Stages table.
- **`M10` — BoardAdapter selection.** The architect
  decides which kanban backend the repo uses
  (`github-project-v2` / `linear` / `jira` per ADR-0005's
  BoardAdapter contract). At v0.5.0 the enum has only
  `github-project-v2`; the future `linear` / `jira`
  options land via registry-only edits (the option's
  `introduced_in` field gates re-prompt: a repo whose
  `kanban_backend` is `github-project-v2` from v0.5.0
  remains `completed` after the v0.6.0 enum bump because
  its `target_state` matches an extant option).
  **Why a separate module from M3 (GitHub Project
  integration).** M3 holds the *operations* against a
  selected board (label management, Status field
  validation, etc.). M10 holds the *selection* of which
  board adapter to operate against. Future Linear / Jira
  adapters land as new M3-pattern modules (or as additive
  M3 implementation routes); M10 stays the single
  selection seam. M3 stages depend on
  `m10.repo.choose-kanban-backend`.

## Stages

The stages registry. Each row is a stage; the table is the
machine-readable source of truth that the unified check
script walks every session start. **Add a new stage = add a
new row. Remove = set `deprecated_in_version`. Migrate = bump
the stage's `target_state_hash_fn` so the lifecycle model
(§ "Stage lifecycle states") flips affected entries to
`stale`.** Column semantics live in § "Stage registry
contract" below.

| stage_id | stage_name | description | module | character | locality | platforms | flags | introduced_in | depends_on | executor |
|----------|------------|-------------|--------|-----------|----------|-----------|-------|---------------|------------|----------|
| `m1.host.create-state-dir` | host state dir | Create `~/.board-superpowers/` (mode 0700) + `__host__/` sentinel subdir | M1 | automated | host-shared | both | — | v0.1.0-minimum | — | `scripts/bootstrap-host.sh` |
| `m1.host.write-manifest` | manifest.yml | Atomic write of host-level `manifest.yml` (`schema_version: 2`, `last_seen_version`, `uv_version`) | M1 | automated | host-shared | both | — | v0.1.0-minimum (schema 2 since v0.3.0) | `m1.host.create-state-dir` | `scripts/bootstrap-host.sh` |
| `m1.repo.write-state-yml` | state.yml | Atomic write of per-repo `state.yml` (`schema_version: 1`, `stages_completed[]`, `routing_blocks[]`) | M1 | automated | repo-shared | both | — | v0.1.0-minimum | `m1.host.write-manifest` | `scripts/bootstrap-project.sh` |
| `m2.host.install-uv` | uv installer | Detect / install `uv` Python tool host-wide via `astral.sh/uv/install.sh` or PATH probe | M2 | automated | host-shared | both | `heavy`, `network-required` | v0.3.0 | — | `scripts/bootstrap-host.sh` |
| `m2.repo.copy-uv-templates` | uv templates | Copy plugin's `pyproject.toml` + `uv.lock` from `<plugin>/scripts/templates/` into `<repo>/.board-superpowers/` | M2 | automated | repo-git | both | — | v0.3.0 | `m1.repo.write-state-yml` | `scripts/bootstrap-project.sh` |
| `m2.repo.sync-venv` | venv sync | Run `uv sync` to materialize `<repo>/.board-superpowers/.venv/` from the copied lock | M2 | automated | repo-clone | both | `heavy` | v0.3.0 | `m2.host.install-uv`, `m2.repo.copy-uv-templates` | `scripts/bootstrap-project.sh` |
| `m3.repo.ensure-labels` | standard labels | Ensure 13 standard GitHub Issue labels exist on the repo (idempotent via `gh` CLI); only runs when `kanban_backend == github-project-v2` | M3 | automated | external | both | — | v0.1.0-minimum | `m10.repo.choose-kanban-backend` | `scripts/setup-labels.sh` |
| `m3.repo.validate-status-field` | status field validation | Validate the GitHub Project's 6-option Status field schema; agentic only on failure (guide architect to GitHub UI); only runs when `kanban_backend == github-project-v2` | M3 | agentic | external | both | `confirm-only`, `agentic-on-failure` | v0.1.0-minimum | `m10.repo.choose-kanban-backend` | `SKILL: bootstrapping-repo` (failure path) / `scripts/validate-status-field.sh` (read path) |
| `m4.repo.acquire-dsn` | audit DSN | Acquire BYO RDBMS DSN; write per-repo `credentials.yml` (chmod 0600); first-time agentic, re-use automated | M4 | agentic | repo-shared | both | `confirm-only` (re-use path is automated) | v0.3.0 (host-shared); per-repo since vX.0.0 (this redesign) | `m1.repo.write-state-yml` | `SKILL: bootstrapping-repo` (first-time) / `scripts/bootstrap-project.sh` (re-use) |
| `m4.repo.apply-audit-ddl` | audit DDL | Apply audit-log DDL to the resolved DB (3-dialect dispatch via `audit-init.sh`) | M4 | automated | external | both | — | v0.3.0 | `m4.repo.acquire-dsn` | `scripts/audit-init.sh` |
| `m4.repo.flush-pending-audit` | audit flush | Replay `mode=bootstrap-pending` rows from jsonl into DB (idempotent via UNIQUE event_uuid) | M4 | automated | external | both | — | v0.3.0 | `m4.repo.apply-audit-ddl` | `scripts/audit-flush-pending.sh` |
| `m4.repo.audit-health-check` | audit health | Print stderr summary of audit-row landing count vs jsonl pending count | M4 | automated | repo-shared | both | — | v0.3.0 | `m4.repo.flush-pending-audit` | `scripts/bootstrap-project.sh` |
| `m5.repo.write-config-yml` | config.yml | Write `<repo>/.board-superpowers/config.yml` with project default knobs (committed to git) | M5 | automated | repo-git | both | — | v0.1.0-minimum | — | `scripts/bootstrap-project.sh` |
| `m5.repo.write-config-local-yml` | config.local.yml | Write `<repo>/.board-superpowers/config.local.yml` with per-architect knobs (gitignored) | M5 | automated | repo-clone | both | — | v0.1.0-minimum | — | `scripts/bootstrap-project.sh` |
| `m5.repo.set-wip-limit` | wip limit | Prompt architect for `wip_limit` (concurrent active Consumer cap) per repo; default 5; persist into `config.local.yml:wip_limit`; architect may accept default to advance | M5 | agentic | repo-clone | both | `confirm-only` | vX.0.0 (this redesign) | `m5.repo.write-config-local-yml` | `SKILL: bootstrapping-repo` |
| `m6.repo.append-gitignore` | gitignore entries | Append three protective entries (`*.local.*`, `claims/`, `.venv/`) to `<repo>/.gitignore` (idempotent) | M6 | automated | repo-git | both | — | v0.1.0-minimum | — | `scripts/bootstrap-project.sh` |
| `m7.repo.detect-agentsmd-form` | agentsmd form | Detect repo's routing-target form (`cc-only` / `codex-only` / `dual` / `neither`) by scanning AGENTS.md + CLAUDE.md presence; cache result in repo-shared state | M7 | automated | repo-shared | both | — | vX.0.0 (this redesign) | `m1.repo.write-state-yml` | `scripts/bootstrap-project.sh` |
| `m7.repo.inject-block.routing-rule` | routing-rule block | Inject `routing-rule` required block (skill-routing trigger) into target file(s) per detected form; check 4 KiB single-block size cap; honor 8 KiB total Codex AGENTS.md budget | M7 | automated | repo-git | both | `kind=required`, `block-size-capped` | v0.1.0-minimum (single-block); per-block stage since vX.0.0 (this redesign) | `m7.repo.detect-agentsmd-form` | `scripts/bootstrap-project.sh` |
| `m7.repo.inject-block.skill-routing` | skill-routing block | Inject `skill-routing` required block (Manager / Consumer dispatch rules) into target file(s) per detected form | M7 | automated | repo-git | both | `kind=required`, `block-size-capped` | v0.1.0-minimum (single-block); per-block stage since vX.0.0 (this redesign) | `m7.repo.detect-agentsmd-form` | `scripts/bootstrap-project.sh` |
| `m9.host.register-codex-hooks` | codex hook registration | Register `~/.codex/config.toml` `[hooks]` table to wire `SessionStart` to `hooks/session-start.sh` | M9 | automated | host-shared | codex-only | `platform-specific` | vX.0.0 (this redesign) | `m1.host.write-manifest` | `scripts/register-codex-hooks.sh` |
| `m8.host.bootstrap-overrides-yml` | autonomy overrides | Prompt architect with curated autonomy-override presets; persist selected subset into the `host-shared` settings file (empty selection is a valid completed state) | M8 | agentic | host-shared | both | `confirm-only` | vX.0.0 (this redesign) | `m1.host.write-manifest` | `SKILL: bootstrapping-repo` |
| `m10.repo.choose-kanban-backend` | kanban backend | Prompt architect to choose BoardAdapter backend per ADR-0005 (`github-project-v2` / `linear` / `jira`). At v0.5.0 the enum has only `github-project-v2`; M3 stages depend on this selection | M10 | agentic | repo-git | both | `confirm-only`, `single-choice-currently` | vX.0.0 (this redesign) | `m1.repo.write-state-yml` | `SKILL: bootstrapping-repo` |

**22 stages** — 14 v0.4.0 baseline (M7 v0.4.0 single-block
stage replaced) + 8 net new / restructured this redesign
(`m7.repo.detect-agentsmd-form`,
`m7.repo.inject-block.routing-rule`,
`m7.repo.inject-block.skill-routing`,
`m9.host.register-codex-hooks`,
`m8.host.bootstrap-overrides-yml`,
`m5.repo.set-wip-limit`,
`m10.repo.choose-kanban-backend`, plus the M4
`acquire-dsn` re-locality). Future `kind=optional` M7 blocks
or new BoardAdapter selections add agentic stages of shape
`m7.repo.inject-block.<name>` or new M10 enum options
without registry-shape changes. The 32 KiB Codex AGENTS.md
budget caps total M7 routing block size — see § "Functional
modules" M7.

### Cross-axis sparsity is the value of the table form

A single 3D matrix (5 localities × 2 characters × 9 modules =
90 conceptual cells) is mostly empty. The table form lets you
scan by row without manually computing the 3D index. Common
queries the table answers at a glance:

- *"What stages does M4 own?"* — filter `module=M4` → 4 rows.
- *"What runs only on Codex?"* — filter `platforms=codex-only`
  → 1 row (`m9.host.register-codex-hooks`).
- *"What stages need network egress?"* — filter `flags`
  contains `network-required` → 1 row
  (`m2.host.install-uv`).
- *"What's the dependency chain into `m4.repo.apply-audit-ddl`?"*
  — read `depends_on` columns transitively.
- *"What stages are agentic and therefore require entering
  the `bootstrapping-repo` SKILL?"* — filter `character=agentic`
  → 3 rows (`m3.repo.validate-status-field` failure path,
  `m4.repo.acquire-dsn` first-time, `m8.host.bootstrap-overrides-yml`).
  Future `kind=optional` M7 blocks add agentic rows.

## Trigger model

The trigger model is **hook-minimal with partitioned status
storage**: the SessionStart hook never runs stages itself —
it reads the partitioned status files (one per locality), runs
the 4-state lifecycle diff against the registry, and emits a
single `INVOKE: bootstrapping-repo` marker if any stage needs
running. The `bootstrapping-repo` SKILL is the **single
executor** for every stage (automated and agentic alike).

### Why hook-minimal beats hook-runs-stages

The earlier draft considered three options:

- **α**: hook minimal (only diff + marker), SKILL runs all
  stages.
- **β**: hook runs all automated stages synchronously, SKILL
  runs only agentic.
- **γ**: hook runs "light automated" only, SKILL runs heavy
  automated + agentic.

β is rejected by CC's SessionStart synchronous-blocking
constraint (uv install + venv sync can total 30-50s, well
past the ≤5s soft limit). γ was the leading candidate but
adds dual-track complexity (hook needs run + write + retry +
concurrency logic; the runtime split between hook and SKILL
fragments error handling).

α wins after re-reading G2 carefully: G2 says automated
stages should run *without architect attention*, not *without
entering an agent session*. An agent autonomously dispatching
`Bash` tool calls to executors inside the SKILL flow is
"automated" by G2's intent — the architect doesn't decide,
input, or wait between stages; they see a single "bootstrap
running" surface and watch agent + scripts handle it. The
SKILL is the single executor path; light vs heavy automated
just differ in elapsed time, not in execution mechanism.

### Hook flow (pseudocode)

```bash
#!/bin/bash
# hooks/session-start.sh — α model with partitioned status
set +e   # never block session

PLUGIN_VERSION=$(read_plugin_json_version)
REPO_IDENTITY=$(compute_repo_identity)  # <owner>-<repo> or fallback

# Step 1: read four partitioned status files (each cheap, ~10ms each)
HOST_STATUS=$(read_yaml ~/.board-superpowers/manifest.yml stages_completed)
REPO_SHARED_STATUS=$(read_yaml ~/.board-superpowers/repos/${REPO_IDENTITY}/state.yml stages_completed)
REPO_GIT_STATUS=$(read_yaml ${REPO_ROOT}/.board-superpowers/repo-state.yml stages_completed)
REPO_CLONE_STATUS=$(read_yaml ${REPO_ROOT}/.board-superpowers/clone-state.yml stages_completed)

# Step 2: compute lifecycle for every stage in the registry
PENDING=()
for stage in $(registry_iter); do
  bucket=$(stage_locality "$stage")  # host-shared | repo-shared | repo-git | repo-clone | external
  status_entry=$(lookup_in_bucket "$bucket" "$stage")
  state=$(compute_lifecycle "$stage" "$status_entry" "$PLUGIN_VERSION")
  case "$state" in
    completed|deprecated) continue ;;
    never-run|stale) PENDING+=("${stage}:${state}") ;;
  esac
done

# Step 3: emit marker if any pending
if [ ${#PENDING[@]} -gt 0 ]; then
  echo "INVOKE: bootstrapping-repo"
  echo "REASON: ${#PENDING[@]} stages need running (${PENDING[*]})"
fi

exit 0
```

Total hook time budget: **~200ms** (4 small YAML reads + 18
hash comparisons + emit). Far below CC's ≤5s soft limit.

### SKILL flow (when marker fires)

The `bootstrapping-repo` SKILL is awakened only when the hook
emits a marker (i.e., something needs running). Inside:

1. **Re-read** the four partitioned status files (fresh
   snapshot — another session might have updated since hook
   ran).
2. **Re-compute** the lifecycle diff (must match hook's diff
   ± any concurrent updates).
3. **Topologically sort** pending stages by `depends_on`.
4. **Execute** stage by stage:
   - `automated` stages: agent calls executor via `Bash`
     tool (light = synchronous, heavy = with progress
     surface). No architect interaction.
   - `agentic` stages: agent surfaces decision / input /
     confirmation request to the architect, waits for reply,
     then executes.
5. **Update status** atomically after each stage (write to
   the appropriate partitioned status file; mktemp + mv +
   read-merge-write for concurrency).
6. **Surface summary** at end: "N stages completed; M
   skipped; K still need attention."

### Hook–SKILL contract

The hook is **observation-only**: it reads, diffs, emits a
marker. It never writes. It never executes a stage.

The SKILL is **execution-only**: it never decides whether to
run (the hook + lifecycle diff already decided). It runs the
listed stages, records completion, and surfaces results.

This split enables:
- **Single-direction state flow**: hook reads → SKILL writes
  → next hook reads. No interleaved hook/SKILL writes to fight.
- **Hook idempotency by construction**: a hook that doesn't
  write is trivially safe to re-run (multiple sessions, hook
  retries, etc.).
- **Error-handling concentration**: all "what went wrong" /
  "how to recover" logic lives in the SKILL with full agent
  context (not split between hook log + SKILL retry).

### Failure modes

| Failure | Hook behavior | SKILL behavior |
|---------|---------------|----------------|
| Status file missing / corrupt | Treat as `never-run` for affected stages; emit marker | First action is to (re-)create the file via `m1.host.write-manifest` / `m1.repo.write-state-yml` etc. |
| Hook takes >2s (CC slow-hook warning) | Already cheap by design; if observed, partitioned files are too large or registry is too big — escalate to ADR | n/a |
| Stage executor fails | n/a (hook doesn't run executors) | Log structured failure to status file (`status: failed`, `last_error`); leave entry in `never-run` / `stale`; next session re-attempts |
| Agentic stage abandoned mid-flow | n/a | SKILL records `status: pending-architect-input`; lifecycle keeps surfacing via marker on next session |
| Concurrent SKILL invocations (two sessions) | n/a | Per-status-file `flock` while updating; reread + merge before write |
| External stage's TTL expired | Lifecycle returns `stale` for that stage; hook emits marker | Re-runs the stage's `target_state_predicate` (e.g., `gh api` to re-validate labels) and refreshes the cached hash |

## Declarative state schema

State is **partitioned by locality** and unified under the
`settings.yml` family — each of the four non-`external` Axis B
values gets its own dedicated YAML settings file. `external`
stages cache their last-validation results inside `repo-shared`'s
settings file (no separate external status file).

The `settings.yml` naming is the architect-facing surface (per
§ "Architect UX"): every architect's plugin configuration is
visible by reading the appropriate `settings.yml`. The same
files are also the plugin runtime's lifecycle source-of-truth
(stages_completed entries with three-layer fingerprint live
inside). Pre-v1 breaking change: existing v0.4.0 plumbing
filenames (`manifest.yml`, `state.yml`, `config.yml`,
`config.local.yml`) rename to the unified family below; existing
host-shared `overrides.yml` content folds into the host-shared
`settings.yml` under a dedicated `autonomy_overrides` key.

### Four settings files (one per locality)

| File | Locality | Cross-clone? | Tracked in git? | Replaces (v0.4.0) | Stage entries |
|------|----------|--------------|-----------------|-------------------|---------------|
| `~/.board-superpowers/settings.yml` | `host-shared` | n/a (host-wide) | No | `manifest.yml` + `overrides.yml` (folded) | M1 host stages, M2 install-uv, M8 autonomy presets, M9 codex-hook |
| `~/.board-superpowers/repos/<repo-identity>/settings.yml` | `repo-shared` | **Yes (cross-clone shared)** | No | `state.yml` | M1 per-repo state stage itself, M4 audit stages, M7 form-detect cache, external-stage TTL caches |
| `<repo>/.board-superpowers/settings.yml` | `repo-git` | No (per-clone-physical, sync via git) | **Yes (committed)** | `config.yml` | M2 templates, M5 config.yml, M6 gitignore, M7 routing-block stages, M10 kanban backend choice |
| `<repo>/.board-superpowers/settings.local.yml` | `repo-clone` | No (per-clone-physical) | No (gitignored) | `config.local.yml` | M2 venv, M5 config.local.yml + WIP limit |

`~/.board-superpowers/repos/<repo-identity>/credentials.yml`
remains a separate file (mode 0600) for secret isolation; it
is not part of the `settings.yml` family because settings files
are mode 0644 and may be inspected casually.

**Why partition?** A single monolithic state file would have
to cross-cut localities (e.g., a `settings.yml` at repo root
holding stages whose outcomes live under `~/...` — confusing).
Partitioning makes each file's *ownership* clear: this file
records progress for stages whose outcomes land in this
locality. The hook reads four small files in parallel; each
file's update path is owned by stages of one locality.

**Why unify the names?** Pre-redesign v0.4.0 has four
plumbing files with four different names (`manifest.yml`,
`state.yml`, `config.yml`, `config.local.yml`) — the
disparate naming reflects implementation history, not
architectural meaning. The redesign makes `settings.yml` the
single architect-facing concept, with `.local.yml` as the
sole suffix variant (matching git-ignore convention). One
mental model, one filename family.

### Per-stage entry shape

Each `stages_completed[]` entry has the same shape regardless
of which file it lives in. The shape carries the
**three-layer fingerprint** (generation + hash + structured
target_state) plus identification + diagnostic fields:

```yaml
stages_completed:
  - stage_id: m1.host.write-manifest
    status: completed              # 4-state lifecycle enum (+ 2 transient)
    completed_at: 2026-04-28T14:23:05Z
    plugin_version: v0.5.0         # the version that ran it
    generation: 3                  # K8s-style integer (registry-bumped)
    target_state_hash: a1b2c3...   # derived from canonical(target_state)
    target_state:                  # structured ground truth (per-stage shape)
      manifest_path: ~/.board-superpowers/manifest.yml
      schema_version: 2
      fields_present: [last_seen_version, host_bootstrapped_at, uv_version]
      mode: 0644
    target_state_schema_version: 1 # schema of the target_state field itself
    last_error: null               # populated on `failed` status
  - stage_id: m4.repo.apply-audit-ddl
    status: completed
    completed_at: 2026-04-28T14:23:12Z
    plugin_version: v0.5.0
    generation: 7
    target_state_hash: d4e5f6...
    target_state:
      audit_log:
        schema_version: 2
        columns_required: [event_id, event_uuid, action_id, ts, ...]
        indexes_required: [idx_event_uuid_unique]
      audit_outbox:
        columns_required: [...]
      audit_schema_meta:
        columns_required: [version, applied_at]
    target_state_schema_version: 1
    last_error: null
```

| Field | Type | Required? | Semantics |
|-------|------|-----------|-----------|
| `stage_id` | string | yes | Lookup key (matches registry). |
| `status` | enum `completed` \| `never-run` \| `stale` \| `deprecated` \| `failed` \| `pending-architect-input` | yes | The 4-state lifecycle plus two transient states (`failed`, `pending-architect-input`) the SKILL may write while a stage is mid-flow. The lifecycle model treats `failed` and `pending-architect-input` as effectively `never-run` (re-attempt next session). |
| `completed_at` | ISO 8601 UTC | when status=completed | Wall-clock observability; never used for trigger logic. |
| `plugin_version` | semver | when status=completed | The plugin version whose registry executed this stage. Used for the lifecycle's composite key. |
| `generation` | non-negative int | when status=completed | Monotonic integer bumped by the registry when the stage's expected target changes (schema, executor, content template). Layer-1 of three-layer fingerprint (cheap fast-path). Always increases; never decreases (rollback unsupported). |
| `target_state_hash` | hex string (sha256) | when status=completed | sha256 of canonical YAML emit of `target_state` (sorted keys, fixed indent, normalized newlines, hash-allowlist excluded). Layer-2 of three-layer fingerprint — catches "developer forgot to bump generation" cases. |
| `target_state` | structured YAML (per-stage shape) | when status=completed | Layer-3 of three-layer fingerprint — full structured ground truth of what was done. SKILL diffs current registry's `target_state` against recorded for human-readable migration messages. |
| `target_state_schema_version` | non-negative int | when status=completed | Schema version of the `target_state` field's *own shape*. Bumped when the stage author changes the structure of `target_state` itself (additive only, lazy-on-read). |
| `last_error` | string | when status=failed | Short failure summary; pointer to log file for details. |

### Hash-allowlist (fields excluded from hash)

The `target_state_hash` is computed over canonical YAML
emit of `target_state` *with the following fields excluded*
(allowlist enforced by canonicalization helper in
`stages_lib/<stage_id>.py`):

- `last_validated_at` (timestamp; non-deterministic)
- `last_run_id` (uuid; per-run unique)
- Any field annotated `[hash-excluded]` in the stage's
  registry entry

Excluded fields still appear in the recorded `target_state`
(for forensics) but don't affect hash equality. Architects
adding a new excluded field MUST add it to the registry's
hash-allowlist, or hash will become unstable across runs.

### Schema versioning

Each status file carries a top-level `schema_version: <int>`
field. Per-file schema versioning lets each file evolve
independently (e.g., `state.yml` schema bumps don't cascade
to `manifest.yml`). Migration policy is **lazy-on-read +
versioned-and-additive only**, per
[`../0005-contracts/03-config-schemas.md`](../0005-contracts/03-config-schemas.md)
§ "Migration policy". A status file with a higher
`schema_version` than the running plugin understands fails
loudly (architect downgraded plugin — manual recovery).

### Why schema_version is per-file AND per-stage-target

Two different schemas evolve independently:

- **File-level `schema_version`** (top of each status file)
  — controls the shape of the file as a whole (the
  `stages_completed[]` entry shape, top-level fields).
  Bumped when the entry's universal fields change (e.g.,
  if a future redesign adds `priority: <int>` to every
  entry).
- **Stage-target `target_state_schema_version`** (per-entry)
  — controls the shape of *that stage's* `target_state`
  blob. Each stage author bumps their own when they evolve
  their target_state structure. Independent per stage.

This separation prevents M4's DDL evolution from forcing a
manifest.yml file-schema bump, and lets each stage author
own their target shape's lifecycle.

### External stage TTL cache (in repo-shared state.yml)

External-locality stages (M3 labels, M3 Status field, M4
DDL, M4 audit-flush) cache their last validation outcome in
`repo-shared`'s `state.yml` to avoid hitting GitHub / DB on
every session start. Entry shape extends with two extra
fields:

```yaml
- stage_id: m3.repo.ensure-labels
  status: completed
  completed_at: 2026-04-28T14:23:08Z
  plugin_version: v0.5.0
  generation: 2
  target_state_hash: 7e8f9a...
  target_state:
    labels_required:
      - {name: "type:bug", color: "d73a4a"}
      - {name: "type:feature", color: "0075ca"}
      # ... 11 more
    labels_present_check: gh-cli-v2-list
  target_state_schema_version: 1
  external_validated_at: 2026-04-28T14:23:08Z  # [hash-excluded]
  external_ttl_seconds: 86400                  # [hash-excluded]
```

`external_validated_at` and `external_ttl_seconds` are in
the hash-allowlist (excluded from hash). If
`now > external_validated_at + external_ttl_seconds`, the
lifecycle returns `stale` regardless of generation /
hash match — forcing a fresh `gh api` call. TTL per stage
is declared in the registry (default 86400 = 24h,
overridable per-stage).

## Repo identity

Repo identity is **GitHub-based**: the host-local per-repo
state directory is keyed by `<owner>-<repo>` derived from the
repo's `origin` remote URL, not by the on-disk absolute path.

### Identity scheme: `<owner>-<repo>` from origin URL

```
git remote get-url origin
  → https://github.com/PanQiWei/board-superpowers.git
  → git@github.com:PanQiWei/board-superpowers.git

bsp_compute_repo_identity()
  → strip scheme prefix and `.git` suffix
  → extract <owner>/<repo> path component
  → replace `/` with `-`
  → "PanQiWei-board-superpowers"
```

Per-repo host-local state lives at:

```
~/.board-superpowers/repos/PanQiWei-board-superpowers/
├── state.yml             ← bootstrap progress (repo-shared)
├── credentials.yml       ← per-repo audit DSN (repo-shared)
├── audit.db              ← optional per-repo SQLite (repo-shared)
└── audit-local.jsonl     ← per-repo audit fallback (repo-shared)
```

### Edge cases

- **Local-only repo (no `origin` remote)** — fallback to the
  current path-based normalization (`bsp_normalize_repo_path`
  on the absolute repo path). State for this repo lives at
  `~/.board-superpowers/repos/_path-Users-foo-myproj/` with
  the `_path-` prefix to distinguish from GitHub identities.
  When the architect later adds an `origin` remote pointing
  to GitHub, the `m1.host.migrate-repo-identity` stage (TBD)
  detects the transition and migrates the state directory to
  the new identity.
- **HTTPS vs SSH URL form** — both
  `https://github.com/A/B.git` and `git@github.com:A/B.git`
  resolve to identity `A-B`. URL form is normalized away.
- **Multi-remote repos** — `origin` is the canonical source.
  If `origin` points to a non-GitHub host (e.g., GitLab),
  identity is derived analogously (`<host>-<owner>-<repo>`)
  but BoardAdapter behavior depends on the configured
  adapter (per ADR-0005).
- **Forks** — fork's `origin` typically points to the fork
  (`<your-name>/<their-repo>`), so fork has its own identity
  separate from upstream. State (audit DSN, bootstrap
  progress) does not transfer between fork and upstream.
- **Repo rename on GitHub** — origin URL no longer matches
  identity. The `bsp-relocate-repo.sh <old> <new>` helper
  atomically `mv`s the state directory; architect runs
  it once after the rename. (Possible future enhancement: a
  stage that detects the mismatch on session start and
  prompts.)
- **All worktrees share identity** — `git rev-parse
  --git-common-dir` resolves any worktree to the primary
  repo, which has the canonical `origin`. Worktrees of the
  same primary repo share state, which is the correct
  behavior for multi-card-multi-worktree workflows.

### I-13 invariant revision (cross-clone state sharing)

The current spec [`../07-cross-cutting-invariants.md`](../0002-product-features-and-flows/07-cross-cutting-invariants.md)
§ "I-13" reads (paraphrased): "Each architect's clone of the
same repo gets a SEPARATE state.yml because their clones have
different absolute paths."

This redesign **revises I-13**:

> **I-13 (revised).** Each `(host, GitHub repo)` pair shares
> a single host-local per-repo state directory at
> `~/.board-superpowers/repos/<repo-identity>/`, regardless
> of how many physical clones exist on the host. Per-clone
> physical isolation is preserved only for `repo-clone`
> locality stages (`.venv/`, `config.local.yml`).

Implications:

- Two clones at `~/Dev/foo` and `~/Sandbox/foo` on the same
  host **share** their `state.yml`, `credentials.yml`, audit
  DB. Changes from one clone are immediately visible to the
  other.
- Two architects on the same host who each clone the same
  repo **share** their host-local per-repo state (audit
  credentials, bootstrap progress). This is intentional —
  the per-`(host, repo)` configuration should be one
  authoritative copy. Per-architect divergence is preserved
  via `repo-clone` locality (each architect's `config.local.yml`
  is in their own clone path).
- Worktrees behave correctly without special handling
  (worktrees inherit primary repo's identity).

The revision lands as **a new ADR** in
[`../adr/`](../0002-product-features-and-flows/../adr/) +
edits to `07-cross-cutting-invariants.md` § I-13 in the
replacement PR.

## Stage registry contract

The Stages table above is the **rendered view** of an
underlying registry. The registry is the single declaration
of every stage; the table renders selected columns for
human reading. Adding a stage means adding a registry entry;
the table is regenerated (mechanically or by hand-edit
discipline).

### Storage: YAML metadata + Python helpers + JSON Schema validation

Per industry pattern (Tekton CRDs, Helm Chart.yaml, npm
package.json, Cargo.toml, Ansible playbooks all use
declarative-markup + sibling source-files), the registry
splits into two artifacts plus a validation schema:

- **`scripts/stages-registry.yml`** — declarative metadata
  for every stage (all `(table)` fields below + the
  per-stage `target_state` schema definition). Single file;
  bash hooks parse it directly via `pyyaml` (already in the
  per-repo venv) without invoking Python helpers.
- **`scripts/stages_lib/<stage_id>.py`** — one Python
  module per stage; provides callables (`idempotency_check`,
  `target_state_predicate`, `executor`,
  `compute_target_state`). Naming convention:
  `stages_lib/m4_repo_apply_audit_ddl.py` (stage_id with
  `.` and `-` replaced by `_`).
- **`scripts/stages-registry.schema.json`** — JSON Schema
  for `stages-registry.yml`. Load-time validation
  (CI-gated and runtime-gated): catches typos in
  `module` / `locality` / `platforms` enums, missing
  required fields, malformed `depends_on` entries, and
  per-stage `target_state` shape divergence. Pattern is
  identical to Tekton's OpenAPI-v3-in-CRDs and Helm's
  `values.schema.json`.

Decision rationale: bash hooks are the lowest-common-denominator
consumer of stage metadata; YAML is the only format bash can
parse cheaply (pyyaml + python3 wrapper). Python is the
right home for callables that need typed function refs
(predicates / hash-fns / executors). JSON Schema gates the
gap. Pure-Python decorator registry (Dagster / Prefect
pattern) is rejected because it would force bash hooks to
shell out to Python just to enumerate stage IDs, breaking
the hook-cheap invariant.

### Column / field semantics

Every stage in the registry has the following fields. Fields
shown as columns in the Stages table are marked **(table)**;
fields elaborated in supporting prose elsewhere are marked
**(prose)**.

| Field | Type | Required? | Semantics |
|-------|------|-----------|-----------|
| `stage_id` **(table)** | string, `<module>.<scope>.<verb>` | yes | Globally unique identifier. `<scope>` is `host` or `repo` (matching Axis B). The lookup key in status files' `stages_completed[]` entries. |
| `stage_name` **(table)** | string, ≤30 chars | yes | Short human-readable display name; appears in CLI output and error messages. |
| `description` **(table)** | string, one line | yes | Statement of *what the stage produces* — its work product, not its mechanics. (Mechanics belong in the executor's source code.) |
| `module` **(table)** | enum M1..M9 | yes | Functional module ownership (Axis C). |
| `character` **(table)** | enum `automated` \| `agentic` | yes | Execution character (Axis A). |
| `locality` **(table)** | enum `host-shared` \| `repo-shared` \| `repo-git` \| `repo-clone` \| `external` | yes | Outcome's locality (Axis B). `repo-shared` = host-local but cross-clone-shared at `~/.board-superpowers/repos/<repo-identity>/`; `repo-clone` = git-ignored, per-clone physical copy at `<repo>/.board-superpowers/`. |
| `platforms` **(table)** | enum `cc` \| `codex` \| `both` \| `cc-only` \| `codex-only` | yes | Cross-platform parity declaration (G4). `both` = identical behavior on both; `cc-only` / `codex-only` = intentionally platform-specific. |
| `flags` **(table)** | string list | no | Free-form binary tags. Reserved tokens: `heavy` (network/IO heavy), `network-required`, `kind=required` / `kind=optional` (M7 only), `confirm-only`, `agentic-on-failure`, `platform-specific`, `block-size-capped` (M7 inject stages). |
| `introduced_in_version` **(table)** | semver string | yes | Plugin version that first shipped this stage's *semantic work* (not when the registry-modeled stage_id concept was introduced). Used by the lifecycle model to detect cohort introduction. |
| `deprecated_in_version` **(table)** | semver string | no | Plugin version where the stage was removed from the registry. When set, lifecycle state for any recorded entry flips to `deprecated`. |
| `depends_on` **(table)** | list of stage_ids | no | Stages that must be `completed` before this one runs. Forms an explicit DAG; the trigger script topologically sorts. |
| `executor` **(table)** | `scripts/<path>` \| `SKILL: <skill-name>` | yes | Where the stage's execution lives. Script paths are relative to plugin root; skill markers are emitted via `INVOKE: <skill-name>` to drive the agent path. |
| `generation` **(prose, registry)** | non-negative int | yes | Monotonic integer; bumped by the registry maintainer whenever any aspect of the stage's expected target changes (schema, executor, content template). Layer-1 of the three-layer fingerprint (cheap fast-path; see § "Stage lifecycle states"). |
| `target_state_schema` **(prose)** | JSON-Schema-style declaration | yes | Per-stage shape declaration for the structured `target_state` field that gets persisted to status files. Validated by `stages-registry.schema.json` at load-time. |
| `target_state_schema_version` **(prose)** | non-negative int | yes | Schema version of the `target_state_schema` itself. Bumped when the stage author evolves the target_state shape (additive only). |
| `compute_target_state` **(prose, callable)** | function ref returning structured data | yes | Returns the *current expected target state* (computed from the registry + repo context). Output validated against `target_state_schema`. Layer-3 (ground truth) of the three-layer fingerprint. |
| `idempotency_check` **(prose, callable)** | function ref returning bool | yes | "Has this stage been run successfully?" — pure function from local state to bool. Cheap; runs every check. |
| `target_state_predicate` **(prose, callable)** | function ref returning bool | yes | "Is the world in the state this stage targets?" — may include external queries (GitHub / DB) for `external`-locality stages. The seam where re-validation happens. |
| `hash_excluded_fields` **(prose)** | list of dotted paths into target_state | no | Fields excluded from the canonical-YAML hash (e.g., `external_validated_at`, `last_run_id`). Allowlist enforced by canonicalization helper; see § "Per-stage entry shape" hash-allowlist. |
| `external_ttl_seconds` **(prose, external stages only)** | non-negative int | external only | TTL for external-stage validation cache. Default 86400 (24h). |
| `kind` **(table, M7 only)** | enum `required` \| `optional` | M7 only | M7 routing-block kind tag (per architect direction). Surfaced as `kind=required` / `kind=optional` in the table's `flags` column. |
| `block_max_bytes` **(prose, M7 only)** | non-negative int | M7 only | Per-block size cap (default 4096 bytes). Honors Codex 32 KiB AGENTS.md budget — see § "Functional modules" M7. |

### Canonicalization invariant for hash stability

The hash is computed over canonical YAML emit of
`compute_target_state()` output:

1. Deep-sort all keys alphabetically.
2. Use fixed indent (2 spaces) and fixed flow style (block).
3. Normalize all line endings to `\n`; strip trailing
   whitespace per line.
4. Strip the `hash_excluded_fields` paths before hashing.
5. sha256 the resulting string.

The canonicalization helper lives in
`scripts/stages_lib/_canonical.py` (shared by all stages).
A stage's `compute_target_state()` must be deterministic
given identical inputs — non-determinism (random keys, set
iteration order, timestamps inside the structure) breaks
hash stability and gets caught by CI.

### What the lifecycle model asks of each stage

The 4-state lifecycle reads the registry + per-stage status
file entries to compute each stage's current state. Each
stage MUST provide:

- A `generation` int — bumped by the maintainer when the
  expected target changes (the **declarative knob** that
  drives the lifecycle).
- A `target_state_schema` — declarative shape of the
  stage's expected outcome.
- A `compute_target_state()` callable — produces the
  current expected target_state for diffing.
- An `idempotency_check()` callable — used by the executor
  to short-circuit "I just ran, no need to re-run."
- A `target_state_predicate()` callable — used at re-run
  time to confirm the outcome actually landed (especially
  for `external`-locality stages where local files lie).

These five together form the **stage's contract with the
lifecycle model**. A stage that fakes any of them silently
breaks the diff-and-replay mechanism. The
`stages-registry.schema.json` validates the declarative
fields; CI tests validate the callable contracts (each
must round-trip a known input → output).

## Stage lifecycle states

Each stage's recorded state is one of four values, computed
deterministically by the unified check script per session
start. The model uses a **three-layer comparison stack**
borrowed from Kubernetes' `metadata.generation` /
`status.observedGeneration` pattern and Terraform's
`serial` + structured state pattern (verified against
industry practice — both systems pair structured state with
a cheap monotonic primitive for fast-path diff):

1. **`generation` integer** (cheap fast-path, O(1)
   comparison) — incremented monotonically by the registry
   when *any* aspect of the stage's expected target changes
   (schema bump, executor change, content template change).
   Hook compares `entry.generation == registry[stage_id].generation`
   first; if equal, skip without further work.
2. **`target_state_hash`** (medium fast-path; derived
   automatically from `target_state` via canonical YAML
   emit + sha256) — distinguishes accidental generation
   non-bumps (developer forgot to bump) from genuine
   identity. Hook computes current hash from canonical
   target_state; compares against recorded
   `entry.target_state_hash`.
3. **`target_state`** (ground truth — full structured
   data) — used by SKILL's structural diff to surface
   "what specifically changed" for migration logic
   derivation and architect-readable error messages. Not
   read by hook (hook never goes deeper than hash).

The `(stage_id, plugin_version, generation, target_state_hash)`
quartet plus the `target_state` ground-truth determine which
state applies — no fuzzy matching, no manual override.

| State | Definition | Detection rule |
|-------|------------|----------------|
| **never-run** | This stage has never been recorded as completed on this `(host, repo)` pair. | No entry with this `stage_id` exists in the relevant status file. |
| **completed** | Last recorded run succeeded **and** the recorded fingerprint matches the current plugin version's expectation. | Entry exists; `entry.generation == registry[stage_id].generation` (fast-path) AND `entry.target_state_hash == current_target_state_hash` (verify). Both equal → up-to-date; no re-run needed. |
| **stale** | Last recorded run succeeded, but the current plugin version's expected target state has drifted (schema bump, content change, dep upgrade, executor change). | Entry exists; either `entry.generation != registry[stage_id].generation` OR (generation equal but) `entry.target_state_hash != current_target_state_hash`. SKILL re-runs the stage on next session start; structural diff between recorded `target_state` and current `target_state` is surfaced for diagnostics. |
| **deprecated** | The stage existed in a prior plugin version but is no longer in the current registry. The recorded entry is preserved as history but no longer drives any execution. | `entry.stage_id ∉ current_registry`. The status file keeps the entry indefinitely (or until a manual prune); the check script ignores it for diff-computation purposes. |

Plus two **transient SKILL-only states** (set by the SKILL
mid-execution; treated as effectively `never-run` /
`stale` by the lifecycle model on next session):

- **`failed`** — stage executor returned non-zero; SKILL
  records `last_error` for diagnostic. Re-attempted next
  session.
- **`pending-architect-input`** — agentic stage waiting for
  architect to respond (e.g., DSN prompt unanswered, optional
  block confirmation pending). Re-surfaced on next session.

### Why three layers, not just hash

A pure-hash model loses the diff-explainability that
`structured target_state` provides. A pure-structured-diff
model wastes hook cycles re-computing structural equality.
The three-layer stack mirrors what production systems do:

- **K8s `metadata.generation` vs `observedGeneration`** —
  fast-path integer compare; structural deep-equal only on
  mismatch.
- **Terraform `serial` + JSON state** — same pattern
  applied to IaC.
- **Pulumi stack checkpoints** — same.
- **Nix derivation hash** — pure-hash, but only because Nix
  is immutable build (no need to diff "what changed in
  production"). Bootstrap stages are stateful, so Nix's
  model doesn't transfer.

The hook stays cheap because layer 1 (generation int compare)
absorbs most "stage hasn't changed" cases; layer 2 (hash)
catches developer-forgot-to-bump bugs; layer 3 (structured
diff) is invoked only by SKILL when re-running and is where
architects see human-readable "what changed."

### Schema-migration seam

**Per-stage `target_state` evolution is the schema-migration
seam.** When module M4 changes its DDL, M4's stage registry
entries bump their `generation` AND get a new derived hash;
M4's recorded entries flip to `stale`; SKILL structural-diffs
the old vs new target_state ("audit_log table needs column
`event_uuid`") and runs M4's stages re-runs which apply the
new target_state. *Module-local schema migration* — no
central migration runner needed (per architect direction;
resolves the M10 question).

**Canonicalization invariant**: hash is computed from a
canonical YAML emit (sorted keys, fixed indentation,
trailing newline normalized). Non-canonical YAML serialization
is forbidden in the executor — see § "Stage registry
contract" for the canonicalization contract. Fields excluded
from hash (timestamps, last_run_id, schema_version itself)
live in an explicit allowlist.

## Cross-version evolution

Cross-version evolution is mechanically implied by the 4-state
lifecycle model above:

- **Adding a new stage** in plugin version `N+1`: the new
  stage_id is absent from `state.yml`'s entries → check script
  reads it as `never-run` on next session start → triggers
  execution. No explicit "upgrade" action required.
- **Changing a stage's behavior** in plugin version `N+1`: the
  stage's `target_state_hash_fn` returns a different value →
  recorded entries flip to `stale` → check script re-runs.
  This is the single mechanism for what F-B3/F-B4 used to
  describe as "version transition."
- **Removing a stage** in plugin version `N+1`: the stage_id
  no longer appears in the current registry → recorded entries
  flip to `deprecated` → no further execution. State file
  preserves history; reverse-migration is not supported in
  v1 (architect downgrade requires manual cleanup).
- **Breaking changes** (e.g., a stage rename, a behavior
  change that cannot be expressed as a hash bump alone) still
  require a new ADR + deprecation window per existing
  [`../0005-contracts/03-config-schemas.md`](../0005-contracts/03-config-schemas.md)
  § "Migration policy". The 4-state model handles
  versioned-and-additive evolution; breaking changes are
  out of band.

The deferred `migrating-repo-version` skill is fully absorbed:
"migration" is just "running the diff that the lifecycle model
identifies." There is no separate migration code path.

## Architect UX

The architect's interaction with bootstrap is the **interactive
configuration surface** for the plugin: every architect-facing
decision the plugin needs to record (audit DSN scheme, autonomy
override presets, WIP limit, kanban backend, future new
features' configuration items) is mediated by an **agentic
stage** in the registry. There is no separate "settings" UX —
agentic stages *are* the settings UX. This section formalizes
the protocol so future plugin versions can add new
configuration items by registry-only edits, without writing
bespoke prompt code per item.

### The reframe: agentic stage = config-item elicitation flow

A bootstrap stage's `character: agentic` means exactly: this
stage requires architect input to compute its `target_state`.
From the architect's vantage point that input is "make a
configuration choice"; from the plugin runtime's vantage point
it is "fill in this stage's `target_state` so the lifecycle
flips to `completed`". The two perspectives are the same
operation, the same persistence, the same lifecycle. Skip
semantics evaporate — an empty / null / "no presets selected"
choice is itself a valid `target_state` and produces
`completed`. The lifecycle's 4 states (never-run / completed /
stale / deprecated) cover all observable architect states; no
fifth "skipped" or "deferred" state is introduced.

### Sequential per-stage flow (decision: B)

The SKILL handles agentic stages **one at a time**, not in a
batch wizard. Flow:

1. Hook emits `INVOKE: bootstrapping-repo + REASON: <N> stages
   need running` (per § "Trigger model").
2. SKILL is woken. Reads partitioned settings files; recomputes
   lifecycle diff; topologically orders pending stages by
   `depends_on`.
3. SKILL iterates pending stages in topological order:
   - For `automated` stages: invokes the stage's `executor`
     via `Bash` tool autonomously; no architect attention.
     Records completion in the appropriate settings file.
   - For `agentic` stages: renders the stage's
     `interactive_prompt` to the architect using the prompt
     kind (single-choice / multi-choice / free-text /
     boolean / numeric-range); waits for response; validates
     against the stage's `target_state_schema`; persists
     `target_state` into the settings file; marks completed.
   - For `agentic` stages where the architect is unreachable
     (CI, scripted environment): SKILL records
     `status: pending-architect-input` and the stage stays
     pending until next session.
4. SKILL emits final summary: "N stages completed; M skipped
   due to depends_on chain breakage (dependencies unmet); K
   pending-architect-input."

The sequential model means architects who interrupt mid-flow
return to a partial state next session — pending stages that
weren't reached pick up from where they left off; completed
stages stay completed. There is no "wizard restart"; the
lifecycle model is the resume primitive.

### Config item protocol — the five required elements

Every config item that the plugin elicits from the architect
is encoded as an agentic stage that satisfies all five of the
following protocol elements. New plugin features that need
architect input add a registry entry that fills in all five;
no bespoke prompt code is written per item.

| Element | What it is | Where it lives | Reuses |
|---------|-----------|----------------|--------|
| **1. Schema declaration** | The stage's `target_state_schema` declares the shape of the architect's choice. Examples: `{wip_limit: int (1..20)}`; `{kanban_backend: enum [github-project-v2, linear, jira]}`; `{presets_chosen: list of enum [allow-pr-creation, ...]}`. Plus required-or-optional, default value, enum option list (with `introduced_in_version` per option for graceful enum-bump compat). | Stage registry entry's `target_state_schema` field (per ADR-0014). | ADR-0014 stage registry contract; ADR-0014 JSON Schema validation gate. |
| **2. Detection** | "Has this config item already been set?" The lifecycle 4-state model answers this purely from local settings files. `never-run` / `stale` ⇒ needs eliciting; `completed` ⇒ already set; `deprecated` ⇒ ignore. | Lifecycle compute function (per ADR-0013) reads stage entries from settings files. | ADR-0013 4-state lifecycle + three-layer fingerprint. |
| **3. Interaction** | How the agent prompts the architect. The stage registry's new `interactive_prompt` field declares the prompt template + kind (`single-choice` / `multi-choice` / `free-text` / `boolean` / `numeric-range`) + options-source (literal list, or computed-from-`target_state_schema.enum`, or runtime-derived). SKILL's prompt-renderer is generic — given an `interactive_prompt` declaration it generates the architect-facing question without per-stage code. | Stage registry entry's new `interactive_prompt` field. SKILL `prompt-renderer.py` is the single implementation. | The `interactive_prompt` field is added to the registry contract per this section. |
| **4. Persistence** | "Where does the choice land on disk?" The stage's `locality` (Axis B) decides which settings file. `host-shared` → `~/.board-superpowers/settings.yml`; `repo-shared` → `~/.board-superpowers/repos/<id>/settings.yml`; `repo-git` → `<repo>/.board-superpowers/settings.yml`; `repo-clone` → `<repo>/.board-superpowers/settings.local.yml`. | Stage registry entry's `locality` field; SKILL writes the resolved settings file with atomic mktemp+mv. | Axis B locality semantics; § "Declarative state schema" partitioned files. |
| **5. Re-prompt trigger** | When does the plugin ask again? Three triggers, all derived from the lifecycle: (a) plugin upgrade bumps the stage's `generation` int (e.g., new enum option added) → flips to `stale` → re-prompts; (b) architect manually edits the settings file in a way that no longer matches `target_state_schema` → load-time validation rejects, stage flips to `stale`; (c) architect explicitly invokes `scripts/bsp-stage-rerun.sh <stage_id>` → forces stage to `never-run`. | Lifecycle stale-detection rule + SKILL's response to stale entries. | ADR-0013 lifecycle; no new mechanism. |

### Future-feature inclusion procedure

When a future plugin version (vN+1) introduces a new feature
that needs architect input:

1. Author the new agentic stage's registry entry in
   `scripts/stages-registry.yml`, filling all five protocol
   elements (`target_state_schema`, `interactive_prompt`,
   `locality`, `generation`, `introduced_in_version`).
2. Author the per-stage Python helpers in
   `scripts/stages_lib/<stage_id>.py` (per ADR-0014 naming
   convention) implementing `compute_target_state`,
   `idempotency_check`, `target_state_predicate`, `executor`.
3. Bump the SKILL test fixture (a settings file fixture +
   expected `target_state` after architect responds) so the
   prompt-renderer + persistence path is regression-tested.
4. **No SKILL code changes are required.** The
   prompt-renderer reads the new stage's `interactive_prompt`
   declaration and renders the question generically.

This is the architectural contract the design relies on:
**adding a config item is a registry edit + Python helpers,
not a SKILL feature**. Failing to honor this constraint
produces SKILL prompt-code drift across config items and
re-introduces the per-feature bespoke-UX cost the redesign
exists to eliminate.

### Settings file naming

Per decision: existing plumbing files are renamed to a
unified `settings.yml` family (one per non-`external`
locality). See § "Declarative state schema" for the rename
table and the in-file structure (each `settings.yml` carries
`schema_version` + `plugin_version` + `stages_completed[]` +
optional human-readable `config_items` projection).

### Failure surfaces (architect-facing)

- **Automated stage failure** (executor non-zero exit):
  SKILL records `status: failed` + `last_error` in the
  appropriate settings file. Lifecycle treats `failed` as
  effectively `never-run` for the next session. SKILL surfaces
  a brief failure summary at end of current session: "stage X
  failed: <one-line>; will retry next session". After 3
  consecutive failed runs, SKILL emits a special
  `INVOKE: bootstrapping-repo / REASON: stage X needs
  troubleshooting` marker on next hook tick to escalate.
- **Agentic stage abandoned** (architect leaves session
  without responding): SKILL records
  `status: pending-architect-input` so the next session's
  hook re-emits the marker.
- **Registry validation failure** (settings file violates
  `target_state_schema`): hook detects via load-time JSON
  Schema; emits a special marker
  `INVOKE: bootstrapping-repo / REASON: settings.yml
  validation failed for <stage_id>`; SKILL guides the
  architect to inspect / repair / re-elicit.

## Open design choices

Resolved (as discussion progresses, decisions move down to the
"Decided" subsection below; this list narrows over time).

### Still open

- **Concurrency on `repo-shared` status writes** — the
  redesign relies on per-status-file `flock` (per § "Trigger
  model" failure-modes table); confirm `flock` semantics
  (advisory vs mandatory) work identically on macOS / Linux
  for both CC and Codex hooks. May require an explicit ADR
  pinning the implementation choice (`flock(2)` vs
  `fcntl(F_SETLK)` vs file-based atomic-rename lock).
- **M7 optional-block content list** — protocol + 4 KiB /
  8 KiB size caps decided. Concrete optional blocks: zero
  in v0.4.0+redesign; each future optional block addition
  is a registry edit, not a SKILL change. Open until first
  optional block is proposed.
- **External-stage TTL per-stage overrides** — default
  86400 (24h) decided. Per-stage override mechanism still
  open: registry field
  (`external_ttl_seconds: 3600` per stage) vs runtime
  override via `config.yml`. I lean registry-field-only
  for simplicity; flagging for confirmation.
- **Hash-allowlist enforcement at CI** — canonicalization
  + hash-stability is critical (Agent 1 flagged
  non-deterministic field ordering as well-known edge
  case). Need a CI test that round-trips
  `compute_target_state()` outputs and asserts hash
  stability. Open: should the test live in
  `tests/test-stages-canonical-hash.sh` (general) or
  per-stage in `stages_lib/<id>_test.py`?

### Decided (by this draft)

- **Pre-v1 breaking changes are accepted** — board-superpowers
  has not had a formal release yet; existing local state on
  architect machines may be deleted on upgrade. This unlocks:
  (a) M4 host-shared → per-repo `credentials.yml` migration
  needs no copy-or-prompt logic — the architect deletes
  `~/.board-superpowers/credentials.yml` + `~/.board-superpowers/repos/<old-id>/state.yml`
  and re-bootstraps; (b) local-only repo → GitHub-origin
  identity transition needs no auto-migration stage — the
  architect deletes the `_path-<...>/` directory once and
  the next session creates fresh state under `<owner>-<repo>/`.
  Replacement plan items reflect this (no migration ADR
  required for either).
- **M8 (autonomy overrides) is in-scope** — adds one stage
  (`m8.host.bootstrap-overrides-yml`, agentic + confirm-only,
  host-shared) that prompts the architect with a small set of
  curated autonomy-override presets at first run. Architect
  may select any subset, including "no presets, skip" (writes
  empty `overrides.yml` and marks completed). Plugin upgrade
  with new presets bumps the stage's `target_state`, flipping
  the entry to `stale` and re-prompting on next session.
- **Trigger model is hook-minimal (α)** — hook reads
  partitioned status, runs lifecycle diff, emits marker; SKILL
  is the single executor for all stages. Resolved by § "Trigger
  model".
- **Status storage is partitioned by locality, unified under
  the `settings.yml` family** — four files (`settings.yml`
  per locality + `settings.local.yml` for `repo-clone`), one
  per non-`external` locality; `external` stages cache TTL'd
  validation in `repo-shared`'s settings file. Pre-v1 breaking
  rename of v0.4.0 plumbing names (manifest.yml / state.yml /
  config.yml / config.local.yml). Resolved by § "Declarative
  state schema".
- **Architect UX uses sequential per-stage flow with config
  item protocol (decision: B)** — SKILL processes pending
  agentic stages one at a time in topological order; no batch
  wizard. Every architect-facing decision is mediated by an
  agentic stage that satisfies the five-element config item
  protocol (schema declaration / detection / interaction /
  persistence / re-prompt trigger). Resolved by § "Architect
  UX".
- **Skip semantics are eliminated** — an empty / null / "no
  presets selected" choice is itself a valid `target_state`
  and produces `completed`. The 4-state lifecycle (never-run
  / completed / stale / deprecated) covers all observable
  architect states; no fifth "skipped" / "deferred" state is
  introduced. Resolved by § "Architect UX" reframe.
- **M10 (BoardAdapter selection) is in-scope** — new module
  with stage `m10.repo.choose-kanban-backend` (agentic,
  repo-git, single-choice for v0.5.0 enum
  `[github-project-v2]`; future Linear / Jira options land via
  registry-only enum extension). M3's GitHub-Project-specific
  stages depend on `m10.repo.choose-kanban-backend`, so non-GH
  backends will skip M3 cleanly when their stages land. Per
  ADR-0005's BoardAdapter contract.
- **M5 stage `m5.repo.set-wip-limit` is in-scope** — new
  agentic stage prompting architect for per-repo WIP limit
  (default 5; numeric-range 1-20). Persists into
  `settings.local.yml:wip_limit` per repo-clone locality.
- **Repo identity is `<owner>-<repo>` from `origin` URL** —
  with `_path-...` fallback for local-only repos. Resolved by
  § "Repo identity". Triggers I-13 invariant revision.
- **Cross-clone state sharing (I-13 revised)** — same
  `(host, GitHub repo)` pair, regardless of clone path,
  shares one host-local state directory. Triggers ADR.
- **Axis B is 5 values, not 4** — `host-shared`,
  `repo-shared`, `repo-git`, `repo-clone`, `external`. The
  cross-clone vs per-clone distinction inside per-repo is the
  fifth value's reason. Resolved by § "Axis B — Locality".
- **Single migration runner is rejected** (M10 candidate
  removed) — each module owns its schema migration via its
  stages' `compute_target_state()` + `target_state_hash`.
  Resolved by § "Stage lifecycle states" + § "Cross-version
  evolution".
- **Stage lifecycle uses K8s-style three-layer fingerprint**
  — `generation` integer (cheap fast-path, registry-bumped) +
  derived `target_state_hash` (canonical YAML emit + sha256,
  catches forgotten generation bumps) + structured
  `target_state` (ground truth, fuels SKILL's structural diff
  for human-readable migration messages). Verified against
  K8s `metadata.generation` / Terraform `serial` / Pulumi
  stack-checkpoint patterns. Pure-hash rejected (Nix-style,
  doesn't transfer to stateful resources). Pure-structured
  rejected (no fast-path).
- **Stage registry storage is YAML metadata + Python helpers
  + JSON Schema validation** — `scripts/stages-registry.yml`
  for declarative metadata; `scripts/stages_lib/<stage_id>.py`
  for callables; `scripts/stages-registry.schema.json` for
  load-time validation. Verified against industry pattern
  (Tekton CRDs, Helm Chart.yaml, npm package.json,
  Cargo.toml). Pure-Python decorator registry rejected
  because it would force bash hooks to shell out to Python
  for stage enumeration, breaking hook-cheap invariant.
- **M7 honors Codex 32 KiB AGENTS.md budget** — single
  block ≤ 4 KiB; total M7 inject + sub-dir AGENTS.md
  contributions ≤ 8 KiB on AGENTS.md (≥ 24 KiB headroom for
  architect content). `m7.repo.detect-agentsmd-form` measures
  total size after Codex's root-to-cwd concat-walk and
  refuses to inject if budget would be exceeded.
- **M7 architecture is per-block multi-stage with prerequisite
  form-detect** — `m7.repo.detect-agentsmd-form` is a
  prerequisite stage that caches the repo's routing-target
  form (`cc-only` / `codex-only` / `dual` / `neither`) in
  repo-shared `state.yml`; downstream
  `m7.repo.inject-block.<name>` stages depend on it and
  inherit `form` into their `target_state`, so any change
  to the repo's routing-target file structure flips every
  M7 inject stage to `stale` and triggers full re-injection.
- **Per-repo audit DB defaults to zero-config SQLite** at
  `~/.board-superpowers/repos/<repo-identity>/audit.db`. No
  prompt at first bootstrap. Architects pick PG/MySQL by
  editing per-repo `credentials.yml` post-bootstrap. First-run
  bootstrap prints a one-line note pointing at the override
  path. WAL mode default; spec already forbids audit.db inside
  project tree (07-path-conventions.md).
- **M9 (hook registration) is in-scope** — Codex-only stage
  with `platforms: [codex]`. Resolved by G4.
- **M4 audit module is per-repo, not host-shared** — including
  `credentials.yml`. Triggers `0005-contracts/03-config-schemas.md`
  + `07-path-conventions.md` updates in the replacement PR.
- **M7 routing-block protocol is multi-block with required /
  optional kinds** — required auto-injected, optional
  agent-confirmed before injection. Per-block versioning +
  hash + marker pair.
- **Stage lifecycle is a 4-state model** (never-run /
  completed / stale / deprecated). Three-layer fingerprint
  comparison: `generation` int → `target_state_hash` →
  `target_state` structural diff. Plus two transient states
  (`failed`, `pending-architect-input`) the SKILL writes
  mid-flow. See above "K8s-style three-layer fingerprint".
- **M3 Status field validation uses TTL caching** in
  `repo-shared`'s `state.yml`, not every-session re-check.
  Default TTL 24h per § "Declarative state schema" external
  cache.
- **Heavy-automated has no special hook treatment** — α model
  retired the γ "hook runs light, SKILL runs heavy" split;
  `heavy` flag is now informational (UX progress surfacing)
  rather than execution-routing.

## Replacement plan (when this draft is approved)

1. Companion ADRs recorded under
   [`../adr/`](../adr/) — one each for: (a) unified check-script
   trigger model (absorbing `migrating-repo-version`); (b)
   declarative state schema + 4-state lifecycle + K8s-style
   three-layer fingerprint (generation + hash + structured
   target_state); (c) stage registry contract (YAML metadata +
   Python helpers + JSON Schema validation); (d) M4 audit
   per-repo locality (replaces host-shared `credentials.yml`
   semantics — pre-v1 breaking change, no in-place migration
   logic); (e) G4 cross-platform parity contract (modeling
   platform-asymmetric stages explicitly via `platforms`
   field); (f) I-13 invariant revision (cross-clone state
   sharing via GitHub-based identity); (g) M7 multi-stage
   per-block protocol with form-detect prerequisite + Codex
   32 KiB AGENTS.md budget enforcement; (h) per-repo zero-config
   SQLite as default audit backend. Decisions immutable once
   accepted.
2. Spec change-impact matrix in
   [`../AGENTS.md`](../AGENTS.md) § "Spec change-impact
   matrix" walked top-to-bottom — every row that cites
   `05-bootstrap-surface.md` or `~/.board-superpowers/`
   path layout updated in the same PR as the replacement.
3. `0005-contracts/03-config-schemas.md` schemas bumped
   (additive fields only) — adds `stages_completed[]` to
   `state.yml` + `manifest.yml`; relocates `credentials.yml`
   from host-shared to per-repo per M4 decision.
   `07-path-conventions.md` updated for the new
   `credentials.yml` location and (if changed) the repo
   identity scheme.
4. Skill catalog ([`../../SKILLS.md`](../../../SKILLS.md))
   updated — `migrating-repo-version` removed (absorbed);
   `bootstrapping-repo` description narrows to "agentic-only
   stages + first-run guidance"; entries audited for any
   stage that gains a `platforms: [codex]` constraint.
5. Hook contract ([`../0005-contracts/02-hook-contracts.md`](../0005-contracts/02-hook-contracts.md))
   updated with the unified check-script protocol — including
   how the hook surfaces `never-run` / `stale` lifecycle states
   (likely as `INVOKE: bootstrap-check / REASON:` markers, but
   exact grammar follows trigger-model decision).
6. Pre-v1 breaking-change procedure documented — release notes
   instruct architects to delete
   `~/.board-superpowers/credentials.yml` (host-shared) +
   any `~/.board-superpowers/repos/_path-<...>/` directories
   (path-based fallback) and re-run bootstrap. No in-place
   migration logic ships.
7. M7 routing-block tooling refactored — `bsp_inject_routing_block`
   helper extended to per-block injection with `kind` flag;
   `agentsmd-routing.md` template restructured into N labeled
   blocks with required/optional metadata each. M7 stage list
   expands per § "M7 routing-block protocol" (one stage per
   block + one form-detect stage).
8. M9 codex-hook stage added — `register-codex-hooks.sh`
   becomes the executor for the M9 stage; the README's
   manual-instruction section deletes (replaced by automatic
   bootstrap behavior).
9. M8 overrides-bootstrap stage added —
   `m8.host.bootstrap-overrides-yml` becomes a first-run
   guided agentic stage with curated presets list (presets
   list itself defined in registry).
10. M5 WIP-limit stage added — `m5.repo.set-wip-limit`
    becomes an agentic stage persisting into
    `settings.local.yml:wip_limit` (default 5; numeric-range
    1-20).
11. M10 BoardAdapter-selection module + stage added —
    `m10.repo.choose-kanban-backend` (agentic, repo-git);
    M3 stages gain `depends_on:
    [m10.repo.choose-kanban-backend]`. Future Linear / Jira
    enum options land via registry-only edits.
12. Settings.yml rename — v0.4.0 plumbing names
    (`manifest.yml`, `state.yml`, `config.yml`,
    `config.local.yml`, host-shared `overrides.yml`)
    rename to the unified `settings.yml` family per
    § "Declarative state schema" → "Four settings files".
    Pre-v1 breaking change; architects delete legacy files
    on upgrade.
13. Architect UX section formalized — § "Architect UX"
    encodes the sequential per-stage flow + the five-element
    config item protocol that future plugin features must
    honor when adding new architect-input items.
14. Companion ADRs land in the same series (extends ADR-0012..0019
    to also cover): (i) Architect UX + config item protocol
    (the five-element contract); (j) settings.yml rename;
    (k) M10 BoardAdapter selection module + M5 wip-limit
    stage (these may be one or two ADRs depending on cohesion
    judgement at write time).
15. This `-redesign.md` file removed; content lives in
    `05-bootstrap-surface.md`.
