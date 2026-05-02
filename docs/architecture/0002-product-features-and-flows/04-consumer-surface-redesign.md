### 1.4 Consumer surface — redesign

> **Status — design draft.** This file captures the in-progress
> systematic redesign of the Consumer-side session abstraction.
> It is **not** the source of truth yet. The currently-shipped
> contract still lives in [`04-consumer-surface.md`](./04-consumer-surface.md).
>
> **Terminal state.** Once this draft is approved and the
> companion ADR(s) are recorded, this file's content **replaces**
> `04-consumer-surface.md`. The replacement happens in a single
> PR that also fans out the spec change-impact matrix updates
> listed in [`../AGENTS.md`](../AGENTS.md) § "Spec change-impact
> matrix". At that point this `-redesign` file is removed
> (or `git mv`'d to `04-consumer-surface.md`, overwriting the
> old body).
>
> **Read order.** Read this file in pair with the existing
> `04-consumer-surface.md`. Where this draft contradicts the
> existing surface, this draft expresses **future intent** and
> the existing surface expresses **shipped behavior**. The gap
> between the two is exactly the redesign work.
>
> **Companion**: [`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)
> (paired — both surfaces redesign together because they share
> the underlying AI-Agent substrate). If commonality justifies,
> a mother-layer protocol contract may be extracted as
> `0005-contracts/0X-session-agent-protocol.md` before terminal
> landing — see § "Open design choices" → "Form choice".

---

## Why a redesign

Today's Consumer surface (per [`04-consumer-surface.md`](./04-consumer-surface.md))
has five structural weaknesses that v1-complete makes acutely
visible:

1. **Mode-2 caveats are scattered across the catalog instead of
   factored as platform projection.** Five features (F-C4 /
   F-C8 / F-C10 / F-C11 / F-C13) each carry their own
   per-feature "Mode-2 caveat" block — empirical-verification
   notes, channel-divergence observations, reachability
   warnings, lifecycle-extension caveats. The pattern is
   structural (Mode-1 / Mode-2 is a *runtime projection*, not
   a per-feature concern), but the spec models it as scattered
   exceptions. Adding a future Codex Mode-2 (currently
   out-of-scope) would multiply the scattered footprint by 2x.

2. **Skill nature and skill layer are implicit.** Same paradigm
   gap as Producer (see
   [`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)
   § "Why a redesign" point 2). The current 04 doesn't
   classify Consumer features by skill nature (workflow guide
   vs mental-model framework) or skill layer (entrypoint /
   molecular / atomic). Empirically all 14 Consumer features
   sit uniformly at (workflow, molecular); the mental-model
   skills they consume (state machine + branch naming + Card
   schema reference, autonomy classification matrix, PR
   contract validation rules, audit schema + write
   conventions) live in the atomic layer external to Consumer
   surface. Surfacing the (workflow, molecular) uniformity
   locates Consumer in the SKILL graph and constrains
   future-feature placement decisions.

3. **SKILL implementation is implicit; hooks and scripts read
   as peers instead of subordinates.** Same paradigm fault as
   Producer — see [`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)
   § "Why a redesign" point 3. Consumer-specific manifestation:
   several Consumer-only scripts squat at plugin-global
   `scripts/` despite having a single SKILL caller, instead
   of being skill-bundled. The flat-listing of "skill / hook /
   script" as peer implementation choices in current 04
   obscures the hierarchical reality: every feature's core IS
   a skill; hooks and scripts are subordinate adjuncts.

4. **Cross-cutting governance pattern (P8) is not factored.**
   Four features (F-C5 TDD-skip, F-C6 cross-card refuse, F-C7
   permission boundary, F-C13 stakeholder routing) are P8
   instances (Default + override + accountability), but each
   spells out its own override-and-justify protocol in
   per-feature prose. P8 is now a positioning premise
   ([`../0001-positioning.md`](../0001-positioning.md) § P8) —
   the redesign should make Consumer's P8 instances declare
   themselves through a shared schema, not duplicate the
   pattern's prose.

5. **Implicit AI-Agent abstraction.** Consumer Session is
   modeled as a "product surface" (14 features in 5 thematic
   groups). The deeper truth — Consumer is an AI Agent
   specific role, kanban-relative — is not surfaced. Every
   feature reads as a standalone product capability rather
   than as one slice of a unified Agent-Session substrate.
   The implicit abstraction makes adding new specific roles
   (the §1.4.2-reserved Reviewer / Bisector / Migration-runner)
   costly — there is no shared substrate to inherit from.

## Goals

The redesign pursues four architect-stated goals (intake
direction, 2026-04-29) — paired with
[`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)'s
goals because both surfaces inherit the same first principle:

**G1 — Recognize Consumer as an AI-Agent specialization.**
Consumer Session is the Agent's kanban-relative role for
single-card delivery. All features are specializations of an
Agent-Session substrate; the substrate's primitives (goal-loop
phase, skill nature, skill layer, hook / script adjuncts
subordinate to skills, mode-projection contract) are
surfaced as first-class concerns of the Consumer spec.

**G2 — Identify orthogonal axes that pin down feature
identity.** Each feature is positioned by a 4-tuple
`(goal-loop-phase, workflow-stage, skill-nature,
skill-layer)`, plus a per-feature Adjuncts attribute (hook
adjuncts + script adjuncts). Per architect's directive "all
dimensions together should determine a skill", the axis
combination identifies the SKILL implementation; adjuncts
describe the implementation's robustness aids without
forming an independent axis. The axes are abstract structural
positions — Axis 4 names the SKILL's layer (entrypoint /
molecular / atomic), not the SKILL's basename; basenames are
downstream of axis values + implementation choice.

