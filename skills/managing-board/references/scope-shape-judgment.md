# Scope-shape judgment — manager-side intake reference

> **Scope**: this file owns *which scope/level* a fresh
> requirement should land at — single card, multi-card sharing
> a milestone, milestone-grouped within a release-gate, or
> cross-release roadmap. It also owns the trigger for "do we
> hand this off to `decomposing-into-milestones`?".
>
> **Out of scope** — this file does NOT own the *how* of
> decomposition. INVEST application, SPIDR vertical-slicing
> mechanics, size calibration, and the converged Card body
> schema are owned by
> [`board-superpowers:decomposing-into-milestones`](../../decomposing-into-milestones/SKILL.md).
> For the **how** of decomposition, see that skill's
> references — explicit pointers per decision below.

This reference is consumed by the `intake.md` decision tree
(see § "Decision tree extension" in `intake.md`) and by the
`managing-board` SKILL body's intake routine.

## Primary-source vocabulary

The hierarchy and vocabulary in this file are anchored to four
canonical primary sources. Each was selected because it covers
the multi-level-aggregation territory **above** what
`decomposing-into-milestones` (#35) covers (story-level
slicing). The sources are borrowed for *structural* shape
only — cadence assumptions (sprints, iterations, fixed-length
release cycles) are explicitly NOT inherited because AI
orchestration collapses time grain ~100× (per the project's
AI-cadence reframe convention).

