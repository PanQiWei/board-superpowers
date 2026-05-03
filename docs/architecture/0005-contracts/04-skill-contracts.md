# 04 — Skill contracts

> Pin the SKILL.md frontmatter shape, the cross-plugin invocation
> contract (per ADR-0008), and the procedural-skill requirement
> that lets Mode-2 Consumer compose the sibling-skill catalog
> without violating `max_depth=1`.
>
> Rationale lives in ADR-0008 + `PLUGIN_DEVELOPMENT.md`. Shape
> lives here.

---

## SKILL.md frontmatter

Per `PLUGIN_DEVELOPMENT.md` "Skills (`SKILL.md`)" — Claude Code +
Codex CLI both load skills from `skills/<name>/SKILL.md`. The
frontmatter is YAML between two `---` lines.

### Portable subset (required for both platforms)

| Field | Type | Required? | Notes |
|-------|------|-----------|-------|
| `name` | string | yes | Kebab-case, unique within the plugin. Becomes the skill's invocation handle (`<plugin>:<skill>`) on CC; CSV-listed in Codex |
| `description` | string | yes | The model-facing description. **Description is behavior, not documentation** — Claude / Codex auto-invoke based on description matching user prompts. Treat edits with the same care as code |

### CC-only fields (using any of these makes the skill CC-only)

| Field | Type | Use |
|-------|------|-----|
| `disable-model-invocation` | bool | If `true`, the skill is user-invocable only (slash command), never auto-routed |
| `user-invocable` | bool | If `true`, exposes as a `/<plugin>:<skill>` slash command |
| `allowed-tools` | string list | Restrict tool access from inside the skill (e.g., `Bash(npm *) Edit Read`) |
| `context: fork` | string literal | Skill body runs in a fresh fork of the parent's context |
| `agent` | string | Bind the skill to a specific subagent type |
| `arguments` | array | Named args passed when the skill is invoked |
| `paths` | array (glob) | Restrict skill applicability by file paths in scope |

Using any CC-only field in the SKILL.md frontmatter makes that
skill **CC-only**; document this explicitly in the skill body if
so. board-superpowers' v1 skills use only the portable subset
(`name`, `description`) and are therefore Codex-portable.

### Codex extension — `agents/openai.yaml`

Per `PLUGIN_DEVELOPMENT.md` "Codex CLI" → "Skill frontmatter /
metadata", richer Codex-side metadata lives in an optional
`skills/<name>/agents/openai.yaml` file (display name, icon, brand
color, default prompt, etc.). board-superpowers does not ship
`openai.yaml` files at v1 — the portable subset is sufficient.

### Description discipline

Per `PLUGIN_DEVELOPMENT.md`:

- **No published character cap on Codex `SKILL.md`.** The community
  prudence of capping at 1024 chars (gstack-style) is not enforced.
  The only documented constraint is the **aggregate** budget:
  skills list is capped at "approximately 2% of the model's
  context window, or 8000 characters when the context window is
  unknown."
- **Auto-shortening** kicks in when many skills are installed —
  descriptions get clipped automatically.

board-superpowers' convention: keep `description` ≤ 1024 chars
(future-proof) and lead with the trigger phrases the architect
will actually say. The five existing skill descriptions all
follow this pattern.

---

## Cross-plugin composition contract — SKILL invocation

Per ADR-0008 (canonical) — **all cross-plugin composition uses
SKILL invocation.**

### Definition

A SKILL invocation is **in-process**: the platform's skill-matching
loads the sibling SKILL's body into the current agent's context,
where it executes as a procedural extension of the current agent's
behavior. SKILL invocation does **not** count as a subagent spawn.
This is the load-bearing property that lets a Mode-2 Consumer
(itself a CC subagent) invoke `superpowers:test-driven-development`
without overflowing the `max_depth=1` budget.

### Forbidden composition mechanisms (per ADR-0008)

| Mechanism | Status | Reason |
|-----------|--------|--------|
| Subagent spawn for sibling-plugin behavior | forbidden | Direct violation of `max_depth=1`; breaks Mode-2 |
| MCP server as sibling-plugin composition channel | forbidden at v1 | Adds IPC lifecycle the architect must operate; sibling plugins don't ship MCP servers |
| Direct `source` of sibling-plugin internals | forbidden | The plugin boundary IS the SKILL surface; sibling internals are not contract |

