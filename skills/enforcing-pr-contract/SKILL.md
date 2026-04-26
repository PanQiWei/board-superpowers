---
name: enforcing-pr-contract
description: Use whenever a PR is being authored from a board-superpowers card claim, OR a PR is being reviewed against the board's contract. Enforces the three required sections — Automated Verification, Human Verification TODO, Retro Notes — and rejects filler content. Apply on the Consumer side at PR submission (F-C12) AND on the Producer side during Review Queue triage (F-02). Apply even when the user doesn't explicitly mention "PR contract" — any time a PR body is being drafted, edited, or reviewed in this plugin's loop, this skill governs.
when_to_use: Use whenever drafting, editing, validating, or reviewing a PR body for a card claimed via consuming-card. Also when the Producer reviews open PRs in the Review Queue routine.
user-invocable: false
---

# enforcing-pr-contract

> **Skeleton type**: C (discipline). This SKILL.md enforces a
> rule that's tempting to skip under shipping pressure.
>
> **Reflexive — does NOT call any other same-plugin skill.**

## The iron law

**A PR opened from a `claim/N-...` branch MUST have all three
sections in this exact order, with non-filler content:**

1. `## Automated Verification`
2. `## Human Verification TODO` (optional in spirit, but must
   not be filler if present)
3. `## Retro Notes`

`scripts/submit-pr.sh` rejects PRs missing any required section
or containing filler. The `managing-board` Review Queue routine
(F-02) re-checks at review time and routes violators back to
the Consumer.

## Why this contract exists

**Automated Verification** = honesty about what was checked
without a human looking. Without this section, a PR description
becomes "trust me, it works" — and reviewers can't distinguish
"I ran 200 tests" from "I compiled it once". The section forces
you to enumerate what evidence the human reviewer can rely on.

**Human Verification TODO** = a list of things the reviewer
SHOULD click / observe that machines can't check (visual
correctness, copy tone, end-user flow). Optional because some
cards are pure mechanical refactors with no visual surface.

**Retro Notes** = the 30-second forward-look that turns this
card's lessons into other cards' input. Without it, the same
mistakes get rediscovered N cards later.

## Section templates

### Automated Verification (required)

```markdown
## Automated Verification

- [x] `bash scripts/verify-skill-metadata.sh` — pass (5 skills)
- [x] `bash scripts/verify-skill-frontmatter.sh` — pass
- [x] `shellcheck -x scripts/**/*.sh hooks/*.sh` — pass
- [ ] `bash scripts/check-deps.sh` — fails locally (gh project scope), works in CI
```

Rules:

- Each entry is an EXECUTABLE check (a bash command, a test
  invocation, a CI job name) — not "tests pass" without
  saying which tests.
- Use `[x]` for confirmed-passed, `[ ]` for known-failing,
  `[!]` for "not applicable to this PR" (with one-line
  reason).
- Empty list is rejected — a PR that mutates code MUST run
  some check. If you genuinely have nothing automated to
  verify (rare), put `[!] no automated check applicable —
  pure docs change` and explain.

### Human Verification TODO (optional, must be non-filler if present)

```markdown
## Human Verification TODO

- [ ] Open a fresh CC session in this worktree; type "what should I work on" — confirm `using-board-superpowers` triggers
- [ ] Run `/board-superpowers:consuming-card 12` — confirm `argument-hint` shows in autocomplete
```

Rules:

- Each entry is an action a HUMAN performs (clicks,
  observations) — not a re-run of an automated check.
- Filler triggers rejection: `(none)`, `N/A`, `n/a`, `TBD`,
  `nothing to verify` — write nothing instead, the section is
  optional. If you genuinely have a UI / UX surface and
  nothing to verify, that itself is a smell — push back.

### Retro Notes (required; explicit "n/a" allowed)

```markdown
## Retro Notes

- The `argument-hint` React crash bug (#22161) was fixed in CC 2.1.47, but the YAML defensive-quote rule still bites — keep the rule in `verify-skill-frontmatter.sh`.
- Splitting `bsp_audit_local_write` into a separate function vs inlining: chose inline for v1-minimum because there's only one caller, but factor out when a second caller appears.
```

Rules:

- Each entry is a reusable lesson — phrased as something the
  next card's Consumer can apply, not a narrative of this
  card's events.
- Acceptable to write `n/a — no reusable lessons emerged from
  this card` IF that's genuinely true (small mechanical
  changes, single-step bug fixes). The section MUST be
  present even when content is "n/a".

## Validation rules (what `submit-pr.sh` checks)

See `references/validation-rules.md` for the precise regex set.
Summary:

1. The literal heading `## Automated Verification` exists
2. The Automated Verification section is non-empty
3. The Automated Verification section is not exactly one of
   the filler phrases (TBD / N/A / etc.)
4. The literal heading `## Retro Notes` exists
5. The Retro Notes section is non-empty
6. (If `## Human Verification TODO` is present) it is not
   filler

The script does NOT enforce ordering of sections beyond the
existence of headings. Reviewers care about ordering for
readability; the gate cares about presence.

## Filler detection

See `references/filler-detection.md` for the full filler
catalog. v1-minimum stops at the obvious phrases:

```
TBD | tbd | TODO: write tests | (none) | n/a | N/A | nothing to verify
```

The full v1-complete catalog will include semantic filler ("I
checked it", "looks good", "tested locally" without saying what
was tested) once we have eval data on real PR bodies.

## How Producer enforces (F-02 Review Queue)

When `managing-board` runs the Review Queue routine, for each
open PR linked to a card it:

1. Fetches the PR body via `gh pr view <N> --json body`
2. Runs the same validation logic as `submit-pr.sh`
3. If validation fails: comment on the PR pointing at the
   violation; transition the card from `In Review` to
   `In Progress` (rework signal) only after Consumer ack.
4. If validation passes: leave the card in `In Review` for
   normal review-and-merge.

This skill is the **single source of truth** for both sides
(Consumer write + Producer validate) — there is no second
implementation of these rules anywhere in the plugin. SPOT
purpose: changes to the contract land in this one SKILL.md and
take effect on both sides automatically.

## Common rationalizations to reject

| "This card is too small to need a full PR contract" | A 1-line bug fix still benefits from the Retro Note that explains WHY — others encountering the same bug get the lesson. The Automated Verification can be `[x] manually re-tested the failing case, now passes`. |
| "Retro Notes is forced ceremony" | The bar is "n/a" if nothing emerged. The section's presence forces a 5-second pause to ask "did anything?" — that pause is the value. |
| "I'll backfill the sections after merge" | Post-merge edits don't reach reviewers. The contract exists for the review moment, not for archaeology. |
