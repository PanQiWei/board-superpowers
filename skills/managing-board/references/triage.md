# managing-board — triage routine reference

Procedure detail for F-15 partial (v1-minimum subset).

## Blocked card investigation

For each card in `Blocked`:

1. Read the card body. Find the blocker comment (per `board-canon` § state machine, Blocked entries name their blocker in a card comment).
2. Determine blocker class:
   - **External-dependency** (waiting on another team / service / vendor): keep blocked; surface to Producer for status check.
   - **Decision-pending** (architect needs to decide): surface to architect for decision.
   - **Stale-block** (blocker resolved long ago but card never moved): unblock — transition Blocked → In Progress (R-class action).

## Stale-claim release

For each `claim/N-...` branch:

1. Compute age of last commit.
2. If > 72h with no progress: flag.
3. If > 7 days with no progress AND original Consumer notified previously: recommend release.

Release procedure (R-class, must ask architect):

```bash
git push origin --delete claim/<N>-<slug>
# Then revert the card's Status: In Progress → Ready
```

Both actions in the same audit-log entry transaction (action_id 102 — Blocked → In Progress, OR action_id 401 — release-claim).

## Suspended card review

Cards labeled `suspended` (Consumer parked them mid-work) get reviewed weekly:

- If suspension reason is still valid: leave alone.
- If suspension reason resolved: ask Consumer to either resume or release.
- If suspended > 30 days: recommend release regardless — the work has gone cold, restart from a fresh card.

## Triage NOT included in v1-minimum

The full F-15 hygiene routine includes:

- Backlog grooming (rotating items between Backlog and Ready)
- Cross-card dependency cycle detection
- Estimate calibration (S/M/L drift)
- Velocity tracking

These are deferred to v1-complete. v1-minimum triage is just "Blocked + stale-claim sweep".
