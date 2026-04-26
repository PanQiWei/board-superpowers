# ADR 0008: Plugin-to-plugin composition via SKILL invocation

**Status:** accepted
**Date:** 2026-04-26
**Deciders:** PanQiWei (maintainer)

## Context

board-superpowers composes its sibling plugins (`superpowers`
and `gstack`) extensively: the entire Consumer pre-submit
chain (F-C9 / F-C10 / F-C11) is delegated to other plugins'
behavior; the Producer Intake routine routes design work to
external skills (F-08 area). ADR-0004 established
composition-over-reimplementation as the philosophy — this
ADR specifies the **mechanism** by which composition
happens.

CC and Codex offer several composition mechanisms in
principle:

1. **SKILL invocation** — the current agent (Consumer or
   Producer) invokes another plugin's SKILL via the standard
   skill-matching mechanism. Execution stays in-process; the
   skill's body runs as a procedural extension of the current
   agent's behavior.
2. **Subagent spawn** — the current agent spawns a child
   process (CC `Agent` tool / Codex `spawn_agents_on_csv`)
   to run the other plugin's behavior in an isolated
   context.
3. **MCP server call** — the current agent calls an MCP tool
   exposed by the other plugin's MCP server, via cross-process
   IPC.
4. **Direct module / function reference** — the current
   plugin's scripts directly source / import / call code
   from another plugin's internals.

These mechanisms differ on cost, boundary respect, portability,
and Mode compatibility. board-superpowers needs **one canonical
mechanism** so the composition pattern is predictable across the
codebase and downstream plugin migrations don't break composition.

The Mode-2 path (Producer-spawned subagent Consumer) makes the
choice especially load-bearing: any mechanism whose execution
counts as a fresh subagent spawn would compound onto the existing
subagent depth and collide with the `max_depth=1` invariant from
`MULTI_AGENT_DEVELOPMENT.md`. This rules out mechanism #2 outright
for Mode-2 and shapes the analysis of #3 / #4 below.

## Decision

**All cross-plugin composition uses SKILL invocation.**

The current agent (whether Producer or Consumer, Mode-1 or
Mode-2) invokes another plugin's behavior by referencing the
sibling plugin's SKILL — `superpowers:test-driven-development`,
`gstack:/codex`, `gstack:/qa`, etc. The platform's skill
matching loads the sibling SKILL's body into the current
agent's context, where it executes as a procedural extension.

**SKILL invocation is a content-loading mechanism, not a
subagent spawn.** This is a category clarification, not an
empirical claim: the platform's skill matcher loads the sibling
SKILL.md's body into the calling agent's context as procedural
guidance — there is no second context window, no second
process, no `Agent` tool call. The `max_depth` budget applies to
subagent-spawning operations (CC `Agent` tool, Codex
`spawn_agents_on_csv` and friends); SKILL invocation is simply
not in that category and the budget does not apply. A Mode-2
Consumer (which is itself a CC subagent) can invoke
`superpowers:test-driven-development` freely because the
sibling skill's body executes inside the existing subagent's
context, not in a newly-spawned one.

**Procedural-skill requirement.** What CAN compound onto
`max_depth` is whatever the *body* of the loaded SKILL instructs
the agent to do. If a sibling SKILL.md tells the agent "spawn a
subagent to do X", THAT instruction does cause an `Agent` tool
call which counts toward `max_depth`. So the requirement is:
**every sibling skill invoked from a Mode-2 Consumer MUST have a
SKILL.md body that does not instruct the agent to spawn
subagents.** Phrased differently: the SKILL body is procedural
(executes as guidance to the calling agent), not orchestrational
(spawns its own children).

Empirical verification (audit of 2026-04-26): the sibling
skills currently composed —
`superpowers:test-driven-development`,
`superpowers:subagent-driven-development`,
`superpowers:verification-before-completion`,
`superpowers:requesting-code-review`, `gstack:/codex`,
`gstack:/qa`, `gstack:/review` — all have SKILL.md bodies that
do not contain spawn-subagent instructions. The
procedural-skill requirement is satisfied by the current
sibling-skill catalog. F-C4 in
`0002-product-features-and-flows/04-consumer-surface.md`
documents the fallback path if a future sibling-skill update
introduces spawn instructions.

The decision applies symmetrically: when board-superpowers
exposes its own SKILLs (`consuming-card`, `managing-board`,
`board-protocol`, etc.), they are designed to be procedural too
— invocable from any calling context without their bodies
instructing subagent spawns.

## Consequences

**What this enables:**

- **Mode-2 Consumer can use the full procedural sibling-skill
  catalog** (TDD chain, verification chain, cross-platform
  adversarial review). The composition pattern works
  identically in Mode-1.
- **Plugin boundaries stay clean.** No internal-module
  imports across plugins; no shared library; no version-
  coupling tax.
- **No installation ceremony for IPC.** No MCP server to
  start, no socket to allocate, no cross-process auth to
  configure. Sibling-plugin install + dependency check
  (F-B1 / 1.5.0 dep check) is sufficient.
- **Skill discovery is platform-native.** CC and Codex both
  match SKILLs by `description` frontmatter; sibling
  plugins are discovered by the platform, not by
  board-superpowers' own discovery layer.
- **Independent versioning of sibling plugins works.** A
  superpowers upgrade is not a board-superpowers concern as
  long as SKILL frontmatter and behavior contracts hold.

**What this constrains:**

