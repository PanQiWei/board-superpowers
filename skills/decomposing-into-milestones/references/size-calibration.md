# Size calibration — 4-bin XS / S / M / L

> **Sources**:
> - Reinertsen 2009, *Principles of Product Development Flow*, principle B3 ("halving batch size halves cycle time").
> - Anderson 2010, *Kanban*, Little's Law operationalized.
> - Fowler, "StoryCounting" — <https://martinfowler.com/bliki/StoryCounting.html>.
> - Fowler, "PurposeOfEstimation" — <https://martinfowler.com/bliki/PurposeOfEstimation.html>.
> The 4-bin calibration below is **original framing** specific to board-superpowers — calibrated for the AI-Consumer / human-architect verification loop, not for human-team velocity.

## The 4-bin calibration

| Bin | Diff | Files | Pattern | When to use |
|---|---|---|---|---|
| **XS** | < 50 LOC | 1-2 | Typo / wire-up / one-line config / param rename | Hot fix; trivial coupling correction; doc one-liner |
| **S** | 50-200 LOC | 3-5 | One isolated change set | The calibration target — most cards should be S |
| **M** | 200-400 LOC | 5-10 | One feature surface | Acceptable; Producer takes one more pass for possible split |
| **L** | 400-500 LOC | up to 15 | One feature crossing 2-3 surfaces | **Ceiling.** Pressure to exceed → STOP and split |

No `XL`. No story points. No fractional values. No hours.

## The ceiling rule

500 LOC + 15 files is the empirical limit at which the architect can still verify a PR in one sitting (~30-45 min focused review). Past that:

- The diff is too large for a single review pass — review fatigue produces shallow approvals or rubber-stamping.
- The cognitive load exceeds the architect's working memory; cross-file consistency checks fail silently.
- Rework cycles balloon — a small misalignment found at line 600 forces the architect to rewalk the first 599 lines.

**If a candidate card exceeds the ceiling, it is by definition more than one slice**. Find the SPIDR axis that separates it; restart from Step 2 of the SKILL pipeline with the split halves.

## Calibration math — Little's Law + batch size

### Little's Law

```
cycle_time  =  WIP / throughput
```

(Reinertsen Ch. 4, Anderson 2010 Ch. 5.)

WIP cap is the operational lever; small batch size is the **input-side** lever. Halving WIP halves cycle time at constant throughput. Halving batch size *also* halves cycle time (Reinertsen B3) AND halves queue length (less work waiting at each stage).

Vertical slicing buys small batch size: each slice is independently flow-able, so it can complete and exit the system, freeing WIP slots. Layer-only slices (frontend / backend / schema) violate this — they cannot complete on their own; they wait for their layer-pair to finish, holding WIP slots open.

### Operational implication for board-superpowers

The repo's `wip_limit` (config field; default 1) is the WIP cap. Card size is the batch size. The product `wip_limit × batch_size` defines the maximum work-in-flight; both levers compress cycle time independently.

board-superpowers' bias toward S-sized cards (200 LOC target) is intentional — at S size, each card completes in one Consumer session (claim → implement → PR → merge), so cycle time is bounded by the architect's review latency, not by stage-to-stage handoffs.

## #NoEstimates — Fowler's stance

Fowler is **non-dogmatic**: > "Estimation is neither good or bad... Decide what are the right techniques for your particular context."

Fowler's canonical refusal of points/velocity (StoryCounting): > "[Teams] find their estimates using story points are no more accurate than if they had simply counted how many stories were in each iteration" — therefore "the effort of calculating story points isn't worth doing."

The replacement: count stories. Velocity = stories / iteration. Presumes stories are kept "within roughly an order of magnitude" — i.e., coarse T-shirt-sized buckets. board-superpowers' 4-bin (XS / S / M / L) is exactly this shape: coarse buckets, no fractional precision.

**What board-superpowers does NOT track**:

- Story points / numeric size.
- Velocity (stories per iteration).
- Cycle time histogram or any KPI dashboard.
- Sprint / iteration boundaries (no time-boxed iterations).

Per `0001-positioning.md` "Non-goals" + memory `feedback_question_human_team_ceremonies_in_ai_context`. board-superpowers tracks **state machine progression** (Backlog → Ready → In Progress → Done) and audit log entries. That is the entire measurement surface.

## AI-cadence reframe (original framing — no canonical source)

> ⚠️ **No canonical primary source found.** Reinertsen / Anderson / Fowler all assume human-team execution. Under AI orchestration, several semantics shift. The reframe below is **original framing** (per memory `feedback_research_canonical_practice_first.md`).

### What changes under AI cadence

| Dimension | Human team | AI orchestration |
|---|---|---|
| Bottleneck | Implementer time | Architect verification time |
| Throughput | Stories per week / sprint | PRs verified per architect session |
| Cycle time | Days to weeks per card | Hours to one day per card |
| Batch-size lever | Smaller stories ship faster | Smaller stories let architect verify more in less time |
| WIP cap | Limits implementer context-switching | Limits architect concurrent-PR review load |

### What stays the same

- **Little's Law** is platform-agnostic — `cycle = WIP / throughput` applies regardless of whether implementers are humans or AI agents.
- **Vertical slicing benefit** is platform-agnostic — a layer-only slice cannot exit the system regardless of who implements it.
- **Ceiling rule rationale** stays the same — 500 LOC limit is set by **architect verification capacity**, not implementer execution time. AI agents can produce 5000-LOC PRs in seconds; the architect still cannot verify them in one sitting.

### What needs explicit recalibration

- **"Few person-weeks" sizing language** (Wake INVEST-S) is meaningless under AI cadence. The 4-bin calibration replaces it with LOC + files + verification-capacity proxies.
- **"Sprint velocity"** is meaningless without time-boxed iterations. board-superpowers does not have sprints.
- **"Story counting per iteration"** (Fowler StoryCounting) becomes "PRs landed per architect day" — same shape, different time grain.
- **Cards-per-feature ratio** scales with AI throughput. A feature that decomposes into 5 cards in a human team may stay at 5 cards under AI cadence (the slicing logic is platform-agnostic) but the **time to deliver all 5** drops by ~100x (per memory `feedback_ai_cadence_100x.md`). Card *count* per feature is platform-agnostic; *delivery wall-clock* is not.

The 100x acceleration applies to **time** AND **scope** (per `feedback_ai_cadence_100x.md`):

- Time: a 5-card feature delivers in hours, not weeks.
- Scope: a "1 sub-project" worth of work in a human team (~6 months / 5-10 PRs) maps to a single cohesive AI-driven PR (e.g., #34 = 53 commits / 9 batches / one PR).

This second meaning is why board-superpowers permits very large PRs when they are cohesive — the natural unit of coordination is the sub-project, not a human-sized PR.

## Calibration drift — how to spot it

Signs that the 4-bin calibration is drifting and needs recalibration on this repo:

- More than 30% of cards are landing as `XS` — the calibration is too generous; tighten LOC bands.
- More than 30% of cards are landing as `L` — the slicing is failing; review SPIDR application.
- Mean card LOC > 350 — most cards are M or L; vertical slicing is producing too few seams. Investigate.
- Mean card LOC < 80 — most cards are XS or low-S; you may be over-slicing (each PR's review-overhead amortizes worse on tiny cards).

board-superpowers does not track these metrics automatically (no KPI infra by design). The architect surfaces drift via retro routines — typically the weekly retrospective routine inside `managing-board`. Manual + low-cadence is sufficient; no dashboard needed.
