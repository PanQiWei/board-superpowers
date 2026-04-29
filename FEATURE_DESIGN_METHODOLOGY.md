# FEATURE_DESIGN_METHODOLOGY.md

> **The analytical method that precedes plugin construction.**
>
> Other root-level companion docs
> (`PLUGIN_DEVELOPMENT.md`, `MULTI_AGENT_DEVELOPMENT.md`,
> `SKILL_DEVELOPMENT.md`, `SETUP_STAGES_DEVELOPMENT.md`,
> `BOARD_DEVELOPMENT.md`) tell you **how to build a specific
> kind of artifact**. This document tells you **how to decide
> what artifacts to build** when a new requirement, surface, or
> specific role lands on the design table.
>
> This is a methodology document, not a handbook. Its outputs
> are *traceable design decisions* — not code, not SKILL
> bodies, not hooks. Code authoring resumes only after this
> methodology has produced a SKILL set candidate; the
> downstream `*_DEVELOPMENT.md` docs take over from there.

## Position in the doc family

| If you need to know... | Read... |
|------------------------|---------|
| **What artifacts to build** for a new requirement / surface / specific role | This file |
| Plugin protocol contracts (CC + Codex) | [`PLUGIN_DEVELOPMENT.md`](./PLUGIN_DEVELOPMENT.md) |
| Subagent / agent-team / orchestration | [`MULTI_AGENT_DEVELOPMENT.md`](./MULTI_AGENT_DEVELOPMENT.md) |
| How to author one SKILL.md | [`SKILL_DEVELOPMENT.md`](./SKILL_DEVELOPMENT.md) |
| Setup-stages subsystem | [`SETUP_STAGES_DEVELOPMENT.md`](./SETUP_STAGES_DEVELOPMENT.md) |
| Board / Kanban Protocol layer | [`BOARD_DEVELOPMENT.md`](./BOARD_DEVELOPMENT.md) |
| Current SKILL catalog topology | [`SKILLS.md`](./SKILLS.md) |

This methodology is the **upstream** of all the documents
above. A surface redesign or new specific role passes through
this methodology first; only after Stage 3 produces a SKILL
set candidate does work move into `SKILL_DEVELOPMENT.md` etc.

## Why this document exists

Plugin design has had a missing middle layer between user
requirements and concrete SKILL set decisions. Without an
analytical framework, several recurring failure modes appear:

1. **One-to-one mapping** — every user-journey node becomes
   its own SKILL, so SKILL set size grows linearly with
   requirement count and never shrinks. There is no pruning
   signal.
2. **Carrier overload** — all "automation" gets compressed
   onto a single trigger carrier (typically the SessionStart
   hook). The hook becomes a noise dispenser; the architect's
   per-session attention budget is silently exhausted.
3. **Feature-group as boundary** — SKILL boundaries are drawn
   along thematic groups (F-01..F-15-style numbering) which
   obscures nested-node relationships and forces
   over-fragmentation.
4. **Single-axis intuition** — single-axis judgments
   ("autonomy level", "frequency", "complexity") masquerade as
   multi-axis derivations. Different reviewers reach different
   conclusions because they implicitly weight different axes.
5. **No long-term health signal** — when base models evolve
   (Claude 5, Codex 5, …), there is no mechanism to detect
   that some shipped SKILLs have become net-negative
   maintenance burden because their gap closed.

This document fixes the missing layer with **three
artifacts**, applied in **three stages**:

1. **Stage 1** — Enumerate user-journey nodes (the raw
   requirement layer).
2. **Stage 2** — Locate each node on the **requirement-layer
   dimensions (J1–J5)** and on the **SKILL-layer dimensions
   (the four axes already documented in SKILLS.md)**.
3. **Stage 3** — Apply the **derivation function (ROI)** to
   determine which nodes become independent SKILLs, which
   become thin "router" SKILLs, and which dissolve into other
   SKILLs as nested sub-steps.

The three stages are sequential. Skipping a stage produces
low-confidence SKILL set decisions; running all three
produces decisions whose every entry is traceable back to a
measured requirement gap.

```
Stage 1            Stage 2                  Stage 3
─────────────      ─────────────────────    ──────────────────
Enumerate          Locate each node on:     Apply ROI function:
user-journey       (a) J1–J5 (requirement   filter, merge nested
nodes              layer)                   nodes, choose grain.
                   (b) layer / nature /
Output:            phase / workflow         Output:
list of nodes      (SKILL layer, recap)     SKILL set
A1, A2, …, G5                               (subset of nodes,
                   Output: each node        possibly merged)
                   has a 5-tuple + a
                   tentative SKILL-layer
                   profile
```

