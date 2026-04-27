# Component architecture

> **Status:** accepted (2026-04-26).

## Purpose

This is the shortest doc in the architecture spec, on purpose. In
plugin form, "components" are not a design choice — both Claude Code
and OpenAI Codex CLI define a fixed set of slots (manifest, hooks,
skills, scripts/commands, MCP servers, subagents, settings).
Cross-slot dependency direction, lifecycle, and invocation semantics
are platform-defined. See `PLUGIN_DEVELOPMENT.md` for the full slot
inventory and contracts, and `MULTI_AGENT_DEVELOPMENT.md` for
subagent/agent-team specifics.

Two genuine design decisions remain for board-superpowers:

1. **Which slots we use** (and which we deliberately don't).
2. **How each business capability maps to a slot.**

This file pins both as tables. Anything more elaborate belongs in
`PLUGIN_DEVELOPMENT.md` (slot contracts), `0005-contracts/`
(specific schemas), or the relevant ADR.

## Decision 1 — Slot activation

| Slot | CC | Codex | Used? | Why / why not |
|------|----|-------|-------|---------------|
| Manifest | `.claude-plugin/plugin.json` | `.codex-plugin/plugin.json` | **yes** | Required by both platforms. |
| Hook — `SessionStart` | `hooks/hooks.json` | `~/.codex/hooks.json` | **yes (intent-injecting)** | Two roles: (a) Layer 1 dep-alert banner; (b) **intent-injection channel** that emits `INVOKE: <skill-name>` markers into `additionalContext` to fast-path the entry skill's routing decision (e.g., `INVOKE: bootstrapping-repo` when `manifest.yml` is absent). Best-effort by design — entry skill must keep a fallback detect path because CC delivery is unreliable. See § "Hook intent injection pattern" below. |
| Hooks — other events (`PreToolUse`, `PostToolUse`, `Stop`, …) | ✓ | ✓ (subset) | no | Nothing in the lifecycle needs them today. Wiring tool-call hooks would be invasive for downstream users; gain does not justify the surface area. |
| Skills | `skills/<name>/SKILL.md` | same | **yes** | The primary surface — every architect-facing capability lives here. |
| Scripts (bash, called from skills + hooks) | via `Bash` tool / `${CLAUDE_PLUGIN_ROOT}` | via shell exec / relative paths | **yes** | Anything needing strict exit-code semantics, filesystem atomicity, or DB-connection lifecycle. |
| Commands (`/<plugin>:<cmd>` flat files) | `commands/<name>.md` | same | no | Skills already cover all user-triggered surfaces. Adding commands would split routing across two mechanisms with overlapping descriptions. |
| MCP servers | `.mcp.json` | `mcpServers` field in plugin manifest | no | No tool-server use case yet — no per-session API key to mediate, no remote service to expose. |
| Subagents | `agents/` directory + `Agent` tool | `[agents]` config + `spawn_agents_on_csv` | **partial** | Reserved for Mode-2 (Producer-spawns-Consumer). CC-only on the fast path; Codex via natural-language spawn. See ADR-0007 §C-PLUGIN-1, `MULTI_AGENT_DEVELOPMENT.md`. |
| Settings (`settings.json`) | ✓ | n/a | no | No knobs end-users should override at install time. Repo-level config lives in `.board-superpowers/config.yml` (see 0005-contracts/03). |

## Decision 2 — Business capability → slot mapping

| Capability | Primary slot | Supporting slot | Why this slot |
|------------|--------------|-----------------|---------------|
| Detect missing dependencies | script (`check-deps.sh`) | hook (`session-start.sh`), skill preflight | Logic must be reusable in three layers; only a script gives shared exit-code semantics. |
| Inject dep-alert banner at session start | hook (`SessionStart`) | — | Only platform surface that fires before the first user prompt. Best-effort by design. |
| Route session to Manager vs Consumer | skill (`using-board-superpowers`) | — | Routing is model behavior keyed on the first user message — exactly what skill `description` matching is for. |
| First-time per-repo bootstrap | skill (`using-board-superpowers` Step 3) | script (`bootstrap-project.sh`) | UX (wait for user, ask for project coordinate) belongs in the skill; mutations to disk + GitHub + host-local state belong in the script. |
| Atomic card claim | script (`claim-card.sh`) | skill (`consuming-card`) Step 2 | Atomicity needs `git push --force-with-lease` exit codes; only a script can return them deterministically. |
| Worktree isolation per Consumer | script (`claim-card.sh`) | — | `git worktree add` mutation bundled with claim to keep the two events atomic. |
| Move a card between Status options | script (`transition-card.sh`) | both Manager and Consumer skills call it | gh CLI invocation needs structured stdin/stdout; script is the right shape. |
| Create a new card with schema | script (`create-card.sh`) | skill (`decomposing-into-milestones`) | Skill owns schema authoring (model behavior); script does the gh call. |
| Decompose requirement into cards | skill (`decomposing-into-milestones`) | references for INVEST + slicing patterns | Pure model behavior; no atomicity, no exit codes — exactly the skill sweet spot. |
| Manager daily/intake/review/retro routines | skill (`managing-board`) | one reference per routine | Model-driven workflows reading the board via `gh` and recommending action. |
| Consumer implementation lifecycle | skill (`consuming-card`) | superpowers/gstack skill chain | Delegates the actual work via skill invocation; the body is glue + protocol enforcement. |
| Shared state machine + card schema | skill (`board-protocol`) | — | Loaded into every Manager and Consumer session as common context. No execution — pure shared contract. |
| Audit-log writes (per ADR-0006) | script (TBD; wraps `psql` / `mysql`) | called from Manager and Consumer skills | RDBMS connection + transaction handling needs a script wrapper. Skills cannot hold a DB session. |
| Routing-block injection into `CLAUDE.md` / `AGENTS.md` | script (`bootstrap-project.sh`) | — | Filesystem mutation with idempotency + marker-pair check — script semantics. |
| Host-local `state.yml` read/update | helper in `scripts/lib/common.sh` | called from any script that needs it | Shared helper across scripts; not a top-level capability. Path resolution per 0005-contracts/07. |
| Mode-2 Consumer dispatch | subagent (CC `Agent` tool) / `spawn_agents_on_csv` (Codex) | Manager skill issues the dispatch | The only platform path for Producer-driven autonomous Consumer launch. See `MULTI_AGENT_DEVELOPMENT.md`. |

## Hook intent injection pattern

The hook slot in Decision 1 is marked **intent-injecting**, not
just **advisory**. This section pins what that means and why it
matters for the rest of the component architecture.

### The mechanism

`hooks/session-start.sh` runs `scripts/check-deps.sh --machine`
on every CC / Codex session start, examines the result against
host-local and per-repo state files
(`~/.board-superpowers/manifest.yml`,
`~/.board-superpowers/repos/<normalized>/state.yml`), and emits
**at most one** `INVOKE:` marker into `additionalContext`. The
marker tells the model which skill to invoke first, before the
model would normally have routed via skill-description matching.

Marker grammar (the exact string contract lives in
`0005-contracts/02-hook-contracts.md`):

```
INVOKE: <skill-name>             # one per fired condition
REASON: <one-line explanation>   # why this invocation fires
```

Example payloads:

```
INVOKE: bootstrapping-repo
REASON: First time using board-superpowers on this (host, repo)
        — manifest.yml absent.
```

```
INVOKE: migrating-repo-version
REASON: Plugin version v0.2.0 detected; state.yml records
        last_seen_version_in_repo=v0.1.0. Routing block may need
        re-injection.
```

The `MISSING_DEPS:` payload is a separate (existing) advisory
banner — orthogonal to `INVOKE:` and never emitted on the same
event firing as an `INVOKE:` marker.

### Why hook, not entry skill

Three reasons the dispatch decision lives in the hook rather than
in `using-board-superpowers/SKILL.md` body:

1. **Description budget.** Putting "Use when bootstrapping" /
   "Use when migrating" / "Use when claiming a card" / "Use when
   asking for morning briefing" all into one entry skill's
   `description` field bloats it past the
   1024-character agentskills.io ceiling and dilutes the matcher.
2. **State, not phrase.** Bootstrap and migration trigger from
   on-disk state (manifest absence, version mismatch), not from
   anything the architect typed. Description matching is the
   wrong tool for state-driven dispatch — hooks read state, the
   model reads prose.
3. **Pre-prompt visibility.** `SessionStart` fires **before** the
   architect's first message. The model can fold the marker into
   its first response without an extra round-trip. Skill-side
   detection runs **after** the first prompt and adds a "let me
   check state first" hop.

### Why the entry skill still has fallback responsibility

CC's `SessionStart` delivery is documented as unreliable
(`PLUGIN_DEVELOPMENT.md` "Hooks (`hooks/hooks.json`)" calls out
the buggy delivery; `hooks/AGENTS.md` mandates
silent-no-op-on-error). So:

- `using-board-superpowers/SKILL.md` Step 1 always re-runs
  `check-deps.sh` and re-checks state, even if a marker arrived.
- If the hook fired and injected a marker, the entry skill
  routes via the marker (fast path).
- If the hook silently dropped (CC bug, missing
  `${CLAUDE_PLUGIN_ROOT}`, network race), the entry skill
  detects the same condition itself and routes the same way
  (fallback path).

The two paths converge on the same skill invocation. The marker
is an optimization, not a correctness requirement.

### Why this generalizes

Other hook events on both platforms (`PreToolUse`, `PostToolUse`,
`Stop`) can use the same `INVOKE:`/`REASON:` payload to broadcast
intent. v1 wires only `SessionStart` (per the slot table above);
later cards can add more events without changing the marker
grammar.

The hard boundary stays the same: every `INVOKE:` is **fast-path
optimization for a behavior the receiving skill could detect on
its own.** Hooks that try to push behavior the skill cannot
otherwise reach are out of scope — that direction would re-create
a daemon by another name and violate ADR-0007 C-PLUGIN-2.

## What this file deliberately does NOT cover

- **Slot contracts** — input formats, exit-code conventions, hook
  event payloads, skill frontmatter schemas. → `PLUGIN_DEVELOPMENT.md`
  and `MULTI_AGENT_DEVELOPMENT.md`.
- **Per-script and per-skill cross-component contracts** — exact
  stdin/stdout shapes, env-var contracts, file paths, audit-log
  schema. → `0005-contracts/`.
- **Layered alert strategy step-by-step** — `AGENTS.md`
  "Architecture at a glance" already documents the three-layer
  runtime behavior; the design rationale is the first two rows of
  Decision 2 above plus the ADR references below.
- **"Why a plugin and not a CLI / daemon / GitHub App"** — answered
  in `0001-positioning.md` (P5 distribution stays minimal, P7
  mechanism not taste-defaults) and reinforced by ADR-0007
  (C-PLUGIN-2 forbids a daemon).
- **Composition with `superpowers` and `gstack`** — the routing
  block at the bottom of `AGENTS.md` is the canonical division of
  labor (gstack owns the bookends, superpowers owns the middle).
  ADR-0004 is the underlying decision.

## Decision references

- **ADR-0001** — GitHub Project as source of truth → forces "skill
  reads via `gh`, script writes via `gh`".
- **ADR-0002** — Atomic claim via remote branch push → forces
  `claim-card.sh` into the script slot (atomicity needs exit codes).
- **ADR-0003** — One worktree per Consumer → bundled into
  `claim-card.sh` for atomicity with the claim.
- **ADR-0004** — Composition over reimplementation → forces
  Consumer skill body to be glue, not implementation.
- **ADR-0006** — Producer autonomy boundary (D-AUTONOMY-1) → drives
  the audit-log slot decision (script around RDBMS, not skill).
- **ADR-0007** — Plugin runtime derived constraints (C-PLUGIN-1/-2/-3)
  → forbids in-memory IPC, daemons, unbounded concurrency. Closes
  the slot inventory against future "let's add a long-running
  service" ideas.
- **ADR-0008** — Plugin-to-plugin skill invocation → SKILL invocation
  is content loading, not subagent spawn. Justifies why cross-plugin
  orchestration lives in skill bodies (Decision 2 rows for Manager
  routines and Consumer lifecycle), not in subagent dispatch.
