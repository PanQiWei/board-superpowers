# Plan: Card #16 — Consumer self-select + per-session worktree isolation

## Context

Two gaps in the current `consuming-card` skill break README.md
promises:

1. **"Pull-based work" is unsupported.** `consuming-card/SKILL.md:47`
   hard-requires `[board-card:#N]`. A user opening a fresh session
   and saying "work on the board" has no path. Trigger list
   already mentions "start on the board card" but the skill body
   ignores it.
2. **Parallel Consumer sessions collide.** `claim-card.sh` operates
   on the current repo's single working tree. Two sessions running
   `claim-card.sh` back-to-back force-move HEAD on top of each
   other's WIP. README.md's "3 Consumer terminals in parallel"
   scenario is not actually safe today.

The existing hedge at `handoff-to-superpowers.md:38-39` ("the
`using-git-worktrees` superpowers skill may or may not engage;
trust its routing") is load-bearing in theory but has no caller
in the claim flow.

This is a **breaking refactor** of `consuming-card` and
`claim-card.sh` — acceptable because board-superpowers has no
external consumers yet.

## Acceptance Criteria (from card)

- [ ] `claim-card.sh` creates a worktree after successful atomic push.
  Default: `~/.config/superpowers/worktrees/<project>/<branch>`
  (global, no gitignore concern). Fallback: `.worktrees/<branch>`
  (project-local) when opted in.
- [ ] Stdout contract: two lines on success — `branch=<name>` +
  `worktree=<absolute path>`. Exit codes unchanged.
- [ ] `consuming-card/SKILL.md` Step 0 Card Selection: no `#N` →
  query Ready cards with satisfied deps, surface top candidates,
  require one-shot user confirmation, then proceed.
- [ ] `[board-card:#N]` path skips Step 0 exactly as today.
- [ ] `references/handoff-to-superpowers.md` — hard-dep on
  `superpowers:using-git-worktrees` (drop "may or may not").
- [ ] Regression tests: existing `test-claim-card.sh` still passes;
  new tests cover worktree creation + concurrent distinctness.
- [ ] `shellcheck` clean.
- [ ] Docs consistency — README.md "3 terminals" clarified.

## Out of Scope (from card — do NOT do these)

- Session-id + symlink work — that is card #3's lane.
- Distributed-lock mechanism stays branch-push.
- Card-priority algorithm beyond "oldest Ready first".
- Worktree cleanup automation on merge.
- Forward-porting card #15's patch.

## Target branch

`claim/16-consumer-self-select-worktree` (claim commit already on
remote, this worktree is checked out from it).

## Size ceiling

M (200–400 LOC / 5–10 files). If work feels like L, STOP and report
NEEDS_CONTEXT — the card may need splitting.

## Execution hints (from card)

Path: `superpowers:subagent-driven-development` for skill changes,
`gstack:/codex` second opinion on shell logic. Three natural
sub-tasks:

1. `claim-card.sh` worktree + stdout contract + tests.
2. `consuming-card/SKILL.md` Step 0 self-select.
3. Docs sweep (handoff-to-superpowers.md, README.md, etc).

**Gotchas (from card, worth re-stating):**

- `git worktree add <path> -b <branch>` wants the branch to NOT
  already exist as a local branch. Current claim-card.sh creates
  the branch locally BEFORE push. Recommended re-order: push first
  via an intermediate mechanism, then `git worktree add --force`.
  Or: do the whole claim from a scratch worktree. **Recommend (a).**
- If the Consumer session is already IN a worktree, `git rev-parse
  --show-toplevel` points at the worktree root. Use
  `git rev-parse --git-common-dir` to find the primary checkout.
- Step 0 Card Selection must NOT claim during selection. It only
  queries + surfaces + confirms. CLAIM still happens in Step 2.
  Aborted select leaves nothing locked.

## Plan structure

Sub-task order (each its own commit):

1. **Plan brief** (this file). No implementation.
2. **claim-card.sh** — worktree creation, stdout contract, primary-
   tree resolution. Update help text + exit code docs.
3. **claim-card.sh tests** — extend `tests/test-claim-card.sh` for
   new stdout shape; add `tests/test-claim-card-worktree.sh` for
   worktree creation + concurrent distinctness.
4. **consuming-card/SKILL.md** — Step 0 self-select, Step 2
   rewrite to consume new stdout, cd-into-worktree note, drop
   "may or may not engage".
5. **handoff-to-superpowers.md** — hard-dep on using-git-worktrees.
6. **README.md + using-board-superpowers** — "3 terminals"
   clarification + forward refs.
7. **board-protocol reference** if claim file schema changes
   (likely no change — worktree path is derivable, not stored).

## Notes for future self

- This session is itself dog-fooding the worktree pattern: worktree
  at `~/.config/superpowers/worktrees/board-superpowers/16-consumer-self-select-worktree/`.
- Card #15 is in-flight in the main working tree; do not touch
  `claim/15-fix-claim-card-force-add` from here.
- Card #3 (session_id + symlink) will later touch the same
  `claim-card.sh`. Whoever merges second rebases. No coordination
  needed at card level.
