# Skill routing — manager-side intake reference

> **Scope**: this file is the manager-mode reading of
> [`AGENTS.md`](../../../AGENTS.md) § "How to compose gstack
> and superpowers". It owns three decisions:
>
> 1. **Pre-card routing** — at intake, which sibling skill
>    runs? `gstack:/*`, `superpowers:*`, this plugin's #35,
>    or direct card creation?
> 2. **Manager-locked vs consumer-deferred design** — which
>    design decisions MUST be settled at intake (architect
>    territory) vs which can be left to the Consumer
>    session.
> 3. **The design-left-to-consumer card-body template** —
>    when a decision IS deferrable, the card-body shape that
>    captures architect's leaning + consumer's authority.
>
> **Out of scope** — implementation-time routing inside a
> Consumer session (TDD, debugging, verification chain) is
> owned by [`consuming-card/SKILL.md`](../../consuming-card/SKILL.md)
> and that skill's `references/handoff-to-superpowers.md`.
> This file stops at the moment the card is created.

This reference is consumed by:

- The `intake.md` decision tree (after [`scope-shape-judgment.md`](./scope-shape-judgment.md)
  decides shape and [`spec-first-checklist.md`](./spec-first-checklist.md)
  clears spec preconditions).
- The `managing-board` SKILL body's intake routine when it
  picks which sibling to invoke.

## Mirror handshake with `AGENTS.md`

`AGENTS.md` § "How to compose gstack and superpowers"
(lines 525-606) is the plugin-maintainer-facing source of truth
for cross-plugin composition. **This file is the manager-mode
reading of that section** — it covers the same composition
rules, but rephrased for an LLM agent doing intake decisions
rather than a human plugin maintainer reading project docs.

The two files MUST stay in sync. The change-impact matrix in
[`docs/architecture/AGENTS.md`](../../../docs/architecture/AGENTS.md)
carries a row enforcing this:

> If you change AGENTS.md compose section, also update
> skill-routing.md AND scope-shape-judgment.md cross-refs to #35.

Updates land same-PR. AGENTS.md gains a 1-paragraph anchor
pointing here (see § "Anchor to add to AGENTS.md" at the
bottom of this file).

## Table 1 — Pre-card routing

The intake routine receives a fresh requirement. After
[`scope-shape-judgment.md`](./scope-shape-judgment.md) decides
shape, this table decides which sibling skill (or direct
creation) runs next. Triggers fire **independently** — a
requirement that fires more than one row gets routed to the
**first** matching row (order matters; rows are listed by
escalation priority).

