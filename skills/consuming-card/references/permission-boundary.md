# consuming-card — permission boundary reference

Mode-1 vs Mode-2 invocation contract per ADR-0008.

## Mode-1: architect-spawned Consumer

Architect (in their primary session) invokes:

```
/board-superpowers:consuming-card 12
```

OR types `[board-card:#12]` and lets `using-board-superpowers` route.

The Consumer runs in the same session as the architect — full conversation history, full tool budget, can spawn subagents normally (Agent depth budget = `max_depth=1`).

Both CC and Codex support Mode-1.

## Mode-2: Producer-spawned Consumer subagent

Producer-side `managing-board` (running on CC) spawns a Consumer subagent for a card via:

```
Agent({ subagent_type: "general-purpose", prompt: "follow consuming-card SKILL.md for card #12" })
```

The subagent runs with isolated context (no architect conversation history) and `max_depth=1` (cannot itself spawn subagents).

Mode-2 is **CC-only at v1-minimum**. Codex CLI's spawn model is not yet symmetric.

## What changes between modes

| Aspect | Mode-1 | Mode-2 |
|--------|--------|--------|
| Conversation history | Full (architect's session) | Empty (subagent isolation) |
| Sub-skill invocation | Normal `Skill` tool | Same — but the sub-skill itself must be procedural (per `references/handoff-to-superpowers.md`) |
| Spawning further subagents | Allowed (depth 1) | NOT allowed (already depth 1; max_depth=1 means depth 2 is rejected) |
| R-class action ack | Architect responds in conversation | The Producer subagent that spawned this Consumer subagent must ack — but Producer can't see Consumer's conversation. Workaround: Consumer surfaces R-class via `report_agent_job_result` tool with structured proposal payload; Producer's outer SKILL evaluates and responds. |
| Audit log identity | `actor: <user>@<session>` | `actor: <user>@<producer-session>:consumer-subagent-<id>` |

## R-class action handling in Mode-2 (the hard part)

A Mode-2 Consumer cannot pause and ask the architect — there's no architect in the loop. R-class actions require ack. Resolution:

1. Consumer subagent prepares the R-class proposal as structured JSON.
2. Consumer subagent calls `report_agent_job_result` with the proposal.
3. Producer subagent receives the result, evaluates against override rules in `.board-superpowers/config.yml`, and either:
   - Acks autonomously (if override allows)
   - Surfaces to the architect (Producer's own session has the architect in the loop)
4. Architect's ack flows back: Producer re-spawns the Consumer subagent (new isolated context) with "act on the previously-proposed action".

This 4-step dance is expensive — Mode-2 has higher latency for R-class actions than Mode-1. Mitigation: cards selected for Mode-2 dispatch should be ones whose actions are mostly A-class (low ratio of architect-prompts).

## v1-minimum simplification

In v1-minimum (where `classifying-actions` is deferred and ALL actions are R-class by default), Mode-2 is much less useful — every action requires the dance above. Recommendation: Mode-2 stays available but unused for v1-minimum. Land Mode-2 dogfood after `classifying-actions` ships in v1-complete.
