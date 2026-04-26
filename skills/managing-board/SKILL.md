---
name: managing-board
description: Use when the user asks about planning today's work, what to work on next, the morning briefing, the board state, the Review Queue, or the intake of a new requirement. Also when triaging blocked cards or reviewing what is currently in flight. Apply this skill even when the user doesn't explicitly say "managing the board" — any time their message reads as Producer-side board orchestration (vs Consumer-side card execution), this is the skill. v1-minimum scope covers F-01 daily routine, F-02 Review Queue, and F-08 intake.
when_to_use: Use when the user says "what should I work on", "morning briefing", "today's work", "show me the board", "review the open PRs", "new requirement", "intake this idea", "what's blocked", "triage the board", "weekly view".
argument-hint: "[routine]"
---

# managing-board

> **Skeleton type**: A (pattern). Producer-session main skill.
> Carries F-01 (daily) + F-02 (Review Queue) + F-08 (intake)
> in v1-minimum. F-03..F-07 + F-09..F-15 are deferred to
> v1-complete.
>
> **REQUIRED SUB-SKILLS**:
> - `board-superpowers:board-canon` (read schema before any
>   transition decision)
> - `board-superpowers:enforcing-pr-contract` (Review Queue
>   contract-violation check)

## When to use

Symptoms (the user says):

- "what should I work on" / "morning briefing" / "today's plan"
  → daily routine
- "review the PRs" / "what's in In Review" / "merge ready" →
  Review Queue routine
- "new requirement" / "intake this idea" / "I have a feature
  for the board" → intake routine
- "what's blocked" / "triage the board" / "release stale claims"
  → triage routine

When NOT to use:

- "claim card N" / "work on #X" / `[board-card:#N]` → that's
  `consuming-card`, not this.
- "decompose this design doc" → that would be
  `decomposing-into-milestones`, **deferred to v1-complete**.
  In v1-minimum, the Producer hand-decomposes via the intake
  routine.

## Routine selection

The `argument-hint: "[routine]"` autocomplete shows the Producer
which routine they're invoking. If invoked WITHOUT an argument
(natural language), pick the routine from the user's prompt
vocabulary using this table:

| Phrase | Routine | Reference |
|--------|---------|-----------|
| "what should I work on" / "morning briefing" | daily | `references/daily.md` |
| "review the PRs" / "Review Queue" | review-queue | `references/review-queue.md` |
| "new requirement" / "intake" | intake | `references/intake.md` |
| "what's blocked" / "triage" | triage | `references/triage.md` |

