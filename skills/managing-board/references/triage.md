# managing-board — triage routine reference

Procedure detail for the triage routine.

## Blocked card investigation

For each card in `Blocked`:

1. Read the card body. Find the blocker comment (per `board-superpowers:board-canon` § state machine, Blocked entries name their blocker in a card comment).
2. Determine blocker class:
   - **External-dependency** (waiting on another team / service / vendor): keep blocked; surface to Producer for status check.
   - **Decision-pending** (architect needs to decide): surface to architect for decision.
   - **Stale-block** (blocker resolved long ago but card never moved): unblock — propose transition Blocked → In Progress and wait for acknowledgement.

## Stale-claim release

For each `claim/N-...` branch:

1. Compute age of last commit.
2. If > 72h with no progress: flag.
3. If > 7 days with no progress AND original Consumer notified previously: recommend release.

Release procedure (mutating, must propose to architect first):

```bash
git push origin --delete claim/<N>-<slug>
# Then revert the card's Status: In Progress → Ready
```

Both actions in the same audit-log entry transaction.

## Suspended card review

Cards labeled `suspended` (Consumer parked them mid-work) get reviewed weekly:

- If suspension reason is still valid: leave alone.
- If suspension reason resolved: ask Consumer to either resume or release.
- If suspended > 30 days: recommend release regardless — the work has gone cold, restart from a fresh card.

## What this triage routine does NOT cover

A fuller hygiene routine would also handle:

- Backlog grooming (rotating items between Backlog and Ready)
- Cross-card dependency cycle detection
- Estimate calibration (S/M/L drift)
- Velocity tracking

These are out of scope for this routine. The triage routine focuses on Blocked + stale-claim sweep.
