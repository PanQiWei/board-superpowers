# managing-board — review-queue routine reference

Procedure detail for the review-queue routine. Parent `SKILL.md` § "Review-queue routine" describes the validation flow; this file documents merge-conflict handling and per-PR escalation.

## Contract validation per PR (3 contracts, in order)

For each open PR linked to a card, run all three contracts (per `enforcing-pr-contract/SKILL.md` "The iron law"):

1. **Contract A — PR body shape**: `## Automated Verification` + `## Retro Notes` headings present and non-empty; `## Human Verification TODO` not filler if present.
2. **Contract B — Card body AC sync**: linked card has zero `- [ ]` lines under `## Acceptance criteria`; every `- [!]` carries a one-line deferral reason.
3. **Contract C — PR↔Issue auto-close keyword**: PR body contains `Closes|Fixes|Resolves #<N>` (case-insensitive) referencing the linked card.

Failures route the card back to `In Progress`; pass leaves the card in `In Review`. Contract C failures carry a special note: appending the keyword post-OPEN does NOT retrigger the GitHub auto-close webhook for an already-merged PR — surface to the architect and prepare for manual cleanup at merge time (Consumer Step 12 stage (a) covers this manual recovery path).

## PR with merge conflicts

If a PR linked to a card has merge conflicts:

1. Comment on the PR: "Merge conflicts present. Pull main into the claim branch and resolve before re-requesting review."
2. Propose to the architect: transition the card from `In Review` back to `In Progress`. Wait for acknowledgement, then transition.
3. Notify the Consumer — they own the rebase.

Do NOT attempt to resolve the conflict from the Producer side. Conflicts are usually semantic; the Consumer has the context.

## PR opened against a non-claim branch

If a PR has a base branch other than `main`, OR the head branch doesn't match `claim/<N>-...`:

1. Flag immediately — this PR is outside the board contract.
2. Comment: "PRs in this repo come from `claim/N-...` branches off `main`. If this PR is outside the board flow, that's fine but document why in the PR body. If it should be a board-managed card, close this PR, open a card, and re-PR from a proper claim branch."
3. Do NOT transition any card — there's no card linkage.

## PR linked to a card not in `In Review`

If `claim/12-...` exists but card #12 is in `In Progress` or `Done`:

- **Card in In Progress**: the Consumer opened a PR but the Status flip didn't happen. Propose running the Status flip yourself and surface the inconsistency.
- **Card in Done**: this is suspicious — Done implies the PR was already merged. Likely a re-open. Flag and ask Consumer.

## Multi-card PR

If a PR's body says "Closes #12, #13, #14":

- Per design, one PR = one card. Multi-card PRs are a smell.
- Comment recommending the Consumer split the work next time.
- Validate the PR contract once (single section set) and route to merge — don't fail it just because of multi-card linkage; existing work shouldn't be punished.

## Producer self-review

When the Producer is also the Consumer (single-person dogfood), the review-queue routine still runs the contract validation, but the "request changes" loop becomes "self-correct in the same session". The audit-log entry uses an actor field marking the conflated identity.

## Approve vs request changes

This skill does NOT approve or merge PRs — that's still a human decision. The skill just **routes**: if contract-compliant, the card stays in `In Review` and the Producer / human decides; if non-compliant, the card flows back to rework.

The merge action itself is performed manually via `gh pr merge` or the GitHub UI. Auto-merge is not in scope; if it ever becomes scope it must be behind explicit config opt-in.
