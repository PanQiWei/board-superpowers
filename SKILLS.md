# Skills system — board-superpowers v1 catalog (14 skills total, all shipped, 3 layers)

> **Always loaded.** This document is referenced from
> [`AGENTS.md`](./AGENTS.md) via `@SKILLS.md` and rides into
> every CC / Codex session as part of the project's standing
> context. It is the **source of truth for the skills system
> topology** — what skills exist, what each one does, and how
> they compose.
>
> **Pair with [`SKILL_DEVELOPMENT.md`](./SKILL_DEVELOPMENT.md)**
> — that file is the generic "how to write a skill" manual; this
> file is the specific "what skills we have" catalog.
>
> **Per-skill `layer`, `type`, `mode`, `bounded-context` are
> authoritative in `<skill-dir>/.skill-meta.yaml`** (see
> [`SKILL_DEVELOPMENT.md`](./SKILL_DEVELOPMENT.md) § "
> board-superpowers metadata convention"). This catalog focuses
> on prose-level role / triggers / dependencies and does NOT
> duplicate the yaml fields. CI gate
> `scripts/verify-skill-metadata.sh` enforces consistency
> between the two.

## Source-of-truth contract

Any change under `skills/` (new skill, removed skill, renamed
skill, changed `description`, changed cross-plugin references,
changed reference-file structure) **MUST** be paired with —
land in the same PR as — an edit to this document.

The reverse also holds: an edit to this document without the
matching `skills/` change makes the spec drift. Both halves
land together.

The skills system has three layers, fourteen skills, and a fixed set
of cross-plugin edges. None of these numbers should change
without an explicit decision recorded here first.

See § "Maintenance contract" at the bottom for the per-action
procedures (add / remove / rename / re-layer / re-edge).

## Three-layer architecture

```
Entry ──(routes to)──> Molecular ──(reads from)──> Atomic
   ▲                       │                          │
   └─── strict downward dependency direction ────────┘

   Atomic skills are reflexes — they MUST NOT call any
   same-plugin skill. Calling upward forms cycles and
   defeats the SPOT (single-point-of-truth) purpose.
```

| Layer | Role | Stability | Body-length budget | How it loads |
|-------|------|-----------|--------------------|--------------|
| **Entry** | First touch. Router only — never does real work itself. | Low (changes when routing scenarios appear). | ≤ 200 lines (loaded every session). | Auto-matched on user prompt + hook-injected `INVOKE: <skill>` markers. |
| **Molecular** | Business workflows. State-machine-shaped. Composes atomic primitives + cross-plugin skills. | Medium. | 250-450 lines. | Auto-matched on triggering scenarios. |
| **Atomic** | Single-purpose reflexes. Reused by multiple molecular skills. No business binding. | High (rarely changes once stable). | 200-300 lines. | Loaded on demand via `Skill` tool from molecular bodies. |

### Three checks for layer assignment

When introducing a new skill, run these in order:

1. **Does it route or does it work?** Body mostly says "based
   on X, invoke skill Y" → **entry**. If it has a procedure of
   its own → not entry.
2. **Does it have business / domain semantics?** Only makes
   sense inside one workflow family (managing the board,
   consuming a card, bootstrapping the repo) → **molecular**.
3. **Does it depend on no other same-plugin skill?** Yes →
   **atomic**.

A skill spanning two layers MUST be split. Layer-mixing is the
single most common authoring mistake (per
[`SKILL_DEVELOPMENT.md`](./SKILL_DEVELOPMENT.md) Anti-pattern
A9).

### Atomic-layer boundary discipline (v0.5.0+)

Two atomic skills can BOTH be valid even when they appear to
cover "the same domain" — provided they consolidate **different
SPOTs**. Mixing two SPOTs into one atomic violates atomic single
responsibility (A9) even when the resulting skill stays under
the body-length budget.

The canonical example, applied first to v0.5.0's
`board-canon` + `operating-kanban` pair (the new atomic landed
in v0.5.0):

| Atomic | SPOT it consolidates | One-line discriminator |
|--------|----------------------|------------------------|
| `board-canon` | "Kanban is what" — ontology, schema rules, state machine, branch-naming convention, WIP formula. **Backend-agnostic.** Stable; rarely changes. | If the question is *"what is legal / what does X mean"*, route to `board-canon`. |
| `operating-kanban` (shipped v0.5.0) | "How to act on the active backend" — backend selection (reads `<repo>/.board-superpowers/settings.yml § modules.m10_kanban`), per-backend action invocation (Form A / B / C projections), failure-mode dispatch, and bootstrap-side setup-capability registry. **Backend-aware.** Mutates as new projections land. | If the question is *"how do I do X on this repo's backend"*, route to `operating-kanban`. |

**Boundary discriminator (one sentence)**: *if the new content
is "what is legal," it belongs in `board-canon`; if it is "in a
specific backend, here is how you make the action happen," it
belongs in `operating-kanban`.*

This discipline rules out a tempting but harmful merge: "kanban-
related rules and operations could co-exist in one skill." That
would couple a backend-agnostic SPOT (which rarely changes) to a
backend-specific SPOT (which changes per projection landing),
forcing every projection landing to re-review the stable
ontology. See ADR-0025 § Decision for the protocol-vs-SDK
rationale that motivates the split.

## v1 minimum vs v1 complete

The v1 catalog defines **14 skills**. As of `v0.7.0`
(post-#72-merge), **all 14 ship** — enough to make the plugin
self-hostable on this very repo AND to bootstrap a fresh
consuming repo from zero AND to govern every mutating action
through classifying-actions + auditing-actions AND to decompose
design artifacts into INVEST-compliant vertically-sliced cards
via decomposing-into-milestones AND to dispatch the eight Kanban
Protocol actions through the active projection via
operating-kanban AND to consolidate the single source of truth
for sibling-plugin invocation discipline via composing-siblings
AND to run each Producer routine as a dedicated SKILL
(briefing-daily / intaking-requirement / reviewing-pr-queue /
triaging-board, replacing the retired managing-board mega-SKILL).
The `migrating-repo-version` molecular SKILL that v0.5.0 carried
as deferred has been **absorbed into `bootstrapping-repo`** per
[ADR-0012](./docs/architecture/adr/0012-unified-check-script-trigger-model.md)
(single sole-executor for setup-stages, including version-
transition migrations). No separate migration SKILL ships.

| Skill | Layer | v1 status | Why this scoping |
|-------|-------|-----------|-------------------|
| `using-board-superpowers` | Entry | **v1-minimum** | Required for routing every session into the right role. |
| `briefing-daily` | Molecular | **v1-complete** (shipped v0.7.0) | Producer daily-briefing routine — board read, WIP flagging, stale-claim detection, recommended-next-action. |
| `intaking-requirement` | Molecular | **v1-complete** (shipped v0.7.0) | Producer intake routine — acknowledge, shape-judge, spec-first check, route / create card. Replaces the intake workflow of the retired `managing-board` skill. |
| `reviewing-pr-queue` | Molecular | **v1-complete** (shipped v0.7.0) | Producer review-queue routine — list open PRs, validate via enforcing-pr-contract, comment, transition cards, summarize. |
| `triaging-board` | Molecular | **v1-complete** (shipped v0.7.0) | Producer triage routine — Blocked scan with 3-class blocker remediation, stale-claim detection and release. |
| `consuming-card` | Molecular | **v1-minimum** | Consumer surface — required for the F-C0..F-C14 lifecycle that delivers each card's PR. |
| `decomposing-into-milestones` | Molecular | **v1-complete** (shipped v0.4.0) | F-09 + §1.6 INVEST + vertical-slicing + card schema + size calibration engine. Lands alongside the schema-drift double-collapse (board-canon ↔ spec § 1.6.3) so the converged terminal Card body schema becomes architecturally authoritative. |
| `bootstrapping-repo` | Molecular | **v1-minimum** (shipped in v0.2.0; rebased v0.6.0) | Sole executor for setup-stages (per [ADR-0012](./docs/architecture/adr/0012-unified-check-script-trigger-model.md), [ADR-0023](./docs/architecture/adr/0023-architect-ux-and-config-item-protocol.md), [ADR-0024](./docs/architecture/adr/0024-settings-rename-and-config-item-stages.md), [ADR-0027](./docs/architecture/adr/0027-board-projection-routes-through-operating-kanban.md)) — first-time setup, plugin-upgrade reconvergence (absorbs the formerly deferred `migrating-repo-version` scope), and agentic config-item elicitation. The entry-skill state probe routes here on first session and on every subsequent session that surfaces a never-run / stale stage. |
| `board-canon` | Atomic | **v1-minimum** | True SPOT — every other v1-minimum skill consumes its state machine + schema + WIP rules. |
| `enforcing-pr-contract` | Atomic | **v1-minimum** | True SPOT — Consumer's F-C12 PR submit + Manager's F-02 Review Queue both depend on it. |
| `operating-kanban` | Atomic | shipped (v0.5.0) | True SPOT shipped in v0.5.0 — every molecular SKILL routes the eight Kanban Protocol actions (per ADR-0025) and the bootstrap-side setup capabilities (per ADR-0027) through this skill's per-projection reference files. |
| `classifying-actions` | Atomic | shipped (v0.3.0) | True SPOT shipped in v0.3.0 — every mutating SKILL consumes its D-AUTONOMY-1 matrix (14 Producer + 14 Consumer + 9 Bootstrap rows) + 5-step triage rule + autonomy_overrides parsing. |
| `auditing-actions` | Atomic | shipped (v0.3.0) | True SPOT shipped in v0.3.0 — every mutating SKILL invokes audit-log-write.sh through this skill's payload templates and propose/resolve sequencing rules. |
| `composing-siblings` | Atomic | shipped (v0.6.0) | True SPOT shipped in v0.6.0 — every molecular SKILL that delegates to `gstack:*` or `superpowers:*` consults this skill for invocation rules, procedural-vs-subagent decision, and Mode-2 max_depth=1 compatibility. |

**Cross-platform hook delivery**: `hooks/session-start.sh` is
identical on both platforms (uses `bsp_plugin_root()` from
`scripts/lib/common.sh` to resolve paths cross-platform).
Registration differs: Claude Code auto-discovers
`hooks/hooks.json`; Codex CLI requires running
`scripts/register-codex-hooks.sh --install-user` (or
`--install-repo`) once after plugin install. See
[`PLUGIN_DEVELOPMENT.md`](./PLUGIN_DEVELOPMENT.md) § "What this
means for board-superpowers" #3 for the full rationale.

## Skill catalog

> Per-skill `layer`, `type`, `mode`, `bounded-context` live in
> `<skill-dir>/.skill-meta.yaml`. The catalog below tags each
> skill name as `(shipped vX)` for every skill in the catalog —
> all 14 ship as of v0.7.0 (post-#72-merge). Tier 2 frontmatter
> recommendations are listed for every skill.

### Entry layer (1 skill)

#### `using-board-superpowers` (v1-minimum)

- **Role**: Manual page + first-touch router. Loaded every
  session; provides full plugin orientation inline (14-skill
  catalog, 6-state Card lifecycle, 5 bounded contexts,
  on-disk state, routing tree) AND routes ambiguous sessions
  or hook-injected `INVOKE:` markers to the right molecular
  skill. Answers "what is this plugin / how does this work /
  what skills exist / explain the architecture" inline.
- **Body target**: Entry-layer 200-line baseline intentionally
  exceeded (currently ~225 lines) to support the manual-page
  double duty — agents in community consumer projects must
  one-shot-ingest the routing context (14-skill catalog,
  6-state lifecycle, 5 bounded contexts, on-disk state,
  routing tree), so progressive disclosure cannot replace
  inline content here. Keep additions justified by the same
  one-shot-disclosure principle; spillover prose belongs in
  `references/`.
- **Triggers (`description` / `when_to_use` WHEN)**:
  `[board-card:#N]`, "set up board-superpowers",
  "what should I work on", "claim card N", "morning briefing",
  "new requirement", "weekly retro",
  "what is this plugin", "how does this work",
  "what skills exist", "explain the architecture",
  `INVOKE:` marker injected by `SessionStart`.
- **Composes (downstream)**: every molecular skill below
  (routing target).
- **Tier 2 frontmatter**: `when_to_use` (extended trigger
  vocabulary outside the primary `description`).

### Molecular layer (7 skills, all shipped)

#### `briefing-daily` (v1-complete, shipped v0.7.0)

- **Role**: Producer daily-briefing routine. Reads the board,
  groups cards by Status, highlights WIP situations and stale
  claims, recommends ONE next action. Covers journey nodes
  A1 (board overview) + A2 (ordered PR queue) + A3 ("what's
  blocking me") + A4 (context-switch reload re-entry) + A5
  (today's dispatch recommendation).
- **Body target**: 250-400 lines (molecular budget).
- **References folder**:
  `references/daily-detail.md` — empty-board case, single-
  Consumer projects, stale-claim age computation, hot-card
  formatting, tone.
- **Composes (atomic)**: `board-canon` (WIP counting formula),
  `board-superpowers:operating-kanban` (`read_board` protocol
  action — board state grouped by Status),
  `board-superpowers:composing-siblings` (sibling-plugin
  invocation rules if delegation is needed),
  `board-superpowers:classifying-actions` +
  `board-superpowers:auditing-actions` (every mutating action;
  read-only routine marker recorded directly via auditing-actions).
- **Composes (cross-plugin)**: none typical (daily is read-only).
- **Triggers**: "morning briefing" / "what should I work on" /
  "today's plan" / "board overview" / "what's running".
- **Tier 2 frontmatter**: `when_to_use` (extended trigger
  vocabulary).

#### `intaking-requirement` (v1-complete, shipped v0.7.0)

- **Role**: Producer intake routine. Acknowledges the incoming
  requirement, runs the 4-step shape judgment → spec-first
  check → skill routing → card creation pipeline. Covers
  journey nodes B1 (design conversation routing) + B3 (single-
  card fast-path) + G4 (design discipline gate: intake →
  decompose bridge cannot be skipped).
- **Body target**: 250-420 lines (molecular budget).
- **References folder**:
  `references/{intake-decision-tree,scope-shape-judgment,spec-first-checklist}.md`
  — the intake-routing trio that encodes shape + spec-first +
  sibling-routing judgments. Anchored to four primary sources
  (Cohn 2005 Planning Onion / Patton 2014 Story Map /
  Cockburn 2004 Walking Skeleton / Denne 2003 MMF/MMR).
- **Composes (atomic)**: `board-canon` (Card body schema for
  direct card creation), `board-superpowers:operating-kanban`
  (`create_card` protocol action), `board-superpowers:composing-siblings`
  (B1 design-conversation routing to `gstack:/*` /
  `superpowers:*` sibling skills),
  `board-superpowers:classifying-actions` +
  `board-superpowers:auditing-actions` (every mutating action).
- **Composes (cross-plugin)**: `gstack:/office-hours`,
  `gstack:/plan-ceo-review`, `gstack:/plan-eng-review`,
  `superpowers:brainstorming` (pre-card design routing),
  `superpowers:writing-plans` (plan synthesis); routes to
  `board-superpowers:decomposing-into-milestones` for multi-card
  requirements.
- **Triggers**: "new requirement" / "intake this idea" / "I have
  a feature" / "add a card" / "new card".
- **Tier 2 frontmatter**: `when_to_use` (extended trigger
  vocabulary for intake scenarios).

#### `reviewing-pr-queue` (v1-complete, shipped v0.7.0)

- **Role**: Producer review-queue routine. Lists open PRs linked
  to cards, validates each against the three-section PR contract,
  comments on violations, transitions non-compliant cards back to
  `In Progress`, summarizes the queue. Covers journey nodes C1
  (review PR) + C2 (return to In Progress, nested in C1).
- **Body target**: 250-380 lines (molecular budget).
- **References folder**:
  `references/review-queue-detail.md` — merge-conflict handling,
  multi-card PRs, Producer self-review, approve-vs-request-changes
  boundary, PR opened against non-claim branch edge cases.
- **Composes (atomic)**: `board-canon` (state machine for Status
  transition validity), `board-superpowers:operating-kanban`
  (`transition_card` protocol action — Status flip to `In Progress`
  on contract violation), `board-superpowers:enforcing-pr-contract`
  (Contract A PR body shape + Contract B AC terminal-state + Contract
  C auto-close keyword validation),
  `board-superpowers:composing-siblings` (invocation rules),
  `board-superpowers:classifying-actions` +
  `board-superpowers:auditing-actions` (every mutating action).
- **Composes (cross-plugin)**: none (review-queue is
  board-superpowers-internal).
- **Triggers**: "review the PRs" / "what's in In Review" / "merge
  ready" / "check the review queue" / "PR queue".
- **Tier 2 frontmatter**: `when_to_use` (extended trigger
  vocabulary for review-queue scenarios).

#### `triaging-board` (v1-complete, shipped v0.7.0)

- **Role**: Producer triage routine. Scans Blocked cards (3-class
  blocker remediation: external-dependency / decision-pending /
  stale-block) and stale claim branches (>72h flag; >7 days
  release recommendation). Covers journey nodes C4 (unblock blocked
  card) + C5 (cancel stale claim).
- **Body target**: 250-350 lines (molecular budget).
- **References folder**:
  `references/triage-detail.md` — blocker classification,
  stale-claim release procedure, suspended-card review schedule,
  what triage does NOT cover.
- **Composes (atomic)**: `board-canon` (state machine — Blocked
  status semantics), `board-superpowers:operating-kanban`
  (`read_board` with status filter `Blocked`, `release_claim`
  for stale-claim cancellation, `transition_card` for
  Blocked → In Progress unblock),
  `board-superpowers:composing-siblings` (invocation rules),
  `board-superpowers:classifying-actions` +
  `board-superpowers:auditing-actions` (every mutating action).
- **Composes (cross-plugin)**: none typical (triage is
  board-superpowers-internal).
- **Triggers**: "what's blocked" / "triage the board" / "release
  stale claims" / "check blockers" / "stale claims".
- **Tier 2 frontmatter**: `when_to_use` (extended trigger
  vocabulary for triage scenarios).

#### `consuming-card` (v1-minimum)

- **Role**: Consumer session main skill. Full F-C0..F-C14
  lifecycle from
  [`docs/architecture/0002-product-features-and-flows/04-consumer-surface.md`](./docs/architecture/0002-product-features-and-flows/04-consumer-surface.md).
  Consumer subactions span action_id 100-113 (100-111 review
  cycle + 112 PR-submit pre-flight card body sync + 113
  post-merge cleanup).
- **Body target**: ≤ 300 lines (current 229).
- **References folder**:
  `references/{handoff-to-superpowers,pr-template,surface-protocol,permission-boundary}.md`.
- **Composes (atomic)**: `board-canon`,
  `board-superpowers:operating-kanban` (`read_card` Step 2,
  `claim_card` Step 3, `transition_card` Step 6,
  `link_pr_to_card` Step 10 — protocol-action dispatch over
  the active projection),
  `board-superpowers:enforcing-pr-contract` (Step 9.5
  card body sync + Step 10 PR submit; action_ids 112 and 113
  also audit via this path),
  `board-superpowers:classifying-actions` +
  `board-superpowers:auditing-actions` (every
  mutating action, action_ids 100-113).
- **Composes (cross-plugin)**: see § "Cross-plugin edges" below.
- **Constraint**: under Mode-2 it runs as a CC subagent —
  `max_depth=1` means it CANNOT spawn further subagents; every
  cross-plugin invocation MUST be procedural (per ADR-0008).
  Mode-2 is CC-only at v1; Mode-1 (architect-spawned) is both.
- **Tier 2 frontmatter**: `when_to_use` (claim card / work on
  card N / `[board-card:#N]`) +
  `argument-hint: "[card-number]"` +
  `arguments: [card_number]` (body uses `$card_number` with
  `$ARGUMENTS` fallback for Codex).

#### `decomposing-into-milestones` (v1-complete, shipped v0.4.0)

- **Role**: F-09 + §1.6 (INVEST + vertical slicing + card
  schema + sizing) engine. Turns design artifact into Ready
  cards on the board. Skeleton A — Discipline (per
  `SKILL_DEVELOPMENT.md` § "SKILL.md body structure") because
  INVEST and vertical-slicing are *refusal conditions* (Wake
  2003 wording), not procedure steps.
- **Body target**: 280-320 lines (current 277 — Iron Law +
  8-step Process + Common Rationalizations + Red Flags +
  Verification Checklist + Failure modes + Examples).
- **References folder**:
  `references/{card-schema,decomposition-patterns,invest-checklist,size-calibration}.md`
  — primary-source-grounded (Wake 2003 INVEST, Cohn SPIDR,
  Reinertsen Little's Law, Fowler StoryCounting); AI-orchestration
  reframes explicitly labeled "original framing" per memory
  `feedback_research_canonical_practice_first`.
- **Composes (atomic)**: `board-canon` (terminal Card body schema
  authority), `operating-kanban` (`create_card` + `transition_card`
  protocol action dispatch), `classifying-actions`, `auditing-actions`.
- **Composes (cross-plugin)**: see § "Cross-plugin edges" below.
- **Tier 2 frontmatter**: `when_to_use` (extended trigger
  vocabulary covering "decompose / 拆 / split / break this into
  cards / intake 后落卡") + `argument-hint:
  "[design-artifact-path | design-artifact-dir | -]"` +
  `arguments: [artifact_path]` (Step 1 dispatches by argument
  type — file / dir / freeform stdin).

#### `bootstrapping-repo` (v1-minimum, shipped v0.2.0; rebased v0.6.0)

- **Role**: Sole executor for setup-stages — automated + agentic
  per [ADR-0012](./docs/architecture/adr/0012-unified-check-script-trigger-model.md)
  (absorbs `migrating-repo-version`'s old scope — version-
  transition migrations are now expressed as `generation:` bumps
  within stage callables) + [ADR-0023](./docs/architecture/adr/0023-architect-ux-and-config-item-protocol.md)
  (5-element config item protocol) + [ADR-0024](./docs/architecture/adr/0024-settings-rename-and-config-item-stages.md)
  (settings.yml family). Drives the sequential per-stage flow
  defined in design doc § "Architect UX". Board reads route
  through `board-superpowers:operating-kanban` actions per
  [ADR-0027](./docs/architecture/adr/0027-board-projection-routes-through-operating-kanban.md)
  (paired with #68's atomic SKILL ship).
- **Body target**: 250-450 lines (molecular budget).
- **References folder**: `references/{intro,first-time-user-guide,stage-execution-flow,config-item-protocol,architect-ux-failure-surfaces}.md`
  + `references/changelog/v0.2.0.md`. (`stage-execution-flow` /
  `config-item-protocol` / `architect-ux-failure-surfaces` land
  in Phase 2 alongside the SKILL body rebase.)
- **Spec authority list**: ADR-0012, ADR-0013, ADR-0014,
  ADR-0021, ADR-0023, ADR-0024, ADR-0027.
- **Composes (atomic)**: `board-canon` (read schema invariants for
  Status validation), `classifying-actions` + `auditing-actions`
  (every mutating action).
- **Composes (cross-plugin)**: none (bootstrap is
  board-superpowers-internal).
- **Trigger model**: `INVOKE: bootstrapping-repo` marker injected
  by the `SessionStart` hook when `manifest.yml` or per-repo
  `state.yml` is absent (fast path), OR architect explicitly says
  "set up board-superpowers" / "first time on this repo" /
  "bootstrap this repo" (fallback path). Per the hook intent
  injection pattern in [`docs/architecture/0004-component-architecture.md`](./docs/architecture/0004-component-architecture.md)
  § "Hook intent injection pattern".
- **Tier 2 frontmatter**: `when_to_use` (extended trigger
  vocabulary covering the architect-spoken fallback phrases plus
  the entry-skill state-probe trigger).

### Atomic layer (6 skills, all shipped)

#### `board-canon` (v1-minimum)

- **Role**: Pure read-only contract — 6-state machine + Card
  body schema (thin-pointer + 5 sections + bottom marker +
  display-only metadata fields per ADR-0026) + branch naming
  (v0.5.0+ canonical `claim/<kanban-id>-<key-slug>-<title-slug>`;
  v0.4.x legacy `claim/<key-slug>-<title-slug>` accepted by
  parser) + WIP counting formula (`In Progress + suspended +
  In Review`; `Blocked` excluded).
- **Body target**: 200-300 lines.
- **References folder**:
  `references/{state-machine,card-body-schema,claim-protocol,wip-counting,branch-naming}.md`.
- **Called by**: every molecular skill (all 7 of them —
  `briefing-daily`, `intaking-requirement`, `reviewing-pr-queue`,
  `triaging-board`, `consuming-card`,
  `decomposing-into-milestones`, `bootstrapping-repo`).
- **Calls**: nothing. Atomic = reflexive.
- **Tier 2 frontmatter**: `user-invocable: false` (atomic
  reflex, never user-driven directly).

#### `enforcing-pr-contract` (v1-minimum)

- **Role**: Two-contract enforcement — **Contract A** (PR body
  three-section shape: `## Automated Verification` required,
  `## Human Verification TODO` optional but must not be filler,
  `## Retro Notes` required when reusable lessons exist) +
  **Contract B** (card body acceptance-criteria sync: every AC
  must be `[x]` or `[!]` with a reason at PR-submit time;
  bare `[ ]` is forbidden). Provides injection templates for
  the Consumer (Step 10 PR submit) and validation rules for
  the Producer (F-02 Review Queue). Both contracts are checked
  by `scripts/submit-pr.sh` and by the Producer's review-queue
  routine.
- **Body target**: ≤ 200 lines (current 151).
- **References folder**:
  `references/{section-templates,validation-rules,filler-detection}.md`.
- **Called by**: `consuming-card` (Step 9.5 card body sync +
  Step 10 PR submit), `reviewing-pr-queue` (contract-violation
  flagging for each open PR in the review queue).
- **Calls**: nothing.
- **SPOT consolidates**: Contract A (PR three-section shape)
  and Contract B (AC terminal-state rule) would otherwise be
  inlined separately in both Consumer and Producer skills —
  this skill is the single source of truth for both.
- **Tier 2 frontmatter**: `user-invocable: false` (atomic
  reflex, never user-driven directly).

#### `operating-kanban` (v1-complete, shipped v0.5.0)

- **Role**: Backend-projection dispatch SPOT — owns "how to act
  on the active backend" for the eight Kanban Protocol actions
  (`read_board`, `read_card`, `create_card`, `transition_card`,
  `claim_card`, `release_claim`, `link_pr_to_card`,
  `comment_on_card` OPTIONAL). Reads `<repo>/.board-superpowers/
  settings.yml § modules.m10_kanban` to resolve the active
  projection per kanban id, loads the per-projection reference
  file under its own `references/` directory, and dispatches per
  Form A (bash CLI) / Form B (plugin-shipped MCP server) / Form C
  (REST/GraphQL). Also owns the bootstrap-side setup-capability
  registry that M3 stage predicates (per ADR-0027) consume.
- **Body target**: 200-300 lines (atomic budget).
- **References folder**:
  `references/{action-dispatch,backend-selection,form-a-bash,form-b-mcp,form-c-rest,failure-mode-dispatch,github-project-v2}.md`
  + future per-projection reference files (`linear.md` /
  `jira.md` ship with their projections).
- **Called by**: every molecular skill that touches the board
  (`briefing-daily`, `intaking-requirement`, `reviewing-pr-queue`,
  `triaging-board`, `consuming-card`, `decomposing-into-milestones`,
  `bootstrapping-repo` — the bootstrap-side setup-capability
  dispatch).
- **Calls**: nothing in-plugin. Atomic = reflexive. Externally,
  invokes the active projection (bash `gh` / MCP tool / REST
  endpoint) per the projection's reference file.
- **SPOT consolidates**: backend-routing logic (which projection
  is active + how each protocol action maps to a backend
  invocation) would otherwise be inlined into 4+ molecular
  callers. Distinct from `board-canon`'s SPOT per the
  Atomic-layer boundary discipline above: `board-canon` owns
  "what is legal" (backend-agnostic), `operating-kanban` owns
  "how to act" (backend-aware).
- **Tier 2 frontmatter**: `user-invocable: false` (atomic
  reflex, never user-driven directly).

#### `classifying-actions` (v1-complete, shipped v0.3.0)

- **Role**: D-AUTONOMY-1 14-row Producer matrix + Consumer
  subaction catalog (`action_id` 100-113: 100-111 review-cycle
  actions, 112 PR-submit pre-flight card body sync, 113
  post-merge cleanup) + Bootstrap subaction catalog (`action_id`
  200-208: host manifest write + per-repo bootstrap sub-steps
  2a-2g + step 4 routing-block injection) + 5-step triage rule +
  `autonomy_overrides:` parsing (project + user layers via
  `bsp_resolve_autonomy_class`). The caller hands in an
  action_id; this skill returns the A / R / N decision.
- **Body target**: ≤ 200 lines (frequently-loaded atomic; current 81).
- **References folder**:
  `references/{matrix,triage-rule,override-parsing,action-id-catalog}.md`.
- **Called by**: every mutating skill (all 7 molecular —
  `briefing-daily`, `intaking-requirement`, `reviewing-pr-queue`,
  `triaging-board`, `consuming-card`,
  `decomposing-into-milestones`, `bootstrapping-repo`).
- **Calls**: nothing.
- **SPOT consolidates**: ADR-0006 matrix would otherwise be
  inlined 4 times — Producer 14 rows + Consumer 14 rows +
  Bootstrap 9 rows = 37 rows × 4 callers = 148 lines of
  duplicated rule encoding drifting independently.
- **Tier 2 frontmatter**: `user-invocable: false` (atomic
  reflex, never user-driven directly).

#### `auditing-actions` (v1-complete, shipped v0.3.0)

- **Role**: Audit log schema (8 columns + 4 enum sets) + R-class
  two-entry rule (propose + resolve) + BYO RDBMS write
  conventions + degradation mode (when DB unavailable, A-class
  degrades to R-class with jsonl fallback, explicit mode-field
  enum).
- **Body target**: ≤ 200 lines (frequently-loaded atomic; current 84).
- **References folder**:
  `references/{schema,two-entry-rule,db-write-conventions,degradation-mode}.md`.
- **Called by**: every mutating skill (all 7 molecular) — invoked
  immediately after `classifying-actions` returns A or R.
- **Calls**: external RDBMS via
  `${CLAUDE_PLUGIN_ROOT}/scripts/audit-log-write.sh`.
- **SPOT consolidates**: ADR-0006 §5 schema would otherwise be
  inlined 4 times.
- **Tier 2 frontmatter**: `user-invocable: false` (atomic
  reflex, never user-driven directly).

#### `composing-siblings` (shipped v0.6.0)

- **Role**: Sibling-plugin invocation discipline SPOT — owns
  "how to invoke `gstack:*` / `superpowers:*` skills correctly"
  across all 9 molecular handoff points. Consolidates: (a) the
  invocation rules (SKILL invocation = content-loading, NOT
  subagent spawn, per ADR-0008); (b) Mode-2 `max_depth=1`
  compatibility check — procedural-vs-subagent decision tree
  for every currently-composed sibling skill; (c) per-phase
  skill routing (gstack bookends + superpowers middle per
  ADR-0004); (d) `<plugin>:<skill>` namespace prefix rule
  (cross-platform, prevents bare-reference ambiguity). See
  `references/handoff-points.md` for the 9 caller × scenario
  table; `references/sibling-plugin-table.md` for the current
  sibling-skill quick-reference; `references/procedural-fallback-rules.md`
  for the Mode-2 decision tree; `references/boundary.md` for
  the atomic reflex constraint.
- **Body target**: ≤ 200 lines (atomic budget).
- **References folder**:
  `references/{handoff-points,sibling-plugin-table,procedural-fallback-rules,boundary}.md`.
- **Called by**: every molecular skill that delegates to sibling
  plugins — `intaking-requirement` (B1 design-conversation routing
  to `gstack:/*` / `superpowers:*`), `consuming-card` (F-C4
  implement, F-C9 verify, F-C11 conditional QA/security),
  `decomposing-into-milestones` (plan synthesis + arch
  validation handoff). All four Producer routine SKILLs carry
  the `composing-siblings` invocation declaration; only
  `intaking-requirement` and `reviewing-pr-queue` typically
  invoke sibling plugins, but all four declare the dependency
  for consistency and future-proofing.
- **Calls**: nothing in-plugin. Atomic = reflexive.
- **SPOT consolidates**: sibling-plugin invocation rules and
  Mode-2 compatibility decision would otherwise be inlined into
  3+ molecular callers (4 Producer routine SKILLs + 5 Consumer
  lifecycle handoff points = 9 inline copies drifting
  independently).
- **Tier 2 frontmatter**: `user-invocable: false` (atomic
  reflex, never user-driven directly).

## Call graph

```
                         ┌──────────────────────────────┐
                         │   using-board-superpowers    │  ENTRY
                         │ (router + dep gate + INVOKE) │
                         └─┬──┬──┬──┬──┬──┬──┬─────────┘
                           │  │  │  │  │  │  │
      ┌────────────────────┘  │  │  │  │  │  └──────────────────────────────┐
      │  ┌────────────────────┘  │  │  │  └──────────────────┐              │
      │  │  ┌────────────────────┘  │  └──────────┐          │              │
      │  │  │  ┌────────────────────┘             │          │              │
      ▼  ▼  ▼  ▼  (Molecular — 7 skills)          ▼          ▼              ▼
  ┌────────┐┌──────┐┌────────┐┌───────┐  ┌──────────┐┌──────────┐  ┌──────────────┐
  │briefing││intak-││review- ││triag- │  │consum-   ││decompos- │  │bootstrapping-│
  │-daily  ││ing-  ││ing-pr- ││ing-   │  │ing-card  ││ing-into- │  │repo          │
  │        ││reqt  ││queue   ││board  │  │          ││milestone │  │              │
  └──┬─────┘└──┬───┘└───┬────┘└──┬────┘  └──┬────┬──┘└──┬───┬──┘  └──┬───────────┘
     │         │         │        │           │    │       │    │        │
     │    ┌────┼─────────┼────────┼──────────┬┘    │       └────┼────────┼──┐
     │    │    │         │        │           │  (sibling-plugin handoff)    │
     │    │    └─────────┼────────┼───────────┴─────────────────┤            │
     │    │              │        │                              ▼            │
     └────┼──────────────┼────────┼─────────────────────┌──────────────┐    │
          │              │        │                      │composing-    │    │
          └──────────────┴────────┴─────────────────��───►siblings      │    │
                                                         └──────────────┘    │
          │                                                                   │
          └──────────────────────────────────────────────────────────────────┘
          (all 7 molecular → atomics below)

   ┌────────────┐ ┌──────────────────┐ ┌──────────────┐ ┌──────────────────┐ ┌──────────────────┐
   │ board-canon│ │enforcing-pr-     │ │ operating-   │ │classifying-      │ │ auditing-actions │
   │ (read-only │ │   contract       │ │   kanban     │ │   actions        │ │ (audit schema +  │
   │   schema)  │ │ (PR 三段式)      │ │ (8-action    │ │ (D-AUTONOMY-1 +  │ │   DB 写入约定)   │
   │            │ │                  │ │  dispatch)   │ │  override 解析)  │ │                  │
   └────────────┘ └──────────────────┘ └──────────────┘ └──────────────────┘ └──────────────────┘
   (Atomic — 反射弧 — 6 skills, all called by relevant molecular skills above)
                                                               │
                                                               └─── after A/R decision ───┐
                                                                                           ▼
                                                                (mutating skill MUST also call auditing-actions)
```

## SPOT derivation — why exactly 6 atomic skills (unchanged by molecular split)

The atomic-layer count is not preference; it's the result of a
SPOT (single-point-of-truth) census. Any contract that
**multiple** molecular skills would inline-copy is a SPOT
candidate that MUST be promoted to atomic. v1 census:

| Contract | Without atomic, inlined by | Atomic that consolidates |
|----------|---------------------------|--------------------------|
| State machine + Card schema + branch naming + WIP rules | All 7 molecular | `board-canon` |
| PR three-section shape + filler detection | `consuming-card` (write) + `reviewing-pr-queue` (validate) | `enforcing-pr-contract` |
| 8-action protocol dispatch + projection routing + setup-capability registry | All 7 board-touching molecular (`briefing-daily`, `intaking-requirement`, `reviewing-pr-queue`, `triaging-board`, `consuming-card`, `decomposing-into-milestones`, `bootstrapping-repo`) | `operating-kanban` |
| D-AUTONOMY-1 matrix + override parsing | All 7 mutating molecular | `classifying-actions` |
| Audit log schema + two-entry rule | All 7 mutating molecular | `auditing-actions` |
| How to invoke sibling-plugin discipline (`gstack:*` / `superpowers:*`) + Mode-2 max_depth=1 compatibility + `<plugin>:<skill>` namespace prefix rule | All 4 Producer routine SKILLs + `consuming-card` + `decomposing-into-milestones` — 6 molecular callers with handoff points across the routines | `composing-siblings` |

Contracts that would NOT meet the SPOT threshold (only 1
molecular inlines) stay inline:

- Daily briefing format / stale-claim detection mechanics →
  only `briefing-daily` (`references/daily-detail.md`).
- Intake decision tree + scope-shape judgment + spec-first
  checklist → only `intaking-requirement` (`references/`).
- Review-queue contract details (merge conflict, self-review,
  multi-card PR, non-claim branch edge cases) → only
  `reviewing-pr-queue` (`references/review-queue-detail.md`).
- Triage blocker classification + release procedure → only
  `triaging-board` (`references/triage-detail.md`).
- F-C0 manual-pull selection → only `consuming-card`.
- §1.5.0 dep-check details → `bootstrapping-repo` and
  `using-board-superpowers` (a single reference file inside
  `bootstrapping-repo/references/` is hybrid-edge-referenced
  by both — does not need its own atomic skill).

## Bounded-context → skill mapping

Per
[`docs/architecture/0003-domain-model/02-bounded-contexts.md`](./docs/architecture/0003-domain-model/02-bounded-contexts.md):

| Bounded context | Owns / reads | Skill(s) acting on it |
|-----------------|--------------|------------------------|
| **Board** | Card + PR aggregates; GitHub Project + Issues + git refs | `briefing-daily` (R board state), `intaking-requirement` (W new cards via `create_card`), `reviewing-pr-queue` (R + W card Status via `transition_card`), `triaging-board` (R Blocked + W release via `release_claim`), `consuming-card` (R + W own card), `decomposing-into-milestones` (W new cards), `bootstrapping-repo` (R Status field), `board-canon` (schema authority), `operating-kanban` (per-projection dispatch authority) |
| **Session** | ProducerSession + ConsumerLogical aggregates; OS processes + worktrees | `briefing-daily` (R board state for daily orientation), `intaking-requirement` (Producer intake lifecycle), `reviewing-pr-queue` (Producer review-queue lifecycle), `triaging-board` (Producer triage lifecycle), `consuming-card` (own session), `composing-siblings` (read-only invocation rules for sibling-plugin handoffs in both roles) |
| **Bootstrap** | HostBootstrap + RepoBootstrap + RepoConfig | `bootstrapping-repo` (R + W — sole executor for first-time setup AND plugin-upgrade reconvergence per ADR-0012), `using-board-superpowers` (R for state checks) |
| **Audit** | AuditTrail aggregate; BYO RDBMS | `auditing-actions` (W via DB script) |
| **Spec** | SpecPointer (thin) | `consuming-card` (R via thin pointer in F-C2) |

## Cross-plugin edges

board-superpowers composes — never reimplements — sibling-plugin
disciplines (per P4b in
[`docs/architecture/0001-positioning.md`](./docs/architecture/0001-positioning.md)
and ADR-0004). All cross-plugin invocations carry the
`<plugin>:<skill>` namespace prefix and use SKILL invocation
(per ADR-0008 — in-process content loading, NOT subagent
spawn).

| From | To | Use |
|------|-----|-----|
| `intaking-requirement` (B1 design conversation routing) | `gstack:/office-hours`, `/plan-ceo-review`, `/plan-eng-review`, `superpowers:brainstorming` | Pre-card design conversation routing |
| `intaking-requirement` (decomposition handoff) | `superpowers:writing-plans` | Spec → executable plan |
| `decomposing-into-milestones` | `superpowers:writing-plans`, `gstack:/plan-eng-review` | Plan synthesis + arch validation |
| `consuming-card` (F-C4 implement) | `superpowers:subagent-driven-development` (TBD) → `superpowers:executing-plans` (Mode-2 fallback), `test-driven-development`, `systematic-debugging`; `gstack:/investigate` | TDD-driven implementation |
| `consuming-card` (F-C9 verify) | `superpowers:verification-before-completion`, `requesting-code-review`; `gstack:/review` | Pre-PR verification chain |
| `consuming-card` (F-C10 cross-platform) | `gstack:/codex` (CC → Codex direction) | Adversarial review on a different platform |
| `consuming-card` (F-C11 conditional) | `gstack:/qa` (UI cards), `/cso` (security-flagged cards) | Conditional QA / security passes |

**TBD entries** require empirical verification per ADR-0008 — if
a sibling skill spawns its own subagents, it cannot be invoked
from a Mode-2 `consuming-card` (`max_depth=1` budget). The
fallback table lives in
`consuming-card/references/handoff-to-superpowers.md`.

## Maintenance contract

Every change touching `skills/` MUST be paired with a change to
this document, in the same PR. Specific procedures:

### Adding a skill

1. Decide its layer using the three checks in § "Three-layer
   architecture". Justify in the PR body.
2. Add a section to § "Skill catalog" with the eight required
   fields (Role / Bounded context / Type / Body target /
   References / Composes atomic / Composes cross-plugin / Mode).
3. Update § "Call graph" — add the new node and its edges.
4. If the new skill is **atomic**, update § "SPOT derivation"
   — explain what SPOT it consolidates (which inline-copy
   contracts it absorbs).
5. Update § "Bounded-context → skill mapping" if it touches a
   new context.
6. Update § "Cross-plugin edges" if it composes a sibling
   plugin.
7. Bump the count in `# header` (`(N skills)` → `(N+1)`) and
   in the appropriate layer subhead (`(M skills)` → `(M+1)`).
8. Then write `skills/<name>/SKILL.md` against this updated
   topology.

### Removing a skill

1. Verify nothing depends on it:
   `grep -r 'board-superpowers:<name>' skills/ docs/architecture/`.
   Any caller MUST be updated in the same PR.
2. Remove its section from § "Skill catalog".
3. Remove its node and edges from § "Call graph".
4. If atomic, demote the SPOT it consolidated — either the
   inline-copy returns (if there is now only one caller), or
   the consolidation moves into a different atomic.
5. Update § "Bounded-context → skill mapping".
6. Update § "Cross-plugin edges" if applicable.
7. Decrement counts in `# header` and the layer subhead.
8. Then `git rm -r skills/<name>/`.

### Renaming a skill

1. Update the section header in § "Skill catalog".
2. Update § "Call graph" labels.
3. Update § "Cross-plugin edges" if listed there.
4. `grep -r '<old-name>' skills/ docs/architecture/` and update
   every mention in the same PR.
5. Then `git mv skills/<old-name> skills/<new-name>`.

### Changing a skill's `description` frontmatter

Every change MUST come with adjacent skills' descriptions
re-read for routing overlap (per `SKILL_DEVELOPMENT.md`
"description = WHEN, not WHAT"). If the description trigger
phrases change, also update:

- The relevant § "Triggers" line in this document's catalog.
- The user-facing trigger phrases in `README.md` /
  `README.zh-CN.md` if they appear there.

### Changing layer assignment (atomic ↔ molecular, etc.)

Treat as remove + add — the skill's responsibilities shift,
the SPOT census may change, the call graph re-shapes. PR body
MUST narrate the layer-change rationale.

### Changing call-graph edges (atomic dependencies)

Atomic skills MUST NOT call same-plugin skills (reflexive
constraint). If a change appears to require an atomic calling
another atomic, the design has gone wrong — split / merge the
atomics instead of introducing the upward call.

### Adding a cross-plugin edge

1. Verify the sibling skill is **procedural** under ADR-0008
   (does its body invoke `Agent` tool / `spawn_agents_on_csv`?).
   If TBD, mark TBD in the new edge row.
2. Add the row to § "Cross-plugin edges".
3. If the new edge is from `consuming-card` and the sibling is
   non-procedural, also add a procedural fallback entry to
   `consuming-card/references/handoff-to-superpowers.md`
   (Mode-2 compatibility per ADR-0008).
