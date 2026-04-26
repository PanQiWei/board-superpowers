# Failure modes

> **Status:** stub.

## Purpose

Catalog every known way the system can fail. For each: trigger,
detection signal, recovery procedure, ownership. FMEA-style. The
goal is that anyone debugging a real outage can find the failure
mode here, learn what to do, and update this file if the mode is
new.

## Format

| ID | Mode | Trigger | Detection | Recovery | Owner |
|----|------|---------|-----------|----------|-------|

`Owner` is "who acts on this" — Manager / Consumer / Architect /
plugin.

## Known failure modes (TBD)

Seed list to populate during the conversation:

- **F-01 Stale claim.** Consumer Session terminated mid-work; claim
  branch exists, no recent commits, no PR. Detected in Daily
  routine. Recovery: resume / reassign / cancel (Triage).
- **F-02 Ghost worktree.** Claim released (branch deleted, PR
  merged) but the local worktree directory not removed. Detected
  by the Consumer next time it tries to claim into the same path,
  or never. Recovery: `git worktree remove --force`. Owner: the
  user on the machine that owns the orphan dir.
- **F-03 Marker race.** Two Sessions push the same claim branch
  concurrently. Atomic-push handles correctness (one wins); Manager
  observation can be momentarily confused. Recovery: none — this
  is the design.
- **F-04 Missing CI.** Repo has no CI configured. Review Queue
  gate has no `gh pr checks` signal. Currently undefined behavior
  (P1 in Manager-path punch list). Recovery: TBD.
- **F-05 Project automation gap.** `In Review → Done` not
  auto-moved on PR merge. Cards stuck at In Review. Recovery:
  `transition-card.sh` by hand. Owner: Architect (one-time
  per-repo setup).
- **F-06 Mid-session dep removal.** `superpowers` or `gstack`
  uninstalled after preflight passed. JIT recheck in Manager /
  Consumer should catch but currently coverage is partial.
- **F-07 Pagination overflow.** `gh project item-list --limit 200`
  truncates Done pile. Daily routine sees stale snapshot of
  Backlog / Ready. Recovery: use pagination loop.
- **F-08 Cross-machine Consumer death.** Manager Triage cannot
  clean a worktree it didn't create — worktree lives on the dead
  Consumer's machine. Recovery: TBD (open question for
  domain-model).
- **F-09 Public-branch info leak.** Committed file under claim
  branch contains absolute local path / OS username / sensitive
  retro content. Detected by `tests/test-claim-card-worktree.sh`
  for marker; not detected for plan briefs (now gitignored) or
  retro reports (open issue).
- **F-10 Routing block drift.** `CLAUDE.md` mirror diverges from
  reference. Detected by `awk` block diff; not enforced in CI yet.
- **F-11 Stale claim pre-design.** Consumer in long
  brainstorming/writing-plans phase, no commits in 6h, Daily flags
  as stale. False positive.
- **F-12 macOS / GNU date drift.** Retro routine uses `date -d`
  (GNU); breaks on macOS BSD `date`. Detected on first weekly
  retro on macOS.

## Recovery primitives (TBD)

Common building blocks:

- `git push origin --delete <branch>`
- `git worktree remove --force <path>`
- `transition-card.sh --to <Status>`
- Manual marker write (when the Consumer is unable to)
- Forced project-status reset

## How to add a failure mode (TBD)

(short procedure: when you debug a new one, write the row before
closing the PR; even "we accept this" is a valid Recovery cell)
