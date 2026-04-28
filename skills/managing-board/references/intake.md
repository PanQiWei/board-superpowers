# managing-board — intake routine reference

This file is the **decision tree** the Producer's intake
routine walks when a fresh requirement arrives. It composes
three sibling references that own different parts of the
decision:

- [`scope-shape-judgment.md`](./scope-shape-judgment.md) —
  decides shape (single-card / multi-card sharing a milestone /
  milestone-grouped / cross-release roadmap).
- [`spec-first-checklist.md`](./spec-first-checklist.md) —
  confirms which spec artifacts must land first (and whether
  the work is itself spec).
- [`skill-routing.md`](./skill-routing.md) — picks the
  pre-card sibling skill (`gstack:/*`, `superpowers:*`, or
  `decomposing-into-milestones`) and frames manager-locked
  vs consumer-deferred design.

The tree below is the spine; each branch points at the
reference file that owns the detailed decision.

## Decision tree at a glance

```
fresh requirement arrives
    │
    ▼
Step 1 — Acknowledge + clarify scope
    │
    ▼
Step 2 — Shape judgment   ─────────────────► consult scope-shape-judgment.md
    │ (Table 1 of that file decides)
    │
    ├── "cross-release roadmap"   ─────────► defer card creation; surface as positioning doc / umbrella
    │
    ├── "milestone-grouped"       ─┐
    │                              │
    ├── "multi-card"               │  ─────► route to decomposing-into-milestones (#35)
    │                              │         (use umbrella-card pattern if Denne MMF holds)
    │                              │
    └── "single card"              │
                                   │
                                   ▼
Step 3 — Spec-first preconditions ────────► consult spec-first-checklist.md
    │ (rows 1-6 of that file check)
    │
    ├── precondition fires       ─────────► land spec edit (separate PR or same-PR
    │                                          paired); pause card creation until spec
    │                                          merges (or paired-PR is in flight)
    │
    └── no precondition fires
                                   │
                                   ▼
Step 4 — Skill routing            ────────► consult skill-routing.md
    │ (Table 1 of that file decides)
    │
    ├── direction question        ─────────► gstack:/office-hours or /plan-ceo-review
    ├── architecture question     ─────────► gstack:/plan-eng-review
    ├── needs sharpening          ─────────► superpowers:brainstorming → re-enter at Step 2
    ├── multi-card shape          ─────────► decomposing-into-milestones (#35)
    └── single-card, ready to draft ──────► proceed to "Direct card creation" below

(After any sibling skill produces output, return to Step 2 with the
sharpened artifact — usually shape becomes obvious once the sibling
runs.)
```

## Step 1 — Acknowledge

Repeat back the requirement in 1-2 sentences. Confirm
understanding before shaping. The cost of asking is low; the
cost of routing wrong is a sibling-skill invocation that
produces useless output.

## Step 2 — Shape judgment

Run [`scope-shape-judgment.md`](./scope-shape-judgment.md)
Table 1 (shape level) against the requirement. The table's
four rows (cross-release roadmap / milestone-grouped /
multi-card / single card) cover all the shapes the project
sees. Common cases:

- **Multi-capability requirement** with 2-N independent
  capabilities → "multi-card sharing a milestone" or
  "milestone-grouped".
- **Single capability** with clear AC → "single card".
- **Vision / strategy / cross-version work** → "cross-release
  roadmap" — defer card creation entirely.

If the requirement is multi-card-or-larger AND on a brand-new
feature surface, attach a **walking-skeleton hint** to the
hand-off (per
[`scope-shape-judgment.md`](./scope-shape-judgment.md) §
"Walking-skeleton hint"). The hint propagates into #35's
decomposition pipeline; #35 enforces it via the
vertical-slicing gate.

## Step 3 — Spec-first preconditions

Run [`spec-first-checklist.md`](./spec-first-checklist.md)
rows 1-6 against the requirement. If a row's trigger fires:

- Architect chooses **separate-PR** (spec lands first; card
  created against merged spec) or **same-PR paired** (spec
  edit + implementation in one PR).
- Pause card creation until the spec change is at least in
  flight (paired) or merged (separate).
- Row 6 (spec-only PR) means the card's Goal IS "land this
  spec"; create the card normally — no separate spec
  precondition needed.

## Step 4 — Skill routing

Run [`skill-routing.md`](./skill-routing.md) Table 1 against
the requirement. The table picks the sibling skill (or direct
creation) by signal type, not by literal phrasing. Surface the
routing call to the architect as a sentence so the architect
can override before the sibling fires:

> This reads as architecture-decision territory (which
> Postgres pooler should we adopt). Routing to
> `gstack:/plan-eng-review` for the design lock; report back
> with the artifact.

After the sibling skill completes, the Producer takes the
artifact and **re-enters at Step 2** — usually the shape
becomes obvious once the sibling has run (the design that
seemed multi-card might land as single-card, or vice versa).

## Direct card creation (single-card-sized)

When Step 2 → Step 3 → Step 4 land at "single card, ready to
draft":

1. Draft the card body using the Card body schema from
   [`board-superpowers:board-canon`](../../board-canon/SKILL.md)
   (terminal schema authoritatively also documented at
   [`decomposing-into-milestones/references/card-schema.md`](../../decomposing-into-milestones/references/card-schema.md)):
   - thin-pointer (Spec / Owner / Estimate)
   - Goal (1 sentence)
   - Acceptance criteria (≥ 2 verifiable bullets; consult
     [`skill-routing.md`](./skill-routing.md) Table 3 for the
     "design-left-to-consumer" template if any AC is a
     deferrable design A/B)
   - Out of scope
   - Dependencies (per
     [`scope-shape-judgment.md`](./scope-shape-judgment.md)
     Table 2 — `depends-on:` chain or umbrella-card-with-soft-
     `depends-on:`)
   - Notes
