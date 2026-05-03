# triaging-board — triage routine reference

Detail for the triage routine. Parent SKILL.md describes the main flow; this
file documents the blocker classification criteria, stale-claim release
mechanics, suspended-card review, and what this routine deliberately excludes.

## Blocked card investigation

For each card in `Blocked`:

1. Read the card body. Find the blocker comment (per the board's state machine,
   Blocked entries name their blocker in a card comment or the card body Notes
   section under a line like "Blocked: waiting on X").

2. Determine blocker class:
   - **External-dependency**: waiting on another team / service / vendor.
     Indicators: "waiting for team X", "waiting for service Y to ship",
     "blocked on external PR #N". Action: surface to Producer for status
     check or escalation.
   - **Decision-pending**: architect needs to decide something. Indicators:
     "need arch decision on", "blocked pending direction from", "A/B
     unresolved". Action: surface to Producer for an explicit decision. If
     the decision maps to a fresh requirement, route to
     `board-superpowers:intaking-requirement`.
   - **Stale-block**: the blocker resolved long ago but the card was never
     moved. Indicators: the blocker note mentions a dependency that has
     since shipped, a decision that was made in a PR thread, or a date > 7
     days ago with no update. Action: propose Blocked → In Progress.

Stale-block evidence criteria:
- The dependency mentioned in the blocker comment has a merged PR or a "done"
  status in its own thread.
- The decision mentioned has been recorded in an ADR or card comment.
- The last update to the card was > 7 days ago and the Consumer has not
  commented since.

Any ONE of these is sufficient to classify as stale-block and propose unblock.

## Stale-claim release

For each `claim/N-...` branch:

1. Compute age of last commit.
2. If > 72h with no progress beyond the initial claim marker: flag.
3. If > 7 days with no progress AND the original Consumer was previously
   notified: recommend release.

Release procedure (mutating — propose to Producer first):

```bash
# Delete the claim branch from origin:
git push origin --delete claim/<N>-<slug>
# Then transition the card: In Progress → Ready
# (via operating-kanban transition_card action)
```

Both actions (branch delete + Status flip) are separate mutating events and
each gets its own audit entry.

## Suspended card review

Cards labeled `suspended` (Consumer parked them mid-work) get reviewed:

- If suspension reason is still valid: leave alone.
- If suspension reason resolved: ask Consumer to either resume or release.
- If suspended > 30 days: recommend release regardless — the work has gone
  cold; restart from a fresh card.

## What this triage routine does NOT cover

A fuller hygiene routine would also handle:

- Backlog grooming (rotating items between Backlog and Ready based on
  priority or estimate calibration).
- Cross-card dependency cycle detection.
- Estimate calibration (S/M/L drift over time).
- Velocity tracking or throughput metrics.

These are out of scope for this routine. The triage routine focuses narrowly
on Blocked + stale-claim sweep. Velocity and hygiene features are deferred
to v1.x pending demand pull.
