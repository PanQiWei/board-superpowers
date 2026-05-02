# 09 — Session Agent Protocol

> **Status.** Draft (introduced in PR #69, paired with the
> Producer / Consumer surface redesign drafts in 0002).
> Promoted to **Stable** once the surface redesigns merge and
> the J1–J5 dimensions have been applied to populate the
> Producer / Consumer / Bootstrap node catalogs.
>
> **Audience.** Plugin maintainers designing or revising any
> Session-Agent surface (Producer, Consumer, Bootstrap, plus
> any future specific role under §1.3.2 / §1.4.x).
>
> **Position.** Upstream contract for the surface specs in
> [`../0002-product-features-and-flows/`](../0002-product-features-and-flows/README.md).
> Downstream of [ADR-0006](../adr/0006-producer-autonomy-boundary.md)
> (D-AUTONOMY-1) and
> [ADR-0007](../adr/0007-plugin-runtime-derived-constraints.md)
> (plugin runtime constraints). Cited by
> [`../../FEATURE_DESIGN_METHODOLOGY.md`](../../FEATURE_DESIGN_METHODOLOGY.md)
> as the requirement-layer dimensions Stage 2 uses.

## Why this contract exists

Producer Sessions, Consumer Sessions, and Bootstrap Sessions
are all instances of the same underlying abstraction: an
AI Agent operating in a kanban-relative specific role. They
share the same dimensional substrate at the requirement
layer — the same way of locating a journey node's identity
along five orthogonal axes.

Without this contract, J1–J5 dimension definitions live
inside each surface spec independently. Three failure modes
follow:

1. **Drift.** Each surface re-derives J1–J5 differently as
   it evolves. After two minor releases, "trigger carrier"
   means subtly different things across surfaces.
2. **Reuse blocker.** New specific roles (e.g., the §1.3.2-
   reserved Triager / Lint-runner) cannot inherit J1–J5
   from an existing surface; they re-derive from scratch.
3. **Methodology fragmentation.** The Stage 2 step
   ("locate each node on requirement-layer dimensions")
   in
   [`../../FEATURE_DESIGN_METHODOLOGY.md`](../../FEATURE_DESIGN_METHODOLOGY.md)
   cannot cite one canonical definition; it cites three,
   and ROI evaluations across surfaces become
   non-comparable.

This protocol pins the shared substrate. Surface specs
declare value distribution and node catalogs without
redefining the substrate.

## What this protocol IS — and is NOT

**This protocol IS:**

- The **canonical definition** of the five requirement-layer
  axes (J1–J5): trigger actor, trigger carrier, autonomy
  class, D-META-1 strength, result destination.
- The **enum value set** for each axis.
- The **cross-axis legal-combination matrix** — which axis
  pairs have constraints, which combinations are illegal
  by construction.
- The **versioning rule** for evolving the axis set or its
  value enums.

**This protocol is NOT:**

- A node catalog. Node catalogs (Producer's 21 nodes,
  Consumer's nodes, Bootstrap's nodes) live in their
  surface specs.
- A SKILL set. SKILL sets are derived from node catalogs
  by the ROI function in
  [`../../FEATURE_DESIGN_METHODOLOGY.md`](../../FEATURE_DESIGN_METHODOLOGY.md);
  this protocol is one input to that derivation.
