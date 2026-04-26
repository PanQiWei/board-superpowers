# enforcing-pr-contract — filler detection

Filler catalog. Parent `SKILL.md` references this for the full list; v1-minimum implements a subset.

## v1-minimum filler set (regex-grade)

These phrases, when they form the **entire content** of a section, are rejected:

```
TBD
tbd
TODO: write tests
TODO: add verification
no notes
(none)
n/a
N/A
nothing to verify
nothing to test
nothing
N/A — see PR description
```

## v1-complete filler set (semantic-grade — deferred)

Once we have eval data on real PR bodies, the catalog expands to include semantically-empty content that passes regex. Expected additions:

- "I checked it" / "checked manually" / "tested locally" without saying WHAT was checked
- "Looks good" / "LGTM" used as the WHOLE section
- "All tests pass" without saying which tests
- "Refactor — no behavior change" used as Automated Verification (it's a description, not a verification)
- A single bullet that paraphrases the card title without adding info

## Why the bar starts low

Strict semantic filler detection requires LLM-grade judgment, which has cost (tokens, latency) AND false positives (some terse PRs are genuinely complete). v1-minimum chooses the regex floor because it catches the worst offenders ("TBD", "(none)") without false positives.

The next iteration will dispatch a small classifier subagent to check sections against semantic-filler heuristics — that's a v1-complete task.

## What to do when filler is detected

The Consumer-side path (`submit-pr.sh`):

1. Print the failing section + the matched filler phrase
2. Exit non-zero
3. Print suggested fix: "Replace the `<phrase>` with at least one concrete entry — see `enforcing-pr-contract` SKILL.md § Section templates for examples"

The Producer-side path (`managing-board` F-02 Review Queue):

1. Comment on the PR with the failing section + suggested fix
2. Transition the card from `In Review` back to `In Progress` (rework loop) — only after Consumer acknowledges, since this is an R-class action in v1-minimum
3. Audit-log the rework transition with reason: `pr-contract-violation: <section>: <filler>`

## What NOT to do when filler is detected

- Auto-fix the PR body. The whole point of the contract is to push the Consumer to think — auto-completion defeats the discipline.
- Block the merge unconditionally. Override mechanism exists; sometimes a human reviewer overrides for genuine reasons.
- Re-validate after each comment. The validator runs on submit + on Producer Review Queue scan — not continuously.