MCP servers ARE allowed for **external integrations** (third-party
REST APIs exposed as MCP tools); the prohibition is specifically
for board-superpowers ↔ siblings.

### Parameter passing

| Surface | Format |
|---------|--------|
| Frontmatter `arguments` field (CC-only) | Named args declared in skill frontmatter |
| Skill-body prose | Free-form natural-language parameter passing — the calling skill's prose names the inputs the sibling skill should consume |

There is **no cross-plugin RPC contract.** No JSON-typed
request/response. No callback / event channel. The composition
unit is a SKILL invocation — the only observables are whatever
the sibling skill chose to emit (PR description, card comment,
audit-log entry, retro note).

---

## Procedural-skill requirement (Mode-2 compatibility)

Per ADR-0008.

### Definition

A **procedural skill** is one whose SKILL.md body executes
in-context, without spawning subagents from inside the body. A
**spawn-orientation skill** is one whose body uses the platform's
`Agent` / `spawn_agents_on_csv` primitive.

### Rule

Sibling skills invoked from a Mode-2 Consumer (which is itself a
CC subagent) MUST be procedural. Spawn-orientation skills are
**incompatible with Mode-2** and require a procedural fallback
wired into the calling skill before they become load-bearing.

### Empirical verification gate

Per ADR-0008 Notes + ADR-0008's Status:

> The procedural-skill requirement for Mode-2 compatibility is
> empirically verified per skill, not asserted from skill
> description. Skills with names suggesting spawn-orientation
> (e.g., `superpowers:subagent-driven-development`) need
> inspection; if found to spawn subagents, the B2 fallback
> table in `consuming-card/SKILL.md` § G4 mode-topology must
> list a procedural alternative.

ADR-0008 promotes from `proposed` to `accepted` once Mode-2 ships
and the procedural-skill requirement is empirically verified across
the B2 (implement) / C1 (verify: verification-before-completion +
requesting-code-review) / C2 (cross-platform codex) / C3 (QA) /
C4 (security) chain — the 23-node Shape X encoding introduced in
Card #73.

### B2 / C1-C4 fallback rules (per `consuming-card/SKILL.md` § G4)

If `superpowers:subagent-driven-development` is found empirically
to spawn subagents, Mode-2 falls back to
`superpowers:executing-plans` (procedural). The fallback table
is wired into `consuming-card/SKILL.md` § G4 mode-topology
subsection (Mode-2 procedural fallback table).

---

## board-superpowers' own SKILL surface