Each stage produces a reviewable artifact. Reviewers can
challenge a Stage 1 enumeration without re-litigating Stage 2
positioning; reviewers can challenge a Stage 3 SKILL-set
choice without re-litigating the J1–J5 dimensions
themselves.

## Stage 1 — User-journey node enumeration

A "user-journey node" is a discrete thing the system or the
human cares about happening, named at the requirement level
**not** the implementation level.

### Two complementary lists are mandatory

Every Stage 1 enumeration produces **two lists**, not one:

1. **Human-initiated nodes** — what does the architect (or
   end user) want to be able to do in this surface / role?
2. **Agent-self-initiated nodes** — what should the system do
   without the architect's intervention?

Both lists are mandatory. The agent-self-initiated list is
typically harder to write because it surfaces cross-cutting
concerns (audit, governance, cadence-driven retros, drift
detection, etc.) that often hide in "implementation detail"
during single-list enumerations.

The cross-reference between the two lists is where
**governance / cross-cutting concerns** surface as their own
node group. Producer's `G1–G5` (audit, autonomy class
resolution, propose-and-await, etc.) emerged exactly here:
not from the human-initiated list (the architect rarely says
"please run governance on this action"), and not from the
agent-self-initiated list as a clear standalone (it is
nested in every mutating action), but from the **product**
of the two lists.

### What to enumerate

Each node is described in **one line of natural-language
intent**, not implementation:

- ✅ "A1 — board overview at session start: see what's
  running, what's awaiting review, what's blocked."
- ✅ "G1 — every mutating action is auditable after the
  fact."
- ❌ "A1 — read GitHub Project via gh CLI, format briefing,
  inject via SessionStart hook." *(too implementation;
  forces premature carrier choice)*
- ❌ "G1 — call auditing-actions atomic SKILL." *(names
  current artifact instead of intent; locks in current
  design)*

Implementation choice (which trigger carrier? which SKILL
shape?) belongs to Stage 2 and Stage 3. Stage 1 stays
implementation-agnostic so the methodology can re-derive
choices when constraints change.

### What is *not* a node

A node is **not**:

- A specific script (e.g., `read-board.sh`) — that's an
  implementation mechanism, not a journey waypoint.
- A specific hook event (e.g., "preflight piggyback") —
  that's a carrier, not an intent.
- A specific SKILL (e.g., `managing-board`) — that's a
  destination of derivation, not its input.

If your enumeration starts citing those, the list has
already drifted into Stage 3 prematurely.

### Worked example: Producer Session

The Producer surface enumeration produced **21 journey
nodes** in 7 groups:

```
A. Start-of-day / context-switch (5 nodes)
B. Bringing in new work (4 nodes)
C. Advancing in-flight work (5 nodes)
D. Async dispatch (2 nodes)
E. Reflection / cadence (3 nodes)
F. Project-level infrastructure (2 nodes)

G. Cross-cutting governance (5 nodes — surfaced from list cross-product)
```

The full enumeration is preserved in
`docs/architecture/0002-product-features-and-flows/03-producer-surface-redesign.md`.
The structure of "5+4+5+2+3+2 + 5 cross-cutting" is project-
specific; the **two-list discipline** that produces it is
reusable across surfaces.

### Anti-patterns at Stage 1

- **Single-list enumeration.** Listing only human-initiated
  intents and treating system-initiated work as "background
  detail." The cross-cutting concerns will resurface
  uncontrolled later, often distorted into ad-hoc per-feature
  spec clauses.
- **Naming current artifacts.** Phrasing nodes as "the X
  SKILL" or "what `read-board.sh` does." Locks the analysis
  to current implementation; defeats the purpose of
  re-derivation.
- **Compressing for brevity.** Merging two distinct intents
  ("see today's PR queue" + "see today's blocked cards") into
  one node because they "feel related." Stage 3 will merge
  for legitimate reasons; Stage 1 should be **exhaustive and
  granular**.

## Stage 2 — Locating each node

Stage 2 positions each node on **two coordinate systems**:

- **The requirement-layer dimensions (J1–J5)** — five
  axes that locate the node *as a requirement*. These are
  the contribution of this methodology document.
- **The SKILL-layer dimensions** — four axes that classify
  *the SKILL that may implement the node*, recapped from
  [`SKILLS.md`](./SKILLS.md). These are tentative at Stage
  2; Stage 3 finalizes them.

The two coordinate systems are **independent**. J1–J5
locate a *requirement*; the four SKILL-layer axes locate a
*SKILL implementation*. A node may locate cleanly on J1–J5
yet not justify any SKILL of its own (Stage 3 prunes it).

### Requirement-layer dimensions (J1–J5)

Each axis answers a distinct question. Together they pin
down a node's identity at the requirement layer.

#### J1 — Trigger actor

**Question**: who pushes the door open to make this node
fire?

**Values (discrete three-valued)**:

