# Intake decision tree — intaking-requirement reference

This file is the **pre-card routing table** for the intake routine. Read it
at Step 4 of the intake pipeline (after scope-shape-judgment.md determined
shape and spec-first-checklist.md cleared preconditions).

Three decisions live here, applied in order:

1. **Pre-card routing** (Table 1) — pick the sibling skill or direct creation.
2. **Manager-locked vs consumer-deferred design** (Table 2) — which decisions
   MUST be settled at intake vs which can be left to the Consumer.
3. **Design-left-to-consumer card-body template** (Table 3) — when a decision
   IS deferrable, this template captures the architect's leaning + the
   Consumer's refusal authority.

## Table 1 — Pre-card routing

Triggers fire independently — a requirement that fires more than one row gets
routed to the first matching row (rows are listed by escalation priority).

| Sibling skill | Trigger signal | Output artifact | Notes |
|---------------|---------------|-----------------|-------|
| `gstack:/office-hours` | "Is this worth building?", "should we do this", "is there real demand" | YC-style demand-reality verdict (build / defer / kill) | If verdict is "build", the discussion seeds the next intake re-entry at Step 2. |
| `gstack:/plan-ceo-review` | "Rethink the problem", "10-star product", "challenge the premise", "expand scope" | CEO-mode scope critique | Updated scope decision; resume intake at Step 2 with revised requirement. |
| `gstack:/plan-eng-review` | Architecture decision questions: "which adapter shape", "which storage", "schema choice", "data flow", "interface design" | Architecture lock — diagrams, edge cases, decision record | Output may be a durable ADR or a gitignored `docs/plans/<feature>/eng-review.md`. |
| `superpowers:brainstorming` | "Let's explore this", "I'm not sure of the design", multi-step requirement that's direction-set but not design-locked | Sharpened requirements + design notes | After brainstorming, resume intake at Step 2 with the sharper artifact. |
| `board-superpowers:decomposing-into-milestones` | scope-shape-judgment.md routes to "multi-card" or "milestone-grouped" | INVEST-compliant batch of Ready cards on the board | Attach walking-skeleton hint for brand-new feature surfaces. |
| **Direct card creation** (this skill's own flow, Step 4 → § "Direct card creation") | shape = single card AND spec preconditions are clear | One Ready card on the board | Card on the GitHub Project (durable). |

### Routing decision flow

```
fresh requirement
    │
    ▼
Step 2: scope-shape-judgment.md → shape
    │
    ├── cross-release roadmap → stop, surface to Producer
    │
    ├── milestone-grouped / multi-card → decomposing-into-milestones
    │
    └── single card
           │
           ▼
        Step 3: spec-first-checklist.md → preconditions clear?
           │ no                          │ yes
           ▼                             ▼
        land spec preconditions    Table 1 → which sibling?
        (separate or same-PR)              │
                                  ┌────────┼────────┐
                                  ▼        ▼        ▼
                              direction  arch?   ready to
                              question?          draft?
                                  │        │        │
                            gstack       gstack   direct
                            office-hours plan-eng  creation
                            or ceo-review review
```

After any sibling produces output, re-enter at Step 2 with the sharpened
artifact.

### Triggers vs phrasings

Match by signal type, not literal phrasing. A requirement saying "we need to
figure out the schema for X" is signal-type "architecture decision" even if
the words "plan-eng-review" don't appear. Surface the routing call as a
sentence so the Producer can override before the sibling fires.

## Table 2 — Manager-locked vs consumer-deferred design

| Decision class | Lock at intake? | Why |
|----------------|-----------------|-----|
| Cross-card contract (data shape shared between cards) | **Locked** | Deferring forces dependent cards to wait or ship against a placeholder. |
| ADR-level decision (architecture trade-off worth recording) | **Locked** | ADRs are immutable once accepted; decide before implementation. |
| Schema change (audit columns, action_id namespace, autonomy matrix rows) | **Locked** | Schema is shared; mid-flight changes break siblings. |
| Cross-bounded-context scope (card touches 2+ of Board/Session/Bootstrap/Audit/Spec) | **Locked** | Cross-context decisions need the architect's view of both contexts. |
| New cross-plugin edge (new `superpowers:*` or `gstack:/*` invocation not in SKILLS.md) | **Locked** | SKILLS.md update is a spec-first precondition (row 2). |
| In-card design A/B between options that don't affect other cards | **Deferrable** (use Table 3 template) | The Consumer has implementation context the architect lacks. |
| Implementation-style choices (variable naming, function decomposition, test layout) | **Deferrable** | Taste choices; the architect doesn't add value by pre-deciding. |
| Local refactor scope (adjacent code cleanup while implementing the card) | **Deferrable** | Consumer decides if local; escalate if it crosses cards. |

### Red-line list — never deferrable to Consumer

These decisions MUST land before the Consumer session starts. Putting them in
a deferrable AC violates the architect's reserved-power boundary:

- audit_log schema changes (column names, types, enum sets)
- action_id namespace allocations (new integer for a new mutating action)
- autonomy matrix changes (promoting/demoting A/R/N rows)
- hook intent injection grammar (INVOKE: / REASON: payload shape)
- routing block injection target
- cross-card schema (Card body sections, PR three-section contract, AC semantics)
- ADR-level architecture decisions (BoardAdapter, plugin invocation contract)
- the BYO RDBMS scheme allowlist
- the bounded-context boundary table

If a Consumer session encounters one of these as an open question
mid-implementation: stop, surface to architect, suspend the card, route the
architect back to intaking-requirement.

## Table 3 — The "design-left-to-consumer" card-body template

When an in-card design A/B is deferrable (Table 2 row 6), use this template
in the card body:

```markdown
- **AC<N> — <decision name> (design-left-to-consumer).**
  <One-sentence framing of the trade-off.>

  **Options** (pick one in implementation):

  - **Option A**: <description>. Pros: <bullets>. Cons: <bullets>.
  - **Option B**: <description>. Pros: <bullets>. Cons: <bullets>.

  **Architect's leaning**: <Option X> — because <one-sentence rationale>.
  Consumer is **not bound** to this leaning; picking a different option is
  fine if the PR description states the reason.

  **Verifiable**: PR description states which option was picked + 1–3
  sentence rationale. Card body updated to record the chosen option post-
  implementation (via the consuming-card Step 9.5 card body sync).
```

Do NOT use this template when the decision is locked per Table 2, when only
one option is viable, or when an existing spec already dictates the answer.
