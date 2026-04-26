# board-canon — state machine reference

Per-transition checklist that the parent `SKILL.md` § "State machine" points at.

Every transition writes one entry to the audit log at `~/.board-superpowers/repos/<normalized>/audit-local.jsonl`. Helper: `bsp_audit_local_write` from `scripts/lib/common.sh`.

## Backlog → Ready

- [ ] Card body has all 5 mandatory sections (Goal / Acceptance criteria / Out of scope / Dependencies / Notes)
- [ ] Acceptance criteria pass INVEST: Independent, Negotiable, Valuable, Estimable, Small, Testable
- [ ] Estimate is set (S/M/L)
- [ ] No hard `depends-on` is still in Backlog or Ready

## Ready → In Progress

- [ ] Consumer's current WIP_count + 1 ≤ wip_cap_per_consumer
- [ ] No other Consumer has an open `claim/N-...` branch for this card
- [ ] All hard `depends-on` cards are in Done

## In Progress → Blocked

- [ ] Blocker is named in a comment on the card
- [ ] Blocker is genuinely external (not "I haven't started yet")

## Blocked → In Progress

- [ ] Blocker resolved per the named comment

## In Progress → In Review

- [ ] PR opened from `claim/N-...` branch to base (default `main`)
- [ ] PR body passes `enforcing-pr-contract` validation (3 sections present)

## In Review → Done

- [ ] PR merged (NOT closed without merge)
- [ ] No outstanding "request changes" review

## In Review → In Progress (rework)

- [ ] Reviewer requested changes; Consumer addresses them on the same claim branch

## How transitions are decided to be auto-OK or ask-architect

By default, every mutating transition follows the "propose → wait for ack → act → log" discipline. Per-repo or per-user override rules in `.board-superpowers/config.yml` may classify some transitions as auto-act-OK. Until those overrides are configured, treat every transition as requiring acknowledgement.