Fourteen skills ship at v1 (post-#72): 1 entry + 7 molecular + 6 atomic. All use
only the portable (`name`, `description`) frontmatter subset and are Codex-portable.

| Skill | Layer | Description (one-line summary) | Composes (sibling skills it invokes) | Mode-2 safe? |
|-------|-------|--------------------------------|--------------------------------------|--------------|
| `using-board-superpowers` | Entry | Entry skill: preflight + role disambiguation + first-time bootstrap | all 4 Producer routine skills + `consuming-card` (its own siblings) | yes — procedural |
| `briefing-daily` | Molecular | Producer daily orientation — board read, WIP flagging, stale-claim detection, next-action recommendation | `board-canon`, `operating-kanban` (`read_board`), `composing-siblings`; `gstack:/office-hours`, `gstack:/plan-ceo-review`, `gstack:/plan-eng-review` (extended orientation) | yes — procedural |
| `intaking-requirement` | Molecular | Producer intake — acknowledge, shape-judge, spec-first check, route to sibling skill or create card | `board-canon`, `operating-kanban` (`create_card`), `composing-siblings`; `gstack:/office-hours`, `/plan-ceo-review`, `/plan-eng-review`; `superpowers:brainstorming`, `writing-plans` | yes — procedural |
| `reviewing-pr-queue` | Molecular | Producer review queue — validate PRs via enforcing-pr-contract, comment on violations, transition cards | `board-canon`, `operating-kanban` (`read_board`, `transition_card`), `enforcing-pr-contract`, `composing-siblings` | yes — procedural |
| `triaging-board` | Molecular | Producer triage — Blocked-card 3-class remediation, stale-claim detection and release | `board-canon`, `operating-kanban` (`read_board`, `release_claim`, `transition_card`), `composing-siblings` | yes — procedural |
| `consuming-card` | Molecular | Consumer session main skill (23-node Shape X: F1-F4 claim/implement/verify/submit + B1-B5 bootstrap + G1-G4 governance + C1-C4 sibling handoffs) | via `composing-siblings`: `superpowers:writing-plans` (B1 plan synthesis), `superpowers:subagent-driven-development` (**TBD B2**) / `test-driven-development` (B2), `verification-before-completion` + `requesting-code-review` (C1 verify); `gstack:/review` (C1), `/codex` (C2), `/qa` (C3), `/cso` (C4) | yes for the SKILL body itself; the B2 delegation depends on per-sibling verification |
| `decomposing-into-milestones` | Molecular | Producer's INVEST + slicing engine (turns design doc into cards) | `superpowers:writing-plans`; `gstack:/plan-eng-review` | yes — procedural |
| `bootstrapping-repo` | Molecular | Sole executor for setup-stages — first-time setup + plugin-upgrade reconvergence | none | yes — procedural |
| `board-canon` | Atomic | Shared contract: card schema + state machine + branching + WIP — the in-session SPOT for Kanban Protocol semantics (per [`00-kanban-protocol.md`](./00-kanban-protocol.md) + ADR-0025). | none (read-only) | yes — procedural, read-only |
| `enforcing-pr-contract` | Atomic | PR three-section shape enforcement + card body AC sync | none | yes — procedural |
| `operating-kanban` | Atomic | 8-action Kanban Protocol dispatch over the active backend projection | none in-plugin (dispatches to `gh` / MCP / REST externally) | yes — procedural |
| `classifying-actions` | Atomic | D-AUTONOMY-1 matrix + override parsing — returns A/R/N decision | none | yes — procedural |
| `auditing-actions` | Atomic | Audit log schema + two-entry rule + BYO RDBMS write | none in-plugin (invokes `audit-log-write.sh`) | yes — procedural |
| `composing-siblings` | Atomic | Sibling-plugin invocation SPOT — namespace prefix rules + Mode-2 max_depth=1 compatibility for all `gstack:*` / `superpowers:*` handoffs | none in-plugin (defines rules, does not itself invoke siblings) | yes — procedural |

### Procedural-skill commitment (own surface)

Per ADR-0008 closing decision — board-superpowers' own SKILLs are
designed to be procedural-skill-compatible: invocable from any
calling context (architect-spawned interactive Mode-1, Producer-
spawned subagent Mode-2, sibling-plugin-invocation chains)
**without spawning subagents from inside the SKILL body**. If a
future board-superpowers SKILL needs to spawn subagents, document
that as a Mode-2 incompatibility and ship a procedural fallback in
the same PR.

---

## Sibling-skill classification (current empirical state)

Per ADR-0008 — these are the sibling skills board-superpowers
currently composes. Classification is "procedural" (safe under
Mode-2) or "TBD" (needs empirical verification). Update this
table as verification lands; the B2 fallback rule depends on
it. Node references use the 23-node Shape X encoding introduced
in Card #73 (consuming-card refactor): B2 = implement delegation,
C1 = verify chain, C2 = cross-platform review, C3 = QA pass,
C4 = security audit.

### `superpowers:*`

| Skill | Classification | Composed by |
|-------|----------------|-------------|
| `superpowers:brainstorming` | procedural (assumed) | `intaking-requirement` Intake |
| `superpowers:writing-plans` | procedural (assumed) | `intaking-requirement`, `decomposing-into-milestones`, `consuming-card` (B1 plan synthesis via `composing-siblings`) |
| `superpowers:test-driven-development` | procedural | `consuming-card` (B2 TDD-driven implementation via `composing-siblings`) |
| `superpowers:executing-plans` | procedural (assumed) | `consuming-card` B2 fallback when `subagent-driven-development` is found to spawn |
| `superpowers:subagent-driven-development` | **TBD** — empirical verification required | `consuming-card` B2 default via `composing-siblings` |
| `superpowers:dispatching-parallel-agents` | **TBD** — name-suggests-spawn | `briefing-daily` (extended dispatch); potentially `consuming-card` |
| `superpowers:systematic-debugging` | procedural (assumed) | `consuming-card` debug path (B2) |
| `superpowers:verification-before-completion` | procedural | `consuming-card` C1 (pre-PR verification chain) via `composing-siblings` |
| `superpowers:requesting-code-review` | procedural | `consuming-card` C1 (pre-PR verification chain) via `composing-siblings` |

### `gstack:/*`

| Skill | Classification | Composed by |
|-------|----------------|-------------|
| `gstack:/office-hours` | procedural (assumed) | `intaking-requirement` Intake |
| `gstack:/plan-ceo-review` | procedural (assumed) | `intaking-requirement` Intake; `briefing-daily` extended orientation |
| `gstack:/plan-eng-review` | procedural (assumed) | `intaking-requirement` Intake; `decomposing-into-milestones` arch validation |
| `gstack:/investigate` | procedural (assumed) | `consuming-card` debug path (B2) |
| `gstack:/review` | procedural (assumed) | `consuming-card` C1 (pre-PR verification chain) via `composing-siblings` |
| `gstack:/codex` | procedural (assumed) | `consuming-card` C2 (cross-platform adversarial review) via `composing-siblings` |
| `gstack:/qa` | procedural (assumed) | `consuming-card` C3 (conditional QA) via `composing-siblings` |
| `gstack:/cso` | procedural (assumed) | `consuming-card` C4 (conditional security audit) via `composing-siblings` |
| `gstack:/browse` | procedural (assumed) | invoked through `gstack:/qa` |

"Assumed" entries default to procedural based on inspection of the
skill's body (no `Agent` tool calls). Mark them "verified" only
after explicit Mode-2 + skill-invocation testing.

### Update protocol

When a sibling skill's classification changes (e.g., empirical
verification reveals subagent spawning):

