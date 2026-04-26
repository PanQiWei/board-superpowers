# Skills system — board-superpowers v1 catalog (10 skills, 3 layers)

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

## Skill catalog

### Entry layer (1 skill)

#### `using-board-superpowers`

- **Role**: First touch. Runs the reliable dep gate, consumes
  any hook-injected `INVOKE: <skill>` marker, routes to the
  right molecular skill. Never does real work itself.
- **Bounded context**: spans all five (Board / Session /
  Bootstrap / Audit / Spec) but only as a router.
- **Type**: pattern.
- **Body target**: ≤ 200 lines.
- **Triggers (`description` WHEN)**: `[board-card:#N]`,
  "set up board-superpowers", "what should I work on",
  "claim card N", "morning briefing", "new requirement",
  "weekly retro", `INVOKE:` marker injected by `SessionStart`.
- **Composes (downstream)**: every molecular skill below
  (routing target).
- **Mode**: both (CC + Codex).

### Molecular layer (5 skills)

#### `managing-board`

- **Role**: Producer session main skill. Carries F-01..F-08 +
  F-10..F-15 from
  [`docs/architecture/0002-product-features-and-flows/03-producer-surface.md`](./docs/architecture/0002-product-features-and-flows/03-producer-surface.md).
- **Bounded context**: Board (read), Session (read), Audit
  (read for retro / weekly report).
- **Type**: pattern.
- **Body target**: 300-400 lines.
- **References folder**:
  `references/{daily,intake,review-queue,triage,retro,weekly-report,harness,hygiene}.md`.
- **Composes (atomic)**: `board-canon`, `enforcing-pr-contract`
  (Review Queue contract-violation check), `classifying-actions`,
  `auditing-actions`.
- **Composes (cross-plugin)**: see § "Cross-plugin edges" below.
- **Mode**: both.

#### `consuming-card`

- **Role**: Consumer session main skill. Full F-C0..F-C14
  lifecycle from
  [`docs/architecture/0002-product-features-and-flows/04-consumer-surface.md`](./docs/architecture/0002-product-features-and-flows/04-consumer-surface.md).
- **Bounded context**: Board (read + write own card), Session
  (own worktree + claim), Spec (fetch via thin pointer).
- **Type**: pattern.
- **Body target**: 350-450 lines.
- **References folder**:
  `references/{handoff-to-superpowers,pr-template,surface-protocol,permission-boundary}.md`.
- **Composes (atomic)**: `board-canon`,
  `enforcing-pr-contract` (F-C12 PR submit), `classifying-actions`
  (every mutating action), `auditing-actions`.
- **Composes (cross-plugin)**: see § "Cross-plugin edges" below.
- **Mode**: both. Mode-2 (Producer-spawned) is CC-only at v1;
  Mode-1 (architect-spawned) on both platforms.
- **Constraint**: under Mode-2 it runs as a CC subagent —
  `max_depth=1` means it CANNOT spawn further subagents; every
  cross-plugin invocation MUST be procedural (per ADR-0008).

#### `decomposing-into-milestones`

- **Role**: F-09 + §1.6 (INVEST + vertical slicing + card
  schema + sizing) engine. Turns design artifact into Ready
  cards on the board.
- **Bounded context**: Board (write).
- **Type**: pattern + reference.
- **Body target**: 300-400 lines.
- **References folder**:
  `references/{card-schema,decomposition-patterns,invest-checklist,size-calibration}.md`.
- **Composes (atomic)**: `board-canon` (schema authority),
  `classifying-actions` (decomposition is row 1 = A; re-split
  is row 3 = R), `auditing-actions`.
- **Composes (cross-plugin)**: see § "Cross-plugin edges" below.
- **Mode**: both.

#### `bootstrapping-repo`

- **Role**: §1.5.0 dep check + F-B1 (host bootstrap) + F-B2
  (per-repo bootstrap, with 5 sub-capabilities: standard
  labels, Status validation, `config.yml` write, `.gitignore`
  entry, BYO-RDBMS credential setup).
- **Bounded context**: Bootstrap (write HostBootstrap +
  RepoBootstrap), Board (read-only — Status field validation).
- **Type**: pattern (state-machine-shaped flow).
- **Body target**: 300-400 lines.
- **References folder**:
  `references/{intro,first-time-user-guide,byo-rdbms-setup,project-creation-walkthrough}.md`.
