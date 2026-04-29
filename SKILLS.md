# Skills system — board-superpowers v1 catalog (10 skills total: 9 shipped + 1 deferred to v1-complete, 3 layers)

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

The skills system has three layers, ten skills, and a fixed set
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
`board-canon` + `operating-kanban` pair (which lands when the
new atomic ships):

| Atomic | SPOT it consolidates | One-line discriminator |
|--------|----------------------|------------------------|
| `board-canon` | "Kanban is what" — ontology, schema rules, state machine, branch-naming convention, WIP formula. **Backend-agnostic.** Stable; rarely changes. | If the question is *"what is legal / what does X mean"*, route to `board-canon`. |
| `operating-kanban` *(lands v0.5.0)* | "How to act on the active backend" — backend selection (reads `<repo>/.board-superpowers/config.yml § kanban`), per-backend action invocation (Form A / B / C projections), failure-mode dispatch. **Backend-aware.** Mutates as new projections land. | If the question is *"how do I do X on this repo's backend"*, route to `operating-kanban`. |

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

The full v1 catalog defines **10 skills**. As of `v0.4.0`,
**9 skills ship** — enough to make the plugin self-hostable on
this very repo AND to bootstrap a fresh consuming repo from zero
AND to govern every mutating action through classifying-actions +
auditing-actions AND to decompose design artifacts into
INVEST-compliant vertically-sliced cards via decomposing-into-milestones.
The remaining **1 is deferred to v1-complete** and ships in a
follow-up PR once unblocked.

| Skill | Layer | v1 status | Why this scoping |
|-------|-------|-----------|-------------------|
| `using-board-superpowers` | Entry | **v1-minimum** | Required for routing every session into the right role. |
| `managing-board` | Molecular | **v1-minimum** | Producer surface — required for "what should I work on" / Review Queue / intake on this repo. v1 ships F-01 + F-02 + F-08 only; F-03..F-07 + F-10..F-15 deferred to v1.x per ADR-0011 (pending demand pull). |
| `consuming-card` | Molecular | **v1-minimum** | Consumer surface — required for the F-C0..F-C14 lifecycle that delivers each card's PR. |
| `decomposing-into-milestones` | Molecular | **v1-complete** (shipped v0.4.0) | F-09 + §1.6 INVEST + vertical-slicing + card schema + size calibration engine. Lands alongside the schema-drift double-collapse (board-canon ↔ spec § 1.6.3) so the converged terminal Card body schema becomes architecturally authoritative. |
| `bootstrapping-repo` | Molecular | **v1-minimum** (shipped in v0.2.0) | F-B1 (host bootstrap) + F-B2 (per-repo bootstrap, including step 4 routing-block injection) — the entry-skill state probe routes here on first session. |
| `migrating-repo-version` | Molecular | deferred to v1-complete | Migration becomes meaningful starting from v0.2.x → v0.3.x transitions; the v0.2.0 ship establishes the baseline. |
| `board-canon` | Atomic | **v1-minimum** | True SPOT — every other v1-minimum skill consumes its state machine + schema + WIP rules. |
| `enforcing-pr-contract` | Atomic | **v1-minimum** | True SPOT — Consumer's F-C12 PR submit + Manager's F-02 Review Queue both depend on it. |
| `classifying-actions` | Atomic | shipped (v0.3.0) | True SPOT shipped in v0.3.0 — every mutating SKILL consumes its D-AUTONOMY-1 matrix (14 Producer + 14 Consumer + 9 Bootstrap rows) + 5-step triage rule + autonomy_overrides parsing. |
| `auditing-actions` | Atomic | shipped (v0.3.0) | True SPOT shipped in v0.3.0 — every mutating SKILL invokes audit-log-write.sh through this skill's payload templates and propose/resolve sequencing rules. |

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
> skill name as `(shipped vX)` once it has landed, or
> `(deferred to v1-complete)` while still on the roadmap.
> Tier 2 frontmatter recommendations are listed for every
> shipped skill.

### Entry layer (1 skill)

#### `using-board-superpowers` (v1-minimum)

- **Role**: Manual page + first-touch router. Loaded every
  session; provides full plugin orientation inline (10-skill
  catalog, 6-state Card lifecycle, 5 bounded contexts,
  on-disk state, routing tree) AND routes ambiguous sessions
  or hook-injected `INVOKE:` markers to the right molecular
  skill. Answers "what is this plugin / how does this work /
  what skills exist / explain the architecture" inline.