**G3 — Distinguish skill nature from skill layer
explicitly.** Same goal as Producer (see
[`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)
§ "Goals" G3 for the full narrative). Consumer-specific:
all 14 features cluster at (workflow, molecular); mental-model
atomics (state-machine reference, autonomy classification,
PR-contract validation, audit conventions) are external
dependencies referenced via each feature's `composes_atomics`
attribute. The uniformity along Axis 3 / 4 within Consumer
surface is itself a structural finding — Consumer surface IS
the molecular workflow projection of card-consumption against
an atomic mental-model substrate.

**G4 — Recognize SKILL as the primary implementation unit;
hooks and scripts as subordinate adjuncts; lift Mode topology
to platform-projection contract.** Every Consumer feature's
core lands in a SKILL.md (Axis 4 — Skill layer identifies
its structural position; identical treatment to Producer). Hooks exist only as **robustness
adjuncts** to specific skill-guided lifecycle phases. Scripts
are **deterministic-mechanism resources** owned by skills —
single-caller skill-bundled, multi-caller plugin-global
primitives consumed by skills. The implicit "execution role
choice" of v0.4.0 (skill OR hook OR script as peer
alternatives) is dissolved. Independently: the Mode-1 /
Mode-2 distinction is **lifted out of per-feature caveats**
into a single platform-projection contract (§ "Trigger model"),
restoring the catalog to platform-agnostic agentic descriptions.

## The orthogonal axes

The Consumer feature catalog is positioned along **two
coordinate systems**, identical structure to
[`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)
§ "The orthogonal axes":

1. **Requirement-layer axes (J1–J5)** — defined canonically
   in
   [`../0005-contracts/09-session-agent-protocol.md`](../0005-contracts/09-session-agent-protocol.md)
   (the Session Agent Protocol mother contract introduced
   alongside this redesign): trigger actor / trigger carrier
   / autonomy class / D-META-1 strength / result destination.
   This surface inherits J1–J5 by reference and does not
   redefine them. § "J1–J5 distribution observation" below
   records Consumer-specific value distribution.
2. **SKILL-layer axes (A1–A4)** — four axes describing
   *the SKILL that may implement* a node, retained inline:
   A1 Agent goal-loop phase / A2 Workflow stage / A3 Skill
   nature / A4 Skill layer. A2 (workflow stage) has a
   different shape from Producer's — Consumer is
   **lifecycle-driven** (single flow, multi-stage); Producer
   is **call-driven** (multi-flow, cross-cutting features).
   A1, A3, A4 are shape-identical to Producer.

The two coordinate systems are **independent**: J1–J5
locate the **node** (the requirement); A1–A4 locate the
**SKILL** (the artifact that may implement the node). The
ROI function in
[`../../../FEATURE_DESIGN_METHODOLOGY.md`](../../../FEATURE_DESIGN_METHODOLOGY.md)
is the only place where the two systems combine.

Cross-axis sparsity is the value of the catalog table form.

### J1–J5 distribution observation (requirement-layer)

The mother protocol defines J1–J5 dimensions and value
enums; this surface declares how Consumer's 23 journey
nodes (the Stage 1 enumeration per
[`../../../FEATURE_DESIGN_METHODOLOGY.md`](../../../FEATURE_DESIGN_METHODOLOGY.md)
§ "Stage 1 — User-journey node enumeration") distribute
across the J values.

Consumer's distribution differs from Producer's in shape
because Consumer is **lifecycle-driven, single-card,
single-session**: most nodes fire automatically as the
agent self-progresses through the lifecycle; architect-class
nodes are concentrated at review-feedback / surface-answer
boundaries; `cron-job` carrier is rare (Consumer sessions
are typically short-lived, not cadence-driven).

| Axis | Consumer distribution |
|------|------------------------|
| **J1** Trigger actor | nested-heavy — implementation stage hosts multiple nested test / debug / verify sub-nodes; `agent-self` for inter-stage transitions; `architect`-class concentrated on review-feedback and surface-answer; `explicit-prompt` rare. |
| **J2** Trigger carrier | `session-hook` for SessionStart card-context injection; `in-process-reflex` heavy (every mutating sub-node fires governance reflex); `cron-job` rare (long-stuck self-surface case only); `explicit-prompt` for architect review-feedback and Producer-agent dispatch (Mode-2 sub-mode). |
| **J3** Autonomy class | A-class for routine TDD-driven mutations and self-check; R-class for SoT-modifying actions (PR submit, branch deletion, post-merge cleanup); N-class reserved. |
| **J4** D-META-1 strength | `low`-dominated — Consumer is an executor, ships mechanism (claim protocol, PR three-section template, AC sync rule); few `medium` nodes (TDD handoff to `superpowers`); near-zero `high` nodes (Consumer does not elicit architect taste). |
| **J5** Result destination | `emit-external` heavy (commit, push, PR creation, PR-comment posting); `persist-state` for card body / claim marker / audit rows; `inject-session` rare (only on `surface` escalation); `inline-return` for nested phase transitions inside implementation. |

Per-node J 5-tuple positioning lives in § "Consumer feature
catalog (table)" below.

> **Note**: the 23 Consumer journey nodes (A1–G5) are
> enumerated in § "Consumer journey nodes (Stage 1
> enumeration)" below; per-node J 5-tuple positioning is in
> § "Consumer feature catalog (table)" further below.

### Axis 1 — Agent goal-loop phase

What cognitive phase is the agent in, **with respect to the
current goal**? This axis is **agentic, not platform-mechanical**.
It does not classify hook events, runtime modes, or process
states — those are *triggers* for entering a phase, captured
separately in § "Trigger model". Together with Axis 2-4, Axis 1
locates the agent's *mindset* at a stage.

