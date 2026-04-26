# ADR 0003: One worktree per Consumer session

**Status:** accepted
**Date:** 2026-04-26
**Deciders:** PanQiWei (maintainer)

## Context

ADR-0002 gives **logical** ownership via the claim branch; it
does NOT give **filesystem isolation**. Two Consumer sessions
operating in the same primary working tree will trample each
other's HEAD and stash, even though the logical claim is held
cleanly. This bug actually surfaced during card #16's
pre-refactor: a fat-fingered claim invocation in the primary
working tree moved HEAD out from under an unrelated active
session.

Git's `worktree` feature solves this cleanly: each session gets
its own checkout sharing the underlying `.git` directory. Disk
cost is small (only working-tree contents are duplicated), and
HEAD-per-worktree is independent. The primitive is built into
`git`, requires no extra dependencies, and is well understood.

The remaining design questions are **where** worktrees live and
**when** they are deleted. The "where" affects gitignore footgun
risk (project-local) vs cross-project visibility (global). The
"when" affects how Mode-2 Consumer wake-up after process death
recovers in-flight work.

## Decision

Each `ConsumerLogical` (the kanban-relative role binding to one
Card, per `0003-domain-model/03-aggregates-and-entities.md`
§ 3.3.3) owns exactly one worktree. The worktree:

- **Path is card-deterministic.** Default location:
  `$HOME/.config/superpowers/worktrees/<project>/<branch>`,
  where `<branch>` is the claim branch (`claim/<N>-<slug>`).
  Card-deterministic means the path is recoverable from the
  Card alone — wake-up after process death finds the same
  worktree without state lookup.
- **Persists across `ConsumerProcess` incarnations.** Mode-2
  terminate-and-resume cycles re-enter the same worktree;
  partial work (uncommitted changes, stash, in-flight
  commits) is preserved. Single-process suspend (Mode-1)
  likewise returns to the same worktree on resume.
- **Self-deletes on success path** (F-C14 success). After the
  PR merges, the Consumer issues `git worktree remove --force
  $WORKTREE` and process exits.
- **Is preserved on failure path** (F-C14 failure). When a
  Consumer terminates into `Blocked`, the worktree stays at
  the original path so a human can `cd` into it and take
  over manually.

Path resolution priority (highest precedence first):

1. `$BOARD_SP_WORKTREE_DIR` env override (advanced setups,
   single-machine multi-checkout)
2. Project-local `.worktrees/` (must exist AND be
   gitignored — explicit opt-in by architect)
3. `$HOME/.config/superpowers/worktrees/<project>/<branch>`
   (the global default)

The two-line stdout contract from `scripts/claim-card.sh`
exposes both the branch and the resolved worktree path:

```
branch=claim/<N>-<slug>
worktree=<absolute path>
```

Consumer Step 2 (per `consuming-card/SKILL.md`) parses both
lines, `cd`s into the worktree, and never returns to the
primary working tree for the lifetime of the
ConsumerLogical.

## Consequences

**What this enables:**

- **N parallel Consumers never trample each other.** Each
  worktree has its own HEAD; primary working tree stays
  pristine.
- **Mode-2 terminate-and-resume preserves partial work.** The
  worktree-as-persistent-sandbox is the physical carrier for
  the logical Consumer's state across process incarnations —
  no separate state-restore mechanism needed.
- **Failure-path human takeover is friction-free.** The
  worktree at the deterministic path lets the architect `cd`
  in directly, see what the Consumer was doing, and continue
  manually.
- **No clone duplication.** All worktrees share the
  underlying `.git`; disk cost is bounded by working-tree
  size, not full repo size.

**What this constrains:**

- **Cross-machine wake-up unsupported at v1.** The worktree
  path is local to the machine that ran the original claim.
  If a Mode-2 Consumer's prior process died on machine M1
  and Producer wakes a new process on machine M2, the
  worktree is unreachable. This is registered as TBD-1 in
  `0003-domain-model/03-aggregates-and-entities.md` § 3.3.3
  and routed to `0006-failure-modes.md` F-08; v1 assumes
  single-machine Mode-2 (P3 — solo / small-team scale).