- `agent-self` — Agent fires the node from an internal
  signal: a hook delivered an `INVOKE:` marker, an `observe`
  phase saw a state change, a previous routine's `conclude`
  decided the next step. **No architect intervention
  required.**
- `architect` — Architect must explicitly prompt
  (natural-language utterance or slash command) to wake the
  node.
- `nested-within-routine` — The node lives inside another
  node's routine. The agent enters it via internal branching
  during the outer routine's execution; the node has no
  independent trigger surface.

**Why this axis matters**: J1 partitions trigger-phrase
table size from "all nodes" to "only `architect`-class
nodes." Nodes in other classes do not consume trigger-phrase
space — they are reached by different mechanisms (J2 covers
the mechanism choice).

#### J2 — Trigger carrier

**Question**: which mechanism realizes the door-opening?

**Values (discrete four-valued)**:

- `session-hook` — Plugin runtime hook (`SessionStart`,
  `PreToolUse`, `PostToolUse`, `Stop`, etc.) injects context
  or invokes a SKILL. **Finite bandwidth** — every injected
  briefing item competes for the architect's attention budget
  on session entry.
- `cron-job` — External scheduler (system cron, CC scheduled
  jobs, GitHub Actions cron) calls the plugin entry on a
  cadence independent of any session. **Effectively
  unlimited bandwidth** — cadences run concurrently and do
  not crowd the session interface.
- `in-process-reflex` — An atomic SKILL invoked synchronously
  from a molecular SKILL's body during execution. **Zero
  latency, zero bandwidth cost** for the architect because
  the architect never sees the reflex directly.
- `explicit-prompt` — Architect's own prompt is the trigger.
  **Bandwidth scales with architect's volition** — this is
  the only carrier where architect typing volume bounds
  trigger frequency.

**Capacity constraint** (the *K-budget rule*): the
session-hook carrier has a per-session injection capacity K.
Empirically `K ≈ 4`. Exceeding K compresses each item's
salience to noise. Designs that need to surface more than K
items must move excess items to a different carrier.

**Carrier selection guideline (the carrier ladder)**:

1. If the node fires on a fixed cadence independent of
   architect presence → `cron-job`.
2. If the node fires only after a mutating action → consider
   `in-process-reflex`.
3. If the node must be visible at session entry → check
   K-budget; if room, `session-hook`; if not, `cron-job`
   with persisted state, then `session-hook` reads state
   on entry (compute / present split).
4. If the node requires an architect's deliberate decision
   → `explicit-prompt`.

#### J3 — Autonomy class

**Question**: under board-superpowers' D-AUTONOMY-1 matrix,
what class is this node's mutating action?

**Values (discrete three-valued, per
[`docs/architecture/adr/0006-producer-autonomy-boundary.md`](./docs/architecture/adr/0006-producer-autonomy-boundary.md))**:

- `A` — Auto with audit log. Agent acts; one audit row
  records the outcome.
- `R` — Propose-then-await-approval. Agent surfaces the
  intent; awaits architect reply; on approval, acts; two
  audit rows (proposal + resolution).
- `N` — Permanently rejected. Agent must refuse. *(v1 has no
  N-class entries; reserved.)*

**Note on multi-phase nodes**: a node that spans multiple
goal-loop phases (e.g., the 5-step triage ladder) may have
**different J3 values per phase**. J3 is recorded per-phase,
not per-node, in those cases.

#### J4 — D-META-1 strength

**Question**: does this node ship deterministic mechanism,
or does it ship a conversation framework that lets the
architect capture project-specific taste?

**Values (discrete three-valued, anchored to
[`docs/architecture/0001-positioning.md`](./docs/architecture/0001-positioning.md)
P7 / D-META-1)**:

- `low` — Deterministic mechanism only. No architect taste
  capture; the node ships rules / schemas / matrices.
  Examples: governance, audit log writing.
- `medium` — Semi-structured template. The node ships a
  framework (e.g., five-stage retrospective, INVEST
  checklist) within which the architect fills domain
  judgment. Examples: retro framing, decomposition.
- `high` — Conversation-only. The node ships virtually no
  defaults; its entire value is the dialogue framework that
  extracts project-specific taste. Examples: harness setup,
  design conversation routing.

**Why J4 matters for SKILL form**: high-J4 nodes are
naturally **router SKILLs** (delegate to sibling skills,
hold a thin routing decision tree, refuse to ship generic
defaults). Low-J4 nodes are **executor SKILLs** (hold the
mechanism inline). Mismatching J4 to SKILL form produces
either over-engineered "configurable" SKILLs (low-J4 node
forced into high-J4 form) or generic-defaults pollution
(high-J4 node implemented with hard-coded defaults).

#### J5 — Result destination

**Question**: where does the node's output land?

