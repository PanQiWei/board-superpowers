# Architecture overview

The architectural picture behind the entry skill body's "10 skills, by layer" and "5 bounded contexts" tables. Read this when you need to understand *why* board-superpowers carves the work the way it does — not just what each skill is named.

## When to read this file

Route by question to a specific section instead of reading end-to-end:

| Question | Section to read |
|----------|-----------------|
| What kind of layer is this plugin? Why scheduling-only and not coding-discipline? | [§ "What kind of layer is board-superpowers"](#what-kind-of-layer-is-board-superpowers) |
| What skill goes where? Which layer does the new skill belong in? | [§ "Three layers, strictly downward"](#three-layers-strictly-downward) |
| What's the layer's stability profile? How does the body-length budget map to the layer? | [§ "Three layers, strictly downward"](#three-layers-strictly-downward) (final table) |
| Why are there exactly five atomic skills? What SPOTs do they consolidate? | [§ "Why exactly five atomic skills (the SPOT census)"](#why-exactly-five-atomic-skills-the-spot-census) |
| How does an atomic-contract change propagate through the molecular consumers? | [§ "How a contract update propagates"](#how-a-contract-update-propagates) |
| What are the five bounded contexts and which skill operates on which? | [§ "The 5 bounded contexts"](#the-5-bounded-contexts) |
| When a Consumer is spawned by the Producer rather than the architect, what changes? | [§ "Mode-1 vs Mode-2 Consumer spawn"](#mode-1-vs-mode-2-consumer-spawn) |
| How do `superpowers:*` and `gstack:/*` compose with this plugin? | [§ "Composition with sibling plugins"](#composition-with-sibling-plugins) |
| Why is there no plugin-side state server? | [§ "No plugin-side state server"](#no-plugin-side-state-server) |
| Why is the architecture shaped this way for an AI-driven board? | [§ "Why this shape for an AI-driven board"](#why-this-shape-for-an-ai-driven-board) |
| Quick check during an active session — is the work in the right context / layer / plugin? | [§ "How to use this picture in an active session"](#how-to-use-this-picture-in-an-active-session) |

## What kind of layer is board-superpowers

board-superpowers is a **scheduling layer**. Its job is to know what work is in flight, who's holding it, and what state each piece is in. It does NOT itself implement the engineering disciplines that produce the work — those live in two sibling plugins (`superpowers` for the coding-discipline loop, `gstack` for the bookends of direction-setting and delivery-side verification). Composition with those siblings is a permanent design decision, not an interim shortcut. Reimplementing TDD, debugging, code review, QA, or security audit inside board-superpowers would defeat the whole point of having a focused scheduling layer.

This split is what lets board-superpowers stay small. Roughly: planning, slicing, claiming, status-tracking, audit, PR contract — that's the surface board-superpowers owns. Everything else is delegated.

## Three layers, strictly downward

```
                    ┌──────────────────────────────┐
                    │          Entry layer         │   1 skill
                    │   using-board-superpowers    │
                    └──────────────┬───────────────┘
                                   │ routes to
                    ┌──────────────▼───────────────┐
                    │       Molecular layer        │   4 skills
                    │  managing-board ·            │
                    │  consuming-card ·            │
                    │  decomposing-into-milestones │
                    │  bootstrapping-repo          │
                    └──────────────┬───────────────┘
                                   │ reads from
                    ┌──────────────▼───────────────┐
                    │         Atomic layer         │   5 skills
                    │  board-canon ·               │
                    │  enforcing-pr-contract ·     │
                    │  operating-kanban ·          │
                    │  classifying-actions ·       │
                    │  auditing-actions            │
                    └──────────────────────────────┘
```

Two rules give the picture its shape:

1. **Dependency is strictly downward.** Entry routes to molecular, molecular reads from atomic, never the other way. An atomic skill calling another same-plugin skill (especially upward) creates cycles, defeats the SPOT property, and makes load order non-deterministic. Atomic skills are reflexes, not orchestrators.
2. **Each layer has a different stability and size profile.** Entry changes when routing scenarios appear (rare). Molecular changes when a workflow's contract shifts (medium frequency). Atomic changes when a contract that other skills depend on changes (rare, and every change ripples through every consumer).

The layer also implies a body-length budget — Entry is loaded every session (every line counts against the shared context budget), so it's the smallest; molecular skills are loaded only when triggered, so they have more headroom; atomic skills are loaded on demand from molecular bodies, so they sit between the two.

| Layer | Loaded | Stability | Body budget | Reflex? |
|-------|--------|-----------|-------------|---------|
| Entry | Every session | Low (rare changes) | Tight — manual-page double duty may push slightly above when full routing context must be disclosed up front | No (router) |
| Molecular | When workflow triggers | Medium | Roomy enough for state-machine-shaped procedures with examples | No (orchestrator) |
| Atomic | On demand from molecular | High (rarely changes once stable) | Mid-sized; frequently re-loaded so kept lean | Yes (no upward calls) |

## Mode-1 vs Mode-2 Consumer spawn

Consumers can come from two places, and the difference matters for what they're allowed to do:

- **Mode-1 — Architect-spawned Consumer.** The human (or a long-running Producer session driven by the architect) starts a Consumer in its own session. This Consumer can spawn its own subagents — for example, dispatching a `superpowers:subagent-driven-development` task to parallelize independent work inside one Card.
- **Mode-2 — Producer-spawned Consumer.** The Producer itself spawns a Consumer as a subagent for an overnight or batch run. This Consumer cannot spawn further subagents; the platform's depth-1 budget is already consumed by the Producer-spawning-Consumer call. Cross-plugin invocations from this Consumer must therefore be procedural — read the sibling skill body, follow the procedure inline — rather than dispatching the sibling as a subagent.

The two modes share the same `consuming-card` skill body; the body branches on detected mode where it matters. Mode-2 is currently Claude Code only.

## Why exactly five atomic skills (the SPOT census)

Atomic skills are not a free-form convenience layer. Each one consolidates a contract that *multiple* molecular skills would otherwise inline-copy. The census that yields five:

| Contract | Inlined by, without atomic | SPOT consolidator |
|----------|----------------------------|-------------------|
| State machine + Card body schema + branch naming + WIP rules (backend-agnostic — *what is legal*) | All 4 molecular skills | `board-canon` |
| PR three-section shape + filler detection + Card AC sync | `consuming-card` (write side) + `managing-board` (validate side) | `enforcing-pr-contract` |
| 8-action protocol dispatch over the active backend projection (Form A bash CLI / Form B MCP / Form C REST) + projection-routing logic + bootstrap-side setup-capability registry (backend-aware — *how to act on this repo's backend*) | All 4 board-touching molecular skills | `operating-kanban` |
| 14-row autonomy matrix + 5-step triage + override parsing | All 4 mutating molecular skills | `classifying-actions` |
| Audit log schema + propose-resolve sequencing + degradation rules | All 4 mutating molecular skills | `auditing-actions` |

The `board-canon` / `operating-kanban` pair sit on the same domain (Kanban) but consolidate distinct SPOTs: if the question is *what is legal / what does X mean*, route to `board-canon`; if the question is *how do I do X on this repo's backend*, route to `operating-kanban`. Mixing them into one atomic would couple a stable backend-agnostic ontology to a mutable backend-specific dispatch layer and force every projection landing to re-review the ontology.

A contract that only one molecular skill needs stays inline. The atomic-layer count is governed by the SPOT threshold, not by aesthetic preference.

### How a contract update propagates

When an atomic skill's contract changes (say, a new Card-body section is added to `board-canon`), the change must cascade through every molecular skill that consumes it. The cascade is deliberately manual — there is no "schema migration" tool that rewrites molecular bodies — so the atomic-layer change PR is required to update the molecular consumers in the same merge. This keeps the cascade short and observable: a stale consumer is caught at review time, not silently shipped.

The reverse direction is forbidden by construction. A molecular skill cannot extend an atomic contract by itself; it must lobby the atomic skill to add the surface. This is what "atomic skills MUST NOT call same-plugin skills" actually buys — a one-way information flow with no upward calls means an atomic skill's behavior is fully self-contained, and consumers cannot retroactively redefine it.

## The 5 bounded contexts

The domain divides into five bounded contexts. Each context has its own vocabulary and its own aggregates; a skill operates over one or more, but the contexts themselves do not bleed into each other.

| Context | Aggregates | Backing store | Skills |
|---------|------------|---------------|--------|
| **Board** | Card + PR | GitHub Project + Issues + git refs | `managing-board` (read), `consuming-card` (read + write own card), `decomposing-into-milestones` (write new cards), `bootstrapping-repo` (read Status field), `board-canon` (schema authority) |
| **Session** | ProducerSession + ConsumerLogical | OS processes + worktrees | `managing-board` (lifecycle read), `consuming-card` (own session) |
| **Bootstrap** | HostBootstrap + RepoBootstrap + RepoConfig | `~/.board-superpowers/manifest.yml`, per-repo `config.yml`, host-local `state.yml` | `bootstrapping-repo` (read + write — sole executor for setup-stages including version-transition migrations per ADR-0012), `using-board-superpowers` (read for state probes) |
| **Audit** | AuditTrail | BYO RDBMS, jsonl on degradation | `auditing-actions` (write via `audit-log-write.sh`) |
| **Spec** | SpecPointer (thin) | Card body's first line | `consuming-card` (read at claim time) |

The bounded contexts answer two practical questions for any new skill: *which aggregates does this skill mutate?* (drives the layer + autonomy decisions) and *what files / external systems does this skill touch?* (drives the dep-check requirements and the audit payload schema).

### Information flow across contexts

The contexts are not independent islands — they exchange information through fixed channels:

- **Spec → Board.** A Card body's first line is a thin SpecPointer to the authoritative architecture doc (when one exists). The pointer is read at claim time so the Consumer knows where the canonical detail lives. The Card body itself stays small; the Spec doc carries the depth.
- **Board → Session.** When a Consumer claims a Card, the claim transaction creates a Session aggregate (worktree + branch + Status flip). Closing the loop, the Session emits status signals back to the Board (PR opened → In Review; PR merged → Done via webhook).
- **Board / Session → Audit.** Every mutating action in either context lands one or two rows in the Audit context. The Audit log is the only context the others write to but never read — it's a one-way trail.
- **Bootstrap → all others.** Bootstrap state (host manifest, per-repo config) seeds everything else. The entry skill's reliable gate reads from Bootstrap on every session start to decide whether to route to bootstrap, migrate, or proceed.

The information flow direction matters for testing: a change to the Bootstrap context potentially affects all other skills, so its tests cover the seeding fan-out. A change to the Audit context is leaf-level — nothing reads from it during normal operation, so its tests focus on write durability and the degradation fallback.

## Composition with sibling plugins

board-superpowers is a runtime dependency of `superpowers` and `gstack`. The composition is structural — pick the right sibling skill for the right phase of work, do not re-invoke board-superpowers for things outside its job:

**Bookends (gstack)** — direction-setting before a Card is claimed and delivery-side verification once a Card's PR is up:

- Pre-claim direction: `gstack:/office-hours`, `/plan-ceo-review`, `/plan-eng-review`, `/plan-design-review`.
- Post-implement verification: `gstack:/review`, `/qa`, `/cso`, `/codex`.
- Project-specific release flow: `/ship`, `/canary`, `/land-and-deploy`. Enable only when these match the consuming repo's deployment shape; board-superpowers does not prescribe a release process.

**Middle (superpowers)** — the coding-discipline loop a Consumer runs while implementing a Card:

`brainstorming` → `writing-plans` → `test-driven-development` → `systematic-debugging` (when stuck) → `verification-before-completion` → `requesting-code-review`.

TDD inside this loop is mandatory; an adjacent planning skill saying "ready, start coding" does NOT excuse skipping Red → Green → Refactor unless the architect explicitly says so in the current conversation.

**Conflict arbitration** follows `superpowers:using-superpowers` precedence: **user instructions > skill > default behavior**. When two sibling skills give conflicting advice, the architect's explicit instruction in the current conversation wins; absent that, the more specific skill's advice wins; absent that, the default behavior wins.

## No plugin-side state server

board-superpowers ships zero server-side state. The plugin runs entirely as hooks + scripts + skills inside the host's agent process. Truth lives on the user's GitHub Project (Cards, Status field, branches, PRs); per-host state lives in `~/.board-superpowers/`; per-repo state lives in `<repo>/.board-superpowers/`; the audit trail lives in a BYO RDBMS (Postgres / MySQL / SQLite) that the user provisions. Nothing about board-superpowers requires a network service the plugin maintainer operates.

This decision has practical consequences:

- **No outage propagation.** When the plugin maintainer is offline, the user's board still works. Hooks fire locally, scripts run locally, GitHub is the only external party in the hot path.
- **Truth lives where the user controls it.** The audit log is in the user's database. The Card data is in the user's GitHub. The host state is on the user's disk. The plugin can be uninstalled without losing anything beyond the dispatch layer.
- **Multi-host coordination is the user's choice.** Two users on different hosts working on the same repo coordinate through GitHub. The plugin doesn't introduce a new sync contract on top.

## Why this shape for an AI-driven board

Two design pressures push the architecture into the shape above:

1. **AI cadence is much faster than human-team cadence.** Human Kanban tools were built around daily standups, weekly planning, two-week sprints. An AI Producer can shape ten Cards in an hour and a parallel fleet of Consumers can drain them overnight. The architecture has to compress: routing has to be instant (Entry layer), workflow skills have to be small enough to load on demand (molecular layer), and contracts that ten skills depend on have to live in exactly one place (atomic layer).
2. **Multi-Consumer parallelism requires per-Card isolation.** When ten Consumers run simultaneously, they cannot share a `HEAD` or compete for a single working tree. The one-Card-one-worktree rule isn't a style preference — it's a physical constraint. Producer-spawned Consumer batches (Mode-2) only work because the underlying isolation is real.

Everything else — atomic-layer SPOT discipline, propose-resolve audit sequencing, hook-injected `INVOKE:` markers, the strict downward dependency direction — falls out of these two pressures plus the contract that cross-plugin work goes through `superpowers:*` and `gstack:/*` rather than being reimplemented inside board-superpowers.

## How to use this picture in an active session

When you're routing a session or making a design decision, this architecture serves as a quick check rather than a tome to re-read end-to-end:

- *Is this work in the right context?* — pin it to one of the 5 bounded contexts; if it spans more than two, it probably needs to be split.
- *Is this work in the right layer?* — Entry routes, molecular orchestrates a workflow, atomic carries one contract. A skill that wants to do all three is mis-layered.
- *Does this work belong here at all?* — if the user is asking for TDD, debugging, QA, security, or release engineering, the right answer is to delegate to `superpowers:*` or `gstack:/*` rather than absorb it.

The architecture is intentionally simple so the answer to each of these is fast.

## Recap

board-superpowers is a small, focused scheduling layer: 1 entry skill, 4 molecular workflows, 5 atomic SPOTs, all reading and writing across 5 bounded contexts whose only shared backing stores are GitHub, the host filesystem, and a user-supplied database. Engineering disciplines come from `superpowers` and `gstack`. The architecture's job is to keep the dispatch layer small enough to load on demand, the contracts authoritative enough to compose, and the parallel-Consumer model isolated enough to scale. When in doubt about whether something belongs in this plugin, ask: *is it scheduling, or is it doing the work?* Scheduling stays here; the rest is delegated.
