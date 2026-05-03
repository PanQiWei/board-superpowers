# Handoff points — 9 caller × scenario table

> **Forward-looking note**: The 4 Producer routine SKILLs (`briefing-daily` /
> `intaking-requirement` / `reviewing-pr-queue` / `triaging-board`) referenced
> below land via Card #72 (Producer Shape Y refactor); the Consumer 5 lifecycle
> handoff points (B1 / C1 / C2 / C3 / C4) are introduced via Card #73 (Consumer
> Shape X refactor). Today (post-#71-merge baseline), the SKILLs invoking sibling
> plugins are `managing-board` (intake routing — turns a new requirement into a
> design conversation or Ready card by delegating to gstack / superpowers),
> `consuming-card` (implementation delegation + pre-PR verification chain +
> conditional QA/security passes), `decomposing-into-milestones` (plan synthesis
> + arch validation handoff). Same handoff semantics, different SKILL boundaries.

This table is informational for the `composing-siblings` skill body. It tracks
the current set of callers and their sibling-skill handoffs. The count (9) may
grow or shrink as molecular skills evolve; the atomic body does not hard-code it.

## Phase labels

- **B1** — Pre-card bookend: direction or architecture question raised at intake
  before a card exists. Producer-side.
- **C1** — Post-claim planning: plan synthesis or architecture validation needed
  before implementation starts.
- **C2** — Implementation delegation: the Consumer delegates coding-discipline
  work to the `superpowers:*` loop.
- **C3** — Pre-PR verification: the Consumer runs the verification chain before
  opening a PR.
- **C4** — Conditional quality gates: UI or security-flagged cards trigger
  additional passes.

## 9 caller × scenario table

| Caller skill | Phase | Trigger signal | Sibling(s) to invoke | Mode-2 safe? |
|--------------|-------|---------------|----------------------|--------------|
| `managing-board` (intake) | B1 | "is this worth doing", "should we build this", "real demand?" | `gstack:/office-hours` OR `gstack:/plan-ceo-review` | n/a (Producer, not Mode-2) |
| `managing-board` (intake) | B1 | "rethink scope", "10-star product", "expand premise" | `gstack:/plan-ceo-review` | n/a |
| `managing-board` (intake) | B1 | architecture trade-off: "which schema", "which adapter", "data flow" | `gstack:/plan-eng-review` | n/a |
| `managing-board` (intake) | C1 | "explore this idea", direction set but design not locked | `superpowers:brainstorming` | n/a |
| `managing-board` (decomp handoff) | C1 | design artifact exists, needs executable plan | `superpowers:writing-plans` | n/a |
| `consuming-card` | C1 | plan phase before implementation | `superpowers:writing-plans` | yes — procedural |
| `consuming-card` | C2 | implementation: TDD + debugging loop | `superpowers:test-driven-development`, `superpowers:subagent-driven-development` (TBD — see procedural-fallback-rules.md) | TBD — check procedural-fallback-rules.md |
| `consuming-card` | C3 | pre-PR verification chain | `superpowers:verification-before-completion`, `superpowers:requesting-code-review`, `gstack:/review` | yes — all three are procedural |
| `consuming-card` | C4 | UI card | `gstack:/qa` | yes — procedural |
| `consuming-card` | C4 | security-flagged card | `gstack:/cso` | yes — procedural |
| `decomposing-into-milestones` | C1 | plan synthesis after decomposition | `superpowers:writing-plans` | n/a (not consumer-mode skill) |
| `decomposing-into-milestones` | B1 | non-trivial architecture validation | `gstack:/plan-eng-review` | n/a |

## Row count note

The table has more than 9 rows because some callers have multiple scenario rows.
The "9 callers" figure in the SKILLS.md SPOT table counts distinct
caller × lifecycle-position pairs:

1. `managing-board` B1 — direction question
2. `managing-board` B1 — scope challenge
3. `managing-board` B1 — architecture question
4. `managing-board` C1 — brainstorming
5. `managing-board` C1 — plan synthesis (decomp handoff)
6. `consuming-card` C1 — planning
7. `consuming-card` C2 — implementation
8. `consuming-card` C3 — verification
9. `consuming-card` C4 — conditional QA/security

`decomposing-into-milestones` shares the same sibling invocations as
`managing-board` B1/C1 and is not counted as a separate position in the SPOT
table because the wiring pattern is identical; it does, however, appear in the
table above for completeness.

## Updating this file

When a new molecular skill adds a sibling-plugin handoff, add a row here.
When an existing handoff is removed, remove the row. This file is the living
record; `SKILLS.md` § "SPOT derivation" row for `composing-siblings` may also
need a count update if the SPOT claim changes substantially.