**Values (discrete four-valued)**:

- `inject-session` — Output enters the architect's current
  or next prompt context (a briefing item, a proposal
  pending reply, a reminder).
- `persist-state` — Output writes to durable state (GitHub
  Project field, host-local `state.yml`, audit DB, card
  body).
- `emit-external` — Output goes to a third-party artifact
  (PR comment, commit, email, GitHub issue).
- `inline-return` — Output is a context fragment passed back
  to an outer routine's next phase (this destination only
  applies to `nested-within-routine` nodes).

**Cross-axis constraint with J2**:

- `cron-job` carriers cannot have `inject-session` as
  result destination (the architect is not in a session
  when cron fires). Cron nodes must use `persist-state` /
  `emit-external`.
- `session-hook` carriers can use any destination but
  `inject-session` is the typical case.
- `in-process-reflex` typically uses `persist-state` (audit
  rows) or `inline-return` (gating signal back to caller).
- `explicit-prompt` triggers any destination.

#### Orthogonality self-check

Each pair of J-axes is independent (moving along one does
not constrain another):

- J1 ⊥ J2: agent-self can use either session-hook or cron;
  architect can use only explicit-prompt; nested can use
  in-process-reflex. (Some combinations are illegal — see
  the legal-combination matrix in surface specs.)
- J1 ⊥ J3: any actor can fire any class of mutating action.
- J2 ⊥ J5: same carrier can target different destinations.
- J3 ⊥ J4: governance class is independent of mechanism vs
  configuration. An `R`-class node can be high-J4 (a
  proposal whose body the architect customizes) or low-J4
  (a templated proposal for an obvious mechanical action).
- J4 ⊥ J5: a router SKILL can persist state (rare but legal:
  a routing-decision audit row) or inject-session (the
  typical case).

If a pair turns out to correlate strongly across all
project-internal usages, that's empirical, not structural —
the design space the orthogonal axes preserve is what lets
future surfaces exercise other corners of the cube.

### SKILL-layer dimensions (recap)

The four SKILL-layer axes are documented authoritatively in
[`SKILLS.md`](./SKILLS.md). They are recapped here for
relating-Stage-2 purposes only:

- **Layer** — `entrypoint` / `molecular` / `atomic`. Where
  the SKILL sits in the dependency graph.
- **Nature** — `workflow` (procedural guide) / `mental-model`
  (thought framework). What kind of SKILL.md body shape.
- **Goal-loop phase coverage** — which Norman-1988-anchored
  cognitive phases (`receive` / `orient` / `plan` / `act` /
  `observe` / `reflect` / `surface` / `verify` / `conclude`)
  the SKILL spans.
- **Workflow coverage** — which surface-level workflow(s)
  the SKILL participates in.

These axes are **independent of J1–J5**. J1–J5 locate a
*requirement*; the SKILL-layer axes locate the *artifact
that may implement* the requirement. Stage 3 chooses the
mapping between the two.

### Worked example: locating one node

Take **A1 — Board overview at session entry**:

| Axis | Value | Notes |
|------|-------|-------|
| J1 (actor) | `agent-self` | Architect doesn't ask; it appears |
| J2 (carrier) | `cron-job` (compute) + `session-hook` (present) | Compute / present split: cron computes briefing every N minutes into state, hook reads state on entry |
| J3 (class) | N/A | Read-only — no mutating action |
| J4 (meta-1) | `low` | Mechanism only; weights are configurable but the briefing shape is fixed |
| J5 (destination) | `inject-session` | Briefing lands in architect's prompt context |
| SKILL layer (tentative) | `molecular` | Workflow shape; consumes atomic `board-canon` for state machine |
| SKILL nature (tentative) | `workflow` | Procedural body |

This 5+2-tuple makes A1 a candidate for Stage 3 evaluation.

Take **G1 — Every mutating action is auditable**:

| Axis | Value | Notes |
|------|-------|-------|
| J1 (actor) | `nested-within-routine` | Fires inside every mutating routine, never independently |
| J2 (carrier) | `in-process-reflex` | Atomic SKILL invoked from molecular |
| J3 (class) | N/A (governs other classes) | Audit *of* mutating actions, not itself a mutating decision |
| J4 (meta-1) | `low` | Schema is mechanism, not taste |
| J5 (destination) | `persist-state` | Audit row to BYO RDBMS |
| SKILL layer (tentative) | `atomic` | Reflexive; called from many molecular SKILLs |
| SKILL nature (tentative) | `mental-model` | Schema + rules |

Both nodes are correctly located and ready for Stage 3.

## Stage 3 — Derivation function (ROI)

Stage 3 turns located nodes into a SKILL set candidate. Not
every node becomes a SKILL. Stage 3's job is to **filter and
merge**.

### The function

