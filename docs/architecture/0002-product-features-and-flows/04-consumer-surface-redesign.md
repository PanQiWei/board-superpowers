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

The Consumer feature catalog is indexed by **four axes** —
identical structure to Producer's redesign with one role-shape
asymmetry on Axis 2 (workflow stage). Each axis answers a
distinct question; together they pin down a feature's identity.
Cross-axis sparsity is the value of the table form.

> **Cross-reference**: axes 1, 3, 4 are defined identically to
> [`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)
> § "The orthogonal axes". The duplication here is intentional
> — each surface stands self-contained at this draft stage.
> If the architect chooses **candidate B** (mother-layer
> protocol extraction), these three shared axes plus the
> Adjuncts attribute migrate up to
> `0005-contracts/0X-session-agent-protocol.md` and both
> surfaces inherit by reference. Until that decision is made,
> definitions duplicate by design.

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

### Axes orthogonality self-check

- 1 ⊥ 2: an `act` phase serves multiple workflow stages
  (claim's `act` is F-C1's atomic push; impl's `act` is
  F-C4's TDD step; submit's `act` is F-C12's PR open).
- 1 ⊥ 3: an `orient` phase can be hosted by either workflow
  SKILL (procedural narrative for fetching context) or
  mental-model SKILL (the consulted schema reference during
  the orient). The phase-vs-nature combination is free.
- 2 ⊥ 3: every workflow stage contains workflow-natured
  feature steps that compose mental-model atomics —
  implementation stage's TDD-driven mutations (workflow
  nature) consult an autonomy classification atomic
  (mental-model nature) for autonomy class on every
  mutation.
- 3 ⊥ 4: although currently strongly correlated (Consumer's
  workflow features all sit at molecular; consumed
  mental-model atomics all sit at atomic), the redesign
  treats them as independent because future shapes can
  break the correlation (a molecular mental-model framework
  spanning Consumer's lifecycle; an atomic workflow
  primitive callable from multiple molecular Consumer
  variants). Same as Producer's 3⊥4 self-check.
- 1 / 2 / 3 ⊥ 4: any cognitive phase × any workflow stage ×
  any nature can in principle sit at any layer. Empirical:
  Consumer features span all 9 goal-loop phases (`receive`
  through `conclude`) and all 5 workflow stages (bootstrap
  through termination), uniformly at (workflow, molecular).
  The single-cell uniformity within Consumer surface is
  itself a finding — see Axis 4 empirical observation above.

## Consumer feature catalog (table)

> **Status**: pending axis-pass sweep. Each of the 14 features
> will be cell-by-cell positioned on the four axes. Format
> mirrors the Stages table in
> [`05-bootstrap-surface-redesign.md`](./05-bootstrap-surface-redesign.md)
> § "Stages".

[TBD — to be filled by axis-pass sweep, brainstorm
convergence pending. The skeleton header row will be:]

| feature_id | feature_name | description | goal_loop_phase(s) | workflow_stage | skill_nature | skill_layer | hook_adjuncts | script_adjuncts | composes_atomics | autonomy_class | mode_projection | introduced_in_version | deprecated_in_version |
|------------|--------------|-------------|--------------------|----------------|---------------|-------------|---------------|-----------------|------------------|----------------|-----------------|----------------------|----------------------|
| ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... |

> **Note**: sample rows intentionally omitted at this draft
> stage. They depend on the redesign's terminal SKILL set,
> which is still settling (see § "Open design choices" →
> "SKILL decomposition granularity"). Filling concrete
> `composes_atomics` / `script_adjuncts` references before
> the SKILL set is final risks freezing names that the
> redesign may change. The full 14-row catalog will be
> filled in the axis-pass sweep once the SKILL decomposition
> question is resolved.

Note: `mode_projection` is included as a per-feature column to
hold *the lifted Mode-1 / Mode-2 caveats*. Until terminal
landing decides whether mode lives here or in mother-protocol
trigger model, the column is provisional.

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

- **Form choice (mother protocol vs surface-only).** Mirrored
  with [`03-producer-surface-redesign.md`](./03-producer-surface-redesign.md)
  § "Open design choices". The empirical case for B
  (mother-layer protocol extraction) is even stronger after
  Axis 1, 3, 4 are confirmed identically defined in both
  files (plus the Adjuncts attribute); only Axis 2 differs by
  role-shape (Consumer lifecycle-driven vs Producer
  call-driven). 3 of 4 axes shared (plus shared adjuncts) is
  a strong B signal. Default B; await architect ratification.
- **Mode projection placement.** Whether the Mode-1 / Mode-2
  distinction lives as a per-feature column in this catalog
  (provisional choice in the table above), or migrates to
  mother-protocol trigger model (under candidate B), or stays
  in 04 alone (under candidate A). The choice cascades
  with Form choice.
- **F-C13 scope-judgment extraction.** Under the new Axis 3
  (skill nature) framing, F-C13 is workflow-natured (a
  procedural response loop) but its scope-judgment portion
  (decide whether to integrate stakeholder feedback or
  escalate as cross-card touch) is mental-model in shape.
  Whether to extract a `scope-judgment` atomic mental-model
  skill that F-C13 composes (cleaner architectural
  separation), or keep the rule inlined as F-C13 prose
  (current state). Extraction is the orthogonal-purity
  choice; inlining preserves continuity. Mirrors the broader
  question of "when should an inlined rule be promoted to
  an atomic SKILL".
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
- **SKILL decomposition granularity.** Whether to split a
  multi-stage Consumer molecular SKILL (one SKILL covering
  all lifecycle stages from bootstrap through termination)
  into per-stage sub-molecular skills. Mirrors Producer's
  decomposition question. Same Axis 4 cardinality trade-off
  applies.

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

## Replacement plan (when this draft is approved)

[TBD — N-step plan to transition this draft into
`04-consumer-surface.md`. Companion ADRs recorded; spec
change-impact matrix walked top-to-bottom; SKILLS.md updated
if new specific roles or skill cross-references emerge;
cross-references audited. Mirrors the Replacement plan
structure in
[`05-bootstrap-surface-redesign.md`](./05-bootstrap-surface-redesign.md)
§ "Replacement plan".]