- **Worktree path info-leak guard required.** The absolute
  path on disk reveals OS username + directory layout. The
  ClaimMarker on the claim branch deliberately omits a
  `worktree:` field (see `claim-card.sh` and the regression
  test in `tests/test-claim-card-worktree.sh`).
- **Consumer must `cd` early and stay.** Step 2 of
  `consuming-card/SKILL.md` is load-bearing — not `cd`-ing
  into the worktree after F-C1 reverts to the multi-trample
  bug ADR-0003 exists to prevent.
- **Manager cannot remove a worktree it didn't create**
  (cross-machine case). Triage workflow surfaces stale
  worktrees but cannot clean them remotely.

**What this forbids:**

- **Mode-2 wake-up that creates a new worktree.** Wake-up
  re-enters the existing worktree (preserving partial work).
  An implementation that creates a fresh worktree at a
  different path on resume violates the one-card-one-
  worktree invariant (I-7).

## Alternatives considered

- **One process-shared working tree with `git stash` /
  `git switch` dances.** Fragile under interruption (stash
  pops can fail mid-merge), and any forgotten stash entry
  becomes lost work. Trampling is pushed forward in time,
  not eliminated.
- **Separate clones per Session.** Wastes disk (full repo
  copy per Consumer), loses shared git history (commits in
  one clone aren't visible in another until pushed and
  fetched), and complicates branch management.
- **Containerizing each Session.** Overkill — the isolation
  needed is HEAD/working-tree, not process or filesystem
  namespace; CC and Codex don't have a container model that
  would compose with this; setup ceremony violates P5.
- **In-memory virtual working tree (libgit2-style).** No
  off-the-shelf primitive in the CC / Codex toolchain;
  architect cannot `cd` into an in-memory worktree to
  inspect partial work; defeats failure-path human
  takeover.

## Notes

- This ADR documents an already-shipped behavior in
  `scripts/claim-card.sh`. Promoting from `stub` to
  `accepted` retroactively captures the canonical rationale.
- The "card-deterministic path" property is what makes Mode-2
  wake-up work without an explicit state-restore step.
  ADR-0003 + ADR-0007 (preflight piggyback) together
  implement persist-as-side-effect: the platform stores the
  session log; the worktree stores the working state;
  Producer's preflight finds both via deterministic paths.

## Related

- ADR-0002 — Atomic claim via remote branch push (claim is the
  logical lock; worktree is the filesystem lock)
- ADR-0007 — Plugin-runtime-derived constraints (C-PLUGIN-2:
  no daemon — wake-up via deterministic-path lookup is the
  no-daemon-friendly alternative to a state-tracking
  service)
- [`0003-domain-model/`](../0003-domain-model/README.md) —
  Worktree is a member entity of the ConsumerLogical
  aggregate (§ 3.3.3); the I-7 invariant maps here.
- [`0002-product-features-and-flows/04-consumer-surface.md`](../0002-product-features-and-flows/04-consumer-surface.md)
  F-C3 (worktree entry + In Progress transition); F-C14
  (success vs failure path treatment)
- [`0002-product-features-and-flows/07-cross-cutting-invariants.md`](../0002-product-features-and-flows/07-cross-cutting-invariants.md)
  I-7 (one-card-one-worktree)
- `0005-contracts.md` (stub) — worktree default-path
  resolution priority (the 3-priority list above) lands
  here as a contract
- `0006-failure-modes.md` (stub) — F-02 ghost worktree, F-08
  cross-machine Consumer death (TBD-1 deferred here)
- `scripts/claim-card.sh` — implementation
- `tests/test-claim-card-worktree.sh` — happy path +
  concurrent + already-claimed + worktree info-leak guard
