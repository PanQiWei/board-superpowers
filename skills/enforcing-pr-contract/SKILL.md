---
name: enforcing-pr-contract
description: Use whenever a PR is being authored from a board-superpowers card claim, OR a PR is being reviewed against the board's contract. Enforces the three required sections — Automated Verification, Human Verification TODO, Retro Notes — and rejects filler content. Apply on the Consumer side at PR submission AND on the Producer side during review-queue triage. Apply even when the user doesn't explicitly mention "PR contract" — any time a PR body is being drafted, edited, or reviewed in this plugin's loop, this skill governs.
when_to_use: Use whenever drafting, editing, validating, or reviewing a PR body for a card claimed via the consuming-card skill. Also when the Producer reviews open PRs in their review-queue routine.
user-invocable: false
---

# enforcing-pr-contract

This skill is a discipline — it enforces a rule that's tempting to skip under shipping pressure. Use it on both sides of the loop: the Consumer drafting a PR and the Producer reviewing one.

## Decision tree at a glance

```mermaid
flowchart TD
    PR["PR opened from claim branch"] --> CA{"Contract A:\nPR body 3 sections\nvalid and non-filler?"}
    CA -- no --> Reject["Reject PR;\nroute card back to In Progress"]
    CA -- yes --> CB{"Contract B:\ncard body ACs all\n[x] or [!] with reason?"}
    CB -- "no, has unchecked [ ]" --> Reject
    CB -- "no, [!] without reason" --> Reject
    CB -- yes --> Pass(["Validation pass\ncard stays In Review"])
```

## The iron law

**A PR opened from a `claim/<N>-...` branch MUST satisfy two contracts simultaneously:**

### Contract A — PR body shape

All three sections in this exact order, with non-filler content:

1. `## Automated Verification`
2. `## Human Verification TODO` (optional in spirit, but must not be filler if present)
3. `## Retro Notes`

### Contract B — Card body acceptance-criteria sync

The card linked from the `claim/<N>-...` branch MUST have every acceptance-criterion checkbox in a terminal state by PR-submit time:

- `[x]` — verified-passing (the default for items the Consumer just shipped).
- `[!]` — explicitly deferred, with a one-line reason inline (`[!] depends on #45 — split as follow-up`). Use for items the Consumer cleanly chose NOT to deliver in this PR.
- `[ ]` — UNSHIPPED. **Forbidden at PR-submit time.** A `[ ]` AC means the Consumer has not addressed it; reviewer is left guessing whether it was forgotten or aborted.

The Consumer toggles each checkbox during `consuming-card` Step 9.5 (PR-submit pre-flight card body sync, action_id 112). Producer-side validation rejects a PR whose linked card has any `[ ]` AC.

### Why both contracts

`Contract A` makes the PR description honest about **what was checked**; `Contract B` makes the card body honest about **what was delivered**. Without B, a reviewer reads the PR body but the card body still claims "[ ] all 12 ACs unimplemented" — instant cognitive dissonance, hidden scope leak, and a stale "to-do" list for the next Consumer to mistakenly pick up.

`scripts/submit-pr.sh` rejects PRs missing any required PR-body section, containing filler, or whose linked card body has unchecked ACs. The `managing-board` skill's review-queue routine re-checks both contracts at review time and routes violators back to the Consumer.

## Why this contract exists

**Automated Verification** = honesty about what was checked without a human looking. Without this section, a PR description becomes "trust me, it works" — and reviewers can't distinguish "I ran 200 tests" from "I compiled it once". The section forces you to enumerate what evidence the human reviewer can rely on.

**Human Verification TODO** = a list of things the reviewer SHOULD click / observe that machines can't check (visual correctness, copy tone, end-user flow). Optional because some cards are pure mechanical refactors with no visual surface.

**Retro Notes** = the 30-second forward-look that turns this card's lessons into other cards' input. Without it, the same mistakes get rediscovered N cards later.

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

- Each entry is an EXECUTABLE check (a bash command, a test invocation, a CI job name) — not "tests pass" without saying which tests.
- Use `[x]` for confirmed-passed, `[ ]` for known-failing, `[!]` for "not applicable to this PR" with a one-line reason.
- Empty list is rejected — a PR that mutates code MUST run some check. If you genuinely have nothing automated to verify (rare), put `[!] no automated check applicable — pure docs change` and explain.

### Human Verification TODO (optional, must be non-filler if present)

```markdown
## Human Verification TODO

- [ ] Open a fresh CC session in this worktree; type "what should I work on" — confirm the entry skill triggers
- [ ] Run `/board-superpowers:consuming-card 12` — confirm the autocomplete shows `[card-number]`
```

