# briefing-daily — daily routine reference

Corner cases and formatting details for the daily routine. The SKILL.md body
describes the main flow; this file documents the edge cases and alternate formats.

## Empty board

If `read_board` returns zero items in every status group, output:

```
## Board state — <date>

The board is empty. Run intake when you have a new requirement
(`/board-superpowers:intaking-requirement`).
```

Do not pad with "(0)" lines per status — terse is better when there is
nothing to report.

## Single-Consumer projects

When there is only one Consumer (Producer and Consumer are the same person),
the WIP-cap logic still applies but the visualization simplifies:

```
### In Progress (1)
- #12 Implement briefing-daily SKILL — you, claimed 2h ago
```

Drop the "by <consumer>" suffix when there is only one Consumer.

## Stale-claim age computation

A claim branch is "stale" when:
- The branch exists on origin.
- Branch is older than 72 hours (first commit timestamp).
- Commit count beyond the initial empty claim marker = 0 (the worktree
  creation typically adds one commit; ignore it).

Compute via:
```bash
# Count commits on the claim branch not on main:
git log origin/claim/<N>-<slug> --not main --oneline | wc -l
# If result is 0 or 1, the branch is stale (1 = empty claim-marker commit).
```

For age, use the first commit's timestamp:
```bash
git log origin/claim/<N>-<slug> --not main --format="%cr" | tail -1
```

## Context-switch reload

When the Producer returns to a specific card or Thread after a gap, the
briefing output narrows:

```
## Context reload — #<N> <title>

**Status**: <status>
**Last commit**: <short-sha> — <message> (<age>)
**Last PR comment** (if any): <summary>

**Recommended next action**: <one sentence>
```

This truncated format fires when the user message references a specific card
number alongside context-reload language.

## Hot-cards formatting

Cards "in flight" (In Progress + In Review) deserve more visual weight than
Backlog. Display ordering:

1. In Progress (most relevant — active work)
2. In Review (needs Producer attention)
3. Blocked (needs unblocking)
4. Ready (queued but not started)
5. Backlog (collapsed to count when > 5 items)

Collapse Backlog to a single line: "Backlog: 12 cards."

## WIP count reference

Per `board-superpowers:board-canon` § "WIP counting formula":
- Counted: In Progress + suspended + In Review cards per Consumer.
- NOT counted: Blocked cards (they are stalled, not consuming WIP budget).
- Typical cap: 2 per Consumer (project-configurable via `config.yml`).

Flag when a Consumer is at or above their WIP cap.

## Tone

The briefing is for a busy Producer reading before coffee. Skip filler
("Here is your morning briefing:"). Go straight to the data. Prefer
sentence fragments in group summaries. One screen, no scroll target.
