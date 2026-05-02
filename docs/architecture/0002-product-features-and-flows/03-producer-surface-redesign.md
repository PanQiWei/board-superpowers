### 1.3 Producer surface — redesign

> **Status — design draft.** This file captures the in-progress
> systematic redesign of the Producer-side session abstraction.
> It is **not** the source of truth yet. The currently-shipped
> contract still lives in [`03-producer-surface.md`](./03-producer-surface.md).
>
> **Terminal state.** Once this draft is approved and the
> companion ADR(s) are recorded, this file's content **replaces**
> `03-producer-surface.md`. The replacement happens in a single
> PR that also fans out the spec change-impact matrix updates
> listed in [`../AGENTS.md`](../AGENTS.md) § "Spec change-impact
> matrix". At that point this `-redesign` file is removed (or
> `git mv`'d to `03-producer-surface.md`, overwriting the old
> body).
>
> **Read order.** Read this file in pair with the existing
> `03-producer-surface.md`. Where this draft contradicts the
> existing surface, this draft expresses **future intent** and
> the existing surface expresses **shipped behavior**. The gap
> between the two is exactly the redesign work.
>
> **Companion**: [`04-consumer-surface-redesign.md`](./04-consumer-surface-redesign.md)
> (paired — both surfaces redesign together because they share
> the underlying AI-Agent substrate). If commonality justifies,
> a mother-layer protocol contract may be extracted as
> `0005-contracts/0X-session-agent-protocol.md` before terminal
> landing — see § "Open design choices" → "Form choice".

---

## Why a redesign

Today's Producer surface (per [`03-producer-surface.md`](./03-producer-surface.md))
has four structural weaknesses that v1-complete makes acutely
visible:

1. **Implicit AI-Agent abstraction.** Producer Session is
   modeled as a "product surface" (15 features in 5 thematic
   groups). The deeper truth — Producer is an AI Agent
   specific role, kanban-relative — is not surfaced. Every
   feature reads as a standalone product capability rather
   than as one slice of a unified Agent-Session substrate.
   The implicit abstraction makes adding new specific roles
   (the §1.3.2-reserved Triager, Lint-runner, Refiner) costly
   — there is no shared substrate to inherit from.

2. **Skill nature and skill layer are implicit.** The current
   03 doesn't classify Producer features along the dimensions
   that matter for the SKILL ecosystem: what *kind* of skill is
   this (a workflow procedural guide the agent executes, or a
   mental-model thought framework the agent consults)? Where
   does it sit in the layer hierarchy (entrypoint router /
   molecular workflow / atomic primitive — per
   [`../../SKILLS.md`](../../../SKILLS.md))? Without these
   axes, every feature reads as a peer instead of occupying
   a specific position in the SKILL graph. Empirically,
   Producer features cluster uniformly at (workflow,
   molecular) — surfacing this position makes the surface's
   ecosystem role visible and constrains future-feature
   placement decisions.

3. **SKILL implementation is implicit; hooks and scripts read
   as peers instead of subordinates.** The current 03 prose
   lists `Composes:` as if scripts, skills, and hooks were
   equal-rank implementation alternatives. The reality is
   hierarchical: every Producer feature's core lives in a
   SKILL (a SKILL.md consumed via the Skill tool). Hooks
   exist only as **robustness adjuncts** — a hook script
   exists to make agent execution more robust at a specific
   Axis 1 phase of a skill's flow, never standalone. Scripts
   are **deterministic-mechanism resources** owned by skills
   (single-caller skill-bundled in `skills/<name>/scripts/`;
   multi-caller plugin-global primitives in top-level
   `scripts/` consumed by skills). The flat-listing in current
   03 obscures this hierarchy. Compounding the problem:
   roughly 60 percent of files in `scripts/` are single-caller
   scripts squatting at plugin root (a violation of the
   adjunct-ownership rule — see § "Open design choices" →
   "skill-relocation cleanup timing").

4. **Cross-cutting governance pattern (P8) is not a Producer
   concern.** P8 (Default + override + accountability) was
   recently elevated to a positioning premise
   ([`../0001-positioning.md`](../0001-positioning.md) § P8),
   but Producer-side governance instances (autonomy class per
   feature, override surface, audit trail) are still spelled
   out per-feature. The cross-cutting hooks (where override
   lands, where audit rows land, who surfaces violations) are
   not factored.

## Goals

The redesign pursues four architect-stated goals (intake
direction, 2026-04-29):

**G1 — Recognize Producer as an AI-Agent specialization.**
Producer Session is the Agent's kanban-relative role. All
features are specializations of an Agent-Session substrate;
the substrate's primitives (goal-loop phase, skill nature,
skill layer, hook / script adjuncts as subordinate to
skills) are surfaced as first-class concerns of the
Producer spec.

**G2 — Identify orthogonal axes that pin down feature
identity.** Each feature is positioned by a 4-tuple
`(goal-loop-phase, workflow, skill-nature, skill-layer)`,
plus a per-feature Adjuncts attribute (hook adjuncts + script
adjuncts) that descriptively records implementation
robustness aids without forming an independent axis. The
combination should be sufficient to determine the SKILL that
implements the feature — per architect's directive "all
dimensions taken together should determine a skill". The
axes are abstract structural positions, not identity
enumerations: Axis 4 names the SKILL's layer (entrypoint /
molecular / atomic), not the SKILL's basename — basenames
are downstream of axis values + implementation choice.

**G3 — Distinguish skill nature from skill layer
explicitly.** Skill nature (workflow vs mental-model) and
skill layer (entrypoint / molecular / atomic) are
**different** classification axes — the former is about what
the skill DOES (procedural guide vs thought framework), the
latter is about WHERE it sits in the dependency graph.
Empirically the two correlate strongly (entrypoint and
molecular skills tend to be workflow-natured; atomic skills
tend to be mental-model-natured), but the redesign keeps them
as separate axes because future skills could break the
correlation (e.g., a molecular mental-model skill that frames
a complex governance pattern across atomics; a small atomic
workflow primitive). Surfacing both axes preserves the design
space for those future shapes.