- **Sibling skills must remain procedural for Mode-2
  compatibility.** If superpowers / gstack ship a future
  skill whose body spawns subagents, Mode-2 cannot use that
  skill — the fallback path must be wired before that
  skill becomes load-bearing for Consumer's pre-submit
  chain.
- **No cross-plugin RPC contract.** The composition unit is
  a SKILL invocation, not a typed function call. Parameter
  passing happens via SKILL frontmatter `arguments` + the
  skill body's prose; no JSON-typed request/response.
- **board-superpowers cannot directly probe sibling-plugin
  internal state.** Whatever the sibling skill chose to
  emit (PR description, card comment, audit-log entry,
  retro note) is the only observable. There is no hook into
  "what is superpowers thinking right now."

**What this forbids:**

- **Spawning subagents to run sibling-plugin behavior.**
  Direct violation of `max_depth=1`; breaks Mode-2.
- **MCP servers as the cross-plugin composition channel.**
  Out of scope for v1. (MCP servers are still allowed for
  *external integrations* — e.g., a third-party REST API
  exposed as MCP tools — but board-superpowers ↔ siblings
  is not that case.)
- **Direct sourcing of sibling-plugin internals.** No
  `source ~/.claude/plugins/superpowers/internal.sh` or
  equivalent. The plugin boundary is the SKILL surface.

## Alternatives considered

- **Subagent spawn for sibling-plugin composition.** Rejected
  on `max_depth=1` grounds — Mode-2 Consumer is already a
  subagent; spawning a sibling-skill subagent underneath it
  overflows the depth budget. Even setting Mode-2 aside,
  subagent spawn introduces context-fork cost (the platform
  allocates a fresh context window) for what should be a
  simple "run this prose" operation.
- **MCP server as composition channel.** Rejected on three
  independent grounds: (a) introduces an IPC layer with
  lifecycle (start / stop / restart / port allocation /
  auth) that the architect must operate, violating P5
  (distribution stays minimal); (b) provides no marginal
  capability over SKILL invocation since both ultimately
  pass prose between contexts; (c) sibling plugins
  (superpowers, gstack) don't ship MCP servers, so we would
  have to either fork them or wrap them — both fragile.
- **Direct module / script-source import.** Rejected — the
  plugin boundary IS the SKILL surface (per
  `PLUGIN_DEVELOPMENT.md`); reaching into sibling-plugin
  internals couples our scripts to the sibling's internal
  layout, which is not part of the sibling's contract and
  changes between releases.
- **Custom RPC over GitHub artifacts.** Rejected — the
  Customer-Supplier-through-GitHub data flow is already the
  pattern for cross-context communication
  (`0003-domain-model/06-context-map.md`); proposing a new
  application-level RPC layer on top of it adds protocol
  complexity with no marginal capability.

## Notes

- The **procedural-skill requirement** is verified by reading
  each sibling SKILL.md body for spawn-subagent instructions;
  skill descriptions alone are not sufficient. Skills whose
  names suggest spawn-orientation (e.g.,
  `superpowers:subagent-driven-development`) were inspected
  during the 2026-04-26 audit and found to be procedural
  (the body instructs the agent on how to drive a subagent
  workflow, but does not itself issue an `Agent` tool call —
  the spawn happens at the architect's invocation level).
  If a future sibling-plugin release introduces a SKILL.md
  whose body does spawn subagents, the F-C4 fallback table in
  `0002-product-features-and-flows/04-consumer-surface.md`
  governs the substitution.
- This ADR governs **board-superpowers ↔ sibling plugins**
  (superpowers, gstack). It does NOT govern
  board-superpowers ↔ the GitHub Project v2 substrate —
  that integration is owned by the BoardAdapter contract
  (ADR-0005), which is a different boundary.
- **Promotion to `accepted` (2026-04-26):** earlier draft
  treated "SKILL invocation does not increment `max_depth`"
  as an empirical claim awaiting CC primary-docs citation.
  That framing was a category error: SKILL invocation is a
  content-loading mechanism that simply does not enter the
  subagent-spawn budget at all. Once that clarification was
  made, the only remaining empirical question — whether the
  sibling SKILL bodies contain spawn-subagent instructions —
  was answered by direct inspection of the seven currently
  composed skills above. ADR therefore promotes from
  `proposed` to `accepted` without waiting for Mode-2 ship.

## Related

- ADR-0004 — Composition over reimplementation (this ADR
  specifies HOW)
- ADR-0007 — Plugin-runtime-derived constraints (C-PLUGIN-1
  no in-memory IPC; the SKILL-invocation channel respects
  it because both sides run in the same process)
- ADR-0005 — v1 BoardAdapter contract (orthogonal — that's
  the substrate-side contract, not the sibling-plugin
  composition channel)
- [`0002-product-features-and-flows/04-consumer-surface.md`](../0002-product-features-and-flows/04-consumer-surface.md)
  F-C4 (TDD delegation), F-C9 / F-C10 / F-C11 (verification
  chain), with explicit procedural-fallback rule for Mode-2
- [`0002-product-features-and-flows/05-bootstrap-surface.md`](../0002-product-features-and-flows/05-bootstrap-surface.md)
  F-B2 (sibling-plugin dep check at bootstrap is the
  precondition for skill invocation later)
- [`0003-domain-model/02-bounded-contexts.md`](../0003-domain-model/02-bounded-contexts.md)
  — Session context's interaction with external skills
- `MULTI_AGENT_DEVELOPMENT.md` — `max_depth=1` invariant
  (the load-bearing constraint)
- `PLUGIN_DEVELOPMENT.md` — SKILL contract surface (CC and
  Codex SKILL formats; what platform skill discovery does)
