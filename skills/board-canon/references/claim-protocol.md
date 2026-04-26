# board-canon — claim protocol reference

Conflict-resolution playbook that the parent `SKILL.md` § "Claim protocol" points at.

## Two Consumers race the same card

Scenario: Consumer A and Consumer B both decide to claim card #12 within seconds of each other.

1. **First push wins**. Whichever consumer's `git push origin claim/12-...` reaches origin first is the canonical owner. The second push is rejected non-fast-forward (different parent).
2. **Loser detection**. The losing Consumer's `claim-card.sh` exits with a non-zero status; the SKILL body in `consuming-card` (F-C2) catches this and routes to "ask architect".
3. **Loser cleanup**. The losing Consumer deletes their local worktree + branch. Status field is NOT reverted (it was set by the winner).
4. **Optional yield**. The losing Consumer can either pick a different Ready card OR negotiate with the winner to take the card themselves (the winner deletes their claim, then the loser claims).

## Stale claim recovery

Scenario: a Consumer claimed card #47 days ago, then went silent (closed the laptop, branch never pushed past the empty marker).

1. **Detection**: `managing-board` F-15 hygiene routine flags claims older than 72 hours with no commits beyond the claim marker.
2. **Surface**: Producer notifies the original Consumer via card comment.
3. **No-response policy**: after 7 days no-response, Producer can `git push origin --delete claim/47-...` to release the claim. Status field reverts to Ready in the same transaction.
4. **Audit**: 2 entries — one R-class for "propose stale-claim release", one A-class for the actual delete.

## Re-claim after release

Released claims are re-claimable normally — the same Consumer who held the original may re-claim if they want. The branch name is reused (Git accepts the new branch since the old one was deleted).

## Mode-2 (Producer-spawned Consumer) claim

In Mode-2, a Producer subagent spawns a Consumer subagent that runs `consuming-card` for a specific card. The Consumer subagent uses the same `scripts/claim-card.sh` — there's no Mode-2-specific path. The only difference: Mode-2 Consumer's `gh` CLI inherits the Producer's auth context, so claims appear to come from the same identity.

> v1-minimum constraint: Mode-2 is CC-only (subagent `max_depth=1` per ADR-0008). On Codex CLI only Mode-1 (architect-spawned) Consumer is supported.