| Sibling skill | Trigger phrase / signal | Output artifact | Output lifecycle |
|---------------|------------------------|-----------------|-----------------|
| `gstack:/office-hours` | "I have an idea but I'm not sure if it's worth doing", "should we even build this", "is this real demand" | YC-style verdict (build / defer / kill) — written discussion + decision | `docs/plans/<feature>/office-hours.md` (gitignored). If verdict is "build", the discussion seeds the next intake; if "defer" or "kill", PR-less close. |
| `gstack:/plan-ceo-review` | "rethink the problem", "10-star product", "expand scope", "challenge the premise" | CEO-mode plan critique — scope expansion / hold / reduction notes | `docs/plans/<feature>/ceo-review.md` (gitignored). Updated card body / scope decision. |
| `gstack:/plan-eng-review` | architecture decision questions: "which adapter shape", "which storage", "schema choice", "data flow" | Architecture lock — diagrams, edge cases, test coverage | ADR (durable, into `docs/architecture/adr/`) OR `docs/plans/<feature>/eng-review.md` (gitignored, becomes spec if durable). |
| `superpowers:brainstorming` | "let's explore this", "I'm not sure of the design", multi-step requirement that's direction-set but not design-locked | Sharpened requirements + design notes | `docs/plans/<feature>/brainstorm.md` (gitignored). Hands off to #35 (decomposition) or back to intake (single-card direct creation). |
| `board-superpowers:decomposing-into-milestones` (#35) | [`scope-shape-judgment.md`](./scope-shape-judgment.md) Table 1 routes to "multi-card" or "milestone-grouped" | INVEST-compliant batch of N Ready cards on the board | Cards on the GitHub Project (durable). Optional decomposition-rationale notes in `docs/plans/<feature>/`. |
| **Direct card creation** ([`intake.md`](./intake.md) § "Direct card creation") | [`scope-shape-judgment.md`](./scope-shape-judgment.md) Table 1 routes to "single card" AND [`spec-first-checklist.md`](./spec-first-checklist.md) preconditions are clear | One Ready card on the GitHub Project | Card on the GitHub Project (durable). |

### Routing decision flow

```
fresh requirement arrives
    │
    ▼
Table 1 from scope-shape-judgment.md → shape decision
    │
    ▼
Is shape "cross-release roadmap"?  ──────► positioning doc / umbrella card; defer card creation
    │ no
    ▼
spec-first-checklist.md → preconditions clear?
    │ no                                                   │ yes
    ▼                                                      ▼
land spec preconditions                          this file (skill-routing.md) → which sibling?
(separate or same-PR)                                      │
    │                                       ┌──────────────┼──────────────┐
    │                                       ▼              ▼              ▼
    │                              direction question?   architecture?   multi-card?
    │                                       │              │              │
    │                                       ▼              ▼              ▼
    │                              gstack office-hours   gstack /        decomposing-into-
    │                                or /plan-ceo-review plan-eng-review   milestones (#35)
    │                                       │              │              │
    └───────────────────────────────────────┴──────────────┴──────────────┘
                                            │
                                            ▼
                                   sibling produces output
                                            │
                                            ▼
                                   intake resumes (often back to this table for the
                                   next phase, e.g., "now decompose the eng-review output")
```

### Triggers vs phrasings

The "trigger phrase / signal" column lists the architect's
likely phrasings. The intake routine should NOT match
phrasings literally — match by *signal type*. A requirement
that says "we need to figure out the schema for the audit log"
is signal-type "architecture decision" even if the words
"plan-eng-review" don't appear. The routine surfaces its
routing call to the architect as a sentence ("This reads as
architecture-decision territory — routing to
`gstack:/plan-eng-review` for the design lock.") so the
architect can override before the sibling fires.

## Table 2 — Manager-locked vs consumer-deferred design

After the sibling completes (or after direct card creation),
the card body is drafted. Some decisions in the body MUST be
locked at intake; others CAN be left to the Consumer session.
This table draws the line.

| Decision class | Lock at intake? | Why | Example |
|----------------|-----------------|-----|---------|
| Cross-card contract (data shape shared between cards, an interface that another card implements against) | **Locked** | Deferring forces the dependent card to wait or to ship against a placeholder; both are wasteful. | The Card body schema (#33 + #44) — every card depends on the schema being settled. |
| ADR-level decision (architecture trade-off recorded in `docs/architecture/adr/`) | **Locked** | ADRs are immutable once accepted; any decision worth an ADR is worth deciding before implementation, not during. | ADR-0006 (autonomy matrix), ADR-0008 (plugin-to-plugin invocation). |
| Schema change (audit_log columns, action_id namespace, autonomy matrix rows, host-local state files) | **Locked** | Schema is shared by every consumer of the schema; mid-flight schema changes break siblings. | Audit log schema rows (#34). Per [`spec-first-checklist.md`](./spec-first-checklist.md) row 3, these have spec-first preconditions; they CANNOT be Consumer-deferred. |
| Cross-bounded-context scope (the card touches Audit + Bootstrap, or Board + Spec) | **Locked** | Cross-context decisions need the architect's view of *both* contexts; the Consumer is in one context, not two. | #34 (Audit + Spec); #43 (Bootstrap + Audit). |
| Cross-plugin edge (this plugin's skill invokes a sibling-plugin skill that's not in `SKILLS.md` § "Cross-plugin edges" yet) | **Locked** | Per [`spec-first-checklist.md`](./spec-first-checklist.md) row 2, the SKILLS.md edit is a precondition. | Any new `superpowers:*` or `gstack:/*` invocation. |
| In-card design A/B between options that don't affect other cards | **Deferrable** (see Table 3 template) | The Consumer has implementation context the architect lacks; let them choose with rationale capture. | #43 AC4 (which audit DB scheme to default to); #44 AC1 + AC3 (which platform-id field shape). |
| Implementation-style choices (variable naming, function decomposition, test layout) | **Deferrable** | These are taste choices; the architect doesn't add value by pre-deciding. | Any "how do I structure this file" question. |
| Local refactor scope (whether to refactor adjacent code while implementing the card) | **Deferrable** with one caveat | The Consumer can decide if the refactor is local; if it crosses cards, escalate. | Inline cleanup in #29 (bootstrap stub-redirect) was Consumer-decided. |

### Red-line list — never deferrable to Consumer

The following decisions MUST land before the Consumer session
starts. Putting them in a deferrable AC violates the
architect's reserved-power boundary:

- audit_log schema changes (column names, types, enum sets)
- `action_id` namespace allocations (assigning a new integer
  to a new mutating action)
- autonomy matrix changes (promoting an action to A, demoting
  to R, adding N rows)
- hook intent injection grammar (`INVOKE:` / `REASON:`
  payload shape)
- routing block injection target (the `<!-- board-superpowers:routing -->`
  marker in `AGENTS.md` / `CLAUDE.md`)
- cross-card schema (the Card body sections, the PR three-section
  contract, the AC `[x]/[!]/[ ]` semantics)
- ADR-level architecture decisions (BoardAdapter contract,
  plugin-to-plugin invocation, plugin-runtime constraints)
- the BYO RDBMS scheme allowlist
- the bounded-context boundary table

If a Consumer session encounters one of these as an open
question mid-implementation, the correct move is **stop, surface
to architect via card thread comment (`action_id` 101),
suspend the card, route the architect to managing-board
intake**. Don't decide on the architect's behalf and ship.

## Table 3 — The "design-left-to-consumer" card-body template

When an in-card design A/B is deferrable (Table 2 row 6),
codify the deferral with this template. The template emerged
from #43 AC4 + #44 AC1 + #44 AC3 + this card's #45 AC4
("design-left-to-consumer is now a stable convention" — see
the project history in
`docs/plans/manager-decision-frameworks/canonical-practice-audit.md`
Pattern 3).

```markdown
- **AC<N> — <decision name> (design-left-to-consumer).**
  <One-sentence framing of the trade-off.>

  **Options** (pick one in implementation):

  - **Option A**: <description>. Pros: <bullets>. Cons: <bullets>.
  - **Option B**: <description>. Pros: <bullets>. Cons: <bullets>.
  - (optionally Option C, D, ...)

  **Architect's leaning**: <Option X> — because <one-sentence
  rationale>. Consumer is **not bound** to this leaning;
  picking a different option is fine if the PR description
  states the reason.

  **Verifiable**: PR description states which option was
  picked + 1-3 sentence rationale. Card body is updated to
  record the chosen option in the post-implementation summary
  (per `consuming-card` Step 9.5 card body sync).
```

### Why this shape works

- **Architect surfaces leaning** — the Consumer doesn't have to
  guess what the architect would have done. Eliminates a
  subtle anchor that would otherwise force the Consumer to
  pick the architect's option even if a better choice
  appears mid-implementation.
- **Consumer has refusal authority** — explicit "not bound to
  this leaning" prevents the leaning from hardening into a
  mandate. The Consumer can pick a different option without
  asking, as long as the PR records the reason.
- **Rationale is captured durably** — the PR description is
  the durable record (the card body update via Step 9.5 is
  the audit trail). Future readers can trace why option X
  was picked.

### When NOT to use the template

- **Decision is locked per Table 2** — if the design A/B
  involves a cross-card contract or schema change, this
  template is wrong. Use a regular AC and lock the decision
  at intake.
- **Decision has only one viable option** — don't fake a 2-N
  options list. If the architect has a clear preference and
  the alternatives aren't worth considering, write a regular
  AC. The template is for genuine A/B trade-offs, not for
  decoration.
- **Decision was already made by spec** — if an existing ADR
  or spec section dictates the answer, cite the spec instead
  of opening it back up.

### Worked example — #43 AC4 trace

#43's AC4 ("which audit DB scheme should bootstrap default
to") fits this template exactly:

- Options: SQLite / Postgres / MySQL.
- Architect's leaning: SQLite-as-a-fallback (lowest setup
  cost; covers solo-architect case). Consumer free to default
  differently if the project shape demands.
- Rationale capture: PR #45's description states "defaulted to
  SQLite, fallback chain attempts Postgres if `DATABASE_URL`
  is set" — the leaning was followed but the PR records why.

The template applied retroactively reproduces #43's actual
shape; this confirms the template is a faithful codification.

## Anchor to add to `AGENTS.md`

`AGENTS.md` § "How to compose gstack and superpowers" gains
the following 1-paragraph anchor (insert before the closing
`<!-- /board-superpowers:routing -->` marker, per AC6 of
this card):

> **Manager-mode mirror**: this section's composition rules
> are mirrored for the Producer's intake routine in
> [`skills/managing-board/references/skill-routing.md`](./skills/managing-board/references/skill-routing.md).
> The two files MUST stay in sync — see the
> change-impact-matrix row "AGENTS.md compose section ↔
> skill-routing.md / scope-shape-judgment.md" in
> [`docs/architecture/AGENTS.md`](./docs/architecture/AGENTS.md).
> If you edit one without the other, the PR is incomplete.

## When this file is wrong

If the intake routine routes to a sibling skill that produces
no useful output (e.g., `gstack:/plan-eng-review` returns
"this isn't an architecture question, it's a direction
question"), that's the signal that this file's trigger column
mis-categorizes the requirement type. Revise the row in the
same PR that observes the mis-routing.
