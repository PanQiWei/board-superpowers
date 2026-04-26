# consuming-card — permission boundary reference

Architect-spawned vs Producer-spawned Consumer invocation contracts.

## Architect-spawned Consumer (the default mode)

Architect (in their primary session) invokes:

```
/board-superpowers:consuming-card 12
```

OR types `[board-card:#12]` and lets `using-board-superpowers` route.

The Consumer runs in the same session as the architect — full conversation history, full tool budget, can spawn subagents normally (Claude Code subagent depth budget = 1, meaning the Consumer can spawn one level of further subagents).

Both Claude Code and Codex CLI support architect-spawned Consumer.

## Producer-spawned Consumer subagent

The Producer-side `managing-board` skill (running on Claude Code) spawns a Consumer subagent for a card via:

```
Agent({ subagent_type: "general-purpose", prompt: "follow consuming-card SKILL.md for card #12" })
```

The subagent runs with isolated context (no architect conversation history) and depth budget 1 — so it CANNOT itself spawn further subagents.

Producer-spawned Consumer is **Claude Code only**. Codex CLI's spawn model is not yet symmetric.

## What changes between modes

| Aspect | Architect-spawned | Producer-spawned |
|--------|-------------------|-------------------|
| Conversation history | Full (architect's session) | Empty (subagent isolation) |
| Sub-skill invocation | Normal Skill tool | Same — but the sub-skill itself must be procedural (per `references/handoff-to-superpowers.md`) |
| Spawning further subagents | Allowed (depth 1 still available) | NOT allowed (already at depth 1; depth 2 is rejected) |
| Architect ack for mutating actions | Architect responds in conversation | The Producer subagent that spawned this Consumer must mediate — but Producer can't see Consumer's conversation. Workaround: Consumer surfaces proposal via `report_agent_job_result` with structured proposal payload; Producer's outer skill evaluates and responds. |
| Audit-log identity | `actor: <user>@<session>` | `actor: <user>@<producer-session>:consumer-subagent-<id>` |

## Mutating-action handling in spawn-Consumer mode (the hard part)

A Producer-spawned Consumer cannot pause and ask the architect — there's no architect in the loop. Mutating actions still need acknowledgement. Resolution:

1. Consumer subagent prepares the proposal as structured JSON.
2. Consumer subagent calls `report_agent_job_result` with the proposal.
3. Producer subagent receives the result, evaluates against override rules in `.board-superpowers/config.yml`, and either:
   - Acknowledges autonomously (if override allows)
   - Surfaces to the architect (Producer's own session has the architect in the loop)
4. Architect's acknowledgement flows back: Producer re-spawns the Consumer subagent (new isolated context) with "act on the previously-proposed action".

This 4-step dance is expensive — spawn-Consumer mode has higher latency for mutating actions than architect-spawned mode. Mitigation: cards selected for spawn-Consumer dispatch should be ones whose actions are mostly auto-act-OK (low ratio of architect-prompts).

## When to use which mode

- **Architect-spawned**: any time the architect is sitting at the keyboard. This is the normal mode. Lower latency, higher acknowledgement bandwidth, full conversation history available.
- **Producer-spawned**: overnight batches, parallel fanout across multiple Ready cards, or when the architect explicitly wants hands-off dispatch. Requires that mutating-action overrides are well-configured to keep the dance loop short.