```
should_become_skill(node) =
        (capability_gap × frequency × failure_cost)
      / (maintenance_cost + routing_complexity)
```

Five factors, three in the numerator (value), two in the
denominator (cost). The ratio tells you whether spending the
cost is worth the value.

The function is **deliberative, not numerical**. The
factors are estimates; the ratio is a structuring device. Its
value is in *forcing the discussion across the same five
factors* every time a SKILL candidate is evaluated, not in
producing a single number.

### Capability gap

Definition: the gap between **base-model native capability +
knowledge** (Claude / Codex / future models) and **what the
node requires**.

#### Specific gap categories

These are board-superpowers-private knowledge / capability;
base models cannot reliably substitute:

1. **Private governance tables** — D-AUTONOMY-1 matrix,
   `autonomy_overrides` resolution rules.
2. **Private ontology** — the 6-state machine, Card schema,
   status enum.
3. **Private convention** — branch naming
   (`claim/<key-slug>-<title-slug>`), claim marker.
4. **Private invariants** — WIP formula
   (`In Progress + suspended + In Review`; `Blocked`
   excluded), terminal-state rule (no bare `[ ]` at PR
   submit).
5. **Private contract** — PR three-section shape, AC sync
   rule.
6. **Private hook protocol** — `INVOKE:` marker grammar,
   cadence trigger semantics.
7. **Project-level private configuration** — GitHub Project
   field IDs, owner / project-number pair.
8. **Private bootstrap mechanism** — stages registry,
   settings layering, `applicable_when` semantics.
9. **Private invocation discipline** — ADR-0008 cross-plugin
   SKILL invocation rules (in-process vs subagent).

#### Base-model native capabilities

These are typically gap = low:

- `gh` CLI usage, Git workflow basics.
- Markdown authoring.
- General design conversation.
- INVEST checklist (high-level recall — though canonical
  quotes need verification).
- Derby & Larsen retrospective five-stage format.
- General code review reasoning.
- TDD discipline (high-level — `superpowers:test-driven-development`
  extends and disciplines this).

#### Measuring gap

Gap measurement is **not algorithmic**. It is a one-prompt
test:

> "If I described this node to a current-generation base
> model in one paragraph (no SKILL.md), would the model
> produce a board-superpowers-compliant outcome?"

- High-confidence yes → low gap.
- Often-wrong → high gap.
- Confident-but-fabricates → high gap (fabrication is the
  most dangerous kind of wrong).

The estimate's *direction* is what matters; an order of
magnitude is enough.

### Frequency

Definition: how many times the node fires over the lifecycle
of a typical project / session role.

| Order | Examples |
|-------|----------|
| Extreme (per mutating action) | G1–G5 |
| High (per SessionStart) | A1–A3 |
| Medium (per day or per PR) | B2, C1 |
| Low (cadence-driven, weekly / monthly) | E1–E3 |
| One-time | F1 (bootstrap) |

Higher frequency amortizes maintenance cost better. A node
that fires once per project should not carry a SKILL.md
unless its `failure_cost` is also extreme.

### Failure cost

Definition: the blast radius when the node misbehaves.

| Order | Examples |
|-------|----------|
| Extreme | Governance failure (G1–G5) — corrupts trust |
| High | PR merge error (C1), bootstrap error (F1), board state corruption (B2) |
| Medium | Triage decision error (C4), retro skipped (E1) |
| Low | Briefing format glitch (A1) — architect notices instantly |

The failure-cost factor is the **rare-but-catastrophic
node's** main argument for SKILL-hood. F1 (bootstrap) fires
once per repo, which would suggest low ROI from frequency
alone — but its extreme failure cost dominates the
calculation.

### Maintenance cost

Definition: SKILL.md authoring effort + ongoing
co-evolution cost as spec changes propagate.

#### Reduced when

- Body length budget is naturally short (router SKILLs ~50
  lines).
- Cross-references are stable (atomic SKILLs rarely change
  once stabilized).
- No nested SKILL dependencies.
- The SKILL is in the same module as its primary callers
  (low cross-module change-impact).

#### Inflated when

- Body covers multiple routines (the current
  `managing-board` challenge — body length budget pressure
  as v1-complete scope expands).
- Cross-plugin edges that require ADR-0008 verification.
- High change-impact-matrix surface area (every related
  spec change requires SKILL re-read).

### Routing complexity

Definition: marginal cost added to entry-point routing /
SKILLS.md catalog / cross-skill dependencies when a new
SKILL is introduced.

#### Lowered by

- **Atomic-layer placement** — atomic SKILLs are called by
  molecular bodies, not by entry-point routing; they don't
  contend for trigger phrases.
- **Nested-within-routine structure** — no independent
  trigger surface; the node is reached via internal
  branching.

#### Raised by