| Source | What it gives this file | Borrow / reframe boundary |
|--------|------------------------|---------------------------|
| Cohn, *Agile Estimating and Planning* (Prentice Hall 2005, ISBN 978-0131479418) — § "Planning Onion" | Six concentric horizons (strategy / portfolio / product / release / iteration / day). | Borrow: layered-horizons shape. Reframe: collapse time grain (iteration ≈ session, release ≈ days, portfolio ≈ release-gate cycle). Reject: fixed sprint cadence, mandatory ceremonies. |
| Patton, *User Story Mapping* (O'Reilly 2014, ISBN 978-1491904909) — § "The Big Picture" | Backbone activities → tasks → stories hierarchy spanning release + multi-release. | Borrow: backbone-tasks-stories vocabulary for cross-card aggregation. Reframe: replace "story-mapping workshop" with the architect's intake conversation. |
| Cockburn, *Crystal Clear* (Addison-Wesley 2004, ISBN 978-0201699470) + c2 wiki <https://wiki.c2.com/?WalkingSkeleton> — § "Walking Skeleton" | Lower bound for vertical slicing on a brand-new feature surface. | Borrow: "first card across a brand-new surface should be the smallest end-to-end skeleton". Reframe: unit is *the feature surface*, not always *the whole system*. |
| Denne & Cleland-Huang, *Software by Numbers* (Prentice Hall 2003, ISBN 978-0131407282) — § "Minimum Marketable Features" | Criterion for what makes a milestone *correct*: a coherent grouping of cards that delivers measurable value when shipped together. | Borrow: MMF-criterion shape. Reframe: "Marketable" → "Useful" (this is a developer-tools plugin, no paying customer). |

For full audit detail (which page numbers, which alternative
sources were considered and rejected, and why each reframe is
needed), see the gitignored audit at
`docs/plans/manager-decision-frameworks/canonical-practice-audit.md`
on the implementing branch.

## Table 1 — Shape level for a fresh requirement

The four-row hierarchy. Each row maps to one Cohn Planning Onion
horizon (strategy + day deliberately omitted — strategy lives
in `0001-positioning.md` and day-level planning is the
architect's, not the manager skill's). Rows are evaluated
top-down; the first row whose triggers fire wins.

| Shape | Cohn horizon | Patton level | Triggers — fire any one | Outcome |
|-------|--------------|--------------|------------------------|---------|
| **Cross-release roadmap** | portfolio | (above backbone) | (a) requirement crosses two or more plugin-version transitions; (b) requirement names a release-gate or cross-version umbrella; (c) requirement bundles features that will not all ship in one cycle. | Defer card creation. Surface to architect: "this is roadmap-level — a positioning doc or umbrella card belongs in `docs/architecture/` first". DO NOT decompose into cards yet. |
| **Milestone-grouped within a release-gate** | release | backbone | (a) the requirement names a coherent shipped-together unit (a release-gate umbrella card, an "audit-pipeline-rollout" group, etc.); (b) the cards in the group together deliver Denne-MMF-shaped value (shipping any subset alone delivers strictly less); (c) cards span 2 or more bounded contexts (e.g., audit + bootstrap, or board + spec). | Use the **umbrella-card-with-soft-`depends-on:`** pattern (this is the project's de-facto milestone substitute — see Table 2). Then route to #35 with the umbrella card as anchor. |
| **Multi-card sharing a milestone** | release sub-batch | tasks | (a) requirement adds 2-N independent capabilities that are conceptually one feature; (b) Independence (INVEST-I) holds across the candidate cards (one can ship before another); (c) **expected internal chunk count >5** — empirical signal that single-card scope will reactively chunk into a multi-PR sequence. | Route to #35 (`decomposing-into-milestones`). The skill's INVEST + SPIDR pipeline produces N cards. Optionally use the umbrella-card pattern if the N cards together are MMF-coherent. |
| **Single card** | iteration | story | (a) a single user-visible / developer-visible capability; (b) Estimable as XS / S / M / L (no extension into "we'll see"); (c) no cross-card design A/B requiring shared rationale (in-card design A/B is fine and uses [`skill-routing.md`](./skill-routing.md) Table 3 template — #43 / #44 / #45 are precedents); (d) belongs in one bounded context. | Direct card creation via `intake.md` § "Direct card creation". Use #35's `card-schema.md` for the body shape. |

### Rationale for the "expected internal chunk count >5" trigger

The trigger is empirical, drawn from project history: cards
#28 (bootstrap, landed via 7-slice PR) and #35 (decomposing
skill, landed via 6-chunk PR) both reactively chunked into
multi-PR sequences after intake said "single card". Reactive
chunking is more expensive than upfront decomposition under
AI cadence — each chunk pays a separate review tax and the
work-in-progress shape is opaque to the architect during
implementation. When the manager skill's intake estimate
projects >5 internal chunks, the requirement is empirically
multi-card-shaped; the right move is to route to #35 upfront,
not to claim "single card" and chunk reactively.

The threshold (>5) is calibrated to the two known misses; if
future cards reveal the threshold should be lower (e.g., >3),
revise this row in the same PR that reports the third
calibration miss.

### Walking-skeleton hint when shape lands at #35

When Table 1 routes to #35 AND the requirement targets a
**brand-new feature surface** (no prior card crosses this
surface), the manager skill emits an explicit hint into the
hand-off: "first card should be a walking skeleton" (per
Cockburn — smallest end-to-end implementation that exercises
every architectural layer). The hint goes into the
intake-to-#35 handoff message; #35's vertical-slicing gate
will enforce the hint via its layer-only and trailing-wire-up
refusals (per
[`board-superpowers:decomposing-into-milestones/references/decomposition-patterns.md`](../../decomposing-into-milestones/references/decomposition-patterns.md)
§ "Five splitting mistakes"). The manager skill does not
itself author the skeleton card; it just flags the surface as
new.

A "brand-new feature surface" means: no existing card / spec
section / SKILL has previously authored functionality at this
surface. Examples that would qualify: a new BoardAdapter
implementation; a new sibling-plugin integration; a new
top-level skill. Examples that would NOT qualify: extending
an existing skill's references, refining an existing ADR, a
follow-up bug-fix to a feature that already shipped.

## Table 2 — Milestone field vs `depends-on:` chain vs label

Three options for expressing cross-card relationships. Each
row says "use when …", "anti-pattern" (don't), and an example.

| Mechanism | Use when | Anti-pattern | Example |
|-----------|----------|--------------|---------|
| **GitHub Project Milestone field** | the cards form a coherent Denne-MMF-shaped group AND the architect wants explicit milestone-level reporting (e.g., "what's left in this release-gate?"). Recognized but **not currently used** in this project — see § "Milestone field substitute" below. | "Milestone as topic tag" — labels are for category/type, milestones are for shipped-together-value units. Don't use a milestone to mean "all cards about audit". | A future release-gate milestone bundling all the cards under one umbrella, including any roadmap-level atomics still on the backlog. |
| **`depends-on:` chain** (hard) | one card cannot start until another finishes. Strict ordering. | Long chains (>3) — that's a missed multi-card decomposition opportunity; the chain is hiding a milestone-grouped shape. | #34 `depends-on: #33` (hard) — governance skills cannot land before their spec rows do. |
| **`depends-on (soft):`** | one card prefers another to land first but can ship in either order. Used to bind a card to an umbrella card without forcing strict ordering. | Treating soft-depends as schedule glue — soft-depends carries no scheduling semantics, only "if both are in flight, prefer this order". | #43 / #44 / #45 each carry `depends-on: #38` (soft) — #38 is the v1-release-gate umbrella. The cards land in any order that the verification chain allows. |
| **Label** | category / type tagging only. `type:feature`, `type:bug`, `type:chore`, `size:S/M/L`, `security`. NOT for shape grouping. | Using labels to mean "v1 work" or "audit work" — that's the milestone field's job (or the umbrella-card pattern's). | The labels actually used: `type:feature`, `type:bug`, `type:chore`, `size:M`, `security`. None convey shape. |

### Milestone field substitute — umbrella card + `depends-on (soft):`

This project has not used the GitHub Milestone field. Instead,
a stable convention has emerged across cards #38 → #43 → #44 →
#45: an **umbrella card** declares the milestone's intent in
its body, and member cards bind to it via
`depends-on (soft): #<umbrella>`. The umbrella card is itself
a real card on the board (it can have AC, can be claimed) but
its primary role is to anchor the milestone-shaped grouping.

The umbrella-card substitute has two properties that the
GitHub Milestone field does not:

1. **The umbrella card carries body content.** Architect
   intent, scope boundary, and "what's in / out" live on the
   card itself; not in a milestone description that fewer
   readers find.
2. **The umbrella card participates in the same governance.**
   The classify / audit pipeline applies. A milestone field
   change has no `action_id`; an umbrella-card edit is
   `action_id = 2`.

Recognize the convention. Do NOT push a switch to the
Milestone field unless an architect requests it explicitly.
Future revision: if cross-release reporting becomes
load-bearing, AC2 should add a row promoting the Milestone
field for *that* use; until then, umbrella-card-with-soft-
`depends-on:` is the canonical milestone substitute.

## Table 3 — When to invoke `decomposing-into-milestones` (#35)

Entry conditions only. The *how* of decomposition lives entirely
inside #35's references — this table just decides whether to
route there.

| Trigger | Action | Pointer to #35's "how" |
|---------|--------|-----------------------|
| Multi-capability requirement (Table 1's "multi-card sharing a milestone" or "milestone-grouped" row fires) | Route to #35 with the requirement as input artifact. If a brand-new feature surface, attach the walking-skeleton hint. | INVEST: [`invest-checklist.md`](../../decomposing-into-milestones/references/invest-checklist.md). Vertical slicing: [`decomposition-patterns.md`](../../decomposing-into-milestones/references/decomposition-patterns.md). Sizing: [`size-calibration.md`](../../decomposing-into-milestones/references/size-calibration.md). Card schema: [`card-schema.md`](../../decomposing-into-milestones/references/card-schema.md). |
| Requirement looks single-card-sized but the architect wants a sanity check | Optional handoff to #35 in `freeform` mode (`/board-superpowers:decomposing-into-milestones -`). #35 will route back to manager intake if the artifact is <30 lines. | Same files as above. |
| Requirement has no clear capabilities (rambling design notes) | Do NOT route to #35 yet. Route to `superpowers:brainstorming` first; #35 needs a sharpened artifact (per its Failure-modes table). | n/a — bring the artifact back for re-routing once sharpened. |
| Single-card requirement with clear AC | Skip #35. Use `intake.md` § "Direct card creation"; for the card body shape, follow #35's [`card-schema.md`](../../decomposing-into-milestones/references/card-schema.md) directly (the schema is shared). | Schema only: [`card-schema.md`](../../decomposing-into-milestones/references/card-schema.md). |
| Pure refactor with no new capability | Skip #35. INVEST gating doesn't apply (no user-visible / developer-visible value to test against); route to direct claim. | n/a. |

The boundary is sharp: #35 owns INVEST + SPIDR + sizing + the
terminal Card body schema authority. This file owns "should
the requirement go through #35 at all, and at what shape?".
Crossing the boundary in either direction (#35 making shape
calls, or this file inlining INVEST mechanics) creates drift
and duplicates content.

## Worked retrofit traces

Running this file's tables on past cards to verify the encoded
judgments reproduce actual decisions:

- **#43** (bootstrap audit drift fix, M, single card with
  design-A/B AC). Table 1: triggers "(d) belongs in one
  bounded context" — bootstrap; AC has design A/B but that
  doesn't change shape. → Single card. Table 2: `depends-on:
  #38 (soft)` — umbrella substitute. Table 3: skip #35
  (single card). **Reproduces actual decision.**
- **#44** (card schema platform field, S, single card). Same
  trace as #43. **Reproduces actual decision.**
- **#45** (this card, M, single card with rich AC). Table 1:
  triggers "(c) NO design A/B requiring rationale capture" is
  borderline (AC4 codifies the design-A/B template, but the
  card itself doesn't *use* it for an A/B). The architect's
  intake judgment was "single card with rich AC" because the
  three sub-judgments (shape / spec-first / routing) are
  nested decisions in one intake step (per the card body
  Notes). **Reproduces actual decision; borderline case
  surfaces correctly.**
- **#28** (bootstrap v0.2.0, S → reactive 7-slice). Table 1:
  trigger "(c) expected internal chunk count >5" would have
  fired given the eventual 7-slice shape. → Multi-card
  sharing a milestone. **Trace catches the calibration miss
  retroactively.**
- **#35** (decomposing skill, S → reactive 6-chunk). Same
  trace as #28. **Trace catches the calibration miss
  retroactively.**

The two retroactive catches (#28, #35) are the empirical
basis for the ">5 chunks" trigger row in Table 1. Future
cards that fire the trigger should land as multi-card from
intake, eliminating the reactive-chunking pattern.

## When this file is wrong

If running these tables against a fresh requirement produces
a shape decision that the architect overrides, that is the
signal to revise this file in the same PR as the override.
The file is calibrated to project reality, not aspirational —
overrides are evidence the calibration drifted.
