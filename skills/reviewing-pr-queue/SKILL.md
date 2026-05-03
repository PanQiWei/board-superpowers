---
name: reviewing-pr-queue
description: |
  Use when the user wants to review open pull requests, check what's in the
  review queue, or validate PRs against the board contract.
  Triggers on: "review the PRs", "what's in In Review", "merge ready",
  "check the review queue", "PR queue", "validate PRs", "review queue",
  "what PRs need attention", "what needs reviewing".
  Use even when the user phrases it casually ("let's look at open PRs",
  "anything waiting to merge?") — the signal of wanting to review or triage
  open PRs is what matters.
  Do NOT use when the user wants to see overall board state (that's
  briefing-daily), bring in new work (intaking-requirement), or investigate
  blocked cards (triaging-board).
when_to_use: |
  Trigger on: "review the PRs", "review queue", "what's in In Review",
  "merge ready", "PR queue", "validate PRs", "what needs reviewing",
  "anything waiting to merge", "check open PRs". Apply when the Producer
  wants to process the PR queue — validate, comment, or route cards.
---

# reviewing-pr-queue

This is the Producer's review-queue routine. It lists open PRs linked to
board cards, validates each against the three-section PR contract, comments
on violations, transitions non-compliant cards back to `In Progress`, and
summarizes the queue.

**Required sub-skills**:
- `board-superpowers:board-canon` — state machine; Status transition validity.
- `board-superpowers:operating-kanban` — dispatch the `transition_card`
  protocol action (Status flip to `In Progress` on contract violation);
  resolves the active projection from settings.
- `board-superpowers:enforcing-pr-contract` — Contract A (PR body three-section
  shape), Contract B (card body AC terminal-state sync), Contract C (PR↔Issue
  auto-close keyword); provides validation rules and the violation comment
  template.
- `board-superpowers:composing-siblings` — consult before any sibling-plugin
  handoff (rare in this routine; included per mandatory declaration).
- `board-superpowers:classifying-actions` + `board-superpowers:auditing-actions`
  — applied at every mutating action in this routine.

## Overview

The review queue is the set of cards with Status = `In Review`. Each card
has one open PR. The routine walks each PR, applies three contract checks,
and routes: compliant PRs stay in `In Review` (human merge decision); non-
compliant PRs get a comment and their card transitions back to `In Progress`.

This routine does NOT merge PRs — that is always a human decision. It only
validates and routes.

The end goal is a clean summary the Producer can act on: a count of compliant
PRs ready for human merge, a count of violations bounced back to the Consumer,
and a set of optional sibling-plugin review escalations for high-value PRs.

## Step 1 — List open PRs linked to cards

Include `isDraft` in the fields requested so draft PRs can be filtered early:

```bash
gh pr list --state open --json number,title,body,headRefName,baseRefName,isDraft
```