**G4 — Recognize SKILL as the primary implementation unit;
hooks and scripts as subordinate adjuncts.** Every Producer
feature's core lands in a SKILL.md (Axis 4 — Skill layer
identifies its structural position; the SKILL's basename is
downstream of axis values).
Hooks exist only as **robustness adjuncts** to specific
skill-guided lifecycle phases (a hook script's purpose is
"make agent execution more robust at this phase of this
skill's flow"). Scripts are **deterministic-mechanism
resources** owned by skills — single-caller skill-bundled in
`skills/<name>/scripts/`, multi-caller plugin-global
primitives in top-level `scripts/` consumed by skills. The
implicit "execution role choice" of v0.4.0 modeling (was this
feature implemented as skill OR hook OR script?) is dissolved
— it presupposed a peer relationship that does not exist.

## The orthogonal axes

The Producer feature catalog is positioned along **two
coordinate systems**:

1. **Requirement-layer axes (J1–J5)** — defined canonically
   in
   [`../0005-contracts/09-session-agent-protocol.md`](../0005-contracts/09-session-agent-protocol.md)
   (the Session Agent Protocol mother contract introduced
   alongside this redesign): trigger actor / trigger carrier
   / autonomy class / D-META-1 strength / result destination.
   This surface inherits J1–J5 by reference and does not
   redefine them. § "J1–J5 distribution observation" below
   records Producer-specific value distribution.
2. **SKILL-layer axes (A1–A4)** — four axes describing
   *the SKILL that may implement* a node, retained inline
   in this surface because A2 (workflow stage) is
   surface-specific and A1 (goal-loop phase coverage) has
   not yet migrated into
   [`../../../SKILLS.md`](../../../SKILLS.md) as a top-level
   axis: A1 Agent goal-loop phase / A2 Workflow stage / A3
   Skill nature / A4 Skill layer. A3 and A4 recap
   definitions from
   [`../../../SKILLS.md`](../../../SKILLS.md).

The two coordinate systems are **independent**: J1–J5
locate the **node** (the requirement); A1–A4 locate the
**SKILL** (the artifact that may implement the node). The
ROI function in
[`../../../FEATURE_DESIGN_METHODOLOGY.md`](../../../FEATURE_DESIGN_METHODOLOGY.md)
is the only place where the two systems combine.

Cross-axis sparsity is the value of the catalog table form
— most cells of the abstract N-dimensional matrix are
empty, so the catalog is rendered as a flat table with axis
values as columns.

### J1–J5 distribution observation (requirement-layer)

The mother protocol defines J1–J5 dimensions and value
enums; this surface declares how Producer's 26 journey
nodes (the Stage 1 enumeration per
[`../../../FEATURE_DESIGN_METHODOLOGY.md`](../../../FEATURE_DESIGN_METHODOLOGY.md)
§ "Stage 1 — User-journey node enumeration", pending
explicit catalog) distribute across the J values:

| Axis | Producer distribution |
|------|-----------------------|
| **J1** Trigger actor | 8 `agent-self` (A1, A2, A3, D2, E1, E2, E3, F1) / 10 `architect` (A4, A5, B1, B2, B3, B4, C1, C4, D1, F2) / 8 `nested-within-routine` (C2, C3, C5, G1–G5). Total 26. |
| **J2** Trigger carrier | mixed; `cron-job` heavy on cadence-driven nodes (E1–E3 retro / weekly / hygiene; A1–A3 compute side via compute-present split); `session-hook` for K-budget present-only nodes; `in-process-reflex` for G1–G5; `explicit-prompt` for architect-driven B / C / D / F nodes (sub-mode: prompter = architect, except D1 dispatch where prompter = Producer-agent in Mode-2). |
| **J3** Autonomy class | A-class for governance reflex (G1, G3), label cleanup, batch dispatch (D1); R-class for SoT-modifying actions (B4 re-split, F2 harness landing, C2 status flip, C5 stale-claim cancel, G2 propose-await); N-class reserved (zero entries at v1). |
| **J4** D-META-1 strength | wide spread — `low` (G1–G5 governance, A1–A3 mechanism); `medium` (B2 INVEST framing, E1 retro Derby & Larsen template); `high` (B1 design conversation, F2 harness setup). |
| **J5** Result destination | `inject-session` for briefing nodes (A1–A3); `persist-state` heavy (board mutations, audit rows, claim states); `emit-external` for PR comments and dispatched artifacts; `inline-return` appears in nested helper nodes (C3 and partial C2, G4, G5). |

Per-node J 5-tuple positioning lives in § "Producer feature
catalog (table)" below.

> **Note**: the 26 Producer journey nodes (A1–G5) are
> enumerated in § "Producer journey nodes (Stage 1
> enumeration)" below; per-node J 5-tuple positioning is
> in § "Producer feature catalog (table)" further below.

### Axis 1 — Agent goal-loop phase

What cognitive phase is the agent in, **with respect to the
current goal**? This axis is **agentic, not platform-mechanical**.
It does not classify hook events or process states — those are
*triggers* for entering a phase, captured separately in
§ "Trigger model". Together with Axis 2-4, Axis 1 locates the
agent's *mindset* at a stage: what kind of cognitive operation
is the agent performing toward its current goal?

