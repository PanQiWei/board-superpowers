---
name: briefing-daily
description: |
  Use when the user wants a morning briefing, asks "what should I work on", wants
  to see the current board state, or needs to orient at the start of a session.
  Triggers on: "morning briefing", "what should I work on", "today's plan",
  "board overview", "what's running", "what's in progress", "board state",
  "show me the board", "daily briefing". Use even when the user phrases it
  casually ("what's up on the board", "catch me up") — the orientation signal
  is what matters, not formality.
  Do NOT use when the user wants to bring in a new requirement (that's
  intaking-requirement), review open PRs (that's reviewing-pr-queue), or
  investigate blocked cards (that's triaging-board).
when_to_use: |
  Trigger on: "morning briefing", "what should I work on", "today's plan",
  "board overview", "show me the board", "daily standup", "what's in progress",
  "board status", "orient me", "catch me up". Use at every Producer session start
  even when the user doesn't explicitly ask for a briefing — anytime the context
  signals "Producer starting a session and needs to know current state."
---

# briefing-daily

This is the Producer's daily orientation skill. It reads the board, produces a
one-screen summary, flags WIP issues and stale claims, and recommends ONE next
action.

**Required sub-skills**:
- `board-superpowers:board-canon` — read before any Status or WIP decision.
- `board-superpowers:operating-kanban` — dispatch the `read_board` protocol
  action; resolves the active projection from settings.
- `board-superpowers:composing-siblings` — consult before any sibling-plugin
  handoff (e.g., if overflow delegation to `gstack:*` / `superpowers:*` is
  needed in an extended orientation session).
- `board-superpowers:classifying-actions` + `board-superpowers:auditing-actions`
  — applied at every mutating action (stale-claim administrative release if any).
  The daily read itself is non-mutating and does NOT invoke auditing-actions.

## Overview

The daily briefing answers three questions:

1. **Where is everything?** — group cards by Status, count each group.
2. **Is anything wrong?** — WIP cap violations, stale claims (>72h with no
   commits beyond the initial claim marker).
3. **What should I do next?** — ONE recommended action, from the priority list
   below.

This skill does NOT merge, transition, or create cards (those are
reviewing-pr-queue, triaging-board, intaking-requirement). If the briefing
surfaces something that needs action, route to the appropriate routine SKILL.

## Step-by-step procedure

### Step 1 — Read the board

Invoke `board-superpowers:board-canon` to load the state machine and WIP
counting formula. Then invoke `board-superpowers:operating-kanban` with action
`read_board`. The projection (GitHub Project v2 / Linear / Jira) is resolved
from `<repo>/.board-superpowers/settings.yml § modules.m10_kanban`; operating-
kanban handles the backend routing transparently.

Parse the JSON output. Expect fields: `number`, `title`, `status`, `url`,
`item_id` per card.

### Step 2 — Group by Status

Produce a markdown summary in this exact format (omit groups with 0 items,
unless ALL groups are 0):

```markdown
## Board state — <YYYY-MM-DD>

### In Progress (<count>)
- #<N> <title> — claimed by <consumer>, <age>

### In Review (<count>)
- #<N> <title> — PR #<P>, <age> since opened

### Blocked (<count>)
- #<N> <title> — blocker: <one-line>

### Ready (<count>)
- #<N> <title> — <estimate or XS/S/M/L>

### Backlog (<count>)
- <count> cards (names omitted when > 5 total)
```

If ALL statuses are empty, use the empty-board format in
`references/daily-detail.md`.

**Hot-card ordering**: In Progress + In Review first; collapse Backlog to a
count when > 5 items.

**Single-Consumer projects**: drop the "by <consumer>" suffix when there is
only one person. See `references/daily-detail.md` for the simplified format.

### Step 3 — Flag WIP issues

Per `board-superpowers:board-canon` § "WIP counting formula" (In Progress +
In Review count; Blocked is excluded):

- **At cap**: if any Consumer is at their WIP cap, flag it: "⚠ <name> is at
  WIP cap — review queue or unblock before claiming new work."
- **Stale claims**: a claim branch is stale if age > 72h AND commit count
  beyond the initial claim marker = 0. Flag: "⚠ #<N> stale claim — no
  commits in <days>d <hours>h".

Stale-claim age computation:
```bash
git log origin/claim/<N>-<slug> --not main --oneline | wc -l
```
If 0 (or 1 for the initial empty-marker commit), count the time since branch
creation. See `references/daily-detail.md` for the exact git invocation.

### Step 4 — Recommend ONE next action

Priority order (pick the first that applies):

1. "Review the review queue" — if `In Review` count > 0. Invoke
   `board-superpowers:reviewing-pr-queue`.
2. "Triage Blocked cards" — if `Blocked` count > 0. Invoke
   `board-superpowers:triaging-board`.
3. "Claim a Ready card" — if `Ready` count > 0 and the Producer wants to
   context-switch into Consumer mode. Show the top card by priority.
4. "Run intake" — if all the above are empty. Invoke
   `board-superpowers:intaking-requirement`.

State the recommendation as ONE sentence: "Recommend: review the PR queue —
#12 and #14 are awaiting validation."

Do NOT list multiple recommendations. The value is the single opinionated
recommendation, not a menu. If the Producer wants a different action, they
can say so.

### Step 4a — Extended orientation (sibling-plugin handoff)

After the board state is presented, the Producer may respond with a strategic
question ("Is this the right work to be doing?", "Should we drop card #N and
start on X instead?") that goes beyond what board data can answer. This is a
sibling-plugin handoff scenario.

When the Producer's response to the briefing reads as a direction or prioritization
question rather than a "what's on the board" question:

1. Invoke `board-superpowers:composing-siblings` to confirm the appropriate
   sibling and its invocation safety (Mode-2 compatibility check).
2. Surface the routing decision to the Producer before routing:
   "This reads as 'is this the right work' territory. Routing to
   `gstack:/office-hours` for a demand-reality check."
3. Route to the appropriate sibling skill:
   - **Direction / prioritization question** ("should we build this?",
     "is card #N still worth doing?") → `gstack:/office-hours` or
     `gstack:/plan-ceo-review`.
   - **Architecture re-check** ("does the current roadmap sequence make sense?",
     "is the dependency graph right?") → `gstack:/plan-eng-review`.
   - **Design exploration triggered by briefing output** (e.g., a new blocker
     surfaces a design question the team hasn't resolved) → route to
     `board-superpowers:intaking-requirement` which then routes to
     `superpowers:brainstorming` via `composing-siblings`.

This extended orientation path is the ONLY place in `briefing-daily` where
a sibling-plugin handoff occurs. All other sibling-plugin calls are routed
through the appropriate routine (intaking-requirement, reviewing-pr-queue,
triaging-board) rather than initiated from within the briefing.

## How mutating actions are handled

On rare occasions the briefing surfaces a clear administrative action
(e.g., deleting a ghost branch for a card that is already Done). Apply the
5-step governance sequence:

1. Resolve the action_id (from `board-superpowers:classifying-actions`
   `references/action-id-catalog.md`).
2. Invoke `board-superpowers:classifying-actions` with that action_id;
   receive A (auto), R (requires approval), or N (forbidden).
3. If A: act → invoke `board-superpowers:auditing-actions` to record one
   entry.
4. If R: invoke auditing-actions to record the proposal; surface to the
   Producer; wait for reply; on approve → act + audit; on decline → audit
   decline and abort.
5. If N: refuse the action, no audit entry.

Prefer to route to triaging-board rather than taking administrative action
from within the briefing. The briefing's job is to orient, not to mutate.

## Context-switch reload (re-entry variant)

When the Producer returns to an old card or Thread after a gap, the briefing
skill runs first to re-establish context before routing to the appropriate
routine. The briefing narrows its output to the card in question:

- Show the card's current status, last-commit timestamp, and most recent
  PR comment.
- Recommend the appropriate next action for that specific card (resume →
  consuming-card; review → reviewing-pr-queue; investigate block →
  triaging-board).

This re-entry variant fires when the user signals **orientation desire** —
"catch me up on #N", "what's the status of #N", "orient me on #N",
"where did we leave off on #N" — NOT resume desire ("claim #N", "work on #N",
"pick up #N"); resume phrases route to `consuming-card` directly. See
`references/daily-detail.md` § "Context-switch reload" for the truncated
output format.

## Today's dispatch recommendation (extended variant)

When the Producer asks "what should I work on today" with a time-window
qualifier ("I have 2 hours", "I can ship one card today"), extend the
recommendation to a dispatch list:

1. Complete Step 1-3 as above.
2. Score Ready cards by (size ≤ available time) × (blocked-on count = 0) ×
   (oldest first for equal scores).
3. Return a ranked list of up to 3 cards with one-line rationale each.

The dispatch recommendation is read-only and non-binding — the Producer
decides. Do NOT pre-claim cards.

## Velocity signal (optional)

When the board shows consecutive Done cards from the past 5 days, append a
one-line velocity note below the recommendation:

```
Velocity: N cards shipped in the last 5 days. Pace: [above / at / below] target.
```

This is informational only. Do NOT compute a prediction or a sprint burn-down —
those are human-team cadence constructs that don't translate directly to the
AI-agent throughput model. Surface the raw count; let the Producer interpret it.

## Failure modes

| Situation | Correct handling |
|-----------|-----------------|
| `read_board` returns empty (network / auth failure) | Surface the failure verbatim. Do NOT synthesize a board state from memory or cache. "Board read failed — operating-kanban returned: <error>. Fix the connection before proceeding." |
| `read_board` returns a stale dataset (e.g., GitHub Project sync lag) | Note the timestamp of the response if available. "Board data as of <timestamp> — if this looks stale, re-run after <30 seconds> to pick up the latest sync." |
| WIP count exceeds cap but no obvious stale claims | Flag the cap violation. Do NOT attempt to release claims or transition cards. Route to triaging-board for the investigation. |
| Producer ignores the recommendation and asks for the next one | Give the next item in the priority list and explain why it ranked lower. Still surface only ONE at a time. |
| All groups are empty (fresh project) | Show the empty-board format (see `references/daily-detail.md`). Recommend intake: "Board is clear — run `board-superpowers:intaking-requirement` to add the first card." |

## Tone and format

The briefing is for a busy Producer. Go straight to the data — no preamble
("Here is your morning briefing:"). Skip group headers with 0 items (unless
all are 0). One screen, no scroll. Sentence fragments are fine: "In Progress:
2 cards, both on track."

Single-page discipline: if the card list would require scrolling, collapse
lower-priority groups. In Progress + In Review always display in full; Ready
shows the top 3 cards with a "(+N more)" trailer; Backlog collapses to a count.
