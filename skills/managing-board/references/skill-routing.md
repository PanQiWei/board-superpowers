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

[`AGENTS.md`](../../../AGENTS.md) § "How to compose gstack
and superpowers" is the plugin-maintainer-facing source of
truth for cross-plugin composition. **This file is the
manager-mode reading of that section** — it covers the same
composition rules, but rephrased for an LLM agent doing
intake decisions rather than a human plugin maintainer
reading project docs.

The two files MUST stay in sync. The maintainer's
change-impact matrix carries a row enforcing this:

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
| `gstack:/plan-eng-review` | architecture decision questions: "which adapter shape", "which storage", "schema choice", "data flow" | Architecture lock — diagrams, edge cases, test coverage | A durable architecture decision record (the maintainer-side ADR area) OR `docs/plans/<feature>/eng-review.md` (gitignored, becomes spec if durable). |
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
| ADR-level decision (an architecture trade-off worth recording as a durable decision record) | **Locked** | ADRs are immutable once accepted; any decision worth an ADR is worth deciding before implementation, not during. | The autonomy classification matrix; the plugin-to-plugin invocation contract. |
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

#43's AC4 ("bootstrap-time audit ordering fixed, one of two
designs picked") fits this template exactly. The card was
written before this template was codified; trace it back:

- **Options** (the Consumer picks one in implementation):
  - **Design A — audit-init-early**: re-order sub-steps so
    the audit table exists before any audit row is written.
    End-to-end test asserts every bootstrap audit lands
    directly in DB. Caveat: 2e/2f/2g themselves still need
    audit rows that cannot land in a table that does not yet
    exist — those fall back to a small jsonl-with-flush.
  - **Design B — jsonl-then-flush**: keep current order;
    bootstrap-time audit rows write jsonl with new
    `mode=bootstrap-pending`; a new
    `scripts/audit-flush-pending.sh` runs after step 2g and
    replays pending rows into DB (idempotent via composite
    key).
- **Architect's leaning**: Design B (jsonl-then-flush) —
  "only drawbacks are mechanical (script + enum + cross-driver
  INSERT), no structural risk near release gate". Consumer is
  **not bound** to this leaning; explicitly free to pick A
  "if they find an acceptable solution to the 2e/2f rollback
  semantics question".
- **Rationale capture**: card #43 directs the Consumer to run
  a 30-min `superpowers:brainstorming` session to lock the
  choice and writes the rationale into the PR description.
  The card body itself records the design A/B framing in its
  Notes section so the rationale lives both in the PR (durable
  record) and the card body (audit trail) per Step 9.5 card
  body sync.

The template applied to #43's AC4 reproduces its actual shape
— Options + Architect's leaning + non-binding-on-Consumer +
PR-records-rationale all present in #43 before this template
existed. This is the empirical basis for codifying the shape
as a reusable AC pattern; verification that the Consumer
honors the template will land when #43's PR opens.

## Anchor present in `AGENTS.md`

`AGENTS.md` § "How to compose gstack and superpowers" carries
a 1-paragraph anchor pointing back to this file (injected
before the closing `<!-- /board-superpowers:routing -->`
marker as part of the same PR that landed this file). The
anchor's canonical text is:

> **Manager-mode mirror**: this section's composition rules
> are mirrored for the Producer's intake routine in
> `skills/managing-board/references/skill-routing.md`.
> The two files MUST stay in sync — the maintainer's
> change-impact matrix carries a row "AGENTS.md compose
> section ↔ skill-routing.md / scope-shape-judgment.md"
> enforcing this. If you edit one without the other, the PR
> is incomplete.

If `AGENTS.md` ever drifts from this canonical text (anchor
missing, wording diverged), the change-impact-matrix row
referenced in the quote is the recovery path — re-injecting
this anchor is a same-PR contract obligation.

## When this file is wrong

If the intake routine routes to a sibling skill that produces
no useful output (e.g., `gstack:/plan-eng-review` returns
"this isn't an architecture question, it's a direction
question"), that's the signal that this file's trigger column
mis-categorizes the requirement type. Revise the row in the
same PR that observes the mis-routing.
