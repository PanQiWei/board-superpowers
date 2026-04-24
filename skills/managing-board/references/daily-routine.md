# Daily Routine

Triggered by: "what should I work on today", "plan today", "give me the
board", "status", "morning standup".

This is the agile daily-standup, adapted for a solo architect running N
parallel Consumer sessions. The goal is for the architect to leave this
conversation knowing exactly:

1. Which PRs need their verification today (highest priority — these
   unblock Consumer work already finished).
2. Whether any in-flight work is stuck.
3. Which Ready cards can be dispatched to new Consumer sessions, and
   the kick-off prompts for them.

## Contents

- Step 1 — Snapshot the board
- Step 2 — Detect stale claims
- Step 3 — Pull PRs linked to cards
- Step 4 — Render today's briefing (fixed template)
- Step 5 — Recommend one thing (priority order)
- Step 6 — Wait
- Anti-patterns

## Procedure

### Step 1 — Snapshot the board

Load the project config and pull the board state in one go:

```bash
# Read config
PROJECT=$(grep '^project:' .board-superpowers/config.yml | awk '{print $2}')
WIP=$(grep '^wip_limit:' .board-superpowers/config.yml | awk '{print $2}')
OWNER=${PROJECT%%/*}
NUMBER=${PROJECT##*/}

# Pull everything on the board
gh project item-list "$NUMBER" --owner "$OWNER" --format json --limit 200
```

Group items by Status: Backlog, Ready, In Progress, In Review, Blocked,
Done (ignore Done for today's view).

### Step 2 — Detect stale claims

For each `In Progress` card, check:

```bash
# Find the claim branch
git fetch origin
git branch -r | grep "claim/<N>-"

# How old is the last commit on that branch?
git log -1 origin/claim/<N>-* --format='%ar'
```

**Stale = no commit in last 6 hours AND no linked PR.** A stale claim
means a Consumer session died or was /clear'd.

### Step 3 — Pull PRs linked to cards

```bash
gh pr list --state open --json number,title,body,labels,isDraft,reviewDecision,headRefName,updatedAt
```

Filter to PRs whose `body` contains `<!-- board-superpowers:pr -->` and
`Closes #<N>`. Cross-reference with In Review cards.

### Step 4 — Render today's briefing

Present the architect with EXACTLY this structure, in this order. Do not
add commentary, do not paraphrase.

```
═══════════════════════════════════════════════════════════════
 BOARD — <project OWNER/NUMBER> — <YYYY-MM-DD>
═══════════════════════════════════════════════════════════════

🔴 NEEDS YOU FIRST — <N> PR(s) awaiting your verification
──────────────────────────────────────────────────────────

 #<card>  <card title>
     PR:  #<pr-number> — <headline from PR title>
     Human TODO: <count> unchecked items from PR body's
                 "Human Verification TODO" section
     Touch: <X files, Y lines> · Opened <time ago>

 [repeat per PR]

🟡 IN FLIGHT — <N> card(s) a Consumer is working on
──────────────────────────────────────────────────

 #<card>  <title>      session <slug>   last commit <time ago>
 [mark stale ones with ⚠️ STALE]

🟠 BLOCKED — <N> card(s)
──────────────────────────────────

 #<card>  <title>      reason: <last comment summarizing block>

🟢 READY TO DISPATCH — <N> card(s)
──────────────────────────────────
 (WIP budget: <in-progress count> / <WIP_LIMIT> used)

 #<card>  <title>   [size: S]
 #<card>  <title>   [size: M]
 ...

═══════════════════════════════════════════════════════════════
```

### Step 5 — Recommend one thing

After the table, write ONE paragraph (3–4 sentences max) telling the
architect what to do next. Pick based on this priority order:

1. **PRs first.** If there is at least one In Review PR, recommend they
   clear one before dispatching new work. A finished PR waiting on
   verification is more valuable than a new card in progress — it means
   a Consumer session's work is idle.

2. **Stale claims.** If any In Progress is stale, recommend triaging that
   next. Offer the three options: resume, reassign, cancel.

3. **WIP at or over limit.** If In Progress >= WIP limit, do NOT suggest
   dispatching new work. Recommend the architect either pair up on an
   in-flight card or raise the WIP limit deliberately.

4. **Dispatch.** If WIP has budget and Ready has cards, offer to
   generate kick-off prompts for up to (WIP_LIMIT - current_WIP) cards.
   Ask which the architect wants first — don't just pick.

### Step 6 — Wait

Do NOT proactively generate kick-off prompts. Do NOT proactively triage.
Let the architect's next message drive the next action.

## Anti-patterns

- ❌ Don't ask "what do you feel like working on today". Your job is to
  give them a decision-ready view. Feelings come after data.
- ❌ Don't generate a kick-off prompt for something you haven't confirmed
  is in `Ready`. Cards in Backlog are explicitly not-yet-actionable.
- ❌ Don't merge this routine with Intake ("we have time for X, should we
  add a new card?"). That's the architect's call, not yours.
- ❌ Don't skip the "NEEDS YOU FIRST" section even if empty. Always show
  the header with "(none)" — architects read the structure, not the
  prose, and expect consistent sections.