- **Body target**: Entry-layer 200-line baseline intentionally
  exceeded (currently ~225 lines) to support the manual-page
  double duty — agents in community consumer projects must
  one-shot-ingest the routing context (10-skill catalog,
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
  (routing target). When the routing target is deferred to
  v1-complete, the entry skill responds with a friendly
  "not implemented in v1-minimum" pointer instead.
- **Tier 2 frontmatter**: `when_to_use` (extended trigger
  vocabulary outside the primary `description`).

### Molecular layer (5 skills: 4 shipped + 1 deferred)

#### `managing-board` (v1-minimum)

- **Role**: Producer session main skill. Carries F-01 (daily) +
  F-02 (review queue) + F-08 (intake) in v1-minimum;
  F-03..F-07 + F-10..F-15 land in v1-complete. Per
  [`docs/architecture/0002-product-features-and-flows/03-producer-surface.md`](./docs/architecture/0002-product-features-and-flows/03-producer-surface.md).
- **Body target**: 300-400 lines.
- **References folder**:
  `references/{daily,intake,review-queue,triage,scope-shape-judgment,spec-first-checklist,skill-routing}.md`
  (retro / weekly-report / harness / hygiene deferred to
  v1-complete). The intake-routing trio
  (`scope-shape-judgment` / `spec-first-checklist` /
  `skill-routing`) lands alongside the extended
  decision-tree in `intake.md`; together they encode the
  shape + spec-first + sibling-routing judgments at
  manager-mode intake. Anchored to four primary sources
  (Cohn 2005 Planning Onion / Patton 2014 Story Map /
  Cockburn 2004 Walking Skeleton / Denne 2003 MMF/MMR);
  `skill-routing.md` is the manager-mode mirror of
  `AGENTS.md` § "How to compose gstack and superpowers"
  (paired same-PR per the change-impact-matrix row in
  `docs/architecture/AGENTS.md`).
- **Composes (atomic)**: `board-canon`,
  `enforcing-pr-contract` (Review Queue contract-violation
  check), `classifying-actions` + `auditing-actions` (every
  mutating action).
- **Composes (cross-plugin)**: see § "Cross-plugin edges" below.
- **Tier 2 frontmatter**: `when_to_use` (intake / daily /
  review-queue / triage trigger phrases) +
  `argument-hint: "[routine]"` (autocomplete shows which
  routine the user wants to run).

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
  authority), `classifying-actions`, `auditing-actions`.