- **Independent trigger phrases** that overlap with adjacent
  SKILLs' descriptions (the "two SKILLs both match this user
  utterance" problem).
- **Cross-plugin entry points** that must be coordinated
  with sibling-plugin descriptions.

### Three SKILL-form archetypes

The function produces three archetypal outcomes:

#### Archetype A — MUST be its own SKILL

**Profile**: high gap × high frequency × high failure cost.

**Examples**: G1–G5 atomic governance + audit, B2 INVEST
decomposition, C1 PR review, F1 bootstrap.

These nodes have no viable alternative. Base models cannot
reliably substitute. Failure cost is high. Frequency
justifies the SKILL.md investment.

#### Archetype B — Thin "router" SKILL

**Profile**: low-to-medium gap × medium frequency × medium
failure cost.

**Examples**: B1 design conversation, F2 harness setup.

Base model is competent at the *substantive work*; the SKILL's
value is in **routing** (to sibling skills like
`gstack:/office-hours`, `superpowers:brainstorming`) and in
**enforcing D-META-1 discipline** (refusing to ship generic
defaults). Body should be ~50–100 lines: a routing decision
tree, delegation templates, and the discipline reminder.

**Treating Archetype B nodes as full molecular SKILLs is
over-investment.** Conversely, **treating them as
inline-able and skipping the router SKILL is
under-investment** — the routing decision and the D-META-1
discipline both need a single home.

#### Archetype C — Should NOT be its own SKILL

**Profile**: low gap × low-to-medium frequency × low failure
cost.

**Examples**: B3 single-card fast-path, isolated fallback
paths, the data-fetch step inside a daily-briefing routine.

These nodes belong **inside another SKILL's body** as
sub-steps. Independent SKILL would inflate routing
complexity without payback.

### Threshold values

The function does not produce a single number cleanly. The
threshold for "MUST be SKILL" / "thin router OK" / "should
NOT be SKILL" is **deliberative**, not numerical — but the
deliberation is *constrained*:

- A node where base-model can produce compliant output ~95%
  of the time without a SKILL is in **Archetype C**.
- A node touching governance / audit / SoT mutation is at
  minimum **Archetype B**.
- A node with frequency >50/day AND non-trivial gap is
  **Archetype A**.

These are heuristics. The function's value is in *structuring
the discussion*, not in producing a verdict.

### Merging via nested-node consolidation

Stage 3 also identifies **node merging opportunities**.
Nodes that share a host routine and only differ in their
internal phase are merge candidates.

Example: in Producer's review-queue routine,
**C1 (review PR)** is the host; **C2 (return to In
Progress)** and **C3 (event-stream lookup)** are nested
nodes — both fire only inside C1's execution. All three
locate cleanly on J1–J5, but Stage 3 merges them into a
single SKILL because separating them would force C1's body
to call C2/C3 SKILLs for what is essentially internal
branching.

The merge rule:

> If two nodes share J1=`nested-within-routine` and reach
> the same outer host, prefer one SKILL hosting all of them
> over multiple SKILLs.

## Plugin long-term health

The methodology is not just a one-shot design tool. It also
provides **plugin health signals over time**.

### Base-model evolution as ROI signal

When base models gain capability, gaps shrink. The
methodology predicts:

- **Pruning** — some current SKILLs should be removed (their
  gap dropped below threshold).
- **Thinning** — some current SKILLs should be kept but
  shrunk (base model now does X natively, only Y still
  requires SKILL guidance).
- **Spawning** — new SKILLs may be needed for newly-emergent
  gaps (new platform conventions, new ontology).

This is the **only mechanism** that prevents SKILL set size
from growing monotonically over the plugin's lifetime.

### The falsification test

For each existing SKILL, ask:

> "If I removed this SKILL today, could a current-generation
> base model reliably substitute its job?"

- **Yes** → pruning candidate. Schedule removal.
- **No, but only because of one specific clause** →
  thinning candidate. Refactor the SKILL body to a
  fraction of its current size, scoped to the still-load-
  bearing clause.
- **No, the SKILL's whole body matters** → keep.

This is the **falsification test for SKILL existence**. A
SKILL that fails this test is a maintenance burden without
payback.

### SKILL set size as health metric

A healthy plugin:

- SKILL set size correlates with the **number of high-gap
  requirement clusters**, not with feature count or
  requirement count.
- SKILL set grows when new gap-rich workflows land.
- SKILL set shrinks when base models close existing gaps.
- Per-SKILL ROI stays roughly constant (no zombie SKILLs
  drifting below threshold).

An unhealthy plugin:

- SKILL set grows monotonically without pruning.
- ROI per SKILL falls over time (SKILLs added to "be safe"
  without measured gap evidence).
- Catalog complexity rises (cross-references multiply,
  routing overlap grows) without gap-coverage gain.

