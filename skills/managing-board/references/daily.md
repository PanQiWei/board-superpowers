# managing-board — daily routine reference

Procedure detail for the daily routine. Parent `SKILL.md` § "Daily routine" describes the user-visible flow; this file documents the corner cases.

## Empty board

If `read-board.sh` returns zero items in every column, output:

```
## Board state — <date>

The board is empty. Run intake (`/board-superpowers:managing-board intake`) when you have a new requirement.
```

Don't pad the briefing with "(0)" lines per status — terse is better when there's nothing to report.

## Single-Consumer projects

When there's only one Consumer (the Producer-Consumer is the same person), the WIP-cap logic still applies but the visualization simplifies:

```
### In Progress (1)
- #12 Implement board-canon SKILL.md — you, claimed 2h ago
```

Drop the "by <consumer>" suffix when there's only one Consumer.

## Stale-claim age computation

A claim is "stale" if:

- Branch exists on origin
- Branch is older than 72 hours (per first commit timestamp)
- Branch has no commits beyond the initial empty claim marker (the worktree creation typically adds one commit; ignore it)

Compute via:

```bash
git log claim/N-slug --not main --oneline | wc -l
```

If 0 (or 1 in the worktree-creation case), it's stale.

## Hot-cards highlighting

Cards "in flight" deserve more attention than Backlog. Format the briefing so In Progress + In Review come first; collapse Backlog to a count when there are > 5 items.

## Tone

The briefing is for a busy Producer. Skip filler ("Here is your morning briefing:") — go straight to the data. The Producer is reading on their phone before coffee.