1. Update the table above.
2. If the skill is composed by Mode-2 Consumer (anywhere in the
   B2 / C1 / C2 / C3 / C4 chain), add a procedural fallback
   to the calling skill in the same PR.
3. If no fallback exists, file a bug: the Mode-2 path is broken
   for that composition.

---

## Skills directory layout

| Path | Purpose |
|------|---------|
| `skills/<name>/SKILL.md` | Required. The skill body Claude Code / Codex matches on. Frontmatter + markdown body. |
| `skills/<name>/references/<topic>.md` | Optional. Lazy-loaded reference content. SKILL.md links to references via standard markdown links; the platform follows links on demand. |
| `skills/<name>/agents/openai.yaml` | Optional. Codex display metadata; not used by board-superpowers at v1. |

Filenames are stable — the Claude Code runtime enumerates them.
Renaming a SKILL or its references file is a contract break;
update the change-impact matrix entry.

---

## Cross-references

- [`05-github-artifact-schemas.md`](./05-github-artifact-schemas.md) —
  the artifacts SKILLs read/write (Card body, PR body, ClaimMarker)
  are the observable surface of every SKILL composition.
- [`08-environment-variables.md`](./08-environment-variables.md) —
  `CLAUDE_PLUGIN_ROOT` is the only reliable way for SKILL bodies
  to reference plugin-internal scripts.
- ADR-0008 (the canonical SKILL-invocation decision).
- ADR-0007 C-PLUGIN-1 (no in-memory IPC; SKILL invocation
  respects it because both sides run in the same process).
- `consuming-card/SKILL.md` § G4 + B2 (the load-bearing Consumer
  composition with the fallback rule — 23-node Shape X encoding).
- `consuming-card/SKILL.md` § F3 C1-C4 (the verification chain).
- `MULTI_AGENT_DEVELOPMENT.md` — `max_depth=1` invariant.
- `PLUGIN_DEVELOPMENT.md` — upstream SKILL contract surfaces (CC +
  Codex).