The 9 phases are anchored to Norman 1988 *The Design of
Everyday Things* seven-stage action model
(<https://www.nngroup.com/articles/seven-stages-action/>),
extended with an explicit *orient* phase before intention
formation and an explicit *surface* phase for
uncertainty-driven escalation:

**Reception** — the goal is incoming, agent has not yet engaged.

- **`receive`** — goal ingestion. The agent has just been
  handed a task (kickoff prompt, hook-injected `INVOKE:`
  marker, dispatched assignment). No work done yet.
- **`orient`** — context gathering. The agent reads relevant
  state to build a situational model (board read, spec fetch,
  dependency scan, history walk).

**Engagement** — the active goal-loop, may iterate.

- **`plan`** — approach decision. The agent decides which
  actions, in what order, with which tools (initial plan and
  any subsequent re-plans).
- **`act`** — action execution. The agent performs one
  planned step (tool call, generation, write, dispatch).
- **`observe`** — action-result perception. The agent reads
  what the action produced (tool output, state delta,
  external feedback).
- **`reflect`** — outcome interpretation. The agent judges
  whether progress was made, whether to continue / re-plan /
  surface.

**Side branch** — escapes the goal-loop without resolving the goal.

- **`surface`** — uncertainty escalation. The agent recognizes
  scope ambiguity, missing input, or boundary violation;
  externalizes the question (architect comment, peer-agent
  message); enters logical-suspend until a resolution arrives.

**Closing** — terminating the goal-loop with resolution.

- **`verify`** — outcome validation. The agent checks the
  produced work against the goal's acceptance criteria.
- **`conclude`** — deliverable finalization. The agent emits
  the result, updates state, releases resources, transitions
  out of the goal.

The phases are nodes in a state diagram, not a strict linear
sequence. Common cycles: `act → observe → reflect → plan →
act` (tight tool-loop with re-planning); `<any> → surface →
resume → <any>` (suspend / wake side branch).

**What this axis is NOT**: it does not enumerate hook events
(`SessionStart`, `PreToolUse`, etc.), platform process states
(spawned, terminated), or runtime modes (Mode-1, Mode-2).
Those are *implementation triggers* for entering an Axis 1
phase — the relationship is documented in § "Trigger model"
(TBD). Keeping Axis 1 platform-agnostic is what lets the
catalog stay valid across CC and Codex projections.

### Axis 2 — Workflow stage

Which workflow does this feature compose, and at what step?
Producer workflows at v1-complete:

- **`daily`** — F-01 / F-02 (briefing for morning ritual).
- **`intake`** — F-08 → F-09 (new requirement → routing →
  decomposition).
- **`decompose-handoff`** — F-09 alone (artifact → cards on
  board).
- **`review-queue`** — F-02 (PR queue with ordering and
  contract-violation flagging).

Workflows deferred to v1.x per ADR-0011 (will surface in this
catalog as `deferred` rows that exist but do not ship): triage
(F-10 / F-11), retro (F-12), weekly-report (F-13),
overnight-dispatch (F-04 → F-07), context-reload (F-06),
harness-setup (F-14), kanban-hygiene (F-15), board-health
(F-05), blocked-inspection (F-03).

### Axis 3 — Skill nature

What kind of SKILL implements this feature? Two values:

- **`workflow`** — a SKILL that **guides a procedural
  sequence the agent executes**. The SKILL.md body reads as
  steps / routines / lifecycle stages. The agent enters the
  skill's procedural narrative and follows it linearly, with
  branching at decision points and surface-suspend at
  uncertainty. Typical body shape: numbered steps, decision
  trees, lifecycle state-machine sections.
- **`mental-model`** — a SKILL that **provides a thought
  framework the agent consults during procedure**. The
  SKILL.md body reads as schema / state machine / classification
  matrix / contract / rule set. The agent does not execute
  it linearly — it queries it for "what is legal" / "how do I
  classify this" / "what is the canonical shape". Typical
  body shape: tables, enum definitions, decision rubrics,
  validation rules, contract clauses.

Producer empirical observation: **all 15 Producer features
are workflow-natured** — they live inside molecular workflow
skills. The mental-model skills they consume are atomic-layer
external dependencies, not Producer features themselves; they
appear in each feature's `composes_atomics` attribute, not as
Producer-surface rows. The uniformity along Axis 3 within the
Producer surface is itself a structural finding: Producer
*surface* IS the workflow projection of a board-orchestration
mental-model substrate, with the substrate living in the
atomic layer.

### Axis 4 — Skill layer

Where in the SKILL graph does this feature's SKILL sit? Three
values, mirroring the three-layer architecture documented in
[`../../SKILLS.md`](../../../SKILLS.md) § "Three-layer
architecture":

- **`entrypoint`** — first-touch router. Loaded every session
  (low body-length budget, ≤200 lines). Routes incoming
  prompts and hook-injected `INVOKE:` markers to the right
  molecular skill. Stability: low (changes when routing
  scenarios appear).
- **`molecular`** — business workflow. State-machine-shaped
  procedural SKILL composing atomic primitives. Body length
  budget 250-450 lines. Stability: medium (changes with
  workflow evolution).
- **`atomic`** — single-purpose reflex / reference. Composed
  by molecular skills via in-process Skill tool invocation
  (per
  [ADR-0008](../adr/0008-plugin-to-plugin-skill-invocation.md)).
  Atomic skills are **reflexive** — they MUST NOT call other
  same-plugin skills (the SPOT discipline per SKILLS.md). Body
  length budget 200-300 lines. Stability: high (rarely changes
  once stable).

Producer empirical observation: **all 15 Producer features
sit at `molecular` layer**. Their atomic dependencies appear
in `composes_atomics`, not as Producer-surface rows. The
single-layer uniformity within Producer surface is structural:
Producer surface IS the molecular workflow layer for board
orchestration. Future Producer specific roles (the
§1.3.2-reserved Triager / Lint-runner / Refiner) will also
land at molecular by construction; whether to split a
multi-routine molecular SKILL into per-routine sub-molecular
skills is a separate decision (see § "Open design choices" →
"SKILL decomposition granularity").

**Why this is not "SKILL home" / "SKILL basename"** — naming
a SKILL is an identity choice downstream of axis values +
implementation; it is not itself a structural dimension. The
axis classifies SKILLs by **structural position in the
dependency graph**; basenames are derived. The
v0.4.0-modeling "skill-home" attempt conflated the two.

### Adjuncts (attribute, not axis)

For each feature, declare two adjunct lists. Adjuncts are
**descriptive**, not classifying — they do not form an
independent orthogonal axis because their presence and
identity are derived from the SKILL's robustness needs, not
from an independent design dimension.

- **Hook adjuncts** — `(hook_event, handler_path)` pairs that
  reinforce agent execution at specific Axis 1 phases. A hook
  adjunct exists *to make a skill-guided flow more robust at
  a specific cognitive phase*; it is never standalone. Most
  features have no hook adjunct (the pure skill flow is
  robust enough). Pattern: a SessionStart hook may inject an
  `INVOKE:` marker that nudges the agent into entering some
  SKILL's `receive` phase — that hook is a hook-adjunct of
  the targeted SKILL, not an independent feature.
- **Script adjuncts** — scripts the skill consumes for
  deterministic mechanism. Skill-private scripts (single
  caller) live in `skills/<name>/scripts/`; plugin-global
  scripts (multi-caller primitives) live in top-level
  `scripts/`. Per-feature script adjuncts are declared with
  their current physical location; misplaced ones (single-
  caller squatting at plugin-global) carry a `*-misplaced`
  suffix, surfacing the cleanup queue.

Adjunct ownership rule: *single-caller scripts MUST be
skill-bundled; multi-caller primitives MAY be plugin-global*.
The current 60-percent-misplaced state of `scripts/` is
documented under each affected feature's `script_adjuncts`
list with the misplacement marker; the cleanup is independently
scheduled (see § "Open design choices" → "skill-relocation
cleanup timing").

### Axes orthogonality self-check (SKILL-layer)

Each pair of A1–A4 (SKILL-layer) axes is independent —
moving along one does not constrain another. **J1–J5
orthogonality is verified by the mother protocol**
([`../0005-contracts/09-session-agent-protocol.md`](../0005-contracts/09-session-agent-protocol.md)
§ "Cross-axis legal-combination matrix"); this surface does
not re-verify J1–J5 orthogonality.

For A1–A4 (the four axes inlined in this surface):

- A1 ⊥ A2: an `orient` phase serves multiple workflows
  (daily briefing's board read, intake's context fetch, and
  decompose-handoff's spec walk all share the `orient` phase
  but belong to different workflows).
- A1 ⊥ A3: any cognitive phase can be hosted by either a
  workflow SKILL (the agent enters a procedural narrative)
  or a mental-model SKILL (the agent consults a framework).
  A workflow feature in `orient` phase typically composes
  one or more mental-model atomics consulted during that
  same `orient` — phase and nature are independent.
- A2 ⊥ A3: every workflow contains feature steps that
  compose mental-model atomics. A routing-decision step
  (workflow nature) at `intake` workflow / `plan` phase
  consults a classification atomic (mental-model nature)
  for autonomy class resolution; both halves coexist at the
  same workflow step but on different natures.
- A3 ⊥ A4: although currently strongly correlated
  (entrypoint and molecular trend workflow; atomic trends
  mental-model), the redesign treats them as independent
  because future shapes can break the correlation (a
  molecular mental-model framework SKILL; an atomic
  workflow primitive). The 2×3 design-space cells are all
  reachable; current uniformity on the diagonal is
  empirical, not structural.
- A1 / A2 / A3 ⊥ A4: any cognitive phase × any workflow ×
  any nature can in principle sit at any layer — though
  atomic layer is reflexive (no upward calls to same-plugin
  skills), which constrains some workflows.

## Producer journey nodes (Stage 1 enumeration)

This section is the **Stage 1 output** per
[`../../../FEATURE_DESIGN_METHODOLOGY.md`](../../../FEATURE_DESIGN_METHODOLOGY.md)
§ "Stage 1 — User-journey node enumeration": the
implementation-agnostic list of every discrete intent the
Producer surface must satisfy, expressed as **two
complementary lists** (human-initiated +
agent-self-initiated) plus their cross-product
(cross-cutting governance).

Producer enumeration produces **26 journey nodes** in seven
groups (A–F human-initiated 21 nodes + G cross-product 5
nodes). The numbering scheme (A1–G5) is internal to this
enumeration and orthogonal to the F-01..F-15 numbering in
the currently-shipped 03 surface (which is feature-grouped,
not journey-grouped). Both numbering schemes coexist during
the redesign window — the shipped surface keeps F-01..F-15
as its row index; this redesign uses A1–G5 as its
journey-node index. Cross-references between the two appear
in § "Producer feature catalog (table)" below.

### Group A — Start-of-day / context-switch (5 nodes)

What the architect wants when entering a session and
deciding where to focus.

- **A1** — Board overview at session entry: see what's
  running, awaiting review, blocked, ready, unscheduled.
- **A2** — Ordered PR queue: not just grouped by status,
  ordered by "what should I review now" (CI signal, claim
  age, Thread priority, contract violation flags).
- **A3** — "What's blocking me": cards stuck on
  blocked-on-architect state.
- **A4** — Context-switch reload: when switching back to
  an old Thread / card, fast reload of recent events plus
  the last decision the architect left.
- **A5** — Today's dispatch recommendation: given current
  WIP / health / Thread priority + architect's available
  time window, recommend cards to claim today.

### Group B — Bringing in new work (4 nodes)

What the architect does to introduce new requirements
onto the board.

- **B1** — Design conversation routing: route ambiguous
  ideas through `gstack:/office-hours`,
  `gstack:/plan-eng-review`,
  `superpowers:brainstorming` for sharpening before
  decomposition.
- **B2** — INVEST decomposition: turn settled design into
  vertically-sliced cards on the board.
- **B3** — Single-card fast-path: drop a known atomic
  task on the board directly (no design conversation
  required).
- **B4** — Resplit existing card: structural break-down
  of an oversized in-flight card.

### Group C — Advancing in-flight work (5 nodes)

What the architect does to manage cards that are already
running.

- **C1** — Review PR: validate three-section contract +
  AC terminal-state + judge substance.
- **C2** — Return to In Progress (nested in C1): when
  review identifies rework, flip status with reason +
  guidance.
- **C3** — Lookup card event stream (nested across
  several outers): fetch commits / comments / status
  history when context is needed.
- **C4** — Unblock blocked card: 5-step remediation
  ladder (unblock / split / reassign / kill / refine).
- **C5** — Cancel stale claim: ghost-claim release with
  notification to original Consumer.

### Group D — Async dispatch (2 nodes)

What turns architect's idle time into productive runtime.

- **D1** — Overnight batch dispatch: cards run while
  architect rests, under controlled concurrency (per
  ADR-0007 C-PLUGIN-3).
- **D2** — Batch result aggregation: rolled into next-day
  briefing (compute / present split with A1).

### Group E — Reflection / cadence (3 nodes)

Periodic cadence-driven workflows that are
calendar-linked, not session-linked. All three rely on
cron-job carrier per
[ADR-0028](../adr/0028-cron-as-trigger-carrier.md).

- **E1** — Retro on cadence trigger: Milestone close /
  N-cards completed / decomposition drift detection.
- **E2** — Weekly aggregated report: quality trend +
  status, merged into one document for the architect-as-
  both-audiences (P1).
- **E3** — Kanban hygiene sweep: drift detection (orphan
  claims, stale labels, field inconsistency) + 5-step
  ladder remediation.

### Group F — Project-level infrastructure (2 nodes)

Long-lived infrastructure setup and evolution.

- **F1** — Bootstrap repo: first-time per-`(host, repo)`
  setup driven by the Setup-Stages registry (per 05).
- **F2** — Harness setup / evolution: lint rules /
  structural tests / auto-PR / automerge harness,
  captured via D-META-1 conversation.

### Group G — Cross-cutting governance (5 nodes)

These nodes do not appear in the human-initiated list
directly. They are surfaced from the **cross-product** of
"human-initiated × agent-self-initiated" lists per
[`../../../FEATURE_DESIGN_METHODOLOGY.md`](../../../FEATURE_DESIGN_METHODOLOGY.md)
§ "Two complementary lists are mandatory" — "the
cross-product is where governance / cross-cutting
concerns surface as their own node group."

- **G1** — Every mutating action is auditable
  (post-action audit row, atomic reflex).
- **G2** — R-class actions surface a proposal awaiting
  architect reply (pre-action propose-resolve, atomic
  reflex).
- **G3** — A-class actions execute without architect
  interruption (pre-action gate, atomic reflex; folded
  into G2's classifier in implementation).
- **G4** — Design discipline preserved (intake →
  decompose bridge cannot be skipped via fast-path).
- **G5** — Cross-platform parity (CC / Codex same
  semantics; path / hook / SKILL invocation flattened by
  `bsp_plugin_root()` and equivalents).

### Two-list provenance summary

A–F come from the **human-initiated list** (what the
architect explicitly wants to do; 21 nodes). G1–G5 come
from the **cross-product** with the agent-self-initiated
list (what the system must do for every mutating action;
5 nodes). Both lists are mandatory per methodology Stage 1
anti-pattern A1 ("single-list enumeration"). The
5+4+5+2+3+2+5 = 26 shape is project-specific — other
surfaces (Consumer in 04, Bootstrap in 05) produce
different totals; the two-list discipline is invariant.

## Producer feature catalog (table)

The Stage 2 + Stage 3 output: each of the 26 journey nodes
positioned on J1–J5 (requirement-layer) plus A1–A2
(SKILL-layer). A3 and A4 are omitted from per-row columns
because the 21 human-initiated nodes (A–F) empirically
resolve to A3=`workflow` × A4=`molecular`, per the
empirical observations in § "Axis 3 — Skill nature" and
§ "Axis 4 — Skill layer" above. The 5 cross-cutting
governance nodes (G1–G5) resolve to A4=`atomic` (G1, G2)
or to non-SKILL adjuncts (G3 fold into G2, G4 fold into
intaking-requirement, G5 script-only) — their SKILL-layer
position is recorded in the per-row "Archetype + SKILL
home" column rather than as a separate axis column.

Per-node ROI archetype (A / B / C) is shown in the last
column with its candidate SKILL home.

> **Notation key**:
>
> - **J1**: `agent-self` / `architect` / `nested`
> - **J2**: `cron+hook` (compute / present split) /
>   `cron-job` / `session-hook` / `in-process-reflex` /
>   `explicit-prompt`
> - **J3**: `A` / `R` / `mixed` / `N/A` (read-only or
>   non-mutating)
> - **J4**: `low` / `medium` / `high`
> - **J5**: `inject-session` / `persist-state` /
>   `emit-external` / `inline-return` / mixed combinations
> - **A1 phases**: arrow chain of Norman-1988 phases
>   (`receive` / `orient` / `plan` / `act` / `observe` /
>   `reflect` / `surface` / `verify` / `conclude`)
> - **A2 workflow**: per § "Axis 2 — Workflow stage" above
> - **Archetype + SKILL home**: ROI archetype A/B/C + the
>   SKILL the node lands in (or "fold into X" for
>   archetype C)

| ID | Name | J1 | J2 | J3 | J4 | J5 | A1 phases | A2 workflow | Archetype + SKILL home |
|----|------|-----|-----|-----|-----|-----|-----------|-------------|------------------------|
| **A1** | Board overview | agent-self | cron+hook (split) | N/A | low | inject-session + persist-state | orient → reflect → conclude | daily | A (merge into routine SKILL) → `briefing-daily` |
| **A2** | Ordered PR queue | agent-self | cron+hook (split) | N/A | low | inject-session + persist-state | orient → reflect → conclude | daily / review-queue | A (merge into routine SKILL) → `briefing-daily` |
| **A3** | "What's blocking me" | agent-self | cron+hook (split) | N/A | low | inject-session | orient → reflect | daily | A (merge into routine SKILL) → `briefing-daily` |
| **A4** | Context-switch reload | architect | explicit-prompt | N/A | low | inject-session | receive → orient → reflect → conclude | ad-hoc | C → fold into `briefing-daily` (re-entry branch) |
| **A5** | Today's dispatch recommendation | architect | explicit-prompt | N/A | medium | inject-session | receive → orient → plan → conclude | daily | C → fold into `briefing-daily` (post-overview phase) |
| **B1** | Design conversation routing | architect | explicit-prompt | N/A (routing) | high | inject-session + emit-external (sibling output) | receive → plan → act (delegate) | intake | C → fold into `intaking-requirement` (uses `composing-siblings` atomic) |
| **B2** | INVEST decomposition | architect | explicit-prompt | A initial / R resplit (handled by B4) | medium | persist-state + inject-session | receive → orient → plan → act → verify → conclude | decompose-handoff | A → MUST own SKILL: `decomposing-into-milestones` (shipped v0.4.0) |
| **B3** | Single-card fast-path | architect | explicit-prompt | A | low | persist-state | receive → plan → act | intake | C → fold into `intaking-requirement` |
| **B4** | Resplit existing card | architect | explicit-prompt | R (per ADR-0006 row 3) | medium | persist-state + inject-session | receive → orient → plan → act → verify | intake (re-entry) / triage | C → fold into `decomposing-into-milestones` (re-entry branch of B2) |
| **C1** | Review PR | architect | explicit-prompt | mixed (A approve / R rework via C2) | medium | persist-state + emit-external | receive → orient → reflect → conclude | review-queue | A → MUST own SKILL: `reviewing-pr-queue` |
| **C2** | Return to In Progress (nested in C1) | nested | in-process-reflex | R (Status flip on in-flight claim) | low | persist-state + emit-external + inline-return | reflect → act (within C1) | review-queue | C → fold into `reviewing-pr-queue` |
| **C3** | Lookup card event stream (nested) | nested | in-process-reflex | N/A (read-only) | low | inline-return | orient (helper) | review-queue / retro / hygiene / context-reload | C → script-only: `scripts/lookup-card-events.sh` (multi-caller deterministic mechanism, NOT a SKILL) |
| **C4** | Unblock blocked card (5-step ladder) | architect or nested in E3 | explicit-prompt or in-process-reflex | mixed (A unblock + refine; R split + reassign + kill) | medium | persist-state + emit-external + inject-session | receive → orient → plan → act | triage | A → MUST own SKILL: `triaging-board` |
| **C5** | Cancel stale claim | nested in E3 / architect | in-process-reflex (nested) or explicit-prompt | R (per ADR-0006 row 8) | low | persist-state + emit-external | reflect → plan → act | hygiene / triage | C → fold into `triaging-board` |
| **D1** | Overnight batch dispatch | architect | explicit-prompt | A (per ADR-0006 row 13) | medium | persist-state + inject-session | receive → plan → act → observe → conclude | overnight-dispatch | v1.x defer (B candidate when shipped) |
| **D2** | Batch result aggregation | agent-self | cron-job | N/A | low | persist-state + inject-session (next-day) | orient → reflect → conclude | overnight-dispatch / daily | v1.x defer (C, fold into briefing-daily or D1 SKILL when shipped) |
| **E1** | Retro on cadence trigger | agent-self (cadence) / architect (manual) | cron-job (cadence) or explicit-prompt | mixed (A cadence-log row 14; R proposed amendments row 4) | medium | emit-external (retro report) + inject-session (proposals) | orient → reflect → conclude → surface (proposals) | retro | v1.x defer (B candidate when shipped) |
| **E2** | Weekly aggregated report | agent-self | cron-job | A (per ADR-0006 row 14) | low | emit-external (commit / email / state.yml) | orient → reflect → conclude | weekly-report | v1.x defer (C candidate when shipped) |
| **E3** | Kanban hygiene sweep | agent-self (cadence) / architect | cron-job or explicit-prompt | mixed (label cleanup A row 11; orphan claim cancel R row 8) | low | persist-state + emit-external + inject-session (R proposals) | orient → reflect → plan → act | kanban-hygiene | v1.x defer (B candidate when shipped) |
| **F1** | Bootstrap repo | agent-self (state.yml absence detection) | session-hook (`INVOKE` injection) | mixed (mostly A; R for SoT-modifying like routing-block injection) | low (Setup-Stages registry mechanism) | persist-state | receive → orient → plan → act → verify → conclude | bootstrap | A → MUST own SKILL: `bootstrapping-repo` (shipped v0.2.0) |
| **F2** | Harness setup / evolution | architect | explicit-prompt | R (per ADR-0006 rows 4 / 10) | high | persist-state + inject-session (proposals) | receive → plan → act (delegate) → verify | harness-setup | v1.x defer (B candidate when shipped) |
| **G1** | Audit row on every mutating action | nested | in-process-reflex | N/A (record, not action) | low (schema) | persist-state (audit DB) | act (record reflex) | N/A (cross-cutting) | A → MUST own atomic SKILL: `auditing-actions` (shipped v0.3.0) |
| **G2** | R-class propose-await | nested | in-process-reflex | R (governs R class) | low | inject-session (proposal) + persist-state (proposal audit row) | reflect → surface | N/A | A → MUST own atomic SKILL: `classifying-actions` (shipped v0.3.0) |
| **G3** | A-class no-interrupt gate | nested | in-process-reflex | A (governs A class) | low | persist-state (audit) | reflect | N/A | C → fold into `classifying-actions` (G2 + G3 share the classifier reflex) |
| **G4** | Design discipline (intake → decompose) | nested (within intake → decompose 串接) | in-process-reflex | N/A (refusal of fast-path is meta-rule) | low (rule) | inject-session (refusal message) + inline-return (gating) | reflect (gate) | intake | C → fold into `intaking-requirement` |
| **G5** | Cross-platform parity | nested (every cross-platform-sensitive action) | in-process-reflex | N/A | low (path / hook resolution) | inline-return | act (helper) | N/A | C → script-only: `scripts/lib/common.sh` (`bsp_plugin_root()` etc.), NOT a SKILL |

### Cross-references to F-01..F-15 (currently-shipped surface)

For backward-compatibility while the redesign is in draft,
this table maps A1–G5 to the currently-shipped F-01..F-15
numbering:

| A1–G5 | F-01..F-15 | Notes |
|-------|------------|-------|
| A1 | F-01 (atomic kanban query primitive — *being demoted to script adjunct*) + F-05 (board health) | F-01 is mechanism, not journey node — see § "Why a redesign" point 3 |
| A2 | F-02 (pending PR queue) | Direct mapping |
| A3 | F-03 (blocked sessions inspection) | Direct mapping |
| A4 | F-06 (context briefing on switch-back) | Direct mapping |
| A5 | F-04 (today's dispatch recommendation) | Direct mapping |
| B1 | F-08 (interactive intake & design routing) | Direct mapping |
| B2 | F-09 (decomposition into cards) | Direct mapping |
| B3 | (no F-equivalent — fast-path implicit at F-08 / F-09 boundary) | New explicit node in this redesign |
| B4 | F-09 R-resplit branch | Direct mapping |
| C1 | F-02 ordering's review-queue routine + currently-shipped Review Queue routine in `managing-board` | Direct mapping |
| C2–C3 | (nested helpers, no F-equivalent) | New explicit nodes |
| C4 | F-10 (triage with remediation ladder) | Direct mapping |
| C5 | F-15 orphan-claim subset + F-10 reassign branch | Composed mapping |
| D1 | F-07 (overnight batch dispatch) | Direct mapping |
| D2 | (no F-equivalent — implicit in F-07 result handling) | New explicit node |
| E1 | F-12 (retro routine) | Direct mapping |
| E2 | F-13 (weekly aggregated report) | Direct mapping |
| E3 | F-15 (kanban hygiene & maintenance ops) | Direct mapping |
| F1 | (no F-equivalent in 03; lives in 05 bootstrap-surface) | Direct mapping (cross-surface) |
| F2 | F-14 (harness setup & evolution conversation) | Direct mapping |
| G1–G5 | (no F-equivalent — these are cross-cutting concerns surfaced by methodology cross-product) | New explicit nodes from methodology |
| F-11 (stale session detection lazy) | (mechanism, not journey node) | Demoted to script adjunct of E3 / D2 |

Two structural findings from the cross-reference:

1. **F-01 and F-11 are mechanisms, not journey nodes.**
   The redesign demotes them from feature catalog entries
   to **script adjuncts** of the journey nodes that
   consume them (A1/A2/A3 consume `read-board.sh`; E3 / D2
   consume staleness-detection logic). This was originally
   noted as a paradigm gap in § "Why a redesign" point 3;
   the demotion is now explicit via this table.
2. **8 journey nodes have no F-equivalent.** B3, C2, C3,
   D2, F1, G1–G5. These are nodes the methodology Stage 1
   enumeration surfaced that the F-01..F-15 grouping
   missed — either by under-enumeration (B3, D2),
   nested-node implicitness (C2, C3), cross-surface bleed
   (F1 lives in 05 bootstrap), or cross-cutting surfacing
   (G1–G5). Recovering these as explicit nodes is a
   primary methodology dividend.

## Producer SKILL set decision (Stage 3 ROI synthesis)

Applying the ROI function (per
[`../../../FEATURE_DESIGN_METHODOLOGY.md`](../../../FEATURE_DESIGN_METHODOLOGY.md)
§ "Stage 3 — Derivation function (ROI)") to each of the 26
nodes yields the archetype distribution below. Strict
re-evaluation under v1-complete scope (architect intake
2026-04-29, post-methodology) **promoted four routine nodes
to archetype-A merge-into-routine** because their host
routines themselves consume private board-superpowers
ontology + private contract + private discipline (gap=high
on the routine, not just on the constituent steps). The
four routines emerge as molecular SKILLs.

### Archetype distribution (v1-complete scope)

| Archetype | Count | Nodes |
|-----------|-------|-------|
| **A — MUST own SKILL** (independent molecular or atomic) | 7 | B2 → `decomposing-into-milestones` (shipped); F1 → `bootstrapping-repo` (shipped); G1 → `auditing-actions` (shipped); G2 → `classifying-actions` (shipped); C1 → `reviewing-pr-queue` (NEW molecular); C4 → `triaging-board` (NEW molecular); B1+B3 host → `intaking-requirement` (NEW molecular); A1+A2+A3 host → `briefing-daily` (NEW molecular). Note: archetype-A counts the *SKILLs* (7), not the nodes (multiple nodes per routine SKILL). |
| **C — fold into other** | 14 | A4, A5 → fold into `briefing-daily`; B3, B1, G4 → fold into `intaking-requirement`; B4 → fold into `decomposing-into-milestones`; C2 → fold into `reviewing-pr-queue`; C5 → fold into `triaging-board`; G3 → fold into `classifying-actions`; C3 → script-only (`scripts/lookup-card-events.sh`, deterministic mechanism); G5 → script-only (`scripts/lib/common.sh`); plus the four merge-into-routine nodes A1/A2/A3/C1/C4 counted above as part of their routine's archetype-A SKILL home. |
| **v1.x defer** | 6 | D1, D2, E1, E2, E3, F2 — out of v1-complete scope per ADR-0011; revisit when demand pulls. |

**Archetype-B count is 0** at v1-complete scope. Every node
that the original Stage 3 draft tagged as archetype-B
either (a) merges into an archetype-A routine because the
routine host already carries D-META-1 routing as part of
its body (B1 into `intaking-requirement`), or (b) defers
to v1.x (D1, E1, E3, F2). Archetype-B "thin router SKILL"
remains a valid form for future v1.x landings, but no v1
SKILL ships in that shape.

### Final SKILL set (v1-complete Producer-side)

```
Entry layer (1 SKILL)
─────────────────────────────────────────────
using-board-superpowers              shipped — routing table updated
                                     for the 4-way molecular fan-out

Molecular layer (6 SKILLs — 4 NEW + 2 shipped)
─────────────────────────────────────────────
briefing-daily              NEW    A1 + A2 + A3 + A4 + A5
intaking-requirement        NEW    B1 + B3 + G4
reviewing-pr-queue          NEW    C1 + C2
triaging-board              NEW    C4 + C5
decomposing-into-milestones shipped v0.4.0   B2 + B4
bootstrapping-repo          shipped v0.2.0   F1

Atomic layer (5 SKILLs — 4 shipped + 1 NEW)
─────────────────────────────────────────────
board-canon                 shipped   schema + state machine + WIP formula
enforcing-pr-contract       shipped   Contract A + B
classifying-actions         shipped   D-AUTONOMY-1 matrix; G2 + G3
auditing-actions            shipped   audit schema + degradation; G1
composing-siblings          NEW       cross-plugin routing SPOT (see below)

Producer-side total: 12 SKILLs (1 + 6 + 5).
```

The `managing-board` mega-SKILL (current v0.4.0 shape;
multi-routine) is **retired** in favor of the four
per-routine sub-molecular SKILLs. The decomposition
rationale is recorded under § "Decided" → "SKILL
decomposition granularity".

### Why per-routine split (Shape Y) wins over the multi-routine `managing-board` shape

| Dimension | Multi-routine `managing-board` (Shape X) | Per-routine split (Shape Y, **chosen**) |
|-----------|-----------------------------------------|------------------------------------------|
| SKILL count | 12 | 12 (same — adding 4 new molecular but retiring `managing-board` = net +3, while atomic `composing-siblings` +1 and the existing 4 atomics unchanged) |
| Trigger description granularity | 1 multi-keyword description (`managing-board` covering daily / intake / review-queue / triage simultaneously) | 4 single-semantic descriptions (one per routine SKILL); trigger phrases for the 4 routines do not overlap |
| Body-length budget | High pressure — body covers 4 routines, approaching 450-line molecular ceiling at v1-complete scope; future v1.x routine additions force re-deciding "merge into managing-board vs new SKILL" each time | Comfortable — each per-routine SKILL settles in the 200–300 line range; future v1.x molecular additions follow the established "one routine, one SKILL" pattern uniformly |
| Routing complexity | Low SKILL count, but post-routing intra-SKILL dispatch needed (architect prompt → `managing-board` → which routine?) | Higher SKILL count, but routing collapses on first match because trigger phrases are disjoint |
| Routine-boundary clarity | Implicit — routines are body sections within one SKILL | Explicit — routines are SKILLs with their own frontmatter, references/, and `.skill-meta.yaml` |
| Cross-routine sharing | Body-sharing trivial (same SKILL) | Goes through atomic SKILLs (`board-canon`, `composing-siblings`) and `scripts/` helpers — already the structural mechanism for shared knowledge anyway |
| Evolution discipline | "Mega-SKILL grows over time" failure mode (v1-complete + v1.x → Triager / Lint-runner / Refiner specific roles squeezing in) | "One specific role, one SKILL, one description" pattern stable across v1-complete and v1.x |

The three decisive dimensions (body-length budget,
trigger description precision, evolution discipline) all
favor Shape Y; the one Shape X advantage (cross-routine
body sharing) is absorbed by the atomic layer where it
already structurally belonged. Methodology-neutral: the
ROI function does not mandate the shape; the choice
follows from the *body-length-budget × evolution
discipline* product favoring Shape Y at v1-complete scope
and beyond.

### New atomic SKILL: `composing-siblings`

The Stage 3 SPOT census surfaced one additional atomic
candidate beyond the four already shipped: the cross-plugin
routing decision framework (when to invoke
`gstack:/office-hours` vs `/plan-eng-review` vs
`superpowers:brainstorming` vs `superpowers:writing-plans`,
plus ADR-0008 in-process-vs-procedural compatibility
dispatch).

**SPOT consolidation**: this routing knowledge is currently
duplicated across three places — top-level `AGENTS.md`
"How to compose gstack and superpowers" section,
`skills/managing-board/references/skill-routing.md`, and
inline mentions in each routine's body within the (now
retired) `managing-board` mega-SKILL. With the Shape Y
split, four molecular SKILLs (`intaking-requirement`,
`reviewing-pr-queue`, `triaging-board`,
`decomposing-into-milestones`) all need this routing
table. Continuing to inline = quadrupled drift risk.

**ROI**: gap=medium (private D-META-1 framework — base
model knowledge of sibling skill descriptions is shallow,
and ADR-0008 procedural-vs-in-process boundaries are
plugin-private) × frequency=medium-high (every routine
that delegates to a sibling consults this) × failure=medium
(wrong sibling wastes one round, recoverable but expensive)
÷ maintenance=low (sibling set is stable) + routing=low
(atomic, never contends for entry-point trigger phrases) =
**archetype A atomic**.

**Knock-on cleanups when this atomic ships**: AGENTS.md
"How to compose gstack and superpowers" section becomes a
1-line pointer to `composing-siblings`;
`managing-board/references/skill-routing.md` is
deleted (the SKILL retires); inline references in the four
new molecular SKILLs reduce to a `composes_atomic:
composing-siblings` declaration. The Spec change-impact
matrix row "AGENTS.md compose section ↔ skill-routing.md
/ scope-shape-judgment.md" simplifies because the
synchronization target collapses to one file.

### D-META-1 conversation framework — v1.x roadmap (NOT shipped at v1-complete)

A second atomic SPOT candidate was evaluated and
**deliberately deferred** to v1.x: the meta-framework for
running D-META-1 conversations (per
[`../0001-positioning.md`](../0001-positioning.md) § P7)
that elicit architect-private taste rather than ship
defaults.

**Why deferred despite ≥2 callers at v1-complete**:
`intaking-requirement` (B1 design conversation routing,
**dispatch-style**) and `decomposing-into-milestones` (B2
+ B4 INVEST + vertical slicing, **deliberation-style**)
both run D-META-1 conversations, but their rhythmic
shapes differ structurally. Dispatch-style runs short
turns (sub-30-second routing decision); deliberation-style
runs long turns (5–10-minute boundary debates). Forcing
both under one atomic at v1-complete produces either an
overly-abstract framework (just "ask open-ended questions,
avoid defaults, persist taste to spec") or an
overly-specific framework (two parallel sub-templates with
shared overhead). Both lose ROI to the inline status quo.

**v1.x lift trigger**: when caller count reaches ≥4
molecular SKILLs (intake + decompose +
`harness-setup` (F2) + `running-retro` (E1)) AND at least
3 of the 4 share a structurally same conversation
rhythm (i.e., dispatch / deliberation / design / review
collapse into 3 or fewer modes), then the atomic
`framing-d-meta-1-conversation` (or
`eliciting-architect-taste`) becomes worth lifting.
Threshold rationale: 3 callers under one mode meets the
SPOT density floor for a non-mechanism atomic.

**Until v1.x lifts it**: each molecular SKILL keeps a
private D-META-1 mode reference at
`skills/<routine>/references/<routine>-d-meta-1-mode.md`
(≤80 lines), describing that routine's specific
conversation rhythm. Multiple unshared mode files are
strictly worse than one over-generalized atomic, but
strictly better than no documented rhythm — they preserve
the specific rhythms until SPOT structure crystallizes.

### Same-PR cleanup obligations (Shape Y)

When this redesign moves from draft to shipped:

- **Retire `managing-board` mega-SKILL** — `git rm -r
  skills/managing-board/`, plus update `SKILLS.md` catalog
  entry, update `using-board-superpowers` routing table,
  remove the change-impact-matrix row referencing
  `managing-board/references/skill-routing.md`.
- **Author 4 new molecular SKILLs** —
  `skills/briefing-daily/`, `skills/intaking-requirement/`,
  `skills/reviewing-pr-queue/`, `skills/triaging-board/`.
  Each gets `SKILL.md`, `references/`,
  `.skill-meta.yaml`, plus per-routine D-META-1 mode
  reference (where applicable).
- **Author 1 new atomic SKILL** — `skills/composing-siblings/`
  with `SKILL.md` + `references/{routing-table,adr-0008-compatibility,sibling-skill-catalog}.md`.
- **Demote F-01 + F-11** from currently-shipped 03 surface
  to script adjuncts (they are mechanisms, not journey
  nodes — see § "Why a redesign" point 3).
- **Add B3, C2, C3, D2, G1–G5** as explicit catalog rows
  (currently absent or implicit in F-01..F-15 numbering).
- **G4 (design discipline gate)** — enforced at the
  intake → decompose boundary inside `intaking-requirement`
  body; no separate SKILL.
- **F1 lives in 05** — cross-surface reference adjusted in
  catalog notes.
- **Update `AGENTS.md`** — the "How to compose gstack and
  superpowers" section collapses to a 1-line pointer to
  `composing-siblings` atomic SKILL.
- **Cross-impact propagation** — Spec change-impact matrix
  in [`../AGENTS.md`](../AGENTS.md) walked top-to-bottom:
  every row mentioning `managing-board` updates to
  reference the corresponding new routine SKILL or the
  new atomic.

## Trigger model

[TBD — describes how each lifecycle phase is triggered under
v1's plugin runtime. Cites
[ADR-0007](../adr/0007-plugin-runtime-derived-constraints.md)
derived constraints (no daemon, preflight piggyback idiom).
Settled in brainstorm Phase 1.]

## Skill nature × layer implications

[TBD — what changes structurally given that all 15 Producer
features sit at (workflow, molecular) and consume atomic
mental-model skills for governance / reference. Implications
to settle in brainstorm Phase 1:
(a) Producer surface positioned as the molecular workflow
layer of board orchestration;
(b) compose-time discipline — workflow features MUST consult
mental-model atomics rather than re-deriving rules inline
(anti-pattern detection);
(c) future Producer specific roles inherit the same
(workflow, molecular) position by construction.]

## Implementation medium responsibility

[TBD — declarative ownership rules for hook adjuncts and
script adjuncts (the post-redesign successors of v0.4.0's
implementation-medium concept). Single-caller scripts MUST
relocate to `skills/<owner>/scripts/`; multi-caller scripts
remain at plugin-global. Hooks always declare their
"reinforces SKILL X at phase Y" purpose. The
60-percent-misplaced finding for `scripts/` is captured here
as a structural observation; cleanup timing is a separate
Open question.]

## Cross-version evolution

[TBD — how to add a new Producer specific role (the
§1.3.2-reserved Triager / Lint-runner / Refiner). How to add a
new feature within Manager. How to deprecate a feature. The
§1.3.2 reservation pattern matches the Setup-Stages
"future-module inclusion procedure" idiom (registry-only
edits, no SKILL or hook code change). Settled in brainstorm
Phase 1.]

## Open design choices

### Still open

- **Workflow granularity.** Whether each row in the catalog
  is a feature (F-01..F-15, current numbering preserved)
  with workflow as a column, or a workflow step (claim /
  fetch / impl / verify / submit / ...) with features
  dissolved into steps. Default is feature-as-unit (preserves
  continuity with current 03 numbering).
- **Skill-relocation cleanup timing.** Whether to bundle the
  60-percent-misplaced single-caller-script relocation
  (moving them from plugin-global `scripts/` into their
  owner SKILL's bundled `scripts/` directory) into the
  redesign PR, or land it as an independent follow-up after
  redesign ships. Tradeoff: bundled clarity (mental model
  alignment) vs PR scope discipline (smaller, more focused
  PR). Per the new skill-as-primary doctrine, this is an
  *adjunct ownership repair* operation, not a generic
  refactor.
- **Codex Mode-2 dispatch source.** v1 ships Producer as
  Mode-1-only (architect-prompt-driven). Whether the redesign
  reserves Codex Mode-2 dispatch as a future axis value, or
  defers entirely to a future ADR after v1.x demand pulls.

### Decided (by intake conversation, 2026-04-29)

- **Producer is an AI-Agent specific role.** Not a product
  surface; not a class hierarchy; not a daemon. An Agent
  whose specific role is board orchestration.
- **Four orthogonal axes characterizing skill capabilities**
  (per architect's intake first principle, revised
  2026-04-29 mid-design): Axis 1 Agent goal-loop phase
  (cognitive / agentic, anchored to Norman 1988 seven-stage
  action model with `orient` and `surface` extensions);
  Axis 2 workflow (Producer call-driven multi-flow);
  Axis 3 skill nature (`workflow` vs `mental-model` — what
  KIND of SKILL implements this); Axis 4 skill layer
  (`entrypoint` / `molecular` / `atomic` per
  [`../../SKILLS.md`](../../../SKILLS.md) three-layer
  architecture). The earlier "capability vs meta-capability"
  classification (a feature-functional cut) and "skill home"
  (a SKILL identity enumeration) were both replaced — the
  former because skill-nature is the more useful structural
  cut, the latter because identity is downstream of axis
  values, not an axis itself.
- **SKILL is the primary implementation unit; hooks and
  scripts are subordinate adjuncts.** Every Producer feature's
  core lands in a SKILL.md. Hooks exist only as robustness
  adjuncts to specific skill-guided lifecycle phases (a hook
  exists "to make agent execution more robust at this phase
  of this skill's flow"). Scripts are deterministic-mechanism
  resources owned by skills (single-caller skill-bundled;
  multi-caller plugin-global primitives consumed by skills).
  The "execution role choice between skill / hook / script"
  modeling of v0.4.0 was a category error; this redesign
  dissolves it. Ownership rule for adjunct scripts:
  single-caller MUST be skill-bundled; multi-caller MAY be
  plugin-global.
- **`scripts/` is a project convention, not a CC / Codex
  plugin protocol-mandated directory.** Verified against
  [`../../PLUGIN_DEVELOPMENT.md`](../../PLUGIN_DEVELOPMENT.md)
  § 41-237 — neither CC nor Codex manifest references
  `scripts/`. The plugin protocol recognizes `hooks/`,
  `skills/<name>/`, `commands/`, `agents/`, plus the
  manifest dirs (`.claude-plugin/`, `.codex-plugin/`).
- **Mother-protocol form choice (candidate B accepted, 2026-04-29).**
  Extract a mother-layer Session Agent Protocol contract at
  [`../0005-contracts/09-session-agent-protocol.md`](../0005-contracts/09-session-agent-protocol.md).
  Trigger: J1–J5 are 5-of-5 shared between Producer / Consumer
  / Bootstrap surfaces (axis definitions and value enums
  identical; only value distribution and node catalogs
  differ). 5-of-5 sharedness exceeds the original 3-of-4
  threshold that defaulted to candidate B. Mother protocol
  pins J1–J5; this surface declares Producer-specific
  distribution and 26-node catalog without redefining J1–J5.
- **Methodology Stage 1 / 2 / 3 applied to Producer surface
  (2026-04-29).** Per
  [`../../../FEATURE_DESIGN_METHODOLOGY.md`](../../../FEATURE_DESIGN_METHODOLOGY.md):
  Stage 1 enumerates 26 journey nodes A1–G5 in § "Producer
  journey nodes (Stage 1 enumeration)"; Stage 2 positions
  each node on J1–J5 + A1–A2 in § "Producer feature catalog
  (table)"; Stage 3 yields three SKILL-form archetypes
  A/B/C and the final SKILL set in § "Producer SKILL set
  decision (Stage 3 ROI synthesis)". Two structural findings
  landed: (i) F-01 and F-11 are demoted from feature
  catalog to script adjuncts (they were mechanisms, not
  journey nodes); (ii) eight new explicit nodes (B3, C2,
  C3, D2, F1, G1–G5) recovered from methodology
  cross-product. The currently-shipped F-01..F-15 numbering
  remains valid as a parallel index in the shipped 03
  surface; the redesign adds the journey-based A1–G5
  numbering as the canonical Stage 1 / 2 / 3 frame.
- **SKILL decomposition granularity — Shape Y chosen
  (2026-04-29).** Per § "Producer SKILL set decision
  (Stage 3 ROI synthesis)" → "Why per-routine split
  (Shape Y) wins". The current `managing-board` mega-SKILL
  (multi-routine; v0.4.0) **retires** in favor of four
  per-routine sub-molecular SKILLs:
  `briefing-daily` (A1+A2+A3+A4+A5),
  `intaking-requirement` (B1+B3+G4),
  `reviewing-pr-queue` (C1+C2),
  `triaging-board` (C4+C5).
  Decisive dimensions: body-length-budget (450-line ceiling
  pressure on `managing-board` at v1-complete scope),
  trigger description precision (4 disjoint single-semantic
  descriptions vs 1 multi-keyword), and evolution discipline
  (one-routine-one-SKILL pattern stable across v1-complete
  + v1.x). Cross-routine body sharing is absorbed by the
  atomic layer where it structurally belongs.
- **New atomic SKILL `composing-siblings` (2026-04-29).**
  Per § "Producer SKILL set decision" → "New atomic SKILL:
  `composing-siblings`". SPOT consolidates the cross-plugin
  routing decision framework currently triplicated across
  `AGENTS.md`,
  `managing-board/references/skill-routing.md`, and inline
  routine bodies. Quadruples in importance under Shape Y
  because all four new molecular SKILLs consume it.
  Authoring checklist: `SKILL.md` + `references/`
  (routing-table, ADR-0008-compatibility, sibling-skill-
  catalog), `.skill-meta.yaml` (`layer: atomic`,
  `nature: mental-model`, `user-invocable: false`).
- **D-META-1 conversation framework atomic — deferred to
  v1.x (2026-04-29).** Per § "Producer SKILL set decision"
  → "D-META-1 conversation framework — v1.x roadmap".
  At v1-complete scope only 2 callers
  (`intaking-requirement` dispatch-style;
  `decomposing-into-milestones` deliberation-style); the
  two conversation rhythms differ structurally and abstract
  unification at v1-complete loses ROI. Each molecular
  SKILL keeps a private
  `references/<routine>-d-meta-1-mode.md` until v1.x lifts
  the SPOT (trigger: ≥4 callers AND ≥3 share one rhythm).
- **Final v1-complete Producer SKILL set: 12 SKILLs
  (2026-04-29).** Entry layer 1 (`using-board-superpowers`,
  routing table updated for the 4-way fan-out); molecular
  layer 6 (4 new + 2 shipped); atomic layer 5 (4 shipped +
  1 new `composing-siblings`). Authoritative listing in
  § "Producer SKILL set decision" → "Final SKILL set".

## Replacement plan (when this draft is approved)

[TBD — N-step plan to transition this draft into
`03-producer-surface.md`. Companion ADRs recorded; spec
change-impact matrix walked top-to-bottom; SKILLS.md updated
if new specific roles or skill cross-references emerge;
cross-references audited. Mirrors the Replacement plan
section in
[`05-bootstrap-surface.md`](./05-bootstrap-surface.md)
§ "Replacement plan". Settled in Phase 3.]