2. **Show the draft to the architect; do NOT create yet** —
   card creation is a mutating action (`action_id = 1`); the
   classify / audit pipeline applies. Per
   [`board-superpowers:classifying-actions`](../../classifying-actions/SKILL.md),
   default is A but the architect can override via
   `autonomy_overrides:` to demand R for card creation.
3. After acknowledgement: `gh issue create --title <title>
   --body <body>` then add to project + set
   `Status = Backlog → Ready` per
   [`board-superpowers:board-canon`](../../board-canon/SKILL.md)
   § "State machine".
4. Append an audit-log entry recording the card creation via
   [`board-superpowers:auditing-actions`](../../auditing-actions/SKILL.md).

## Cross-plugin handoff syntax

When routing to a sibling plugin's skill, use the namespace
prefix and explain WHY the routing applies. The framing is
consumed by [`skill-routing.md`](./skill-routing.md) Table 1:

```
This requirement reads as architecture-decision territory (which
Postgres pooler should we adopt). Routing to `gstack:/plan-eng-review`
for the design lock; report back with the artifact.
```

After the sibling skill completes, the Producer takes the
artifact (a doc, a decision record) and continues the intake
— usually returning to Step 2 above with a now-clearer scope.

## When to NOT route

If the requirement is genuinely just "fix this typo": skip
intake entirely, do it in a 1-line PR yourself, no card
needed. The intake routine assumes work that benefits from
being tracked on the board. Per
[`scope-shape-judgment.md`](./scope-shape-judgment.md)
Table 1's note — pure refactors with no new
user-visible / developer-visible capability also skip INVEST
gating; they route to direct claim, not to #35.

## Decline policy

If the requirement is misaligned with the project's premises
(per the project's positioning doc / non-goals — see
[`docs/architecture/0001-positioning.md`](../../../docs/architecture/0001-positioning.md)
P1..P8 + non-goals), the intake routine produces a
"we won't do this and here's why" response. The architect can
override; the routine surfaces the conflict explicitly so the
override is conscious.

## Worked retrofit traces

Running the four-step tree against past cards reproduces
their actual shape decisions:

- **#34** (governance skills, M, single card). Step 2: shape
  = single card (one bounded-context-spanning capability that
  must land atomically). Step 3: rows 1 + 3 fire; ADR-0006 +
  spec 06 land separate-PR. Step 4: direct creation (no
  sibling skill needed once spec is settled). **Reproduces.**
- **#38** (release-gate umbrella, S, single umbrella card).
  Step 2: shape = single card (the umbrella card itself; the
  cards under the umbrella are separate intakes that bind via
  soft-`depends-on:`). Step 3: row 6 fires (the umbrella body
  IS the spec for the gate); no separate spec precondition.
  Step 4: direct creation. **Reproduces — and confirms the
  umbrella-card pattern as a legitimate single-card shape
  even when the body's purpose is to anchor a milestone.**
- **#43** (audit drift fix, M, single card with AC4
  design-A/B). Step 2: single card (one bounded-context fix).
  Step 3: row 1 fires; F-B2 spec edit bundled same-PR. Step 4:
  direct creation; AC4 uses
  [`skill-routing.md`](./skill-routing.md) Table 3 template.
  **Reproduces.**
- **#44** (card schema platform field, S, single card with
  AC1 + AC3 design-A/B). Step 2: single card (one schema
  field addition). Step 3: row 6 partial — the schema edit
  is itself the spec; the implementation card claims the
  same PR. Step 4: direct creation; AC1 + AC3 use
  [`skill-routing.md`](./skill-routing.md) Table 3 template
  (same shape as #43). **Reproduces.**
- **#45** (this card, M, single card with rich AC). Step 2:
  single card (the three sub-judgments are nested in one
  intake step per the card's Notes). Step 3: row 6 partially
  fires — references files are skill-level spec; AC6 adds a
  change-impact-matrix row. Step 4: direct creation;
  `docs/plans/manager-decision-frameworks/` is mandatory
  (canonical-practice audit). **Reproduces.**
- **#28** (bootstrap v0.2.0, S → reactive 7-slice). Step 2:
  shape would have triggered "(c) expected internal chunk
  count >5" — multi-card. Step 3: row 5 fires; spec edits
  paired same-PR. Step 4: would have routed to #35 (had it
  existed at the time of #28; #35 didn't exist until later
  in v0.4.0). **Trace catches calibration miss; #35's
  unavailability at the time explains why intake did not
  decompose.**
- **#35** (decomposing skill, S → reactive 6-chunk). Same
  trace as #28. **Trace catches calibration miss
  retroactively.**

The two retroactive catches feed back into
[`scope-shape-judgment.md`](./scope-shape-judgment.md)'s ">5
chunk" trigger. Future cards firing the trigger should land
multi-card from intake, eliminating reactive chunking.

## When this file is wrong

If running the tree on a fresh requirement produces a
different routing than what the architect actually picks,
that's the signal to revise this file (or one of the three
sibling references) in the same PR that records the override.
The tree is calibrated to project reality, not aspirational.