- **Composes (atomic)**: `board-canon` (read schema invariants
  for Status validation), `auditing-actions`.
- **Composes (cross-plugin)**: none (bootstrap is
  board-superpowers-internal).
- **Trigger model**: `INVOKE: bootstrapping-repo` marker
  injected by the `SessionStart` hook when `manifest.yml` or
  `state.yml` is absent (fast path), OR architect explicitly
  says "set up board-superpowers" (fallback path). Per the hook
  intent injection pattern in
  [`docs/architecture/0004-component-architecture.md`](./docs/architecture/0004-component-architecture.md)
  § "Hook intent injection pattern".
- **Mode**: both.

#### `migrating-repo-version`

- **Role**: F-B3 (host version transition) + F-B4 (per-repo
  version transition with schema migration, new-feature
  opt-out, routing-block re-injection with three-way prompt on
  user modification).
- **Bounded context**: Bootstrap (read + write HostBootstrap +
  RepoBootstrap).
- **Type**: pattern (lifecycle migration flow).
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
- **Mode**: both.

### Atomic layer (4 skills)

#### `board-canon`

- **Role**: Pure read-only contract — 6-state machine + Card
  body schema (thin-pointer + 5 sections + bottom marker) +
  branch naming (`claim/<N>-<slug>`) + WIP counting formula
  (`In Progress + suspended + In Review`; `Blocked` excluded).
- **Bounded context**: Board (schema authority).
- **Type**: reference (Skeleton B per
  [`SKILL_DEVELOPMENT.md`](./SKILL_DEVELOPMENT.md)).
- **Body target**: 200-300 lines.
- **References folder**:
  `references/{state-machine,card-body-schema,claim-protocol,wip-counting,branch-naming}.md`.
- **Called by**: every molecular skill (5 of them).
- **Calls**: nothing. Atomic = reflexive.

#### `enforcing-pr-contract`

- **Role**: PR three-section contract enforcement —
  `## Automated Verification` (required), `## Human
  Verification TODO` (optional, must not be filler),
  `## Retro Notes` (required when reusable lessons exist).
  Provides both injection templates (Consumer side, F-C12) and
  validation rules (Producer side, F-02 Review Queue).
- **Bounded context**: Board (PR aggregate).
- **Type**: reference + discipline.
- **Body target**: 200-250 lines.
- **References folder**:
  `references/{section-templates,validation-rules,filler-detection}.md`.
- **Called by**: `consuming-card` (F-C12 PR submit),
  `managing-board` (F-02 Review Queue contract-violation
  flagging).
- **Calls**: nothing.
- **SPOT consolidates**: PR three-section schema would
  otherwise be inlined in both Consumer and Producer skills.

#### `classifying-actions`

- **Role**: D-AUTONOMY-1 14-row matrix + Consumer subaction
  catalog (`action_id` 100-111) + 4-step triage rule +
  `autonomy_overrides:` parsing (project + user layers). The
  caller hands in an action; this skill returns the A / R / N
  decision.
- **Bounded context**: cuts across Board + Session + Bootstrap
  (anywhere a mutating action fires).
- **Type**: discipline (pressure-tested).
- **Body target**: 200-250 lines.
- **References folder**:
  `references/{matrix,triage-rule,override-parsing,action-id-catalog}.md`.
- **Called by**: every mutating skill (5 of them).
- **Calls**: nothing.
- **SPOT consolidates**: ADR-0006 matrix would otherwise be
  inlined 5 times — 14 rows × 5 = 70 lines of duplicated rule
  encoding drifting independently.

#### `auditing-actions`

- **Role**: Audit log schema (8 columns + 4 enum sets) + R-class
  two-entry rule (propose + resolve) + BYO RDBMS write
  conventions + degradation mode (when DB unavailable, A-class
  degrades to R-class).
- **Bounded context**: Audit (AuditTrail aggregate).
- **Type**: reference.
- **Body target**: 200-300 lines.
- **References folder**:
  `references/{schema,two-entry-rule,db-write-conventions,degradation-mode}.md`.
- **Called by**: every mutating skill (5 of them) — invoked
  immediately after `classifying-actions` returns A or R.
- **Calls**: external RDBMS via
  `${CLAUDE_PLUGIN_ROOT}/scripts/audit-log-write.sh`
  (script TBD per ADR-0006).
- **SPOT consolidates**: ADR-0006 §5 schema would otherwise be
  inlined 5 times.

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