If the prompt is genuinely ambiguous (e.g., "let's look at the
board"), **ask the Producer** which routine they want — do NOT
pick by default. v1-minimum has only 4 routines so the choice
is small; degrading to "do all four sequentially" wastes
attention.

## Daily routine (F-01)

Goal: produce a one-screen briefing of the board's current state
that helps the Producer decide what to do next.

### Procedure

1. **Read the board** — call `bash scripts/read-board.sh
   --owner <owner> --project <number>`. Owner + number live in
   `.board-superpowers/config.yml`. Parse the JSON output.

2. **Group by Status**. Produce a markdown summary in this
   exact format:

   ```markdown
   ## Board state — <YYYY-MM-DD>

   ### In Progress (<count>)
   - #<N> <title> — claim by <consumer>, <age>

   ### In Review (<count>)
   - #<N> <title> — PR #<P>, <age> since opened

   ### Blocked (<count>)
   - #<N> <title> — blocker: <one-line>

   ### Ready (<count>)
   - #<N> <title> — <estimate>

   ### Backlog (<count>)
   - <count> cards — names omitted unless ≤ 5 total
   ```

3. **Highlight WIP situations** — flag any Consumer who is at
   their WIP cap (per `board-canon` § "WIP counting"). Flag any
   Consumer with stale claims (>72h with no commits).

4. **Recommend the next action** — pick ONE of:
   - "Review the Review Queue" (if `In Review` count > 0)
   - "Triage Blocked" (if `Blocked` count > 0)
   - "Claim a Ready card" (if `Ready` count > 0 and Producer
     wants to context-switch into Consumer mode)
   - "Run intake" (if all the above are empty — board is idle)

5. **Audit log entry** — write one R-class entry to
   `audit-local.jsonl` (action_id 200, summary
   `daily-routine ran at <timestamp>`).

## Review Queue routine (F-02)

Goal: validate every open PR linked to a card against
`enforcing-pr-contract`, surface violations, route cards back
to `In Progress` for rework when needed.

### Procedure

1. **List open PRs linked to cards** — `gh pr list --state
   open --json number,title,body,headRefName`. Filter to
   branches matching `claim/<N>-...`.

2. **For each PR**: invoke
   `board-superpowers:enforcing-pr-contract` to validate the
   body. (See that skill's § "How Producer enforces (F-02
   Review Queue)" for the exact rules.)

3. **For each violation**:
   - Comment on the PR pointing at the failing section + the
     fix template from `enforcing-pr-contract` references.
   - DO NOT immediately transition the card — that's an
     R-class action. Wait for the Consumer to acknowledge,
     then transition.
   - Audit-log the violation: action_id 201, decision_class R.

4. **For each compliant PR**: no action — leave the card in
   `In Review` for human merge approval.

5. **Summarize** — return a count of (compliant / violated /
   total).

See `references/review-queue.md` for the full procedure
including merge-conflict handling and per-Consumer notification
patterns.

## Intake routine (F-08)

Goal: turn a new requirement (text, design doc, idea) into a
shape decision: spec doc / design conversation / direct card.

### Procedure

1. **Acknowledge the requirement** — repeat back what the
   Producer said in 1-2 sentences. Confirm understanding before
   shaping.

2. **Pick the routing** based on signal type (see
   `references/intake.md` for the decision tree):

   - **Idea / vision**: route to
     `gstack:/office-hours` for direction-setting. Produces a
     YC-style "is this worth building" verdict.
   - **Architecture decision**: route to
     `gstack:/plan-eng-review`. Produces an architecture lock.
   - **Multi-step requirement** that's already direction-set:
     route to `superpowers:brainstorming` for sharper
     decomposition. (In v1-complete this hands off to
     `decomposing-into-milestones`; in v1-minimum the Producer
     hand-decomposes after.)
   - **Single-card-sized work** that's clearly defined:
     directly create the card (R-class action — propose the
     card body to the architect, ack, then `gh issue create`).

3. **Whatever path was taken, NOT a Consumer's job** — the
   intake routine ends with the work being either a
   spec/design artifact or a Ready card on the board. If the
   architect tries to "just do it" mid-intake, push back: the
   v1 design rests on intake → decompose → claim being separate
   acts.

4. **Audit log** — action_id 800, decision_class A
   (Producer-managed intake).

## Triage routine (F-15 partial — v1-minimum)

Goal: scan Blocked cards + stale claims; recommend either
unblocking actions or release.

### Procedure

1. **Read Blocked cards**:
   `bash scripts/read-board.sh --status Blocked`.
2. For each: read the card body, find the named blocker (per
   `board-canon` § "State machine" Blocked → In Progress
   transition rules). Recommend an action.
3. **Read stale claims**: list `claim/N-...` branches; check
   commit count beyond initial empty marker; flag any > 72h
   with no progress.
4. **Recommend release** for stale claims older than 7 days
   with the original Consumer notified — release is an R-class
   action (must ask architect).

## v1-minimum degradation block

> All mutating actions in this skill (Status flips, card body
> writes, PR comments, branch deletes, audit-log writes) run as
> R-class with the architect by default. The full
> D-AUTONOMY-1 matrix from `classifying-actions` is **deferred
> to v1-complete**. When that atomic ships, this block gets
> replaced with `Apply classifying-actions to the action; act
> on its A/R/N decision.`

> All audit log writes go to
> `~/.board-superpowers/<host>/<repo>/audit-local.jsonl` via
> `bsp_audit_local_write` from `scripts/lib/common.sh`. The full
> BYO RDBMS schema from `auditing-actions` is **deferred to
> v1-complete**. When that atomic ships, this block gets
> replaced with `Apply auditing-actions for the schema +
> two-entry rule.`
