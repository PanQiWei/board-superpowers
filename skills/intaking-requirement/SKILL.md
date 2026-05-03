---
name: intaking-requirement
description: |
  Use when the user brings a new requirement, idea, feature, bug, defect, or
  request that needs to be evaluated and potentially turned into a card on the
  board. Triggers on: "new requirement", "intake this idea", "I have a feature",
  "add a card", "new card", "I want to build", "I have an idea", "I have a bug",
  "I have a defect", "found an issue", "create a card for",
  "put this on the board", "let's intake".
  Use even when the user phrases it casually ("I've been thinking about X",
  "can we add Y", "we should fix the broken Z") — the signal of bringing new
  work is what matters.
  Do NOT use when the user wants to see current board state (that's
  briefing-daily), review open PRs (reviewing-pr-queue), investigate blocked
  cards (triaging-board), or decompose an already-decided multi-card requirement
  into INVEST-shaped cards (that's decomposing-into-milestones directly).
when_to_use: |
  Trigger on: "new requirement", "intake this idea", "I have a feature",
  "add a card", "create a card", "new card", "put this on the board",
  "I want to build X", "let's capture this", "fresh requirement".
  Apply when the Producer brings work that hasn't been shaped yet.
---

# intaking-requirement

This is the Producer's intake routine. It acknowledges a fresh requirement,
runs a 4-step pipeline (shape judgment → spec-first check → skill routing →
card creation), and ends with either a design artifact handed to a sibling
skill or a Ready card on the board.

**Required sub-skills**:
- `board-superpowers:board-canon` — Card body schema for direct card creation;
  state machine for Status transitions.
- `board-superpowers:operating-kanban` — dispatch the `create_card` protocol
  action when creating a card; resolves the active projection from settings.
- `board-superpowers:composing-siblings` — consult before routing to any
  sibling-plugin skill (`gstack:*`, `superpowers:*`). Provides namespace
  prefix rules, Mode-2 max_depth=1 compatibility check, and per-phase
  routing table.
- `board-superpowers:classifying-actions` + `board-superpowers:auditing-actions`
  — applied at every mutating action in this routine.

## Overview

Intake is the gateway between "I have an idea" and "there is a card on the
board that a Consumer can claim." Its job is to keep the design discipline
intact — shape decisions belong at intake, not mid-implementation.

The four-step pipeline:
1. **Acknowledge** — repeat back, confirm scope.
2. **Shape** — decide the requirement's structural level (single card / multi-
   card / milestone-grouped / cross-release roadmap).
3. **Spec-first check** — verify any prerequisite spec artifacts are in place.
4. **Route** — pick the right sibling skill OR create the card directly.

Intake is NOT a design session. If the requirement needs exploration, route to
the appropriate sibling skill and return when the sibling produces output.
Each return from a sibling skill re-enters the pipeline at Step 2 — the shape
judgment may change once the sibling produces a refined artifact. The pipeline
is a loop, not a one-shot sequence; iterate until the shape resolves to
"single card, ready to draft" or the requirement is explicitly declined.

## Step 1 — Acknowledge

Repeat back the requirement in 1-2 sentences. Confirm understanding before
shaping. Keep it brief: "You want to add X so that Y, correct?" Ask one
clarifying question if the scope is genuinely ambiguous. The cost of asking
is low; the cost of routing wrong is a sibling-skill invocation that produces
useless output.

## Step 2 — Shape judgment

Read `references/scope-shape-judgment.md` Table 1. The table has four rows
(cross-release roadmap / milestone-grouped / multi-card sharing a milestone /
single card). The first row whose triggers fire wins.

Shape outcomes:
- **Cross-release roadmap** → stop. Surface to the Producer: "This reads as
  roadmap-level — a positioning doc or umbrella card belongs in the
  architecture spec first. No card created yet."
- **Milestone-grouped** or **multi-card** → route to
  `board-superpowers:decomposing-into-milestones`. Attach a walking-skeleton
  hint if the requirement targets a brand-new feature surface.
- **Single card** → proceed to Step 3.

The design discipline gate (G4) applies here: the intake → decompose pipeline
cannot be skipped for multi-card requirements. If the Producer says "just make
one card," but the shape judgment says multi-card, surface the conflict. The
Producer can override — record the override in the card body's Notes.

## Step 3 — Spec-first check

Read `references/spec-first-checklist.md`. Run each of the six rows against
the requirement:

| # | Fires when | Action required |
|---|-----------|-----------------|
| 1 | Touches multiple bounded contexts | ADR or spec edit first |
| 2 | Adds a new cross-plugin edge | `SKILLS.md` update first |
| 3 | Changes audit/action_id/autonomy schema | ADR + schema spec first |
| 4 | Affects routing block or hook grammar | Hook contracts spec edit first |
| 5 | Modifies host-local state layout | Path-conventions spec first |
| 6 | This work IS the spec itself | No pre-card artifact needed |

If a row fires: pick separate-PR (spec first, then card) or same-PR paired
(spec + implementation together). Pause card creation until the spec precondition
is at least in flight. Surface the spec edit to the Producer as a sentence:
"This touches the audit schema — row 3 fires. The autonomy matrix needs updating
before the card ships. Separate-PR or same-PR paired?"

If no row fires: proceed to Step 4.

## Step 4 — Route or create

Read `references/intake-decision-tree.md` for the pre-card skill routing
table. The routing table fires by signal type, not literal phrasing.

**Direction question** ("should we build this?", "is this real demand") →
Invoke `board-superpowers:composing-siblings`, then route to
`gstack:/office-hours` or `gstack:/plan-ceo-review`. Surface the routing call
to the Producer before routing: "This reads as 'is this worth building'
territory. Routing to `gstack:/office-hours` for a demand-reality check."