The 9 phases are anchored to Norman 1988 *The Design of
Everyday Things* seven-stage action model
(<https://www.nngroup.com/articles/seven-stages-action/>),
extended with `orient` (pre-intention context-gathering) and
`surface` (uncertainty-driven escalation). Identical
definitions to Producer's Axis 1 — see
[`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)
§ "Axis 1 — Agent goal-loop phase" for the per-phase
definitions. The 9 phases:

- Reception: `receive`, `orient`
- Engagement (active loop): `plan`, `act`, `observe`, `reflect`
- Side branch: `surface`
- Closing: `verify`, `conclude`

**Consumer-specific note**: Consumer's full lifecycle exercises
*all 9* phases on the canonical card-consumption flow. Producer
tends to skip `surface` and `conclude` on read-only routines.
This is a Consumer/Producer shape difference but uses the same
phase vocabulary.

### Axis 2 — Workflow stage

Which stage of the card-consumption flow does this feature
occupy? Consumer's Axis 2 has a different shape from
Producer's: Consumer features each occupy **exactly one** stage
of one canonical flow (`card-consumption`); Producer features
can compose **multiple** workflows (a single feature like F-01
serves daily / decompose-handoff / triage). The asymmetry is a
structural finding:

- Consumer is **lifecycle-driven** — single flow, multiple
  stages.
- Producer is **call-driven** — multiple flows, features
  compose across.

Consumer workflow stages (5 values, one per feature):

- **`bootstrap`** — kickoff, claim, spec fetch, worktree
  entry. Currently Group A in `04-consumer-surface.md`.
- **`implementation`** — TDD-driven impl, governance gates,
  surface protocol. Currently Group B.
- **`self-check`** — pre-submit verification chain,
  cross-platform review, conditional QA / security passes.
  Currently Group C.
- **`pr-cycle`** — PR submission with mandatory sections,
  review-cycle response. Currently Group D.
- **`termination`** — close-out (success / failure / crash
  paths), heartbeat. Currently Group E.

The 5-stage Consumer flow is itself the canonical flow
documented in `02-roles.md` § "Card consumption flow"; this
axis preserves the existing Group A-E thematic breakdown.

### Axis 3 — Skill nature

What kind of SKILL implements this feature? Same definition as
Producer (Axis 3) — see
[`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)
§ "Axis 3 — Skill nature" for the full narrative. Two values:
`workflow` (procedural guide the agent executes) vs
`mental-model` (thought framework the agent consults).

Consumer empirical observation: **all 14 Consumer features
are workflow-natured** — they are lifecycle stages inside a
single molecular workflow SKILL. The mental-model skills they
consume (state-machine + branch-naming + Card schema
reference; autonomy classification matrix; PR-contract
validation rules; audit schema + write conventions) are
atomic-layer external dependencies, not Consumer features.
They appear in each feature's `composes_atomics` attribute,
not as Consumer-surface rows.

The previous edit-cycle's classification of F-C13 as "mixed"
(both capability and meta-capability) is dissolved under the
new framing: F-C13 is workflow-natured (a procedural response
loop), and the scope-judgment portion is a mental-model atomic
that F-C13 should compose (currently inlined as prose; future
ADR may extract it as a separate atomic).

### Axis 4 — Skill layer

Where in the SKILL graph does this feature's SKILL sit? Same
definition as Producer (Axis 4) — see
[`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)
§ "Axis 4 — Skill layer" for the full narrative. Three
values: `entrypoint` / `molecular` / `atomic`, mirroring
existing
[`../../SKILLS.md`](../../../SKILLS.md) three-layer
architecture.

Consumer empirical observation: **all 14 Consumer features
sit at `molecular` layer**. The atomic mental-model
dependencies appear in `composes_atomics`, not as Consumer
rows.

The single-layer uniformity within Consumer surface is
structural: Consumer surface IS the molecular workflow layer
for card consumption. Future Consumer specific roles (the
§1.4.2-reserved Reviewer / Bisector / Migration-runner) will
also land at molecular by construction. Whether to split a
multi-stage molecular SKILL into per-stage sub-molecular
skills is a separate decision (see § "Open design choices" →
"SKILL decomposition granularity").

The earlier-iteration "SKILL home" framing (naming the
SKILL.md basename as an axis value) is dropped — basenames
are identity, not structural dimension.

### Adjuncts (attribute, not axis)

Same definition as Producer — see
[`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)
§ "Adjuncts" for the full narrative.

Consumer-specific misplacement (current state, names elided
to avoid premature commitment): several Consumer-only scripts
currently squat at plugin-global `scripts/` despite having a
single SKILL caller. Per the adjunct ownership rule
("single-caller MUST be skill-bundled; multi-caller MAY be
plugin-global"), they should relocate to skill-bundled
location once the redesign's terminal SKILL set is settled.
The concrete file list is captured in the Replacement plan
when the SKILL decomposition decision is made; each affected
feature's `script_adjuncts` field will carry a `*-misplaced`
suffix in the catalog row until relocation lands.

### Axes orthogonality self-check (SKILL-layer)

Each pair of A1–A4 (SKILL-layer) axes is independent.
**J1–J5 orthogonality is verified by the mother protocol**
([`../0005-contracts/09-session-agent-protocol.md`](../0005-contracts/09-session-agent-protocol.md)
§ "Cross-axis legal-combination matrix"); this surface does
not re-verify J1–J5 orthogonality.

For A1–A4 (the four axes inlined in this surface):

- A1 ⊥ A2: an `act` phase serves multiple workflow stages
  (claim's `act` is F-C1's atomic push; impl's `act` is
  F-C4's TDD step; submit's `act` is F-C12's PR open).
- A1 ⊥ A3: an `orient` phase can be hosted by either
  workflow SKILL (procedural narrative for fetching context)
  or mental-model SKILL (the consulted schema reference
  during the orient). The phase-vs-nature combination is
  free.
- A2 ⊥ A3: every workflow stage contains workflow-natured
  feature steps that compose mental-model atomics —
  implementation stage's TDD-driven mutations (workflow
  nature) consult an autonomy classification atomic
  (mental-model nature) for autonomy class on every
  mutation.
- A3 ⊥ A4: although currently strongly correlated
  (Consumer's workflow features all sit at molecular;
  consumed mental-model atomics all sit at atomic), the
  redesign treats them as independent because future shapes
  can break the correlation (a molecular mental-model
  framework spanning Consumer's lifecycle; an atomic
  workflow primitive callable from multiple molecular
  Consumer variants). Same as Producer's A3⊥A4 self-check.
- A1 / A2 / A3 ⊥ A4: any cognitive phase × any workflow
  stage × any nature can in principle sit at any layer.
  Empirical: Consumer features span all 9 goal-loop phases
  (`receive` through `conclude`) and all 5 workflow stages
  (bootstrap through termination), uniformly at (workflow,
  molecular). The single-cell uniformity within Consumer
  surface is itself a finding — see Axis 4 empirical
  observation above.

## Consumer journey nodes (Stage 1 enumeration)

This section is the **Stage 1 output** per
[`../../../FEATURE_DESIGN_METHODOLOGY.md`](../../../FEATURE_DESIGN_METHODOLOGY.md)
§ "Stage 1 — User-journey node enumeration": the
implementation-agnostic list of every discrete intent the
Consumer surface must satisfy, expressed as **two
complementary lists** (human-initiated +
agent-self-initiated) plus their cross-product
(cross-cutting governance).

Consumer enumeration produces **23 journey nodes** in seven
groups, organized by lifecycle stage (Groups A–E mirror the
five workflow stages declared in § "Axis 2 — Workflow stage")
plus one stakeholder-loop node (Group F) and the shared
cross-cutting governance group (Group G). The numbering
scheme (A1–G5) is internal to this enumeration and
orthogonal to the F-C0..F-C14 numbering in the
currently-shipped 04 surface (which is feature-grouped, not
journey-grouped). Both numbering schemes coexist during the
redesign window — the shipped surface keeps F-C0..F-C14 as
its row index; this redesign uses A1–G5 as its
journey-node index. Cross-references between the two appear
in § "Consumer feature catalog (table)" below.

### Group A — Bootstrap (3 nodes)

What the Consumer agent does on session start, before
implementation begins.

- **A1** — Receive card assignment: Mode-1 (architect
  explicit prompt with `[board-card:#N]`) or Mode-2
  (Producer-agent dispatch via `Agent` tool spawn).
  Session lifecycle starts here.
- **A2** — Atomic claim + worktree entry: branch push as
  claim primitive (per
  [ADR-0002](../adr/0002-claim-via-branch-push.md)) +
  worktree creation at the canonical path (per
  [ADR-0003](../adr/0003-worktree-per-consumer.md)).
- **A3** — Spec fetch: thin pointer in card body resolved
  to actual spec document(s); plan brief location set up
  per `consuming-card` skill convention.

### Group B — Implementation (5 nodes)

The active implementation cycle, including in-flight
discipline reflexes.

- **B1** — Plan synthesis: delegate to
  `superpowers:writing-plans` for the executable
  TDD-driven plan.
- **B2** — TDD-driven mutation cycle: delegate to
  `superpowers:test-driven-development` for the
  Red → Green → Refactor loop on each acceptance
  criterion.
- **B3** — TDD-skip refusal (governance reflex):
  in-flight discipline that refuses to bypass TDD even
  when implementation feels "obvious" — preserves the
  verification chain's integrity per P8.
- **B4** — Cross-card refusal (boundary reflex): edits
  restricted to the card's slice; refuses to modify files
  claimed by other cards or shared infrastructure without
  explicit authorization.
- **B5** — Permission-boundary preservation (governance
  reflex): cannot bypass D-AUTONOMY-1 classification "for
  convenience" — every mutating action passes through the
  autonomy classifier.

### Group C — Self-check (4 nodes)

The pre-submit verification chain, including conditional
external-skill passes.

- **C1** — Verification chain: delegate to
  `superpowers:verification-before-completion` +
  `superpowers:requesting-code-review` +
  `gstack:/review` for the evidence-first pre-PR chain.
- **C2** — Cross-platform review: CC sessions dispatch to
  `gstack:/codex` (and Codex sessions dispatch to a
  CC-equivalent) for an adversarial second-platform pass.
- **C3** — Conditional QA: `gstack:/qa <url>` for any
  UI-touching card; gated by card-label heuristic.
- **C4** — Conditional security audit: `gstack:/cso` for
  security-flagged cards (label or path-based detection).

### Group D — PR cycle (3 nodes)

PR submission and review-feedback handling.

- **D1** — PR submit with three-section contract: PR body
  MUST contain `## Automated Verification` (required) +
  `## Human Verification TODO` (optional but no-filler) +
  `## Retro Notes` (required when reusable lessons exist),
  per the `enforcing-pr-contract` atomic SPOT.
- **D2** — Card body AC terminal-state sync: every
  acceptance criterion must be `[x]` or `[!]<reason>` at
  PR-submit time; bare `[ ]` is forbidden.
- **D3** — Review-feedback response loop: when Producer
  review returns the card to In Progress, agent integrates
  feedback, re-runs the verification chain, re-submits.

### Group E — Termination (2 nodes)

Session close-out paths, both happy and crash.

- **E1** — Post-merge cleanup: branch delete + worktree
  delete + claim marker delete + final audit row.
- **E2** — Crash / failure path: abnormal exit handling
  (timeout, error, system crash) — heartbeat row +
  partial-state recovery hint persisted for next session
  pickup.

### Group F — Stakeholder loop (1 node)

Mid-implementation external feedback handling.

- **F1** — Stakeholder routing: when external feedback
  arrives mid-implementation (PR comment, Slack message,
  architect surface), agent decides "integrate within
  current card slice" vs "escalate as cross-card touch"
  vs "defer to follow-up card."

### Group G — Cross-cutting governance (5 nodes — substrate shared with Producer)

These nodes do not appear in the human-initiated list
directly. They are surfaced from the **cross-product** of
"human-initiated × agent-self-initiated" lists per
[`../../../FEATURE_DESIGN_METHODOLOGY.md`](../../../FEATURE_DESIGN_METHODOLOGY.md)
§ "Two complementary lists are mandatory". Producer's G1–G5
and Consumer's G1–G5 share the same atomic SKILL substrate
(`auditing-actions` + `classifying-actions`) — only the J
distribution differs.

- **G1** — Every mutating action is auditable
  (post-action audit row, atomic reflex).
- **G2** — R-class actions surface a proposal awaiting
  architect reply (pre-action propose-resolve, atomic
  reflex).
- **G3** — A-class actions execute without architect
  interruption (pre-action gate, atomic reflex; folded
  into G2's classifier in implementation).
- **G4** — Mode topology surfacing (Mode-1 / Mode-2
  projection): Mode-1 (architect-prompt-driven) vs Mode-2
  (Producer-agent dispatch via subagent spawn). Mode-2
  caveats previously scattered across F-C4 / F-C8 /
  F-C10 / F-C11 / F-C13 are factored here as a single
  trigger-model concern.
- **G5** — Cross-platform parity (CC / Codex same
  semantics; `bsp_plugin_root()` equivalents abstract
  platform-specific paths).

### Two-list provenance summary

A–F come from the **human-initiated list** (what the
architect wants Consumer to do for the card) plus the
agent's lifecycle phases that follow each architect
trigger. G1–G5 come from the **cross-product** with the
agent-self-initiated list. The 3+5+4+3+2+1 / 5 = 18 + 5
shape is Consumer-specific — Producer's surface produced
21 nodes (5+4+5+2+3+2 + 5); the lifecycle-driven shape of
Consumer concentrates more nodes inside the implementation
stage (5 nodes B1–B5) and produces fewer in the
non-implementation stages.

## Consumer feature catalog (table)

The Stage 2 + Stage 3 output: each of the 23 journey nodes
positioned on J1–J5 (requirement-layer) plus A1–A2
(SKILL-layer; A3 and A4 omitted because all 23 nodes
empirically resolve to A3=`workflow` × A4=`molecular`, per
the empirical observations in § "Axis 3 — Skill nature"
and § "Axis 4 — Skill layer" above).

Per-node ROI archetype (A / B / C) is shown in the last
column with its candidate SKILL home.

> **Notation key**: same as Producer's catalog — see
> [`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)
> § "Producer feature catalog (table)" notation key block.
> Mother-protocol J1–J5 enums are pinned in
> [`../0005-contracts/09-session-agent-protocol.md`](../0005-contracts/09-session-agent-protocol.md).

| ID | Name | J1 | J2 | J3 | J4 | J5 | A1 phases | A2 workflow stage | Archetype + SKILL home |
|----|------|-----|-----|-----|-----|-----|-----------|-------------------|------------------------|
| **A1** | Receive card assignment | architect (Mode-1) or nested (Mode-2 dispatched) | session-hook (`INVOKE: consuming-card`) or explicit-prompt | A | low | inject-session (card briefing) | receive → orient | bootstrap | C → fold into `consuming-card` (lifecycle entry) |
| **A2** | Atomic claim + worktree entry | nested | in-process-reflex (`claim-card.sh`) | A (per ADR-0002) | low | persist-state (claim marker + branch on remote) | act → observe | bootstrap | C → fold into `consuming-card`; mechanism delegated to `scripts/claim-card.sh`; branch naming SPOT in `board-canon` |
| **A3** | Spec fetch | nested | in-process-reflex (file read) | N/A (read-only) | low | inline-return (spec content) | orient | bootstrap | C → fold into `consuming-card` |
| **B1** | Plan synthesis (delegate) | nested | in-process-reflex (Skill tool: `superpowers:writing-plans`) | A | medium | inline-return (plan brief) | plan | implementation | C → fold into `consuming-card`; cross-plugin routing via `composing-siblings` atomic |
| **B2** | TDD-driven mutation cycle (delegate) | nested | in-process-reflex (Skill tool: `superpowers:test-driven-development`) | A (each mutation per ADR-0006 rows 100+) | low | persist-state (commits) + emit-external (push) | act → observe → reflect (loop) | implementation | C → fold into `consuming-card` |
| **B3** | TDD-skip refusal (governance reflex) | nested | in-process-reflex | N/A (refusal of override) | low (rule) | inline-return (gate signal) | reflect (gate) | implementation | C → fold into `consuming-card` (refusal pattern; SPOT not yet structurally same across B3/B4/B5 — defer atomic lift to v1.x if a 3-caller same-rhythm pattern emerges) |
| **B4** | Cross-card refusal (boundary reflex) | nested | in-process-reflex | N/A (refusal) | low (rule) | inline-return (gate signal) | reflect (gate) | implementation | C → fold into `consuming-card` |
| **B5** | Permission-boundary preservation (governance reflex) | nested | in-process-reflex | N/A (gate of D-AUTONOMY-1) | low (rule) | inline-return (gate signal) | reflect (gate) | implementation | C → fold into `consuming-card`; classification reflex delegated to `classifying-actions` atomic |
| **C1** | Verification chain (delegate) | nested | in-process-reflex (Skill tools: `superpowers:verification-before-completion` + `requesting-code-review` + `gstack:/review`) | A | low | inline-return (verification artifacts) | verify | self-check | C → fold into `consuming-card`; cross-plugin routing via `composing-siblings` atomic |
| **C2** | Cross-platform review (delegate) | nested | in-process-reflex (Skill tool / explicit-prompt to sibling platform) | A | medium | emit-external (review notes posted on PR) | verify | self-check | C → fold into `consuming-card`; cross-plugin routing via `composing-siblings` atomic |
| **C3** | Conditional QA (delegate) | nested (gated by card label) | in-process-reflex (Skill tool: `gstack:/qa <url>`) | A | medium | emit-external (QA report) | verify | self-check | C → fold into `consuming-card`; cross-plugin routing via `composing-siblings` atomic |
| **C4** | Conditional security audit (delegate) | nested (gated by card label / path) | in-process-reflex (Skill tool: `gstack:/cso`) | A | medium | emit-external (security report) | verify | self-check | C → fold into `consuming-card`; cross-plugin routing via `composing-siblings` atomic |
| **D1** | PR submit with three-section contract | nested | in-process-reflex (atomic SKILL: `enforcing-pr-contract`) | R (per ADR-0006 — PR open is SoT-modifying) | low (mechanism: contract validation) | persist-state (card body sync) + emit-external (PR open) | act → verify → conclude | pr-cycle | A → atomic SKILL: `enforcing-pr-contract` (shipped — used here as SPOT) |
| **D2** | Card body AC terminal-state sync | nested (within D1) | in-process-reflex (within `enforcing-pr-contract`) | R (with D1; SoT-modifying) | low (rule) | persist-state (card body) | reflect → act | pr-cycle | C → folded into D1's atomic SKILL `enforcing-pr-contract` |
| **D3** | Review-feedback response loop | architect (Producer's review returns the card) | explicit-prompt (Producer comment / status flip) | mixed (A integrate / R re-submit) | low | persist-state (additional commits) + emit-external (reply comment) | receive → orient → plan → act → verify | pr-cycle | C → fold into `consuming-card` |
| **E1** | Post-merge cleanup | nested or cron-fired | in-process-reflex (within `consuming-card`) or cron-job (`post_merge_cleanup` config; per ADR-0027) | A (per ADR-0006 row) | low (mechanism) | persist-state (state.yml + audit) + emit-external (branch / worktree delete) | conclude | termination | C → fold into `consuming-card`; mechanism delegated to per-routine cron helper script (compute / present split) |
| **E2** | Crash / failure path | nested (heartbeat / abnormal exit handler) | in-process-reflex | A (heartbeat audit row) | low | persist-state (heartbeat row + partial-state recovery hint) | conclude (abnormal) | termination | C → fold into `consuming-card` |
| **F1** | Stakeholder routing | nested or architect-triggered | in-process-reflex or explicit-prompt | mixed (A integrate within slice; R if cross-card touch needed) | high (D-META-1: scope judgment is architect taste) | inject-session (proposal for cross-card escalation) + emit-external (acknowledge stakeholder) | reflect → plan → surface | (cross-stage) | C → fold into `consuming-card`; scope-judgment knowledge inline (1 caller; SPOT threshold not met). v1.x lift candidate: `scope-judgment` atomic if cross-routine reuse emerges. |
| **G1** | Audit row on every mutating action | nested | in-process-reflex | N/A (record, not action) | low (schema) | persist-state (audit DB) | act (record reflex) | N/A | A → atomic SKILL: `auditing-actions` (shipped v0.3.0 — shared with Producer's G1) |
| **G2** | R-class propose-await | nested | in-process-reflex | R (governs R class) | low | inject-session (proposal) + persist-state (proposal audit row) | reflect → surface | N/A | A → atomic SKILL: `classifying-actions` (shipped v0.3.0 — shared with Producer; G2 + G3 share the classifier) |
| **G3** | A-class no-interrupt gate | nested | in-process-reflex | A (governs A class) | low | persist-state (audit) | reflect | N/A | C → folded into `classifying-actions` (G2 + G3 share the classifier reflex) |
| **G4** | Mode topology surfacing | nested (every Mode-2-sensitive action) | in-process-reflex | N/A (projection) | low | inline-return (mode signal) | act (helper) | N/A | C → fold into `consuming-card` body. v1.x lift candidate: `mode-projection` atomic when caller count reaches ≥2 (e.g., when Producer overnight-dispatch ships). |
| **G5** | Cross-platform parity | nested | in-process-reflex | N/A | low (path / hook resolution) | inline-return | act (helper) | N/A | C → script-only: `scripts/lib/common.sh` (`bsp_plugin_root()` etc.), NOT a SKILL — same script as Producer's G5 |

### Cross-references to F-C0..F-C14 (currently-shipped surface)

For backward-compatibility while the redesign is in draft,
this table maps A1–G5 to the currently-shipped F-C0..F-C14
numbering:

| A1–G5 | F-C0..F-C14 | Notes |
|-------|-------------|-------|
| A1 | F-C0 (claim entry — Mode-1 / Mode-2 startup) | Direct mapping |
| A2 | F-C1 (atomic claim) + F-C3 (worktree entry) | Composed mapping |
| A3 | F-C2 (spec fetch) | Direct mapping |
| B1 | (no F-C-equivalent — implicit at F-C4 entry as `superpowers:writing-plans` handoff) | New explicit node from methodology |
| B2 | F-C4 (TDD-driven implementation) | Direct mapping |
| B3 | F-C5 (TDD-skip refusal) | Direct mapping |
| B4 | F-C6 (cross-card refusal) | Direct mapping |
| B5 | F-C7 (permission boundary) | Direct mapping |
| C1 | F-C8 (verification chain entry) + F-C9 (verification execution) | Composed mapping |
| C2 | F-C10 (cross-platform review) | Direct mapping |
| C3 | F-C11 conditional QA branch | Split from F-C11 into C3 + C4 |
| C4 | F-C11 conditional security branch | Split from F-C11 into C3 + C4 |
| D1 | F-C12 (PR submit) | Direct mapping |
| D2 | F-C12 Step 9.5 (card body AC sync) | Direct mapping (sub-step of F-C12) |
| D3 | (no F-C-equivalent — implicit in F-C12 review-cycle) | New explicit node |
| E1 | F-C14 termination — post-merge branch | Direct mapping |
| E2 | F-C14 termination — crash branch | Direct mapping |
| F1 | F-C13 (stakeholder routing) | Direct mapping |
| G1–G5 | (no F-C-equivalent — cross-cutting concerns surfaced by methodology cross-product; substrate shared with Producer's G1–G5) | New explicit nodes from methodology |

Two structural findings from the cross-reference:

1. **Methodology recovers 7 nodes lost to thematic
   grouping.** B1 (plan synthesis), D3 (review-feedback
   loop), G1–G5 (cross-cutting governance) have no
   F-C-equivalent in the currently-shipped 04. They are
   nodes the F-C0..F-C14 grouping missed — by
   under-enumeration (B1 plan synthesis was "implicit at
   F-C4 entry"; D3 review-feedback was "implicit in F-C12
   review-cycle") or cross-cutting surfacing (G1–G5).
2. **F-C11 splits into 2 distinct nodes.** F-C11
   "conditional QA / security" combined two conditional
   passes (UI / security) under one feature; methodology
   Stage 1 splits them into C3 (QA, gated by UI label,
   dispatching `gstack:/qa`) and C4 (security audit,
   gated by security label / path, dispatching
   `gstack:/cso`) because they have different gating
   heuristics and different sibling-skill targets.

## Consumer SKILL set decision (Stage 3 ROI synthesis)

Applying the ROI function (per
[`../../../FEATURE_DESIGN_METHODOLOGY.md`](../../../FEATURE_DESIGN_METHODOLOGY.md)
§ "Stage 3 — Derivation function (ROI)") to each of the 23
nodes yields the archetype distribution below. Strict
re-evaluation under v1-complete scope (architect intake
2026-04-29, post-methodology) confirms Consumer's
**lifecycle-driven single-session** structure — Producer's
"routine-as-archetype-A" promotion (per
[`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)
§ "Producer SKILL set decision") does NOT replicate to
Consumer's stages because Consumer stages are internal
lifecycle phases, not user-facing call-points.

### Archetype distribution (v1-complete scope)

| Archetype | Count | Nodes |
|-----------|-------|-------|
| **A — MUST own SKILL** (independent molecular or atomic) | 4 | D1 → atomic `enforcing-pr-contract` (shipped); G1 → atomic `auditing-actions` (shipped); G2 → atomic `classifying-actions` (shipped); `consuming-card` host SKILL itself (shipped) → archetype A by virtue of hosting all 19 fold-in nodes plus the lifecycle orchestration logic (high gap × extreme freq × high fail-cost). |
| **C — fold into other** | 19 | A1, A2, A3 → fold into `consuming-card`; B1, B2, B3, B4, B5 → fold into `consuming-card`; C1, C2, C3, C4 → fold into `consuming-card`; D2 → fold into `enforcing-pr-contract`; D3 → fold into `consuming-card`; E1, E2 → fold into `consuming-card`; F1 → fold into `consuming-card` (scope-judgment inline; 1 caller below SPOT threshold); G3 → fold into `classifying-actions`; G4 → fold into `consuming-card`; G5 → script-only (`scripts/lib/common.sh`, deterministic mechanism). |

**Strict ROI corrections** versus the prior Stage 3 draft:

- **F1 archetype B → C.** The prior draft tagged F1 as
  archetype-B candidate for a thin `scope-judgment` router
  SKILL. Strict ROI re-evaluation: caller count = 1 (F1
  itself), SPOT threshold not met. The scope-judgment
  knowledge inlines into `consuming-card`'s F1 section
  until v1.x cross-routine reuse emerges (e.g., a future
  Triager-like specific role that also performs
  in-slice-vs-cross-card decisions).
- **G3 archetype A → C.** The prior draft tagged G3 as
  archetype-A "folded into `classifying-actions`" — that
  phrasing is structurally an archetype-C (fold into G2's
  atomic). The atomic SKILL is `classifying-actions`
  serving G2; G3 is one of its consumed code paths, not a
  separate SKILL candidate.

**Archetype-B count is 0** at v1-complete scope. Every node
is either archetype-A (independent SKILL) or archetype-C
(fold into another SKILL or script). Archetype-B remains a
valid form for v1.x landings (e.g., the future
`scope-judgment` atomic if cross-routine reuse emerges) but
no v1-complete Consumer SKILL ships in archetype-B shape.

### Why Shape X (mega `consuming-card`) wins — and why this is NOT inconsistent with Producer's Shape Y

The Stage 3 SKILL set shape decision lands **Shape X**
(single mega-`consuming-card`), the **opposite** of
Producer's Shape Y per-routine split. This is not a
methodology inconsistency; it is the methodology correctly
detecting **two surfaces with structurally different
shapes**.

| Dimension | Shape X — mega `consuming-card` (**chosen**) | Shape Y — per-stage 6 SKILL split |
|-----------|----------------------------------------------|-----------------------------------|
| Trigger description precision | 1 user-facing trigger (`[board-card:#N]` / "claim card N" / "work on card N"); the 5 stages (bootstrap / impl / self-check / pr-cycle / termination) are **internal time-ordered phases**, not independent user-facing trigger points | 6 stage SKILLs **cannot have non-overlapping user-facing trigger phrases** — the architect does not say "now do self-check" or "now do termination". This violates SKILL_DEVELOPMENT.md "description = WHEN, not WHAT" first principle. |
| Lifecycle coherence | Single orchestrator agent owns the full receive → conclude lifecycle; plan → tests → impl → verify → PR chain flows linearly inside the body | 5+ cross-SKILL handoffs per card; each handoff serializes lifecycle context across SKILL boundaries; introduces per-edge handoff contract maintenance |
| Mode-2 portability (per ADR-0008) | `consuming-card` mature procedural form under Mode-2 `max_depth=1`; verified compatibility | 6 stage SKILLs each need fresh ADR-0008 verification; introduces compatibility risk that may not pass without re-architecting |
| Body-length budget | Currently 229 lines; finalized lifecycle estimated at 350–420 lines, comfortably inside molecular 250–450 budget; stage detail moves to `references/` per progressive disclosure | Each stage SKILL 150–250 lines; but 6× frontmatter + `references/` + `.skill-meta.yaml` overhead and 6 disjoint trigger descriptions to maintain |
| Cross-stage helper sharing | Same body → trivial | Atomic layer + scripts (already the structural mechanism — accidentally pulled into Shape Y as an artifact, not a benefit) |
| Evolution discipline | A future v1.x specific role that is **lifecycle-driven** (e.g., Refiner) inherits this shape; a future role that is **call-driven** (e.g., Triager) inherits Producer's Shape Y. The Producer/Consumer Shape divergence becomes a **placement guidance signal** for future roles. | Forces all future Consumer-like roles into Shape Y regardless of fit |

**Producer Shape Y / Consumer Shape X — the structural reason**:

- **Producer = call-driven multi-flow.** Architect triggers
  one of N independent routines (`daily` / `intake` /
  `review-queue` / `triage`) per session entry; each
  routine has its own user-facing trigger phrases. Independent
  trigger surfaces force per-routine SKILL split (Shape Y).
- **Consumer = lifecycle-driven single-session.** Architect
  triggers one card claim; all stages happen in time-ordered
  sequence inside that one session. Single trigger surface
  rules out per-stage SKILL split (Shape Y becomes a SKILL
  protocol violation), favors mega orchestrator (Shape X).

Same ROI function, same five factors, opposite shape
decisions — driven by surface-level trigger topology, not
by methodology preference. This is exactly what the ROI
function is supposed to do: detect structural fit instead
of imposing a single shape.

### Final SKILL set (v1-complete Consumer-side)

```
Entry layer (1 SKILL — shared with Producer)
─────────────────────────────────────────────
using-board-superpowers              shipped — routing unchanged
                                     (consuming-card remains the entry's
                                     Consumer-routing target)

Molecular layer (1 SKILL — Consumer-exclusive)
─────────────────────────────────────────────
consuming-card                       shipped v0.1.0 — finalized to host
                                     all 23 journey nodes; lifecycle
                                     orchestrator from receive to conclude;
                                     stage detail progressively disclosed
                                     via `references/`; preserves
                                     Mode-1 / Mode-2 dual compatibility

Atomic layer (5 SKILLs — ALL shared with Producer)
─────────────────────────────────────────────
board-canon                          shipped   schema + state machine + WIP formula
enforcing-pr-contract                shipped   Contract A + B (D1 + D2 SPOT)
classifying-actions                  shipped   D-AUTONOMY-1 matrix; G2 + G3 + B5
auditing-actions                     shipped   audit schema + degradation; G1
composing-siblings                   NEW (Producer-side decision; Consumer-side validates with 5 callers — B1/C1/C2/C3/C4)

Consumer-side total: 7 SKILLs (1 + 1 + 5)
Of which Consumer-exclusive: 1 (consuming-card, already shipped)
```

The Consumer surface contributes **zero new SKILLs** in
v1-complete scope. `consuming-card` is shipped and only
gets body-content updates to host the 23 journey nodes;
all 5 atomics are shared with Producer (4 already shipped;
`composing-siblings` lifted by Producer's Shape Y decision).

### `composing-siblings` cross-surface validation

`composing-siblings` was lifted as a new atomic SKILL in
Producer's Stage 3 finalization (per
[`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)
§ "Producer SKILL set decision" → "New atomic SKILL").
Producer-side caller count: 4 molecular SKILLs
(`intaking-requirement`, `reviewing-pr-queue`,
`triaging-board`, `decomposing-into-milestones`).

Consumer-side caller count under Shape X: **5 nodes**
within `consuming-card` body — B1 (plan synthesis
delegate), C1 (verification chain delegate), C2
(cross-platform review delegate), C3 (conditional QA
delegate), C4 (conditional security audit delegate).

**Cross-surface total caller count: 9** (4 Producer +
5 Consumer). This validates the SPOT consolidation: the
cross-plugin routing decision framework is Producer's
multi-routine concern AND Consumer's multi-stage concern.
Single SoT in `composing-siblings` atomic; both Producer
molecular SKILLs and `consuming-card` body declare
`composes_atomic: composing-siblings` and consult the same
routing table.

### v1.x atomic candidates (NOT shipped at v1-complete)

Three Consumer-related SPOT candidates were evaluated and
**deliberately deferred** to v1.x:

- **`scope-judgment`** (F1 stakeholder routing) — D-META-1
  high judgment of in-slice-vs-cross-card-vs-defer. v1-complete
  caller count = 1 (F1 only); SPOT threshold not met.
  v1.x lift trigger: when a future Triager-like specific
  role also performs scope judgment, OR when Producer's
  `triaging-board` formalizes its "5-step ladder" remediation
  judgments around scope. At ≥2 callers with structurally
  same rhythm, lift `scope-judgment` to atomic.
- **`mode-projection`** (G4 Mode topology surfacing) —
  Mode-1 / Mode-2 dispatching protocol + ADR-0008
  `max_depth=1` boundary projection. v1-complete caller
  count = 1 (`consuming-card` only; Producer's overnight-
  dispatch D1 is v1.x defer). v1.x lift trigger: when
  Producer overnight-dispatch ships, caller count reaches
  2; lift to atomic at that point with paired Mode-2
  contract documentation.
- **`refusing-out-of-scope`** (B3 + B4 + B5 refusal /
  gate pattern) — three refusal reflexes share an element
  structure but trigger conditions are not yet structurally
  same (TDD skip vs cross-card edit vs permission bypass).
  v1-complete: keep inlined in `consuming-card`. v1.x lift
  trigger: when a 4th refusal node lands AND ≥3 of the 4
  share a same-rhythm refusal-with-explanation framework.
  Until then, multiple unshared inline refusals are
  strictly worse than one over-generalized atomic but
  strictly better than absent documentation.

### Same-PR cleanup obligations (Shape X)

When this redesign moves from draft to shipped:

- **No new SKILL authoring needed.** `consuming-card` is
  already shipped (v0.1.0); finalization is body / references
  refactor only — host the 23 journey nodes (with stage
  detail moved to `skills/consuming-card/references/`),
  declare `composes_atomic: composing-siblings`, lift
  Mode-2 caveats from per-feature mentions into the G4
  cross-cutting subsection.
- **Lift Mode-1 / Mode-2 caveats** out of F-C4 / F-C8 /
  F-C10 / F-C11 / F-C13 individual feature blocks into the
  G4 (Mode topology surfacing) cross-cutting subsection of
  `consuming-card`. The currently-shipped 04 surface's
  per-feature Mode-2 paragraphs become "see G4" pointers.
- **Add B1, D3, G1–G5** as explicit catalog rows
  (currently absent or implicit in F-C0..F-C14).
- **Split F-C11** into two catalog rows (C3 + C4) with
  distinct gating heuristics.
- **Demote `claim-card.sh` Mode-2 wakeup hook adjunct**
  references that scattered across F-C0..F-C14 into the
  A1 catalog row's J2 column (the carrier is now
  explicit, not implicit per-feature footnote).
- **Update `consuming-card` body to consult `composing-siblings`**
  at B1 / C1 / C2 / C3 / C4 instead of inlined cross-plugin
  routing references.
- **Cross-impact propagation** — Spec change-impact matrix
  in [`../AGENTS.md`](../AGENTS.md) walked top-to-bottom:
  rows referencing `consuming-card` body content do not
  rename, but new row added for `consuming-card ↔
  composing-siblings` SKILL-tool dependency.

## Trigger model

[TBD — describes how each goal-loop phase is triggered for a
Consumer session. Includes the Mode-1 / Mode-2 platform
projection (Mode-1 trigger = architect interactive prompt,
Mode-2 trigger = Producer's `Agent` tool spawn + preflight
piggyback wake-up). The 5 scattered Mode-2 caveats currently in
F-C4 / F-C8 / F-C10 / F-C11 / F-C13 are factored out and
consolidated here.]

## Skill nature × layer implications

[TBD — same shape as Producer (see
[`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)
§ "Skill nature × layer implications"). All 14 Consumer
features sit at (workflow, molecular) and consume atomic
mental-model skills for governance / reference. Consumer-
specific implication: lifecycle uniformity (one molecular
SKILL, multi-stage) makes Consumer the canonical example of
"workflow + molecular" surface; future split into per-stage
sub-molecular skills (Open question) would test Axis 4 value
cardinality.]

## Implementation medium responsibility

[TBD — declarative ownership rules for hook adjuncts and
script adjuncts. Same content shape as Producer (see
[`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)
§ "Implementation medium responsibility"). Consumer-specific
finding: several Consumer-only scripts currently squat at
plugin-global `scripts/` despite having a single SKILL caller;
these are candidates for skill-bundled relocation.
Specific script enumeration deferred until terminal SKILL set
settles (per the SKILL decomposition granularity Open
question). Cleanup timing is a separate Open question.]

## Cross-version evolution

[TBD — how to add a new Consumer specific role (the
§1.4.2-reserved Reviewer / Bisector / Migration-runner). How
to add a new feature within Implementer. How to deprecate a
feature. The §1.4.2 reservation pattern matches the Setup-
Stages "future-module inclusion procedure" idiom (registry-only
edits, no SKILL or hook code change).]

## Open design choices

### Still open

- **Codex Mode-2 inclusion in v1-complete.** v1 ships
  Mode-2 as CC-only. Whether the redesign reserves Codex
  Mode-2 as a future-supported projection value (table grows
  a column once) or defers entirely to a future ADR after
  v1.x demand pulls. Mirrors Producer's Codex-dispatch
  question.
- **Skill-relocation cleanup timing.** Mirroring Producer's
  cleanup question — Consumer-only scripts currently
  plugin-global need to relocate to skill-bundled location.
  Whether to bundle into the redesign PR or land independently.
  Same tradeoff as Producer; decisions should be coordinated
  between 03 / 04 to avoid splitting cleanup across multiple
  PRs.

### Decided (by intake conversation, 2026-04-29)

- **Consumer is an AI-Agent specific role.** Not a product
  surface; not a class hierarchy. An Agent whose specific
  role is end-to-end card delivery (claim through merge).
- **Four axes characterizing skill capabilities, identical
  structure to Producer except Axis 2** (per architect's
  intake first principle, revised 2026-04-29 mid-design):
  Axis 1 Agent goal-loop phase (cognitive / agentic);
  Axis 3 skill nature (`workflow` vs `mental-model` — what
  KIND of SKILL); Axis 4 skill layer (`entrypoint` /
  `molecular` / `atomic` per
  [`../../SKILLS.md`](../../../SKILLS.md) three-layer
  architecture) are defined identically across both surfaces.
  Axis 2 (workflow stage) differs in shape — Consumer is
  lifecycle-driven (single flow, multi-stage); Producer is
  call-driven (multi flow, cross-cutting features). Adjuncts
  (hook + script + composes_atomics) are per-feature
  attributes, not axes. The earlier "capability vs
  meta-capability" classification (a feature-functional cut)
  and "SKILL home" (a SKILL identity enumeration) were both
  replaced — skill-nature is the more useful structural cut;
  identity is downstream of axis values, not an axis itself.
- **SKILL is the primary implementation unit; hooks and
  scripts are subordinate adjuncts.** Same doctrine as
  Producer (see
  [`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)
  § "Decided"). Every Consumer feature's core lands in a
  SKILL.md. Hooks exist only as robustness adjuncts to
  specific lifecycle phases. Scripts are deterministic-
  mechanism resources owned by skills (single-caller
  skill-bundled; multi-caller plugin-global). Adjunct
  ownership rule: single-caller MUST be skill-bundled;
  multi-caller MAY be plugin-global.
- **Mode-1 / Mode-2 is a runtime projection, not an
  agent-cognitive axis.** Mode lives in trigger model (or
  mother-protocol), not in per-feature caveats.
- **Skill nature × layer uniformity within Producer /
  Consumer surfaces.** Both surfaces' features cluster
  uniformly at (workflow, molecular). The mental-model +
  atomic substrate (governance schemas, classification
  matrices, contract validation rules, audit conventions)
  lives external to these surfaces and is referenced via
  each feature's `composes_atomics` attribute. Single-cell
  uniformity is a structural finding (Producer / Consumer
  surfaces ARE the molecular workflow projection), not a
  calibration error or low-information artifact. The
  earlier-iteration "Producer 73% meta / Consumer 64% meta"
  finding (based on the now-retired capability vs
  meta-capability axis) is superseded by this layer-vs-nature
  framing.
- **Mother-protocol form choice (candidate B accepted, 2026-04-29).**
  Extract a mother-layer Session Agent Protocol contract at
  [`../0005-contracts/09-session-agent-protocol.md`](../0005-contracts/09-session-agent-protocol.md).
  Trigger: J1–J5 are 5-of-5 shared between Producer /
  Consumer / Bootstrap surfaces (axis definitions and value
  enums identical; only value distribution and node catalogs
  differ). 5-of-5 sharedness exceeds the original 3-of-4
  threshold that defaulted to candidate B. Mother protocol
  pins J1–J5; this surface declares Consumer-specific
  distribution and (precise) 23-node catalog without
  redefining J1–J5. Mode-1 / Mode-2 projection is part of
  the mother protocol's J2 (`explicit-prompt` carrier
  sub-modes — the prompter being architect vs Producer-agent),
  not a per-feature column in 04.
- **Methodology Stage 1 / 2 / 3 applied to Consumer surface
  (2026-04-29).** Per
  [`../../../FEATURE_DESIGN_METHODOLOGY.md`](../../../FEATURE_DESIGN_METHODOLOGY.md):
  Stage 1 enumerates **23 journey nodes** A1–G5 in
  § "Consumer journey nodes (Stage 1 enumeration)" (the
  earlier 14+ symbolic count was an underestimate; the
  precise count is 23 = 3 + 5 + 4 + 3 + 2 + 1 + 5);
  Stage 2 positions each node on J1–J5 + A1–A2 in
  § "Consumer feature catalog (table)"; Stage 3 yields the
  final archetype distribution (4 A / 0 B / 19 C — 83%
  archetype-C ratio, structural to lifecycle-driven shape)
  and the SKILL set decision (Shape X mega-`consuming-card`)
  in § "Consumer SKILL set decision (Stage 3 ROI synthesis)".
  Two structural findings landed: (i) seven nodes (B1, D3,
  G1–G5) recovered from methodology cross-product, absent
  in F-C0..F-C14 thematic grouping; (ii) F-C11 splits into
  two distinct nodes (C3 QA vs C4 security audit) due to
  different gating heuristics + sibling-skill targets.
  The currently-shipped F-C0..F-C14 numbering remains
  valid as a parallel index in the shipped 04 surface;
  the redesign adds the journey-based A1–G5 numbering as
  the canonical Stage 1 / 2 / 3 frame. Mode-1 / Mode-2
  projection lifted from per-feature caveats into G4 +
  Trigger model.
- **SKILL decomposition granularity — Shape X chosen
  (2026-04-29).** Per § "Consumer SKILL set decision
  (Stage 3 ROI synthesis)" → "Why Shape X (mega
  `consuming-card`) wins". Consumer keeps the existing
  `consuming-card` mega molecular SKILL hosting all 23
  journey nodes (lifecycle from receive to conclude); does
  NOT split into 6 per-stage sub-molecular SKILLs.
  Decisive dimensions: trigger description precision (1
  user-facing trigger vs 6 stage SKILLs that cannot have
  non-overlapping trigger phrases — violates
  SKILL_DEVELOPMENT.md "description = WHEN" first
  principle), lifecycle coherence (single orchestrator vs
  5+ cross-SKILL handoffs), and Mode-2 portability
  (`consuming-card` already verified procedural under
  ADR-0008 `max_depth=1`; per-stage SKILLs would each need
  fresh verification). Producer's Shape Y / Consumer's
  Shape X is **not a methodology inconsistency** — it is
  the methodology correctly detecting two surfaces with
  structurally different shapes (Producer = call-driven
  multi-flow; Consumer = lifecycle-driven single-session).
- **Cross-surface validation of `composing-siblings` atomic
  (2026-04-29).** The `composing-siblings` atomic SKILL
  lifted by Producer's Stage 3 finalization (per
  [`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)
  § "Producer SKILL set decision" → "New atomic SKILL")
  receives 5 additional callers from Consumer side under
  Shape X — B1 (plan synthesis delegate), C1 (verification
  chain delegate), C2 (cross-platform review delegate),
  C3 (conditional QA delegate), C4 (conditional security
  audit delegate). Total cross-surface caller count: 9
  (4 Producer + 5 Consumer). The SPOT census is empirically
  validated cross-surface, not just intra-Producer; ships
  once at v1-complete and serves both surfaces.
- **F1 archetype B → C correction (2026-04-29).** The
  prior Stage 3 draft tagged F1 stakeholder routing as
  archetype-B candidate for a thin `scope-judgment` router
  SKILL. Strict ROI re-evaluation: caller count = 1
  (F1 itself), SPOT threshold not met. Final archetype
  assignment: C, fold into `consuming-card`; scope-judgment
  knowledge inlines until v1.x cross-routine reuse emerges.
  See § "v1.x atomic candidates" for lift triggers.
- **v1.x atomic candidate roadmap — three SPOT-watch
  entries (2026-04-29).** Three Consumer-related atomics
  deliberately deferred to v1.x and recorded as
  SPOT-watchlist:
  (i) `scope-judgment` (F1) — lift when ≥2 callers with
  same rhythm emerge;
  (ii) `mode-projection` (G4) — lift when Producer
  overnight-dispatch ships and creates the 2nd caller;
  (iii) `refusing-out-of-scope` (B3 + B4 + B5 refusal /
  gate pattern) — lift when a 4th refusal node lands AND
  ≥3 of 4 share same-rhythm refusal-with-explanation
  framework. Each remains inline in `consuming-card` body
  until its lift trigger fires.
- **Final v1-complete Consumer SKILL set: 7 SKILLs
  (2026-04-29).** Entry layer 1 (`using-board-superpowers`,
  shared with Producer); molecular layer 1 (`consuming-card`,
  Consumer-exclusive, already shipped); atomic layer 5
  (all shared with Producer — `board-canon`,
  `enforcing-pr-contract`, `classifying-actions`,
  `auditing-actions`, `composing-siblings`). Consumer
  surface contributes **zero new SKILLs** in v1-complete
  scope; `consuming-card` only receives body-content
  refactor to host the 23 journey nodes. Authoritative
  listing in § "Consumer SKILL set decision" → "Final
  SKILL set".

## Replacement plan (when this draft is approved)

[TBD — N-step plan to transition this draft into
`04-consumer-surface.md`. Companion ADRs recorded; spec
change-impact matrix walked top-to-bottom; SKILLS.md updated
if new specific roles or skill cross-references emerge;
cross-references audited. Mirrors the Replacement plan
structure in
[`05-bootstrap-surface.md`](./05-bootstrap-surface.md)
§ "Replacement plan".]
