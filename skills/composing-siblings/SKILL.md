---
name: composing-siblings
description: |
  Use whenever a board-superpowers molecular SKILL is about to invoke a sibling
  plugin SKILL from `gstack:*` or `superpowers:*` namespaces. Callers: all four
  Producer routines (`briefing-daily`, `intaking-requirement`, `reviewing-pr-queue`,
  `triaging-board`), `consuming-card`, and `decomposing-into-milestones`. Apply at
  every cross-plugin handoff point — this skill is the single source of truth for
  namespace prefix rules and Mode-2 max_depth=1 compatibility decisions. Do NOT use
  for: (a) board-superpowers internal SKILL calls (governed by `SKILLS.md`
  topology); (b) user-facing direct invocations of sibling skills (route directly
  per `using-board-superpowers/references/routing.md`).
when_to_use: |
  Use at every sibling-plugin handoff inside the four Producer routine SKILLs
  (briefing-daily, intaking-requirement, reviewing-pr-queue, triaging-board),
  consuming-card, and decomposing-into-milestones. Trigger points: Producer intake
  B1 routing (direction / architecture / plan sibling selection); Consumer lifecycle
  C1 (brainstorming/planning handoff), C2 (implementation delegation), C3 (pre-PR
  verification chain), C4 (conditional QA/security passes). Use when deciding
  whether a sibling skill is safe to invoke from a Mode-2 Consumer context.
user-invocable: false
---

# composing-siblings

This skill is the single source of truth for invoking sibling-plugin skills
(`gstack:*` / `superpowers:*`) from any board-superpowers context. It does
not perform actions itself; it provides the invocation contract that callers
follow before routing to a sibling.

## How to apply this skill

| What you need | Where to look |
|---------------|---------------|
| Which sibling skill to invoke at a specific handoff | `references/handoff-points.md` (9 caller × scenario table) |
| Current `gstack:*` / `superpowers:*` skill names and descriptions | `references/sibling-plugin-table.md` |
| Whether a sibling skill is safe to invoke from Mode-2 Consumer | `references/procedural-fallback-rules.md` |
| Namespace prefix rules + atomic reflex constraint | `references/boundary.md` |

## Invocation rules

**Rule 1 — SKILL invocation, not subagent spawn.**
All cross-plugin composition uses SKILL invocation. The platform's skill matcher
loads the sibling SKILL.md body into the calling agent's context as procedural
guidance — no second context window, no `Agent` tool call. This is content-
loading, not a spawn. The `max_depth` budget applies only to `Agent` tool calls;
SKILL invocation does not consume depth.

**Rule 2 — Always carry the namespace prefix.**
Every sibling-plugin reference uses `<plugin>:<skill>` form:
- `superpowers:test-driven-development` (correct)
- `gstack:/review` (correct — gstack uses `/` prefix by convention)
- `test-driven-development` (wrong — bare reference fails cross-plugin resolution)

**Rule 3 — Procedural check before Mode-2 invocation.**
A Mode-2 Consumer runs as a CC subagent (`max_depth=1`). SKILL invocation itself
does not consume depth, but any spawn-instruction inside the invoked skill's body
would. Before invoking any sibling from a Mode-2 context, verify it is procedural
(its body does not instruct an `Agent` / `spawn_agents_on_csv` call). Consult
`references/procedural-fallback-rules.md` for the current status of each sibling.

**Rule 4 — Phase-based routing.**
Route by phase, not by preference:
- **Bookend phases** (direction-setting before a card is claimed; delivery-side
  QA / review / security) → `gstack:/*` skills.
- **Middle phase** (implementation loop: brainstorming → writing-plans → TDD →
  debugging → verification → code-review) → `superpowers:*` skills.
- Conflict arbitration: user instructions > skill > default behavior. A gstack
  skill's "start coding" output does not override `superpowers:test-driven-development`
  discipline unless the user explicitly says so in the current conversation.

## Handoff points quick reference

All current callers in the v0.7.0 Producer/Consumer surfaces use this skill. See
`references/handoff-points.md` for the full table. High-frequency summary:

| Caller | Phase label | Primary sibling(s) |
|--------|-------------|-------------------|
| `intaking-requirement` (intake) | B1 — direction question | `gstack:/office-hours`, `gstack:/plan-ceo-review` |
| `intaking-requirement` (intake) | B1 — architecture question | `gstack:/plan-eng-review` |
| `intaking-requirement` (intake) | B1 — plan synthesis | `superpowers:brainstorming`, `superpowers:writing-plans` |
| `consuming-card` | C1 — planning | `superpowers:writing-plans` |
| `consuming-card` | C2 — implementation | `superpowers:subagent-driven-development`, `superpowers:test-driven-development` |
| `consuming-card` | C3 — pre-PR verification | `superpowers:verification-before-completion`, `superpowers:requesting-code-review`, `gstack:/review` |
| `consuming-card` | C4 — conditional QA/security | `gstack:/qa` (UI cards), `gstack:/cso` (security-flagged) |
| `decomposing-into-milestones` | plan synthesis | `superpowers:writing-plans` |
| `decomposing-into-milestones` | arch validation | `gstack:/plan-eng-review` |

## What this skill does NOT cover

- **Which sibling skill wins** when two could apply — that's the caller's
  routing logic using the phase-based rule above.
- **Whether to use a sibling at all** — that's the calling skill's decision
  based on the card's Execution Hints and the architect's signal.
- **Autonomy classification** of sibling-skill invocations — that's
  `board-superpowers:classifying-actions`.
- **Audit rows for sibling-skill handoffs** — that's
  `board-superpowers:auditing-actions`.
- **Same-plugin (board-superpowers internal) skill references** — those follow
  the `SKILLS.md` call-graph topology, not this skill.
