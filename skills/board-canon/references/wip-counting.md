# board-canon — WIP counting reference

Corner cases that the parent `SKILL.md` § "WIP counting" points at.

## The formula in detail

```
WIP_count(consumer) =
    |{cards | status == "In Progress" AND consumer == self}|
  + |{cards | status == "In Progress" AND label == "suspended" AND consumer == self}|
  + |{cards | status == "In Review" AND PR.author == self AND PR.state == "open"}|
```

A card belongs to a Consumer if they pushed the card's claim branch (per the parent SKILL § Branch naming).

## Multi-kanban WIP semantics

When multiple kanbans are registered (per ADR-0026), the WIP formula `In Progress + suspended + In Review` is evaluated **per kanban**, not summed across kanbans. Each kanban's `wip_limit` (from `<repo>/.board-superpowers/settings.yml § modules.m5_wip.kanbans.<kanban-id>.wip_limit`) is checked independently. Cross-kanban totals are observability metrics, not gating constraints.

The v1.0 carve-out of length=1 means single-kanban repos see no behavioral difference from v0.4.x.

## Edge cases

### Suspended cards

A "suspended" card is one a Consumer parked because of a deeper dependency or context switch. The card stays in In Progress with a `suspended` label. Suspended cards still count toward WIP — the Consumer should resolve or release them, not accumulate them.

### Abandoned worktrees

If a Consumer's local worktree is deleted but the card's claim branch still exists on origin, the card is still in "In Progress" and still counts. Recovery: either re-create the worktree (`git worktree add ... <claim-branch>`) or release the claim via the `managing-board` triage routine.

### Post-merge lag

When a PR is merged, GitHub's webhook updates the Status field to Done — but there's a delay (usually <30s). During this window the card is in Done in GitHub's UI but the Consumer's WIP_count still shows it because `read-board.sh` reads Status from the project, not from PR state. Self-corrects on the next read.

### Cross-repo claims

A Consumer working on multiple repos has independent WIP counts per repo. The cap is enforced per `(host, repo)`.

### WIP cap = 0

Setting `wip_limit: 0` in `.board-superpowers/config.local.yml` means "no claims allowed without explicit architect override". Useful for read-only Producer sessions or audit-only modes.

## Why Blocked is excluded

Blocked cards are genuinely *not* active work — the Consumer is waiting on something external. Counting Blocked toward WIP would push Consumers toward acting on the wrong cards just to free their slot, which is the opposite of WIP's intent. The cost of excluding Blocked: a Consumer can in principle accumulate many Blocked cards. This is a known footgun; the `managing-board` triage routine surfaces it.

## Override mechanism

A Producer can override WIP cap for a single claim by adding the `wip-override` label to the card BEFORE the Consumer claims. The label triggers an audit entry so the override is traceable. After the card transitions to Done, the label is manually removed.
