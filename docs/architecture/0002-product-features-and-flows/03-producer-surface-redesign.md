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
enums; this surface declares how Producer's 21 journey
nodes (the Stage 1 enumeration per
[`../../../FEATURE_DESIGN_METHODOLOGY.md`](../../../FEATURE_DESIGN_METHODOLOGY.md)
§ "Stage 1 — User-journey node enumeration", pending
explicit catalog) distribute across the J values:

| Axis | Producer distribution |
|------|-----------------------|
| **J1** Trigger actor | 13 `agent-self` (A1–A3, D2, E1–E3, F1, G1–G5) / 9 `architect` (A4, A5, B1–B4, C1, D1, F2) / 4 `nested-within-routine` (C2–C5, all nested in C1 review-queue routine). |
| **J2** Trigger carrier | mixed; `cron-job` heavy on cadence-driven nodes (E1–E3 retro / weekly / hygiene; A1–A3 compute side via compute-present split); `session-hook` for K-budget present-only nodes; `in-process-reflex` for G1–G5; `explicit-prompt` for architect-driven B / C / D / F nodes (sub-mode: prompter = architect, except F-07 dispatch where prompter = Producer-agent in Mode-2). |
| **J3** Autonomy class | A-class for governance reflex (G1–G5), label cleanup, batch dispatch (F-07); R-class for SoT-modifying actions (B4 re-split, F2 harness landing); N-class reserved (zero entries at v1). |
| **J4** D-META-1 strength | wide spread — `low` (G1–G5 governance, A1–A3 mechanism); `medium` (B2 INVEST framing, E1 retro Derby & Larsen template); `high` (B1 design conversation, F2 harness setup). |
| **J5** Result destination | `inject-session` for briefing nodes (A1–A3); `persist-state` heavy (board mutations, audit rows, claim states); `emit-external` for PR comments and dispatched artifacts; `inline-return` exclusive to the 4 nested nodes (C2–C5). |

Per-node J 5-tuple positioning lives in § "Producer feature
catalog (table)" below.

> **Note**: 21 Producer journey nodes (A1–G5) are referenced
> symbolically here; the explicit Stage 1 enumeration is
> pending application as the next round of redesign work.
> This distribution table will be regenerated once the
> enumeration lands.

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

## Producer feature catalog (table)

> **Status**: pending axis-pass sweep. Each of the 15 features
> will be cell-by-cell positioned on the four axes. Format
> mirrors the Stages table in
> [`05-bootstrap-surface-redesign.md`](./05-bootstrap-surface-redesign.md)
> § "Stages".

[TBD — to be filled by axis-pass sweep, brainstorm
convergence pending. The skeleton header row will be:]

| feature_id | feature_name | description | goal_loop_phase(s) | workflow | skill_nature | skill_layer | hook_adjuncts | script_adjuncts | composes_atomics | autonomy_class | introduced_in_version | deprecated_in_version |
|------------|--------------|-------------|--------------------|----------|---------------|-------------|---------------|-----------------|------------------|----------------|----------------------|----------------------|
| ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... |

> **Note**: sample rows intentionally omitted at this draft
> stage. They depend on the redesign's terminal SKILL set,
> which is still settling (see § "Open design choices" →
> "SKILL decomposition granularity"). Filling concrete
> `composes_atomics` / `script_adjuncts` references before
> the SKILL set is final risks freezing names that the
> redesign may change. The full 15-row catalog will be
> filled in the axis-pass sweep once the SKILL decomposition
> question is resolved.

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
- **SKILL decomposition granularity.** Whether to split a
  current multi-routine molecular SKILL into per-routine
  sub-molecular skills, or keep the single-skill multi-routine
  shape. The decision affects Axis 4 value cardinality and
  skill-trigger granularity. Applies to any current molecular
  SKILL whose body covers multiple workflows or lifecycle
  stages.
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
  distribution and 21-node catalog without redefining J1–J5.

## Replacement plan (when this draft is approved)

[TBD — N-step plan to transition this draft into
`03-producer-surface.md`. Companion ADRs recorded; spec
change-impact matrix walked top-to-bottom; SKILLS.md updated
if new specific roles or skill cross-references emerge;
cross-references audited. Mirrors the Replacement plan
section in
[`05-bootstrap-surface-redesign.md`](./05-bootstrap-surface-redesign.md)
§ "Replacement plan". Settled in Phase 3.]
