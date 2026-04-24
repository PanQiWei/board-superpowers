# Plan: Card #15 — Fix claim-card.sh: force-add claim marker to bypass .gitignore

## Context

Discovered during the 2026-04-24 self-hosting kickoff of card #2. The claim
mechanism in `scripts/claim-card.sh` is globally broken on this repo from
the moment `scripts/bootstrap-project.sh` runs.

Root cause: `bootstrap-project.sh` adds `.board-superpowers/claims/` to
`.gitignore` (per-session local state), but `claim-card.sh:132` does
`git add "$MARKER_FILE"` without `-f`. Git refuses to stage an ignored
path, `set -euo pipefail` triggers `bsp_die 20`, and the atomic
`git push` that establishes the claim lock never runs.

**Consequence**: every Consumer session in this repo exits with
`claim-card.sh: error: git add ... failed` before it can touch any card.
Production-severity blocker for the plugin's core flow.

Primary file: `scripts/claim-card.sh` (line 132, 2-character change).
New file: `tests/test-claim-card.sh` (self-contained regression harness).
`tests/` does not exist yet — create it.

## Acceptance Criteria (from card)

- [ ] `scripts/claim-card.sh` force-adds the claim marker
      (`git add -f "$MARKER_FILE"`), so the claim commit succeeds even
      when `.board-superpowers/claims/` is in `.gitignore`.
- [ ] A regression test lives under `tests/` (create directory if absent)
      that: (a) sets up a temp git repo + bare remote with
      `.board-superpowers/claims/` in `.gitignore`; (b) runs
      `claim-card.sh <N> <slug>` against it; (c) asserts the script exits
      0, the remote has the claim branch, and the branch tip contains
      `.board-superpowers/claims/<N>.claim` as a tracked file.
- [ ] Test fails deterministically against the pre-fix `claim-card.sh`
      (proves it catches this specific regression, not a stale
      tautology).
- [ ] `shellcheck` passes on the modified `claim-card.sh` and the new
      test script.
- [ ] Public interface (help text, exit codes, stdout shape) is
      unchanged.

## Out of Scope (from card — do NOT do these)

- Rethinking whether claim markers should be gitignored at all.
- Sweeping all other `git add` call sites for similar hazards.
- Adding CI to run the new test on every push.
- Documenting the claim mechanism in `board-protocol` SKILL (card #10).

## Target branch

`claim/15-fix-claim-card-force-add` (already created via **manual
claim**; first commit `claim: card #15 [s-7baf] (manual bootstrap
claim)` is already pushed).

## Size ceiling

**XS** (< 50 LOC across 1–2 files). Fix is literally 2 characters;
test harness is the bulk of the diff.

If work feels bigger, STOP and report NEEDS_CONTEXT — this card is not
the place to re-architect the claim mechanism.

## Execution hints (from card)

- Direct edit; `superpowers:subagent-driven-development` is overkill.
- End with `gstack:/codex` for a second opinion on the test harness
  (git test-isolation is subtle — bare remotes, `$GIT_DIR`, working-tree
  cleanup traps).
- **Manual claim exception documented**: the branch was pushed by hand
  because `claim-card.sh` cannot claim its own fix. The first commit on
  the branch uses `git add -f` explicitly — live proof the fix works.
- Some bash/git versions print `The following paths are ignored by one
  of your .gitignore files:` to stderr even with `-f`. Harness must
  tolerate that chatter.

## Execution order

1. Write `tests/test-claim-card.sh` against the **pre-fix** code, run
   it, confirm RED (exit non-zero). This is TDD's signal that the test
   catches the real bug.
2. Apply the 2-char fix to `scripts/claim-card.sh:132`.
3. Re-run the test, confirm GREEN.
4. `shellcheck scripts/claim-card.sh tests/test-claim-card.sh` — expect
   clean.
5. `gstack:/codex consult` for a second opinion on the test harness.
6. Commit test + fix (separate commits — test first, then fix — so the
   TDD lineage is preserved in history).
7. PR via `superpowers:finishing-a-development-branch`, then append
   the three protocol-required sections.
