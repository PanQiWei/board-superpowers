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

When multiple kanbans are registered (the registry shape is `modules.m10_kanban.kanbans: [{ id, projection, project_ref, role, wip_limit_local? }, ...]` in `<repo>/.board-superpowers/settings.yml`), the WIP formula `In Progress + suspended + In Review` is governed by two caps that BOTH must hold for any transition that would increment WIP:

- **Primary cap — per-actor cross-kanban total.** Default WIP cap is per-actor and **summed across all kanbans the actor has work in** — architect attention is a single budget that does not partition across kanbans. A Consumer holding 3 cards in `primary` and 2 cards in `legal` has WIP=5, not WIP=3 + WIP=2 separately. The cap is the global `modules.m5_repo_configuration.wip_limit` in `<repo>/.board-superpowers/settings.yml`.
- **Additional cap (optional) — per-kanban local.** Each kanban entry may set `modules.m10_kanban.kanbans[].wip_limit_local: N` as an additional per-kanban cap. The kanban-local count must not exceed this AND the global cap. The local cap is enforced only when set; absence means only the primary cap applies for that kanban.
- **Both hold conjunctively.** A new claim transitions only when (cross-kanban total + 1 ≤ global `wip_limit`) AND (kanban-local count + 1 ≤ that kanban's `wip_limit_local`, if set).

The v1.0 carve-out of length=1 makes the per-kanban cap trivially equal to the global cap (the kanban's local count IS the cross-kanban total), so single-kanban repos see no behavioral difference from v0.4.x.

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
