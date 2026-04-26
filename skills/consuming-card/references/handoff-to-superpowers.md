# consuming-card — handoff to superpowers reference

Procedural-fallback table for Mode-2 compatibility per ADR-0008.

## The constraint

Under Mode-2, `consuming-card` runs as a CC subagent with `max_depth=1`. It CANNOT spawn `superpowers:*` skills as subagents — only as in-process Skill invocations (which load the sibling SKILL.md content into the Consumer's own context).

This works fine when the sibling skill is **procedural** (its body is content the model reads + follows). It breaks when the sibling skill itself spawns subagents internally (because that would be a depth-2 spawn).

## Sibling skill compatibility table (v1-minimum)

| Sibling skill | Procedural (Mode-2 OK)? | Fallback if not |
|---------------|-------------------------|-----------------|
| `superpowers:writing-plans` | ✅ procedural | n/a |
| `superpowers:test-driven-development` | ✅ procedural | n/a |
| `superpowers:systematic-debugging` | ✅ procedural | n/a |
| `superpowers:verification-before-completion` | ✅ procedural | n/a |
| `superpowers:requesting-code-review` | ⚠️ TBD — verify before relying | If non-procedural, fall back to `gstack:/review` only (skip the second-pair-of-eyes step in Mode-2; surface as Retro Note) |
| `superpowers:subagent-driven-development` | ❌ spawns subagents | NOT usable in Mode-2; in Mode-1 fine |
| `superpowers:dispatching-parallel-agents` | ❌ spawns subagents | NOT usable in Mode-2 |
| `gstack:/review` | ✅ procedural | n/a |
| `gstack:/investigate` | ✅ procedural | n/a |
| `gstack:/qa` | ✅ procedural | n/a |
| `gstack:/cso` | ✅ procedural | n/a |
| `gstack:/codex` | ⚠️ spawns Codex session | Mode-1 only; in Mode-2 surface as "request the architect to run /codex on this diff" |

## How to verify a sibling skill's mode

When you're about to invoke a sibling skill from a Mode-2 Consumer subagent:

1. Read the sibling SKILL.md briefly. Search for: `Agent` tool, `subagent_type`, `spawn_agents_on_csv`, `dispatching-parallel-agents`.
2. If any of these appear in the body's procedure: it's a spawning skill — incompatible with Mode-2.
3. Use the fallback from the table above; if no fallback is documented, surface to the architect for instruction.

## Future hardening

In v1-complete, each sibling skill's procedural-vs-spawning status will be encoded in a sibling-skill compatibility manifest auto-checked by CI. v1-minimum maintains this table by hand; updates land per discovered incompatibility.
