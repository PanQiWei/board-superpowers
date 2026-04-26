# consuming-card — handoff to superpowers reference

Procedural-fallback table for the Producer-spawned-Consumer mode.

## The constraint

When this Consumer skill runs as a subagent that the Producer's `managing-board` skill spawned (rather than as the architect's direct session), it operates under a depth-1 subagent budget on Claude Code. It CANNOT spawn `superpowers:*` or `gstack:*` skills as further subagents — only as in-process Skill invocations (which load the sibling SKILL.md content into the Consumer's own context).

This works fine when the sibling skill is **procedural** — its body is content the model reads and follows. It breaks when the sibling skill itself spawns subagents internally, because that would push the depth budget past 1.

## Sibling skill compatibility table

| Sibling skill | Procedural (spawn-Consumer-mode OK)? | Fallback if not |
|---------------|--------------------------------------|-----------------|
| `superpowers:writing-plans` | ✅ procedural | n/a |
| `superpowers:test-driven-development` | ✅ procedural | n/a |
| `superpowers:systematic-debugging` | ✅ procedural | n/a |
| `superpowers:verification-before-completion` | ✅ procedural | n/a |
| `superpowers:requesting-code-review` | ⚠️ verify before relying | If non-procedural in this version, fall back to `gstack:/review` only (skip the second-pair-of-eyes step in spawn-Consumer mode; surface the gap as a Retro Note) |
| `superpowers:subagent-driven-development` | ❌ spawns subagents | NOT usable in spawn-Consumer mode; fine in architect-spawned mode |
| `superpowers:dispatching-parallel-agents` | ❌ spawns subagents | NOT usable in spawn-Consumer mode |
| `gstack:/review` | ✅ procedural | n/a |
| `gstack:/investigate` | ✅ procedural | n/a |
| `gstack:/qa` | ✅ procedural | n/a |
| `gstack:/cso` | ✅ procedural | n/a |
| `gstack:/codex` | ⚠️ spawns Codex session | Architect-spawned mode only; in spawn-Consumer mode surface as "ask the architect to run /codex on this diff" |

## How to verify a sibling skill's mode

When you're about to invoke a sibling skill from a spawn-Consumer subagent:

1. Read the sibling SKILL.md briefly. Search for: `Agent` tool, `subagent_type`, `spawn_agents_on_csv`, `dispatching-parallel-agents`.
2. If any of these appear in the body's procedure: it's a spawning skill — incompatible with spawn-Consumer mode.
3. Use the fallback from the table above; if no fallback is documented, surface to the architect for instruction.

## Future hardening

A future iteration could encode each sibling skill's procedural-vs-spawning status in a sibling-skill compatibility manifest auto-checked by CI. For now this table is maintained by hand; updates land per discovered incompatibility.
