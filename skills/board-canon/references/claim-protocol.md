# board-canon — claim protocol reference

Conflict-resolution playbook that the parent `SKILL.md` § "Claim protocol" points at.

## Two Consumers race the same card

Scenario: Consumer A and Consumer B both decide to claim card #12 within seconds of each other.

1. **First push wins**. Whichever Consumer's `git push origin claim/12-...` reaches origin first is the canonical owner. The second push is rejected non-fast-forward (different parent commit).
2. **Loser detection**. The losing Consumer's `claim-card.sh` exits with a non-zero status; the body of the `consuming-card` skill catches this in its claim step and routes to "ask architect".
3. **Loser cleanup**. The losing Consumer deletes their local worktree + branch. Status field is NOT reverted (it was set by the winner).
4. **Optional yield**. The losing Consumer can either pick a different Ready card OR negotiate with the winner to take the card themselves (the winner deletes their claim, then the loser claims).

## Stale claim recovery

Scenario: a Consumer claimed card #47 days ago, then went silent (closed the laptop, branch never pushed past the empty marker).

1. **Detection**: the `managing-board` triage routine flags claims older than 72 hours with no commits beyond the claim marker.
2. **Surface**: Producer notifies the original Consumer via card comment.
3. **No-response policy**: after 7 days no-response, Producer can `git push origin --delete claim/47-...` to release the claim. Status field reverts to Ready in the same transaction.
4. **Audit**: 2 entries — one for the proposal, one for the actual delete.

## Re-claim after release

Released claims are re-claimable normally — the same Consumer who held the original may re-claim if they want. The branch name is reused (Git accepts the new branch since the old one was deleted).

## Producer-spawned Consumer claim

When the Producer's `managing-board` skill spawns a Consumer subagent that runs `consuming-card` for a specific card, the Consumer subagent uses the same `scripts/claim-card.sh` — there's no separate path. The only difference: the spawned Consumer's `gh` CLI inherits the Producer's auth context, so claims appear to come from the same identity.

This Producer-spawned-Consumer mode is currently Claude Code only (Claude Code subagents have a depth-1 budget that constrains nested orchestration). On Codex CLI only architect-spawned Consumer is supported.
