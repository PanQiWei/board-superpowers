# enforcing-pr-contract — taste.md

Reusable quality checklist that goes BEYOND filler detection. Filler-detection (in `references/filler-detection.md`) catches the worst offenders mechanically. This file documents the **taste judgments** that distinguish "passes the validator" from "actually useful for the reviewer." A PR can pass `submit-pr.sh` and still be a low-quality submission.

Apply this when the Producer reviews PRs in the review-queue routine — not as a hard validator (it's subjective), but as a coaching reference when surfacing improvement asks.

## Automated Verification — taste calls

| ✅ Good shape | ❌ Bad shape (passes regex but low value) |
|---------------|-------------------------------------------|
| `[x] bash scripts/verify-skill-metadata.sh — pass (5 skills checked)` | `[x] tests pass` |
| `[x] manually re-tested the original failing case in <file>:<line> — bug no longer reproduces` | `[x] tested locally` |
| `[!] no shell scripts touched — shellcheck N/A` | (omitting Automated Verification entirely on a code-touching PR) |
| `[ ] gh project field-list returns empty in CI — investigating with @user` (open work, named) | `[ ] there are some failures` (vague, no owner, no plan) |
| Each entry names the SPECIFIC command run AND the result | Each entry could be true of any PR ever opened |

The line: an automated-verification entry should be something a future maintainer can RE-RUN and get the same result. If a reader can't tell what to type to reproduce the check, it's not a verification — it's an assertion.

## Human Verification TODO — taste calls

| ✅ Good shape | ❌ Bad shape |
|---------------|--------------|
| `[ ] Open /board-superpowers:consuming-card  — confirm autocomplete shows [card-number]` | `[ ] Test the new feature` |
| `[ ] Trigger the `daily` routine via "what should I work on" in a fresh session — confirm the briefing format from references/daily.md` | `[ ] Make sure it works` |
| `[ ] Re-read the relevant skill-authoring section with fresh eyes — confirm the diagnostic regex catches what you'd expect a Producer to catch by hand` | `[ ] Looks correct` |
| Each entry is a concrete user action with a concrete observable outcome | Each entry is "verify the thing is good" without saying what good looks like |

The line: a human-verification entry should give the reviewer a 30-second-or-less concrete task. If the reader has to interpret what "test the feature" means, you've shifted the design burden onto them.

## Retro Notes — taste calls

| ✅ Good shape | ❌ Bad shape |
|---------------|--------------|
| `The argument-hint React crash bug was fixed in CC 2.1.47, but the YAML defensive-quote rule still bites — keep verify-skill-frontmatter.sh's check.` (lesson + actionable) | `Learned a lot about CC frontmatter` (no actionable lesson) |
| `Splitting bsp_audit_local_write into a separate function vs inlining: chose inline since there's only one caller; factor out when a second appears.` (decision + trigger condition) | `Refactored some helpers` (description not lesson) |
| `n/a — pure typo fix, no reusable lessons emerged.` (genuine n/a, explicit) | `n/a` (without explanation — could be hiding skipped reflection) |
| `superpowers:requesting-code-review didn't compose well in spawn-Consumer mode — fall back to gstack:/review only and document the gap.` (lesson + future reader's action) | `Some skills don't compose well` (vague generalization) |

The line: a retro note should change what the next Consumer does on the next card. If reading it doesn't update behavior somewhere, it's a journal entry, not a retro.

## What this file is NOT

- **Not a hard validator** — `submit-pr.sh` doesn't check taste. A taste-bad PR still passes the contract; the Producer comments and asks for improvement during review.
- **Not exhaustive** — taste evolves as the team's repertoire grows. Add patterns here when you spot a recurring "passed validator but should have been better" case.
- **Not a substitute for examples** — concrete templates live in `references/section-templates.md`. This file is the meta-pattern (what makes templates good); section-templates is the recipe book.