Rules:

- Each entry is an action a HUMAN performs (clicks, observations) — not a re-run of an automated check.
- Filler triggers rejection: `(none)`, `N/A`, `n/a`, `TBD`, `nothing to verify` — write nothing instead, the section is optional. If you genuinely have a UI / UX surface and nothing to verify, that itself is a smell — push back.

### Retro Notes (required; explicit "n/a" allowed)

```markdown
## Retro Notes

- The `argument-hint` React crash was fixed in CC 2.1.47, but the YAML defensive-quote rule still bites — keep the rule in `verify-skill-frontmatter.sh`.
- Splitting `bsp_audit_local_write` into a separate function vs inlining: chose inline because there's only one caller, but factor out when a second caller appears.
```

Rules:

- Each entry is a reusable lesson — phrased as something the next card's Consumer can apply, not a narrative of this card's events.
- Acceptable to write `n/a — no reusable lessons emerged from this card` IF that's genuinely true (small mechanical changes, single-step bug fixes). The section MUST be present even when content is "n/a".

## Validation rules (what `submit-pr.sh` checks)

`references/validation-rules.md` documents the precise regex set. Summary:

**PR body shape (Contract A):**

1. The literal heading `## Automated Verification` exists.
2. The Automated Verification section is non-empty.
3. The Automated Verification section is not exactly one of the filler phrases (TBD / N/A / etc.).
4. The literal heading `## Retro Notes` exists.
5. The Retro Notes section is non-empty.
6. (If `## Human Verification TODO` is present) it is not filler.

**Card body AC sync (Contract B):**

7. The card linked from the `claim/<N>-...` branch has zero `- [ ]` lines under its `## Acceptance criteria` heading. Every AC must be `- [x]` or `- [!]`.
8. (If any `- [!]` appears) the line must continue with prose (≥ 5 chars) explaining the deferral. A bare `- [!]` is filler.

The script does NOT enforce ordering of PR body sections beyond the existence of headings. Reviewers care about ordering for readability; the validator cares about presence + (for the card) terminal-state ACs.

## Filler detection

`references/filler-detection.md` lists the filler catalog. The current floor catches the obvious phrases:

```
TBD | tbd | TODO: write tests | (none) | n/a | N/A | nothing to verify
```

A semantic-grade catalog (catching "I checked it manually" without saying what was checked) is in scope for a future iteration but not implemented today.

## Beyond filler — the taste reference

`submit-pr.sh` only catches whole-section filler. PRs can pass the validator and still be low-quality (vague checks, generic "tested locally" claims, retro notes that don't change anyone's behavior). The Producer-side review catches these — `references/taste.md` documents the **good vs bad shapes** for each section as a coaching reference. Use it during the review-queue routine when commenting on a PR that passed validation but should have been better.

## How the Producer enforces

When the Producer's `managing-board` skill runs its review-queue routine, for each open PR linked to a card it:

1. Fetches the PR body via `gh pr view <PR-N> --json body`.
2. Fetches the card body via `gh issue view <card-N> --json body`.
3. Runs the full validation logic as `submit-pr.sh` — both Contract A (PR body shape) and Contract B (card body AC sync).
4. If validation fails: comments on the PR pointing at the specific violation (cite which contract + which rule); the Producer then proposes routing the card from `In Review` back to `In Progress` (rework signal) and asks the Consumer to acknowledge before transitioning.
5. If validation passes: leaves the card in `In Review` for normal review-and-merge.

This skill is the **single source of truth** for both sides (Consumer write + Producer validate) — there is no second implementation of these rules anywhere in the plugin. Changes to the contract land in this one SKILL.md and take effect on both sides automatically.

## Override mechanism

The Producer can override validation for a specific PR by adding the `pr-contract-override` label BEFORE merge. The override creates an audit-log entry so the bypass is traceable.

## Common rationalizations to reject

| Rationalization | Reality |
|-----------------|---------|
| "This card is too small to need a full PR contract" | A 1-line bug fix still benefits from the Retro Note that explains WHY — others encountering the same bug get the lesson. The Automated Verification can be `[x] manually re-tested the failing case, now passes`. |
| "Retro Notes is forced ceremony" | The bar is "n/a" if nothing emerged. The section's presence forces a 5-second pause to ask "did anything?" — that pause is the value. |
| "I'll backfill the sections after merge" | Post-merge edits don't reach reviewers. The contract exists for the review moment, not for archaeology. |
