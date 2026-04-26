# consuming-card — surface protocol reference

How the Consumer surfaces information back to the architect during a card's lifecycle.

## Three surface channels

1. **Card comments** — durable, visible in the board UI; use for status updates that future readers need (blocker named, decision rationale, post-mortem note).
2. **PR body / PR comments** — visible during review; use for verification evidence and reviewer guidance.
3. **Conversation with the architect** (the active session) — ephemeral; use for R-class action proposals and acks.

## When to surface

| Event | Channel | Format |
|-------|---------|--------|
| Card claimed | (no surface — claim signal is the branch push) | n/a |
| Hit blocker mid-flight | Card comment + R-class proposal in conversation | Comment: "Blocked on <X> — <one-line>". In conversation: "Card #N hit blocker <X>. Propose Status: In Progress → Blocked. ack?" |
| Discovered scope creep | Card comment + R-class proposal in conversation | Comment: "Out-of-scope detected: <Y>. Recommending split." In conversation: discuss split. |
| About to take destructive action | R-class proposal in conversation only | "Propose: delete `claim/47-...` branch — original Consumer notified 8 days ago, no response. ack?" |
| Verification step failed | Conversation + (after fix) PR body Retro Note | "Verification failed: `<command>` returned `<err>`. Investigating." |
| PR ready for review | (auto via PR open) | n/a |
| Architect requested change mid-implementation | Card comment recording change + carry on | Comment: "Architect requested: <change>. Adjusting acceptance criteria interpretation." |

## Avoiding surface noise

A Consumer's value is partly being able to work silently between surface events. Resist the urge to status-update for the sake of it. The architect should hear from you when:

- An R-class action needs ack
- A blocker needs surfacing
- A merge-ready PR is open
- The card is in a state the architect should know about that they couldn't infer from the board

A "good morning, working on card #12" message is noise; the board already shows the claim.

## Cross-session continuity

If a Consumer's session pauses (compaction, end-of-day), the durable record is on the card and in the worktree. The next session resumes by:

1. Reading the card body + comments
2. `cd $HOME/.config/superpowers/worktrees/<repo>/claim/<N>-<slug>`
3. `git status` + `git log --oneline main..HEAD`
4. Picking up where things left off

Don't try to "save context" via long card comments; the comments should record decisions, not narrate history.