Run the falsification test as part of major plugin version
bumps — at least once per minor version (`vX.Y.0`).

## Spec governance integration

### How this methodology informs other spec / catalog docs

| Spec / doc | How it consumes the methodology |
|------------|---------------------------------|
| Surface specs (`docs/architecture/0002-product-features-and-flows/03-…`, `04-…`, `05-…`) | Each surface's "Trigger model" / "axes" / "SKILL-set rationale" sections cite this document; J1–J5 appear as the surface's axis framework. The surface spec body **does not duplicate** J1–J5 definitions — it references this document and supplies the surface-specific value distribution. |
| [`SKILLS.md`](./SKILLS.md) | Catalog rationale per shipped SKILL cites the ROI archetype it falls in. Pruning / thinning candidates noted in the same place. |
| [`SKILL_DEVELOPMENT.md`](./SKILL_DEVELOPMENT.md) | The "When to create a new SKILL" section (currently informal) cites this methodology's ROI function as the formal evaluation. |
| [`docs/architecture/0001-positioning.md`](./docs/architecture/0001-positioning.md) | The long-term plugin health section (this document) elevates "SKILL set ROI as ongoing maintenance signal" to a positioning-level premise candidate. |
| ADR family | New ADRs that introduce or remove SKILLs cite ROI evaluation as part of the Decision section. The `Consequences` section enumerates which factors of ROI changed. |

### Same-PR contract

Changes to this methodology document trigger:

1. Surface spec re-evaluation — do J1–J5 still locate all
   journey nodes? Have any surfaces grown nodes that need a
   new axis or value? Are ROI archetype assignments still
   right?
2. SKILLS.md re-evaluation — does each shipped SKILL still
   pass ROI under the new methodology revision?
3. SKILL_DEVELOPMENT.md "When to create" section sync.

These are listed as one row in the Spec change-impact matrix
in [`docs/architecture/AGENTS.md`](./docs/architecture/AGENTS.md).

The matrix also gets an *outbound* row: changes to surface
specs / SKILLS.md / SKILL_DEVELOPMENT.md may force this
document's anti-pattern catalog to grow or its archetype
examples to update.

## Anti-patterns

Known recurring failure modes when this methodology is
ignored or partially applied.

### A1. Mapping nodes 1:1 to SKILLs

> Every Stage 1 node becomes its own SKILL because "they're
> different requirements."

Result: SKILL set grows linearly with requirement count;
nested nodes get fragmented across multiple SKILLs;
entry-point routing is overwhelmed by description overlap.

**Fix**: run Stage 3 ROI; merge `nested-within-routine`
nodes into their host SKILL; promote only Archetype A
candidates.

### A2. Compressing all automation into SessionStart hook

> All `agent-self`-initiated nodes are wired to
> SessionStart preflight piggyback because "that's how the
> automation gets in."

Result: K-budget exhausted; per-session noise carpet;
architect attention bottleneck (P1) hit harder than under
manual workflows.

**Fix**: run carrier ladder (J2). Cadence-driven nodes →
`cron-job` with compute / present split. Nodes that don't
need to be visible at session entry → cron + persisted
state, retrieved later.

### A3. Feature-group as SKILL boundary

> SKILL boundaries follow the F-01..F-15 numbering / the
> "Group A / B / C" thematic clusters in the surface spec.

Result: fragmentation along thematic lines that may not
match agentic boundaries; nested nodes split across
SKILLs; the nature × layer profile of each "SKILL" ends up
incoherent.

**Fix**: Stage 3 starts from the located nodes
(J1–J5 + tentative SKILL-layer profile), not from the
surface spec's existing grouping. The grouping was an
authoring convenience for the surface spec, not a SKILL
design directive.

### A4. Single-axis intuitive cuts

> "Autonomy class is the dimension that matters most." or
> "Frequency is what determines whether a SKILL is needed."

Result: different reviewers reach incompatible conclusions.
Single-axis arguments cannot resolve disagreement because
the disagreement is *between* axes.

**Fix**: ROI explicitly multiplies / divides across five
factors. Each factor must be addressed in the design
discussion. Disagreement on the ratio gets reframed as
disagreement on a specific factor's estimate.

### A5. Treating low-gap nodes as full SKILLs

> A node where base model can produce 95%-compliant output
> from a one-paragraph prompt gets its own 250-line
> SKILL.md.

Result: maintenance burden without payback; routing
complexity inflation; description-overlap with sibling
plugins that already cover the gap.

**Fix**: archetype-C nodes dissolve into outer SKILLs as
sub-steps; archetype-B nodes get thin router SKILLs (~50
lines); only archetype-A nodes get full molecular bodies.

### A6. Skipping ROI when adding a SKILL

