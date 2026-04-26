# board-canon — state machine reference

Per-transition checklist that the parent `SKILL.md` § "State machine" points at.

## Backlog → Ready

- [ ] Card body has all 5 mandatory sections (Goal / Acceptance criteria / Out of scope / Dependencies / Notes)
- [ ] Acceptance criteria pass INVEST: Independent, Negotiable, Valuable, Estimable, Small, Testable
- [ ] Estimate is set (S/M/L)
- [ ] No depends-on hard dependencies still in Backlog or Ready
- audit_id: 200, decision_class: A (Producer-managed)

## Ready → In Progress

- [ ] Consumer's current WIP_count + 1 ≤ wip_cap_per_consumer
- [ ] No other Consumer has an open `claim/N-...` branch for this card
- [ ] All hard `depends-on` cards are in Done
- audit_id: 100, decision_class: A (Consumer claims)

## In Progress → Blocked

- [ ] Blocker is named in a comment on the card
- [ ] Blocker is genuinely external (not "I haven't started yet")
- audit_id: 101, decision_class: R (must surface to Producer)

## Blocked → In Progress

- [ ] Blocker resolved per the named comment
- audit_id: 102, decision_class: A

## In Progress → In Review

- [ ] PR opened from `claim/N-...` branch to base (default `main`)
- [ ] PR body passes `enforcing-pr-contract` validation (3 sections present)
- audit_id: 110, decision_class: A

## In Review → Done

- [ ] PR merged (NOT closed without merge)
- [ ] No outstanding "request changes" review
- audit_id: 111, decision_class: A (Producer-managed via Review Queue)

## In Review → In Progress (rework)

- [ ] Reviewer requested changes; Consumer addresses them
- audit_id: 112, decision_class: A

> v1-minimum: all of these run as inline R-class with the architect since `classifying-actions` is deferred. Replace with full A/R routing when the atomic skill ships.