- **Composes (cross-plugin)**: see § "Cross-plugin edges" below.
- **Tier 2 frontmatter**: `when_to_use` (extended trigger
  vocabulary covering "decompose / 拆 / split / break this into
  cards / intake 后落卡") + `argument-hint:
  "[design-artifact-path | design-artifact-dir | -]"` +
  `arguments: [artifact_path]` (Step 1 dispatches by argument
  type — file / dir / freeform stdin).

#### `bootstrapping-repo` (v1-minimum, shipped v0.2.0)

- **Role**: F-B1 (host bootstrap) + F-B2 (per-repo bootstrap with
  7 sub-capabilities — standard labels, Status validation,
  `config.yml` write, `.gitignore` entry, BYO-RDBMS credential
  setup, per-repo venv via `uv`, audit DDL dispatch) + step 4
  routing-block injection into `AGENTS.md` +
  `CLAUDE.md` + initial host-local `state.yml` write. Drives
  `scripts/bootstrap-host.sh` and `scripts/bootstrap-project.sh`
  end-to-end and orchestrates the architect's first-session UX.
- **Body target**: 250-450 lines (molecular budget).
- **References folder**: `references/{intro,first-time-user-guide}.md`
  + `references/changelog/v0.2.0.md`.
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

#### `migrating-repo-version` (deferred to v1-complete)

- **Role**: F-B3 (host version transition) + F-B4 (per-repo
  version transition with schema migration, new-feature
  opt-out, routing-block re-injection with three-way prompt on
  user modification).
- **Body target**: 250-350 lines.
- **References folder**:
  `references/{changelog/v<X>.md,tamper-prompt,migration-runner}.md`.
- **Composes (atomic)**: `board-canon` (when a new version
  changes the state machine), `auditing-actions`.
- **Composes (cross-plugin)**: none.
- **Trigger model**: `INVOKE: migrating-repo-version` marker
  injected by `SessionStart` when
  `state.yml:last_seen_version_in_repo` ≠
  `plugin.json:version` (fast path), OR architect says
  "what's new in this version" (fallback path).

### Atomic layer (4 skills, all shipped)

#### `board-canon` (v1-minimum)

- **Role**: Pure read-only contract — 6-state machine + Card
  body schema (thin-pointer + 5 sections + bottom marker) +
  branch naming (`claim/<N>-<slug>`) + WIP counting formula
  (`In Progress + suspended + In Review`; `Blocked` excluded).
- **Body target**: 200-300 lines.
- **References folder**:
  `references/{state-machine,card-body-schema,claim-protocol,wip-counting,branch-naming}.md`.
- **Called by**: every molecular skill (5 of them in
  v1-complete; 2 of them in v1-minimum: `managing-board` +
  `consuming-card`).
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
  Step 10 PR submit), `managing-board` (F-02 Review Queue
  contract-violation flagging).
- **Calls**: nothing.
- **SPOT consolidates**: Contract A (PR three-section shape)
  and Contract B (AC terminal-state rule) would otherwise be
  inlined separately in both Consumer and Producer skills —
  this skill is the single source of truth for both.
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
- **Called by**: every mutating skill (5 of them).
- **Calls**: nothing.
- **SPOT consolidates**: ADR-0006 matrix would otherwise be
  inlined 5 times — Producer 14 rows + Consumer 14 rows +
  Bootstrap 9 rows = 37 rows × 5 callers = 185 lines of
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
- **Called by**: every mutating skill (5 of them) — invoked
  immediately after `classifying-actions` returns A or R.
- **Calls**: external RDBMS via
  `${CLAUDE_PLUGIN_ROOT}/scripts/audit-log-write.sh`.
- **SPOT consolidates**: ADR-0006 §5 schema would otherwise be
  inlined 5 times.
- **Tier 2 frontmatter**: `user-invocable: false` (atomic
  reflex, never user-driven directly).

## Call graph

```
                       ┌──────────────────────────────┐
                       │   using-board-superpowers    │  ENTRY
                       │ (router + dep gate + INVOKE) │
                       └─┬───────┬─────────┬────────┬─┘
                         │ routes│         │        │
            ┌────────────┘       │         │        └──────────────┐
            │                    │         │                       │
            │           ┌────────┼─────────┼────────┐              │
            ▼           ▼        ▼         ▼        ▼              ▼
      ┌─────────────┐ ┌──────┐ ┌──────┐ ┌──────────┐ ┌────────────────┐
      │ managing-   │ │consu-│ │decom-│ │bootstrap-│ │ migrating-     │
      │   board     │ │ ming-│ │posing│ │ ping-repo│ │  repo-version  │
      │ (Producer)  │ │ card │ │      │ │          │ │                │
      └──┬─────┬────┘ └─┬──┬─┘ └──┬───┘ └────┬─────┘ └────────┬───────┘
         │     │        │  │      │          │                │
         │     │  (cross-plugin: 见 § "Cross-plugin edges")    │
         │     │        │  │      │          │                │
   ┌─────┼─────┼────────┼──┼──────┼──────────┼────────────────┘
   │     │     │        │  │      │          │
   ▼     ▼     ▼        ▼  ▼      ▼          ▼            (Atomic — 反射弧)
   ┌────────────┐  ┌─────────────────┐  ┌──────────────────┐  ┌──────────────────┐
   │ board-canon│  │enforcing-pr-    │  │classifying-      │  │ auditing-actions │
   │ (read-only │  │   contract      │  │   actions        │  │ (audit schema +  │
   │   schema)  │  │ (PR 三段式)     │  │ (D-AUTONOMY-1 +  │  │   DB 写入约定)   │
   │            │  │                 │  │  override 解析)  │  │                  │
   └────────────┘  └─────────────────┘  └──────────────────┘  └──────────────────┘
                                                  │
                                                  └─── after A/R decision ───┐
                                                                              ▼
                                                       (mutating skill MUST also call auditing-actions)
```

## SPOT derivation — why exactly 4 atomic skills

The atomic-layer count is not preference; it's the result of a
SPOT (single-point-of-truth) census. Any contract that
**multiple** molecular skills would inline-copy is a SPOT
candidate that MUST be promoted to atomic. v1 census:

| Contract | Without atomic, inlined by | Atomic that consolidates |
|----------|---------------------------|--------------------------|
| State machine + Card schema + branch naming + WIP rules | All 5 molecular | `board-canon` |
| PR three-section shape + filler detection | `consuming-card` (write) + `managing-board` (validate) | `enforcing-pr-contract` |
| D-AUTONOMY-1 matrix + override parsing | All 5 mutating molecular | `classifying-actions` |
| Audit log schema + two-entry rule | All 5 mutating molecular | `auditing-actions` |

Contracts that would NOT meet the SPOT threshold (only 1
molecular inlines) stay inline:

- F-08 intake routing logic → only `managing-board`.
- F-15 kanban hygiene rules → only `managing-board`.
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
| **Board** | Card + PR aggregates; GitHub Project + Issues + git refs | `managing-board` (R), `consuming-card` (R + W own card), `decomposing-into-milestones` (W new cards), `bootstrapping-repo` (R Status field), `board-canon` (schema authority) |
| **Session** | ProducerSession + ConsumerLogical aggregates; OS processes + worktrees | `managing-board` (R lifecycle), `consuming-card` (own session) |
| **Bootstrap** | HostBootstrap + RepoBootstrap + RepoConfig | `bootstrapping-repo` (R + W), `migrating-repo-version` (R + W), `using-board-superpowers` (R for state checks) |
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
| `managing-board` (intake F-08) | `gstack:/office-hours`, `/plan-ceo-review`, `/plan-eng-review`, `superpowers:brainstorming` | Pre-card design conversation routing |
| `managing-board` (decomposition handoff) | `superpowers:writing-plans` | Spec → executable plan |
| `managing-board` (overnight batch F-07) | `superpowers:dispatching-parallel-agents` (TBD verification) | Mode-2 Consumer dispatch |
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