**Architecture decision** ("which storage", "schema choice", "adapter shape") →
Invoke `board-superpowers:composing-siblings`, then route to
`gstack:/plan-eng-review`. Surface: "This reads as architecture-decision
territory. Routing to `gstack:/plan-eng-review` for the design lock."

**Design sharpening** ("let's explore", "I'm not sure of the design",
multi-step but direction-set) → Invoke `board-superpowers:composing-siblings`,
then route to `superpowers:brainstorming`. After brainstorming completes,
re-enter at Step 2 with the sharpened artifact.

**Multi-card** (Step 2 routed here) → Route to
`board-superpowers:decomposing-into-milestones` with the requirement artifact.
After decomposition completes, the cards are on the board — this routine ends.

**Single card, ready to draft** → proceed to § "Direct card creation".

After any sibling skill produces output, re-enter at Step 2 with the sharpened
artifact — usually the shape becomes clear once the sibling has run.

## Direct card creation

When Steps 2–4 land at "single card, ready to draft":

1. Draft the card body using the Card body schema from
   `board-superpowers:board-canon` § "Card body schema":
   - Thin pointer (Spec / Owner / Estimate)
   - Goal (1 sentence)
   - Acceptance criteria (≥ 2 verifiable bullets)
   - Out of scope
   - Dependencies (if any)
   - Notes

2. **Show the draft to the Producer; do NOT create yet.** Card creation is a
   mutating action (action_id = 1). Apply the 5-step governance sequence
   from § "How mutating actions are handled" below. Default autonomy class is
   A (auto), meaning the Producer's acknowledgement of the draft satisfies
   the propose step.

3. After acknowledgement, prepend the creator-trace marker block to the body:
   ```bash
   creator_trace="$(bsp_render_creator_trace_block)"
   body="${creator_trace}
   ${body}"
   ```
   The `bsp_render_creator_trace_block` helper is in `scripts/lib/common.sh`.
   Then dispatch the `create_card` protocol action via
   `board-superpowers:operating-kanban`.

4. Set Status to Ready (or Backlog if the card needs further sizing before
   claiming). Status transition is also mutating — apply the governance
   sequence (action_id = 3 for Status flip to Ready).

5. Invoke `board-superpowers:auditing-actions` to record the card creation.

## How mutating actions are handled

Every mutating action this skill performs (card creation, Status flip, card
body edit) follows this 5-step governance sequence:

At each mutating action point in this routine:
1. Resolve the action_id (from `board-superpowers:classifying-actions`
   `references/action-id-catalog.md`).
2. Invoke `board-superpowers:classifying-actions` with that action_id;
   receive A (auto), R (requires approval), or N (forbidden).
3. If A: act → invoke `board-superpowers:auditing-actions` to record one
   entry.
4. If R:
   a. Invoke `board-superpowers:auditing-actions` to record the proposal.
   b. Surface the proposal to the Producer.
   c. Wait for the Producer's reply (approve / decline).
   d. On approve: act → invoke auditing-actions to record the result.
   e. On decline: invoke auditing-actions to record the decline; abort.
5. If N: refuse the action and surface the block reason; no audit entry.

## Decline policy

If the requirement conflicts with the project's stated premises or non-goals,
produce a clear "we won't do this because..." response. The Producer can
override — the intake routine surfaces the conflict explicitly so any override
is conscious and documented. Record the override and rationale in the card's
Notes section so the decision is traceable.

## When NOT to route

Tiny fixes that genuinely don't warrant a card (one-line typo, trivial
config change) skip intake entirely. Make the change directly, no card needed.
Intake assumes work that benefits from board tracking.

Work that is clearly out of scope for the project (conflicts with a recorded
project premise or stated non-goal in the project's architecture spec)
does not go through the full 4-step pipeline. Decline with a clear rationale
in Step 1 and do not proceed further. The Decline policy section below
governs this path.

## Cross-plugin handoff syntax

When routing to a sibling plugin's skill (via `board-superpowers:composing-siblings`),
always surface the routing decision before routing:

```
This reads as architecture-decision territory (which Postgres pooler to adopt).
Routing to `gstack:/plan-eng-review` for the design lock; report back with the
artifact.
```

After the sibling completes, resume intake at Step 2 with the output artifact.

## Autonomy defaults for this routine

| Action | Default class | Rationale |
|--------|--------------|-----------|
| Card creation (new card on board) | A (auto) | Standard intake output; Producer drove the session. |
| Status flip to Ready | A (auto) | Follows card creation; redundant proposal adds friction. |
| Card body edit (after creation, pre-claim) | R (requires approval) | Mutates existing work; Consumer may have already read the body. |
| Sibling-plugin routing decision | A (auto) | Routing is informational; no board mutation. |

Rationale for A-class card creation: the intake routine is explicitly
Producer-driven. The Producer participated in Steps 1-4 and the card draft
was shown before creation — the propose step is satisfied by the inline
review, not a separate R-class approval round.

## Failure modes

| Situation | Correct handling |
|-----------|-----------------|
| Producer says "just make the card" but shape judgment fires multi-card | Surface the conflict explicitly. Record the override in Notes if the Producer insists. Do NOT silently create a single card. |
| Spec-first check fires but Producer wants to proceed immediately | Surface the risk. Record the spec-precondition skip in Notes: "Skipping spec-first check — <reason>. Follow-up ADR pending." Do NOT block intake entirely. |
| `create_card` via operating-kanban fails | Surface the error verbatim. Do NOT re-attempt without Producer acknowledgement. Show the card draft so the Producer can create it manually if needed. |
| Sibling skill is unavailable or returns an error | Record the failure. Resume intake at Step 2 without the sibling's output — the intake routine degrades to "create a card with what we know, TODO the design." |
