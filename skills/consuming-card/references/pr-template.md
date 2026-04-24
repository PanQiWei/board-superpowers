# PR Body Template

The exact structure a Consumer session's final PR must follow. The
delegated PR skill (`superpowers:finishing-a-development-branch` or
`gstack:/ship`) writes the first half; this skill's Consumer appends
the protocol-required second half.

## Contents

- Full PR body — final form
- Section-by-section (Summary · Test Plan · Automated Verification · Human Verification TODO · Retro Notes)
- The closing line (`Closes #<N>`)
- The marker comment

## Full PR body — final form

```markdown
## Summary

<2–3 bullets from the delegated skill. Do not edit.>

## Test Plan

<from the delegated skill — what automated checks were run. Do not edit.>

## Automated Verification

<NEW — written by the Consumer. Concrete commands and outcomes.>

Ran `<primary test command>`: <passed/failed/skipped counts>.
Ran `<linter/typecheck command>`: <result>.
Coverage on new code: <%>.

<Any skipped or flaky tests, with one-line reason each:>
- `<test name>` — skipped: <reason>.

## Human Verification TODO

<NEW — each item a concrete action the architect can take in the
running product. If no human verification is needed at all:>

None — this change is fully covered by automated tests.

<OR:>

- [ ] <concrete step 1>
- [ ] <concrete step 2>

## Retro Notes

<NEW — always three sub-points.>

- **Estimate vs actual:** <card Size was X; PR felt like X because ...>
- **Surprises:** <what wasn't in the card's Context that cost time, OR "none">
- **Suggested decomposition next time:** <if you'd split differently, how; OR "n/a">

Closes #<card-number>.

<!-- board-superpowers:pr -->
```

## Section-by-section

### Summary + Test Plan (from delegated skill)

Do NOT modify. If the delegated skill produced a bad summary (e.g.,
obvious typo, wrong card reference), re-run the delegation. Don't
patch by hand — it breaks the contract that those skills own their
part.

### Automated Verification (yours)

Purpose: give the architect a precise answer to "did the gates pass".

What to include:

- The actual command(s) run, verbatim. Not "ran the tests" — `pnpm test`
  or `cargo test --workspace` or whatever.
- Pass/fail counts. Before and after if possible.
- Coverage percentage on the new code, if the project measures it.
- Any green CI badges that will auto-refresh (GitHub will render them).
- Explicit acknowledgment of any skipped or flaky test.

What to exclude:

- ❌ Opinions about code quality. Not your job.
- ❌ Implementation narration. The diff is the narration.
- ❌ "All tests pass" without the actual command and counts.

### Human Verification TODO (yours — the critical section)

This is the section the architect reads first when triaging the review
queue. Getting it right is the highest-leverage thing a Consumer session
does.

#### Rule 1 — One TODO per irreducibly-human check

If two items can be verified in the same browser session on the same
staging environment, write them as separate items but note the
co-verification in parentheses:

```
- [ ] Sign in with Google lands on /dashboard with avatar visible.
- [ ] (Same session:) Sign-out button returns to /login and clears cookie.
```

#### Rule 2 — Concrete means: environment + steps + expected outcome

```
- [ ] On staging (https://staging.app), click "Sign in with Google".
      Expect: redirect to Google's consent screen with scopes
      "openid email profile". After allowing, expect redirect to
      /dashboard within 3s with avatar in top-right.
```

Not:

```
- [ ] Make sure Google sign-in works.
```

#### Rule 3 — If nothing is irreducibly human, say so

Write exactly this, nothing more:

```
None — this change is fully covered by automated tests.
```

Do not pad with "the CI covers this" or "tests are green". That's what
Automated Verification is for.

#### Rule 4 — Dev environments count, but say which

Some TODOs are "run locally":

```
- [ ] Run `pnpm dev` locally. Expect: new log line "metrics collector
      started on port 9091" within 2s of startup.
```

That's fine. But explicit is required — "run it" is not enough.

### Retro Notes (yours)

Three mandatory sub-points, even if one is "n/a" or "none". The Manager
aggregates these across merged PRs during the Retro Routine — consistent
structure is what makes aggregation possible.

#### Estimate vs actual

Honest signal about sizing.

Good:

- Card Size was S. PR ended up S (~150 LOC). Matched.
- Card Size was M. PR ended up S (~180 LOC). Over-sized — could have
  split by moving the error-handling into its own card.
- Card Size was S. PR ended up M (~320 LOC). Under-sized — the OAuth
  callback had more edge cases than Context suggested.

Bad:

- ❌ "Was about right."
- ❌ "Took longer than expected." (Longer in what sense? LOC? Time? Effort?)

#### Surprises

What wasn't in the card that cost time. Be specific and name the
missing fact, not the emotion.

Good:

- `src/auth/middleware.ts` imports from `legacy/session.ts` via a
  re-export chain. Card Context didn't mention `legacy/`. Cost ~20 min
  of confusion.
- The staging env doesn't have the new `provider` column yet. Had to
  coordinate with the architect for a migration run mid-PR.

Bad:

- ❌ "Harder than I thought."
- ❌ "Edge cases."

If nothing surprised you: `none`.

#### Suggested decomposition next time

If, in hindsight, this card should have been split (or merged with a
sibling), describe how.

Good:

- Would have been cleaner as two cards: (1) happy path sign-in only,
  (2) all error flows as a follow-up. Error flows ended up being ~40%
  of the diff.

If the card was well-sized: `n/a`.

## The closing line

```
Closes #<card-number>.
```

This is what triggers GitHub's auto-close on merge AND is what the
Manager's Review Queue routine uses to link a PR to its card. Always
include. Single-digit precision — `Closes #42`, not `closes #42`
(the capital C is recognized by GitHub's automation but lowercase is
not guaranteed across all setups).

## The marker

```
<!-- board-superpowers:pr -->
```

Last line of the PR body. How tooling finds board-superpowers PRs vs.
any other PR. Never omit.
