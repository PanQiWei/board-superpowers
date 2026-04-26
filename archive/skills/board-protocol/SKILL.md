---
name: board-protocol
description: Use before creating, reading, or transitioning a board card — defines the canonical schema, state machine, branching, and concurrency rules for board-superpowers. Both Board Manager and Board Consumer skills invoke this to confirm they're obeying the protocol. Triggers include "card schema", "card status", "state transition", "claim branch", "WIP limit", or any ambiguity about what belongs on a card.
---

# board-protocol

The shared contract every board-superpowers session obeys. If Manager
and Consumer agree on this document, they coordinate through GitHub
alone — no direct conversation needed.

## The board

A single **GitHub Project v2**. Every card is a **GitHub Issue** in a
configured repository (never a draft item — draft items cannot be
claimed via branch push).

Each project has a `Status` single-select field with these options, in
this order:

```
Backlog → Ready → In Progress → In Review → Done
                            ↘
                             Blocked
```

## State machine

Allowed transitions. Anything else is a protocol violation.

| From → To | Who | When |
|-----------|-----|------|
| Backlog → Ready | Manager | Decomposition confirms INVEST compliance |
| Ready → In Progress | Consumer | Atomic claim succeeds |
| Ready → Backlog | Manager | Deprioritized |
| In Progress → In Review | Consumer | PR opened |
| In Progress → Blocked | Consumer | Unrecoverable blocker or scope problem |
| In Progress → Ready | Consumer | Abandoned cleanly (must remove worktree AND delete claim branch) |
| Blocked → Ready | Manager | After unblocking or re-scoping |
| In Review → Done | Human / GH auto-close | PR merged |
| In Review → In Progress | Consumer | Review changes require more work |

Never bypass Ready: `Backlog → anywhere else` is forbidden. The Ready
gate is where the architect confirms a card is actually actionable.

## Card body — schema

Every card's Issue body follows a fixed template with five named
sections (plus an optional one) and a trailing marker:

```
## Context
## Acceptance Criteria
## Out of Scope
## Size
## Execution Hints    (optional)

<!-- board-superpowers:card -->
```

**Full template, rules, and a worked example**: see the
[decomposing-into-milestones references/card-schema.md](../decomposing-into-milestones/references/card-schema.md).

The marker comment distinguishes board-superpowers cards from plain
issues on the project. Tooling keys off it; never remove it.

## PR body — schema

Consumer sessions produce a PR body that keeps whatever
`superpowers:finishing-a-development-branch` or `gstack:/ship`
generated and **appends** three protocol-required sections and a
marker:

```
## Summary           (from delegated skill)
## Test Plan         (from delegated skill)
## Automated Verification   (new — Consumer writes)
## Human Verification TODO  (new — Consumer writes)
## Retro Notes              (new — Consumer writes)

Closes #<card>.

<!-- board-superpowers:pr -->
```

**Full template, per-section rules, and examples**: see the
[consuming-card references/pr-template.md](../consuming-card/references/pr-template.md).

The marker lets Manager's Review Queue routine find board-superpowers
PRs among ordinary ones.

## Branch naming

Consumer work lives on `claim/<N>-<short-slug>` where `N` is the card
number and `<short-slug>` is lowercase-hyphenated, ≤ 40 characters (40
because GitHub truncates branch-name UI at roughly that width, and
longer branches turn the branch picker into a mess).

That branch is three things at once:

- **Atomic lock** — first `git push` wins; others see "already claimed".
- **Feature branch** for the PR.
- **Debugging aid** — `git branch -r | grep claim/` shows in-flight work.

Each claim branch is paired with a dedicated **git worktree** —
`scripts/claim-card.sh` creates both in one atomic step. The worktree
is what lets N Consumer sessions share one clone without clobbering
each other's HEAD. Default location:
`$HOME/.config/superpowers/worktrees/<project>/<branch>`. See
`consuming-card` Step 2 for the full resolution priority.

Always create claim branches via `scripts/claim-card.sh` — never by
hand. The script performs the atomic push + collision check AND the
worktree creation; skipping it loses the isolation guarantee.

## Session slug

On claim, a Consumer session generates a short slug (e.g., `s-a7b3`).
It appears in:

- The claim commit message.
- `.board-superpowers/claims/<N>.claim` on the branch.
- The first comment the Consumer posts on the card.

It is **not** a GitHub identity — all sessions authenticate as the same
user. It's a session-level tag so Manager can tell "which of my 5
Consumer sessions owns card #42" at a glance.

## Concurrency rules

1. **One Consumer per card.** The atomic branch push is the single
   source of truth.
2. **Failed claim exits cleanly.** A Consumer that fails to claim
   (`claim-card.sh` exit 10) reports which session beat it and stops.
   Never retry automatically. The script cleans up any partial
   worktree / local branch it created before the failed push.
3. **Each Consumer has its own worktree.** Parallel sessions share
   the clone (so fetches and refs are common) but not the working
   tree. HEAD and uncommitted files in session A cannot be observed
   or mutated by session B.
4. **Crashed session leaves the branch AND the worktree.** If a
   session dies mid-flight, both stay. Manager's Daily Routine
   detects stale claims (no commit in 6 h, no open PR — 6 h is the
   compromise between "Consumer is thinking" and "session is dead")
   and asks the architect to resume / reassign / release. Stale
   worktrees are disk overhead, not a correctness issue; clean up
   via `git worktree remove --force` when releasing the claim.
5. **Never delete another session's claim branch or worktree**
   without architect consent.

## WIP limit

Default: **5** cards in `In Progress` per project. Soft limit —
Manager warns but doesn't block. The default comes from small-team
kanban practice: beyond ~5 in-flight items a solo architect cannot
keep E2E verification context fresh.

Override in `.board-superpowers/config.yml`:

```yaml
wip_limit: 5
```

When WIP is at or over limit, Manager's first move for "what should I
work on" is **triage existing WIP**, not dispatch new cards.

## Out of scope

This protocol says nothing about:

- **Design / brainstorming** — `superpowers:brainstorming` or
  `gstack:/office-hours` produce the design docs that feed into
  `decomposing-into-milestones`.
- **Implementation discipline** — `superpowers:subagent-driven-development`
  or `superpowers:executing-plans` own TDD and code review inside one
  card.
- **PR mechanics** — `superpowers:finishing-a-development-branch` or
  `gstack:/ship` own the base PR body; Consumer only appends.
