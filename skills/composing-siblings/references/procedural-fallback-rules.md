# Procedural fallback rules — Mode-2 max_depth=1 decision tree

This file documents the procedural-vs-subagent decision tree for sibling-plugin
invocations from a Mode-2 Consumer context. It applies the platform constraints
to the concrete sibling-skill catalog without re-deriving the underlying logic.

## Core constraints (inline summary)

Two platform constraints govern this decision:

**Constraint A — SKILL invocation is content-loading, not a subagent spawn.**
The platform's skill matcher loads a sibling SKILL.md body into the calling
agent's context as procedural guidance. There is no second context window, no
`Agent` tool call, no depth increment. The max_depth budget applies only to
`Agent` tool calls (CC) and `spawn_agents_on_csv` (Codex); SKILL invocation
simply does not enter that category. A Mode-2 Consumer can invoke any number of
sibling SKILLs without consuming additional depth.

**Constraint B — Subagents cannot spawn subagents.**
A Mode-2 Consumer runs as a CC subagent. It cannot itself spawn further
subagents. What CAN compound depth is whatever the *body* of an invoked SKILL
instructs the agent to do: if a sibling SKILL.md body tells the agent "spawn an
Agent subagent to do X", that instruction causes a depth increment. The
requirement is therefore: every sibling skill invoked from Mode-2 MUST have a
body that does not instruct a subagent spawn.

## The decision tree

When a Mode-2 Consumer is about to invoke a sibling skill, apply in order:

```
1. Is this a SKILL invocation (via the Skill tool)?
   YES → SKILL invocation does not consume max_depth. Proceed to step 2.
   NO  → If you are about to spawn an Agent subagent, STOP — max_depth=1
         budget is exhausted. Use a procedural fallback instead.

2. Does the sibling skill's SKILL.md body contain an Agent tool call
   or spawn_agents_on_csv instruction?
   NO  → Skill is procedural. Safe to invoke from Mode-2. Proceed.
   YES → Skill is non-procedural. Use the fallback for this skill (see table below).
   TBD → Treat as non-procedural until verified. Use the fallback.
```

## Per-skill status and fallback table

| Sibling skill | Procedural? | Fallback if not procedural |
|---------------|-------------|---------------------------|
| `superpowers:brainstorming` | yes | n/a |
| `superpowers:writing-plans` | yes | n/a |
| `superpowers:test-driven-development` | yes | n/a |
| `superpowers:subagent-driven-development` | procedural-verified (2026-04-26; re-verify on each superpowers release) | Use `superpowers:executing-plans` as procedural substitute; note substitution in PR description |
| `superpowers:systematic-debugging` | yes | n/a |
| `superpowers:verification-before-completion` | yes | n/a |
| `superpowers:requesting-code-review` | yes | n/a |
| `gstack:/office-hours` | yes | n/a |
| `gstack:/plan-ceo-review` | yes | n/a |
| `gstack:/plan-eng-review` | yes | n/a |
| `gstack:/review` | yes | n/a |
| `gstack:/qa` | yes | n/a |
| `gstack:/cso` | yes | n/a |
| `gstack:/investigate` | yes | n/a |

## When the fallback fires

If a skill's body is found to have become non-procedural (e.g., a superpowers
release introduces subagent spawning in `subagent-driven-development`):

1. Mark it TBD or "no" in the table above.
2. Use the listed fallback skill instead.
3. Note the substitution in the PR description and in the card body
   (card body sync per `consuming-card` Step 9.5).
4. Open a follow-up card (or comment on the consuming-card thread) to track
   the upstream skill returning to procedural — when it does, revert the fallback.

The fallback table for `consuming-card`'s handoff-to-superpowers also lives in
`skills/consuming-card/references/handoff-to-superpowers.md`. Keep both files in
sync when a status changes (same-PR change-impact obligation).

## Re-verification procedure

1. Read the sibling skill's SKILL.md body.
2. Search for `Agent` tool calls or `spawn_agents_on_csv` references.
3. If found: skill is non-procedural — update the table.
4. If not found: skill is procedural — update the table and the verification date.
5. Record the verification date in `sibling-plugin-table.md`
   § "Verification status" (see SKILL.md § "How to apply this skill"
   for the full reference file index).