- A surface-specific value-distribution observation. Each
  surface declares its own distribution (e.g., "Producer's
  agent-self / architect / nested ratio is 13/9/4"); this
  protocol does not.
- A trigger model. Trigger models in surface specs describe
  how each surface's node catalog actually fires; this
  protocol provides the vocabulary, not the mapping.

## The five orthogonal dimensions

### J1 — Trigger actor

**Question**: who pushes the door open to make this node
fire?

**Values** (discrete three-valued):

| Value | Meaning |
|-------|---------|
| `agent-self` | Agent fires the node from an internal signal — hook-injected `INVOKE:` marker, observe-phase state-change detection, previous routine's `conclude` deciding next-step. **No architect intervention required.** |
| `architect` | Architect must explicitly prompt (natural-language utterance or slash command) to wake the node. |
| `nested-within-routine` | The node lives inside another node's routine. Agent enters via internal branching during the outer routine; the node has **no independent trigger surface**. |

**Why this axis matters**: J1 partitions trigger-phrase
table size from "all nodes" to "only `architect`-class
nodes." Nodes in other classes are reached via different
mechanisms (J2 covers carrier choice).

### J2 — Trigger carrier

**Question**: which mechanism realizes the door-opening?

**Values** (discrete four-valued):

| Value | Meaning | Bandwidth |
|-------|---------|-----------|
| `session-hook` | Plugin runtime hook (CC `SessionStart`, `PreToolUse`, `PostToolUse`, `Stop`; equivalents in Codex CLI per [`../../PLUGIN_DEVELOPMENT.md`](../../PLUGIN_DEVELOPMENT.md)) injects context or invokes a SKILL. | **Finite** — every injected briefing item competes for the architect's per-session attention budget. |
| `cron-job` | External scheduler (system cron, CC scheduled jobs, GitHub Actions cron) calls the plugin entry on a cadence independent of any session. Governed by [ADR-0028](../adr/0028-cron-as-trigger-carrier.md) (complement to ADR-0007 — plugin-runtime constraints unchanged). | **Effectively unlimited** — cadences run concurrently, do not crowd the session interface. |
| `in-process-reflex` | An atomic SKILL invoked synchronously from a molecular SKILL's body during execution, per [ADR-0008](../adr/0008-plugin-to-plugin-skill-invocation.md). | **Zero latency, zero bandwidth cost** for the architect — the architect never sees the reflex directly. |
| `explicit-prompt` | Architect's own prompt is the trigger. (Sub-mode: in Mode-2 dispatch, the prompter may be a Producer agent rather than the architect — see § "Surface-specific extensions".) | **Bandwidth scales with the prompter's volition.** |

#### K-budget rule (session-hook capacity constraint)

The session-hook carrier has a per-session injection
capacity **K**. Empirically `K ≈ 4`. Exceeding K compresses
each item's salience to noise and silently exhausts the
architect's attention budget on session entry. Designs that
need to surface more than K items at session entry MUST move
excess items to a different carrier — typically `cron-job`
with a *compute / present split* (cron computes into
persistent state; session-hook reads state on entry).

This rule is the requirement-layer counterpart to P1
("architect attention is the bottleneck") in
[`../0001-positioning.md`](../0001-positioning.md). Without
it, P1 silently fails under hook-piggyback over-loading.

#### Carrier ladder (selection algorithm)

When choosing J2 for a node:

1. If the node fires on a fixed cadence independent of
   architect presence → `cron-job`.
2. If the node fires only after a mutating action →
   consider `in-process-reflex`.
3. If the node must be visible at session entry → check
   K-budget; if room, `session-hook`; if K saturated, use
   `cron-job` with persisted state, then read state on
   entry (compute / present split).
4. If the node requires architect's deliberate decision →
   `explicit-prompt`.

### J3 — Autonomy class

**Question**: under D-AUTONOMY-1
([ADR-0006](../adr/0006-producer-autonomy-boundary.md)),
what class is this node's mutating action?

**Values** (discrete three-valued):

| Value | Meaning |
|-------|---------|
| `A` | Auto with audit log. Agent acts; one audit row records the outcome. |
| `R` | Propose-then-await-approval. Agent surfaces the intent; awaits architect reply; on approval, acts; two audit rows (proposal + resolution). |
| `N` | Permanently rejected. Agent must refuse. *(v1 has no N-class entries; reserved.)* |

**Multi-phase note**: a node spanning multiple goal-loop
phases (e.g., a 5-step triage ladder) MAY have **different
J3 values per phase**. J3 is recorded per-phase, not
per-node, in those cases.

**Read-only nodes**: nodes with no mutating action are
J3 = N/A (e.g., daily briefing read of board state). N/A is
not a J3 value; it indicates J3 does not apply.

### J4 — D-META-1 strength

**Question**: does this node ship deterministic mechanism,
or does it ship a conversation framework that lets the
architect capture project-specific taste?

**Values** (discrete three-valued, anchored to
[`../0001-positioning.md`](../0001-positioning.md) P7 /
D-META-1):

| Value | Meaning |
|-------|---------|
| `low` | Deterministic mechanism only. No architect taste capture; the node ships rules / schemas / matrices. |
| `medium` | Semi-structured template. The node ships a framework (e.g., five-stage retrospective, INVEST checklist) within which the architect fills domain judgment. |
| `high` | Conversation-only. The node ships virtually no defaults; its entire value is the dialogue framework that extracts project-specific taste. |

**SKILL-form connection**: high-J4 nodes are naturally
**router SKILLs** (delegate to sibling skills, hold a thin
routing decision tree, refuse to ship generic defaults).
Low-J4 nodes are **executor SKILLs** (hold the mechanism
inline). Mismatching J4 to SKILL form produces either
over-engineered "configurable" SKILLs (low-J4 forced into
high-J4 form) or generic-defaults pollution (high-J4
implemented with hard-coded defaults).

### J5 — Result destination

**Question**: where does the node's output land?

**Values** (discrete four-valued):

| Value | Meaning |
|-------|---------|
| `inject-session` | Output enters the architect's current or next prompt context (briefing item, proposal pending reply, reminder). |
| `persist-state` | Output writes to durable state (GitHub Project field, host-local `state.yml`, audit DB, card body). |
| `emit-external` | Output goes to a third-party artifact (PR comment, commit, email, GitHub issue). |
| `inline-return` | Output is a context fragment passed back to an outer routine's next phase. (This destination ONLY applies to `nested-within-routine` nodes — see § "Cross-axis legal-combination matrix".) |

## Cross-axis legal-combination matrix

The five axes are **orthogonal in definition** (each answers
a distinct question), but **not every combination of values
is legal in practice**. The constraints below are pinned.

### J1 × J2

|              | session-hook | cron-job | in-process-reflex | explicit-prompt |
|--------------|--------------|----------|-------------------|-----------------|
| `agent-self` | ✓ | ✓ | — | — |
| `architect`  | — | — | — | ✓ |
| `nested-within-routine` | — | — | ✓ | — |

`✓` = legal. `—` = illegal. Rationale:

- `agent-self × in-process-reflex` — illegal because
  `in-process-reflex` is, by construction, called from a
  host routine; it cannot independently fire. A node that
  looks like `agent-self × in-process-reflex` is probably
  `nested-within-routine` misclassified.
- `architect × {session-hook, cron-job, in-process-reflex}`
  — illegal because architect-class nodes by definition
  require explicit prompt; other carriers do not surface
  the architect's volition.
- `nested-within-routine × {session-hook, cron-job, explicit-prompt}`
  — illegal because nested nodes have no independent
  trigger surface; only their host routine fires them, and
  the dispatch is in-process.

### J2 × J5

|              | inject-session | persist-state | emit-external | inline-return |
|--------------|----------------|---------------|---------------|---------------|
| `session-hook` | ✓ | ✓ | △ | — |
| `cron-job` | — | ✓ | ✓ | — |
| `in-process-reflex` | — | ✓ | △ | ✓ |
| `explicit-prompt` | ✓ | ✓ | ✓ | — |

`✓` = common. `△` = legal but rare. `—` = illegal.

Rationale:

- `cron-job × inject-session` — illegal because cron fires
  outside any session; the architect is not present to
  receive an injection. Cron must use `persist-state` or
  `emit-external`.
- `in-process-reflex × inject-session` — illegal because
  reflexes are called from molecular SKILL bodies; they
  return values inline (`inline-return`) or write state
  (`persist-state`); they do not cross the session
  boundary directly.
- `inline-return` is exclusive to `in-process-reflex`
  carrier (and to `nested-within-routine` actor by
  consequence) — other carriers cross a process or session
  boundary that `inline-return` cannot survive.

### J3 × J4

J3 (autonomy class) and J4 (D-META-1 strength) are
**independent** at this protocol level — any combination is
legal. Common patterns:

- `A × low` — atomic governance / audit reflex (e.g.,
  audit log writes).
- `R × low` — mechanical proposal awaiting approval (e.g.,
  branch deletion, status flip).
- `R × high` — conversational proposal (e.g., harness setup
  recommendations awaiting the architect's taste input).

There is no illegal J3 × J4 combination at this protocol
level. Surface specs MAY further constrain.

## Relationship to SKILL-layer dimensions

The four SKILL-layer axes are documented authoritatively in
[`../../SKILLS.md`](../../SKILLS.md):

- **Layer** — `entrypoint` / `molecular` / `atomic`
- **Nature** — `workflow` / `mental-model`
- **Goal-loop phase coverage** — Norman-1988-anchored
  phases (`receive` / `orient` / `plan` / `act` /
  `observe` / `reflect` / `surface` / `verify` /
  `conclude`)
- **Workflow coverage** — surface-specific (Producer
  workflows: daily / intake / decompose-handoff /
  review-queue; Consumer workflows: claim / implement /
  verify / submit / cleanup; Bootstrap: per
  `setup-stages` registry)

These are **independent** of J1–J5. J1–J5 locate a
*requirement node*; SKILL-layer axes locate the *artifact
that may implement* the node. The two coordinate systems
overlap **only** through the ROI function in
[`../../FEATURE_DESIGN_METHODOLOGY.md`](../../FEATURE_DESIGN_METHODOLOGY.md):
J1–J5 + node metadata feed the function, which produces a
SKILL set candidate whose entries each have a SKILL-layer
profile.

This protocol does NOT redefine SKILL-layer axes. Surface
specs and `SKILLS.md` own them.

## Surface-specific extension contracts

Each surface spec (Producer / Consumer / Bootstrap; future
specific roles) MUST:

1. **Cite this protocol.** A § "Orthogonal axes" or
   equivalent section that explicitly references this
   document and lists the five axes by name.
2. **NOT redefine J1–J5.** Surface specs do not contain
   axis definitions; they reference this document.
3. **Declare value distribution.** The distribution of node
   values across J1–J5 is surface-specific and goes in the
   surface spec (e.g., Producer's "13 agent-self / 9
   architect / 4 nested" finding).
4. **Declare divergence rationale, if any.** If a surface
   needs to *narrow* the value set (e.g., Consumer not
   using `cron-job` carrier for any node), the spec
   states why and which value is excluded.
5. **NOT broaden the value set.** A surface that needs a
   new value triggers a protocol revision (see §
   "Versioning + evolution"); it does not add the value
   inline.

### Mode-2 dispatch carrier disambiguation

When a Producer agent dispatches a Consumer subagent
(Mode-2 per [ADR-0008](../adr/0008-plugin-to-plugin-skill-invocation.md)
and the Producer surface redesign), the **Consumer
session's startup event is NOT a J2 value of any
Consumer-internal node**. It is a Consumer-session-level
lifecycle event, outside any individual node's J2.

From the Producer's outgoing-action perspective, dispatch
itself is a Producer node with `J2 = explicit-prompt` and
prompter = Producer-agent (sub-mode of explicit-prompt).
The protocol does not introduce a new J2 value for this
case; it is an explicit-prompt sub-mode noted in the
Producer surface spec's distribution declaration.

## Versioning + evolution

The five-axis structure is intentionally compact. Changes
follow stricter discipline than typical contract revisions.

### Adding a new dimension (J6 candidate)

**Threshold**: at least **two surface specs** independently
surface the same missing axis during their derivation. A
single surface's perceived gap is not sufficient — single-
surface gaps are usually distribution skews, not dimension
absences.

Rationale: dimension addition expands the design space of
every existing surface. The cost is high; the threshold
must match.

### Adding a value to an existing axis

**Threshold**: at least **one surface spec** demonstrates
that no existing value captures the case. The candidate
value is added to this protocol AND the relevant cross-
axis legal-combination matrix is updated AND every
existing surface spec is reviewed for the new
combination's applicability.

### Removing a value

Removed only if **no surface uses it** AND the value's
absence does not break the axis's coverage of its question
domain. Removals are rare; deferred-to-stub values stay in
the enum (e.g., `J3 = N` is reserved at v1 with zero
current entries).

### Same-PR contract update

Changes to this protocol trigger:

- Every surface spec citing the changed axis re-reviews
  its distribution declaration.
- The
  [`../AGENTS.md`](../AGENTS.md) spec change-impact matrix
  gets the row for the protocol-to-surface coupling
  walked.
- [`../../FEATURE_DESIGN_METHODOLOGY.md`](../../FEATURE_DESIGN_METHODOLOGY.md)
  re-reviews its Stage 2 description.
- An ADR records the protocol revision (if the change
  rises to architectural significance — e.g., new
  dimension; not for cosmetic clarifications).

## Open / TBD

- ~~**Cron-as-trigger-carrier ADR placement.**~~
  **Resolved 2026-04-29 by**
  [ADR-0028](../adr/0028-cron-as-trigger-carrier.md). Cron
  is an explicit, first-class external trigger carrier;
  ADR-0007's plugin-runtime constraints remain unchanged.
  The two ADRs co-exist as complementary rules — see
  ADR-0028 § Decision and § Alternatives considered for the
  full rationale. The carrier ladder no longer needs an
  Open item placeholder; the J2 `cron-job` row in § "J2
  — Trigger carrier" cites the governance ADR directly.
- **Sub-mode notation for explicit-prompt prompter.** When
  the prompter is the architect vs. a Producer agent
  (Mode-2 dispatch), should the protocol track this
  distinction with a sub-value (`architect-prompt` vs
  `agent-prompt`), or is the surface-spec prose sufficient?
  Currently prose; revisit when more Mode-2 patterns
  emerge.
- **Bootstrap surface application.** Bootstrap's stages
  registry already encodes a per-stage trigger model.
  Whether the 05 Bootstrap surface redesign reuses J1–J5
  verbatim or extends with stage-specific variants is open
  until the 05 redesign converges in a follow-up PR. Likely
  outcome: J1–J5 reused verbatim; stage-specific variants
  expressed as distribution observations, not new values.
