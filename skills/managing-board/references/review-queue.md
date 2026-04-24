# Review Queue Routine

Triggered by: "What PRs need me?", "Review queue", "What should I verify?",
"Show me what's ready for E2E".

The architect's verification attention is the bottleneck this plugin is
designed to minimize. This routine's job is to make that attention go as
far as possible: load all waiting PRs, extract the human-verification
TODOs, group them so the architect can batch similar checks, and prioritize.

## Contents

- Step 1 — Pull all In Review PRs
- Step 2 — Gate: did Consumer follow the contract?
- Step 3 — Group for batching (same area · fast-lane · UI · else)
- Step 4 — Render the queue (fixed template)
- Step 5 — Recommend an order
- Step 6 — Offer retrospective signal
- Anti-patterns

## Procedure

### Step 1 — Pull all In Review PRs

```bash
gh pr list --state open \
  --json number,title,body,headRefName,baseRefName,labels,reviewDecision,updatedAt,files,additions,deletions,mergeable
```

Filter to PRs whose body contains `<!-- board-superpowers:pr -->`.
Non-board PRs are outside this routine's scope.

For each surviving PR, extract:

- Linked card number (search `Closes #<N>` in PR body).
- Contents of the `## Human Verification TODO` section — parse each
  unchecked `- [ ]` item.
- Contents of the `## Retro Notes` section — scan for "surprises" or
  "suggested decomposition" language; these feed into Retro Routine.
- File surface area (number of files, additions + deletions).
- Whether CI is green (`gh pr checks <N>`, or whatever the repo uses).

### Step 2 — Gate: did Consumer actually do its job?

Before presenting PRs to the architect, audit each for protocol
compliance. If ANY of these fail, do not present the PR to the architect
— add a note that the Consumer didn't follow protocol and suggest the
architect bounce it back with a comment.

- [ ] PR body has `## Human Verification TODO` section (may contain
      "None — fully covered by automated tests." and that's valid).
- [ ] PR body has `## Automated Verification` section with concrete
      results, not a placeholder.
- [ ] PR body has `## Retro Notes` section.
- [ ] PR body references `Closes #<N>` pointing to a real card.
- [ ] The linked card is in `In Review` (not still `In Progress` —
      means Consumer forgot to transition).
- [ ] CI is green OR PR is explicitly marked Draft.

### Step 3 — Group for batching

Architects verify faster when similar PRs come back-to-back. Group by:

- **Same area of the product** (detect via file path overlap: two PRs
  both touching `/src/checkout/` group together).
- **Zero-TODO PRs** (fully automated verification) — these deserve their
  own fast lane: architect just reviews the diff and merges.
- **UI-heavy PRs** — detect via file paths matching common UI
  extensions (.tsx, .vue, .svelte, .html, .css). Group because
  architect usually wants to spin up one local / staging run.
- **Everything else.**

### Step 4 — Render the queue

```
═══════════════════════════════════════════════════════════════
 REVIEW QUEUE — <N> PRs awaiting you
═══════════════════════════════════════════════════════════════

🟢 FAST LANE — no manual verification needed (<M> PRs)
──────────────────────────────────────────────────────

 #<pr>  →  card #<card>  —  <PR title>
     <files changed>, <+adds -dels>  ·  CI ✓
     "None — fully covered by automated tests."

 [repeat]

🖼️  UI VERIFICATION (<M> PRs — spin up one local/staging run and batch)
──────────────────────────────────────────────────────────────────────

 #<pr>  →  card #<card>  —  <title>
     Human TODO:
       • <todo 1>
       • <todo 2>

 [repeat]

🧪 FUNCTIONAL VERIFICATION (<M> PRs — grouped by area)
──────────────────────────────────────────────────────

 Area: <path prefix>
   #<pr>  →  card #<card>
       • <todo>
       • <todo>

 [repeat per area]

⚠️  PROTOCOL ISSUES (<M> PRs — Consumer didn't follow contract)
──────────────────────────────────────────────────────────────

 #<pr>  card #<card>  —  <why it failed the gate>
     Suggested reply to Consumer:
       "Please add <missing section> per board-protocol, then re-request
        review."

═══════════════════════════════════════════════════════════════
```

### Step 5 — Recommend an order

After the queue, write ONE sentence recommending the order:

> "Suggest: clear the Fast Lane (~5 min), then batch the UI checks in one
> staging session, then tackle the two checkout-area functional checks
> together."

### Step 6 — Offer retrospective signal

If two or more Retro Notes sections mention the same type of surprise
(e.g., multiple Consumers saying "the card should have been split"),
flag it:

> "Two Consumers flagged cards that should have been split (#42, #47).
> Want to queue a mini-retro when you're done reviewing?"

Do not run the retro now — that's a separate routine.

## Anti-patterns

- ❌ Don't merge PRs for the architect. Merge is their signal, not yours.
- ❌ Don't open PR review threads on the architect's behalf. Let them
  click through.
- ❌ Don't estimate time-to-verify. You have no ground truth.
- ❌ Don't rank PRs by "importance" — you don't know the architect's
  priorities. Group by similarity and let them decide order.
- ❌ Don't surface PRs that failed protocol to the Fast Lane. They
  belong in Protocol Issues until fixed.