> A new SKILL is added because "it would be cleaner to
> separate this concern."

Result: catalog drift; ROI per SKILL erodes; the plugin
accumulates zombie SKILLs that could have lived inside
their callers.

**Fix**: every new SKILL PR cites ROI evaluation in the PR
body. Reviewers may push back on any factor's estimate.
"Cleaner separation" is not a substitute for measured ROI.

### A7. Reusing this methodology without adapting J value sets

> Another plugin imports J1–J5 and applies them with the
> exact value sets used in board-superpowers.

Result: the dimensions are stable across plugins (the
*shape* of the analysis is reusable), but the **value sets
are project-specific**:

- J3's `A`/`R`/`N` is board-superpowers' D-AUTONOMY-1; another
  plugin may have different governance levels.
- J4's `low`/`medium`/`high` follows P7 / D-META-1; another
  plugin may have a different mechanism-vs-configuration
  premise.
- J5's destination set depends on the plugin's surface area;
  a plugin without a board has no `persist-state` to a
  GitHub Project.

**Fix**: when reusing the methodology, **redefine the J
value sets** to match the target plugin's surface. The
**structure** transfers; the **enumerations** do not.

### A8. Confusing methodology output with implementation

> Stage 3 produces "8 SKILLs as the candidate set" and
> someone starts authoring 8 SKILL.md files immediately.

Result: SKILL bodies authored against the methodology's
abstract output, not against the surface spec's concrete
contracts. The bodies miss critical implementation context
(hook payload shape, script call signatures,
cross-plugin edge specifics).

**Fix**: Stage 3's output is a **design candidate**, not
an authoring directive. Authoring proceeds through
SKILL_DEVELOPMENT.md, with the surface spec's concrete
contracts as input. Stage 3 says "this should be a SKILL";
SKILL_DEVELOPMENT.md says "this is how the SKILL.md is
written."

## Closing — How to use this document

### Common entry points

**Designing a new surface or specific role**:

1. Run Stage 1 (two-list enumeration).
2. Run Stage 2 (locate each node on J1–J5 + tentative
   SKILL-layer profile).
3. Run Stage 3 (ROI per node + nested-merge + archetype
   classification).
4. Output: SKILL set candidate.
5. Hand off to SKILL_DEVELOPMENT.md for authoring;
   surface spec captures J1–J5 distribution + Stage 3
   archetype assignment.

**Proposing a new SKILL outside a surface redesign**:

1. Run Stage 2 + Stage 3 on the candidate node.
2. Document ROI evaluation in the PR body.
3. If archetype A → proceed. If archetype B → consider
   thin-router form. If archetype C → reject; merge as
   sub-step.

**Existing SKILL feels too thin / too heavy**:

1. Run the falsification test ("could base model
   substitute?").
2. If yes → pruning candidate.
3. If "yes for most of the body, no for one clause" →
   thinning candidate.
4. If no → keep, but check whether the body has accumulated
   anti-patterns (A1–A8).

**Major base-model upgrade**:

1. Re-run the falsification test on every shipped SKILL.
2. Compare current ROI estimates to previous-version
   estimates; flag changes.
3. Schedule pruning / thinning PRs for affected SKILLs.

### What this methodology does not do

- It does not produce automatic answers. The factors are
  estimates; reviewers can challenge each estimate and the
  ratio.
- It does not replace surface specs. Surface specs supply
  concrete contracts; the methodology supplies the
  derivation framework.
- It does not replace SKILL_DEVELOPMENT.md. SKILL bodies
  are authored under SKILL_DEVELOPMENT.md's discipline
  *after* the methodology produces a SKILL candidate.
- It does not produce Stage 1 enumerations on its own.
  Surfaces' two-list enumerations are surface-specific
  authoring work; the methodology guides their *form*, not
  their *content*.

### Methodology revision

This document itself evolves. Triggers for revision:

- A new dimension turns out to be necessary at the
  requirement layer (J6 candidate). Threshold: at least two
  surface redesigns surface the same missing axis.
- ROI's five-factor decomposition turns out to be
  insufficient for some node class. Threshold: three or
  more nodes escape archetype assignment because no factor
  combination captures their character.
- Anti-pattern catalog grows. Threshold: a new
  recurring-failure mode appears in plugin retrospectives.

Revisions land via standard ADR + spec-update PR. The
document's revision history is not maintained inline (use
`git log`); only the current state is authoritative.

---

*End of methodology document. The companion
`SKILL_DEVELOPMENT.md`, `MULTI_AGENT_DEVELOPMENT.md`,
`PLUGIN_DEVELOPMENT.md`, `SETUP_STAGES_DEVELOPMENT.md`, and
`BOARD_DEVELOPMENT.md` take over once a Stage 3 SKILL
candidate has been produced.*