Filter to PRs where `headRefName` matches the pattern `claim/<N>-...` (board-
managed claim branches). These are the PRs in scope. Ignore PRs from branches
that don't match the claim pattern — those are outside the board workflow and
get a flag (see `references/review-queue-detail.md` § "PR opened against a
non-claim branch").

Build a list of (PR number, card number extracted from branch name, PR body).

## Step 2 — Validate each PR against three contracts

For each PR, invoke `board-superpowers:enforcing-pr-contract`. It runs:

- **Contract A** — PR body three-section shape: `## Automated Verification`
  required and non-empty; `## Human Verification TODO` optional but must
  not be filler if present; `## Retro Notes` required when reusable lessons
  exist.
- **Contract B** — Linked card body AC terminal-state sync: every
  `- [ ] ` line under `## Acceptance criteria` must be `[x]` or `[!]` with
  a deferral reason. Bare `[ ]` is forbidden at PR-submit time.
- **Contract C** — PR body contains `Closes|Fixes|Resolves #<N>`
  (case-insensitive) referencing the linked card.

Collect pass / fail status per contract per PR.

## Step 3 — Handle violations

For each PR with at least one contract violation:

1. Post a comment on the PR identifying the failing contract(s). The comment
   template lives in `board-superpowers:enforcing-pr-contract`
   `references/section-templates.md`. Include the specific violation (which
   section is missing/empty, which ACs are still `[ ]`, whether the auto-close
   keyword is absent).

2. Transition the linked card from `In Review` to `In Progress`. This is a
   mutating action (action_id = 6 — Status flip on an in-flight claim).
   Apply the 5-step governance sequence from § "How mutating actions are
   handled" below. The `transition_card` protocol action is dispatched via
   `board-superpowers:operating-kanban`.

3. Record the violation in the summary (see Step 5).

Contract C failures carry a special note: appending the auto-close keyword
after a PR is already merged does NOT retrigger the GitHub auto-close webhook.
Surface this to the Producer and prepare for manual cleanup at merge time
(the Consumer's post-merge cleanup step handles this).

## Step 4 — Handle compliant PRs

For each PR with all contracts passing: no action. The card stays in
`In Review` and the Producer / human decides whether to merge. Do NOT
auto-approve or auto-merge.

The routine's job is validation and routing, not merge authorization. Even a
fully-passing PR requires a human merge decision. The Producer may then request
the optional deep-code-review handoff (see § "Sibling-plugin handoffs")
before merging, but that is a separate step initiated explicitly.

## Step 4a — Flag draft PRs

PRs in draft state (`isDraft: true` in the GitHub API response) are NOT in the
review queue by definition. List them separately in the summary under
"Drafts (not in scope)". Do NOT run contract checks on draft PRs — the Consumer
is signaling that the work is in flight and not ready for review. When the
Consumer marks the PR as ready for review, it becomes part of the next
review-queue run.

## Step 5 — Summarize

Return a one-screen summary:

```
## Review queue — <YYYY-MM-DD>

Total: <N> PRs in review

### Compliant (<count>) — waiting for human merge decision
- #<PR> (card #<N>) — <title>

### Violations found (<count>) — card returned to In Progress
- #<PR> (card #<N>) — <title>
  Violations: [Contract A: missing ## Automated Verification] [Contract B: 2 open ACs] [Contract C: no Closes keyword]
```

If the queue is empty: "No open PRs in the review queue."

Draft PRs are listed below the main summary if any exist.

## How mutating actions are handled

Every mutating action this skill performs (Status flip, PR comment) follows
the 5-step governance sequence:

At each mutating action point:
1. Resolve the action_id (from `board-superpowers:classifying-actions`
   `references/action-id-catalog.md`).
2. Invoke `board-superpowers:classifying-actions` with that action_id;
   receive A (auto), R (requires approval), or N (forbidden).
3. If A: act → invoke `board-superpowers:auditing-actions` to record one
   entry.
4. If R:
   a. Invoke `board-superpowers:auditing-actions` to record the proposal.
   b. Surface the proposal to the Producer.
   c. Wait for the Producer's reply (approve / decline).
   d. On approve: act → invoke auditing-actions to record the result.
   e. On decline: invoke auditing-actions to record the decline; abort.
5. If N: refuse the action and surface the block reason; no audit entry.

**Typical autonomy class for this routine:**
- PR comment (violation notice) → A-class (auto, per the autonomy matrix).
- Status flip to `In Progress` on contract violation → R-class (requires
  Producer approval — it's an in-flight card state change).

## Sibling-plugin handoffs in this routine

The review-queue routine has two sibling-plugin handoff points. Both go through
`board-superpowers:composing-siblings` before routing.

### Handoff 1 — Deep code review escalation

When a PR passes all three contract checks (Contracts A, B, C) but the Producer
wants a thorough code-quality review before approving the merge decision:

1. Invoke `board-superpowers:composing-siblings` with the PR URL and the
   "deep code review" intent to confirm sibling routing.
2. Surface the routing decision: "Contracts all pass — routing to
   `gstack:/review` for a production-bug-angle review of #<PR>."
3. Route to `gstack:/review` with the PR URL. The gstack `/review` skill
   examines the diff for production risk patterns (error handling, performance
   cliffs, security surfaces) from a reviewer angle independent of board-
   superpowers' contract checks.
4. After `gstack:/review` completes, optionally route to
   `superpowers:requesting-code-review` for an independent second-pair-of-eyes
   pass if the PR is large (diff > 300 lines) or touches a sensitive surface.

Trigger phrases: "give this a thorough review", "I want a second opinion on
#<PR>", "review the code quality of this PR", rather than just running the
normal single-pass contract validation.

### Handoff 2 — Contract violation that surfaces an architectural gap

When Contract A fails AND the PR author's explanation suggests a test-
architecture gap (e.g., "we don't have automated tests for this surface yet"),
the Producer may want to open a design conversation rather than just bounce
the PR.

1. Invoke `board-superpowers:composing-siblings` with the "design gap" intent.
2. Surface: "This looks like a test-architecture gap, not just a missing
   section. Routing to `board-superpowers:intaking-requirement` to create a
   follow-up card for the gap — or routing to `superpowers:brainstorming`
   if the gap needs design exploration first."
3. Route to `board-superpowers:intaking-requirement`.

The PR still gets the violation comment and the card transitions back to
In Progress regardless of this handoff. The handoff is about capturing the
architectural gap — it does NOT change the enforcement decision.

## Autonomy defaults

| Action | Default class | Rationale |
|--------|--------------|-----------|
| PR comment — violation notice | A (auto) | Non-destructive; Consumer reads it. |
| Status flip In Review → In Progress | R (requires approval) | In-flight claim state change; Consumer's work is affected. |
| `gstack:/review` comment posted on PR | A (auto) | Informational; authored by the review tool. |

Override mechanism: `autonomy_overrides:` in `<repo>/.board-superpowers/config.yml`.
`board-superpowers:classifying-actions` resolves overrides before every
mutating action — do NOT cache the class result across calls.

## Failure modes

| Situation | Correct handling |
|-----------|-----------------|
| `gh pr list` returns empty | "No open PRs — review queue is empty." No further action. |
| PR with no matching `claim/<N>-...` branch | Flag as out-of-band PR. Add to summary under a separate "Out-of-band PRs" section. Do NOT run contract checks on it. |
| Linked card is not in `In Review` | Note the status mismatch. Do NOT transition. Surface to Producer: "#<PR> is linked to card #<N> which is in <status>, not In Review. Investigate before processing." |
| Contract B: card body unreachable | Flag the unreachable body. Do NOT infer AC state from the PR body. Surface: "Card #<N> body unreadable — cannot verify Contract B." |
| `gstack:/review` fails or times out | Record the failure. Mark the PR as "code review pending" in the summary. Do NOT block the contract-check pipeline on it. |

## Edge cases

See `references/review-queue-detail.md` for:
- PR with merge conflicts
- PR opened against a non-claim branch
- PR linked to a card not currently in `In Review`
- Multi-card PR (one PR closes multiple cards)
- Producer self-review (Producer = Consumer, same person)
