---
name: operating-kanban
description: Use when an agent needs to perform any of the eight Kanban Protocol actions on the active backend — read_board, read_card, create_card, transition_card, claim_card, release_claim, link_pr_to_card, comment_on_card (OPTIONAL). Routes through the active projection's reference file (Form A bash CLI / Form B plugin-shipped MCP server / Form C REST/GraphQL) per the kanban entry recorded in this repo's settings. Also owns the bootstrap-side setup-capability registry that bootstrap stage predicates consume. Use even when the molecular skill body just says "read the board" or "transition card N to In Review" — that is a protocol action and dispatch goes through this skill. Do NOT use this skill for backend-agnostic schema questions ("what states does a card have", "what is the canonical Card body shape", "how is WIP counted") — that is the board-canon skill.
when_to_use: Use whenever a board-touching skill body invokes a Kanban Protocol action against the live backend, OR a bootstrap stage predicate evaluator needs to know whether the active projection declares a given setup capability.
user-invocable: false
---

# operating-kanban

This skill is the dispatch authority for "how to act on the active backend" — the runtime-and-bootstrap counterpart to `board-superpowers:board-canon`'s "what is legal." It does not perform actions itself; it routes the eight Kanban Protocol actions and the per-projection setup capabilities through the projection reference file selected by this repo's kanban configuration.

## Reflexive constraint

This skill is atomic. It MUST NOT call any other same-plugin skill. It is a leaf in the skill graph: molecular skills (`managing-board`, `consuming-card`, `decomposing-into-milestones`, `bootstrapping-repo`) call this skill; this skill does not call upward. Externally it invokes the active projection (a bash command, an MCP tool, or an HTTP endpoint), but it never reaches back into the plugin's other skills. Calling another same-plugin skill from here would form a cycle through the molecular layer that consumes this skill, defeating the single-source-of-truth purpose.

## The eight protocol actions

Every board-touching molecular skill issues at most these eight named actions. The semantic contracts (intent / pre-condition / post-condition / failure modes / idempotency) are pinned in [`docs/architecture/0005-contracts/00-kanban-protocol.md`](../../docs/architecture/0005-contracts/00-kanban-protocol.md) § "Action contracts"; this skill dispatches them per the active projection.

| Action | Intent (one line) | Compliance level |
|--------|-------------------|------------------|
| `read_board` | Snapshot all cards on the board with their canonical statuses. | L0 |
| `read_card` | Fetch one card's complete body, labels, status, url, timestamps. | L0 |
| `create_card` | Land a new card in `Backlog`. | L1 |
| `transition_card` | Move a card from one canonical status to another. | L1 |
| `claim_card` | Acquire exclusive Consumer ownership of a card. | L2 |
| `release_claim` | Release Consumer ownership; delete the claim branch. | L2 |
| `link_pr_to_card` | Establish bidirectional discoverability between a Card and a PR. | L2 |
| `comment_on_card` (OPTIONAL) | Append a textual exchange entry on a card. | L1 |

Per-action invocation patterns (how each action maps to a concrete bash / MCP / REST call on each backend) live in `references/action-dispatch.md` and the per-projection reference files in this same `references/` directory.

## Backend selection algorithm

When a caller hands in a protocol action plus the repo root, this skill resolves the active projection by reading this repo's kanban configuration. The procedure:

1. Read `<repo>/.board-superpowers/settings.yml` and walk to the kanban registry block (`modules.m10_kanban`).
2. From the registry, pick the active kanban entry. Single-kanban repos have exactly one entry; multi-kanban repos disambiguate via the `<kanban-id>` segment of the caller's claim branch or via an explicit qualifier passed by the caller.
3. Read the `projection` field of that kanban entry (e.g., `github-project-v2`) — the projection identifier names the per-projection reference file in this skill's `references/` directory.
4. Load `references/<projection-id>.md`. The reference file documents the projection's invocation form (Form A / B / C) and the per-action invocation patterns.
5. Dispatch the requested action per the loaded reference.

Failure modes — and the corresponding caller-visible behavior — are tabulated in `references/backend-selection.md` (kanban registry missing or malformed; projection identifier unknown to this skill; setup not yet completed).

## Three invocation forms

The Kanban Protocol is transport-agnostic. Each projection chooses one form for its invocation surface; this skill dispatches uniformly across all three.

| Form | What it looks like | When backends choose it |
|------|--------------------|--------------------------|
| **Form A — bash CLI** | The reference file documents `gh project ...` / `linear ...` / equivalent shell invocations; this skill runs them through the plugin's `scripts/` helpers. | Backends with a stable, scriptable CLI and no MCP server. The v0.5.0 GitHub Project v2 projection is Form A. |
| **Form B — plugin-shipped MCP server** | The plugin's `.mcp.json` registers the backend's MCP server; the reference file names the MCP tools and their input shapes; this skill calls the MCP tools through the platform's MCP runtime. | Backends with an official MCP server (Linear, Atlassian Remote MCP for Jira). Roadmap for v1.x. |
| **Form C — REST / GraphQL** | The reference file documents the HTTP endpoint shape, auth header derivation, and response parsing; this skill issues the HTTP calls directly. | Backends with no MCP server and where CLI is insufficient. No instances at v0.5.0; the form is recognized so future authors don't feel forced to ship Form B. |

Per-form dispatch conventions (stdout / stderr / exit-code expectations for Form A; tool-call patterns for Form B; auth + response parsing for Form C) live in `references/form-a-bash.md`, `references/form-b-mcp.md`, and `references/form-c-rest.md`.

## Setup capabilities — the bootstrap-side dispatch

Every projection also declares a list of **setup capabilities** — one-time board-preparation operations the projection can perform during the architect's bootstrap flow (creating the canonical label set, validating the backend's status taxonomy, and similar). The semantic contract for setup capabilities lives in [`docs/architecture/0005-contracts/00-kanban-protocol.md`](../../docs/architecture/0005-contracts/00-kanban-protocol.md) § "Setup capabilities"; this skill owns the registry side.

How the registry is consumed:

1. A bootstrap stage declares `applicable_when: {kanban_projection_capability: <capability-name>}`.
2. The bootstrap stage predicate evaluator asks this skill whether the active projection declares `<capability-name>`.
3. This skill reads the active projection's reference file under `references/<projection-id>.md` § "Setup capabilities" and returns true / false based on whether the named capability is in the declared list.
4. Match → bootstrap stage runs, invoking the capability through the same Form-aware dispatch as runtime actions. Miss → bootstrap stage returns `not-applicable` and the bootstrap flow continues.

The v0.5.0 GitHub Project v2 projection declares two capabilities (`ensure-labels`, `validate-status-field`); future Linear / Jira projections add their own. The capability vocabulary is registry-internal — no external surface depends on it, so renames are cheap until a second projection ships.

## Failure-mode taxonomy

| Symptom | Caller-visible behavior |
|---------|-------------------------|
| `<repo>/.board-superpowers/settings.yml` missing or has no kanban registry block. | Surface "kanban not yet configured on this repo; route to the bootstrapping flow"; do NOT invent a projection. |
| Active projection identifier names a projection not present in this skill's `references/`. | Surface "unknown projection <id>; check plugin version or projection registry"; do NOT silently fall back to a different projection. |
| Bootstrap stage predicate asks for a capability the active projection does not declare. | Return `not-applicable` (this is normal flow per the bootstrap predicate contract); the stage executor skips. |
| Form A invocation fails (non-zero exit, malformed JSON on stdout). | Surface the exit code and the captured stderr to the caller verbatim; the caller decides whether to retry, escalate, or surface to the architect. |
| Form B / Form C invocation fails (transport error, auth rejection, 5xx response). | Surface a typed failure to the caller (transport / auth / server / unknown); do not retry transparently — retry policy is the caller's. |
| Active projection's compliance level is below what the requested action requires (e.g., the projection advertises L0 but the caller asked for `claim_card` which needs L2). | Refuse before invoking the projection; surface the compliance gap. |

Detailed failure surfacing rules and the architect-visibility tiers (silent / log-only / audit-row / surface-immediately) live in `references/failure-mode-dispatch.md`.

## Composition

| Direction | Who calls this skill, and from where | Who this skill calls |
|-----------|--------------------------------------|----------------------|
| Inbound | `managing-board` (Producer routines that read the board, transition cards, create new cards on intake), `consuming-card` (Consumer's claim, transition, link-PR steps), `decomposing-into-milestones` (creates new cards on the active backend), `bootstrapping-repo` (bootstrap stage predicate evaluator + capability dispatch — consumed once the v0.5.0 paired-PR setup-stages rebase lands). | None in-plugin (atomic = reflexive). Externally: the active projection's bash command / MCP tool / REST endpoint. |
| Outbound | — | Active projection only. |

Cross-plugin invocations (e.g., `superpowers:test-driven-development`, `gstack:/qa`) are NOT made from this skill — they live on the molecular skills that consume protocol actions.

## What this skill does NOT cover

- **What is legal** — the state machine, the Card body schema, the branch-naming convention, the WIP counting formula. That is the `board-superpowers:board-canon` skill. This skill enacts the protocol; that skill defines the protocol's read-only contract.
- **Whether an action proceeds automatically or waits for architect approval** — that is the `board-superpowers:classifying-actions` skill. The caller consults that skill before invoking this one.
- **Audit-row writing** — that is the `board-superpowers:auditing-actions` skill. The caller writes the audit row before and after invoking this skill, per the propose / resolve sequencing rules in that skill.
- **Bootstrap stage execution machinery** — running a bootstrap stage end-to-end (lifecycle diff, executor selection, stale-state detection) is the bootstrapping flow's responsibility. This skill answers the predicate question and dispatches the capability invocation; orchestration sits one layer up.
- **Discovering the projection list** — the projection identifiers this skill recognizes are the names of files in its `references/` directory. There is no introspection API; new projections land by adding a reference file in a normal PR.

## References

| File | Purpose |
|------|---------|
| `references/action-dispatch.md` | Per-action dispatch patterns — invocation shape, return shape, idempotency property, error semantics — for each of the eight protocol actions, parameterized by Form. |
| `references/backend-selection.md` | The kanban-registry read algorithm + composite identity `(kanban-id, Card.key)` resolution + multi-kanban disambiguation + fallback paths when the registry is absent. |
| `references/form-a-bash.md` | Form A (bash CLI) projection conventions — stdout / stderr / exit-code expectations, helper-script invocation patterns, the v0.5.0 GitHub Project v2 projection as the reference instance. |
| `references/form-b-mcp.md` | Form B (plugin-shipped MCP server) conventions — `userConfig.sensitive` credential storage, MCP tool-call shape, response parsing. No live instance at v0.5.0; documented for the v1.x roadmap. |
| `references/form-c-rest.md` | Form C (REST / GraphQL) conventions — auth header derivation, request shape, response parsing. No live instance at v0.5.0; documented so future authors are not forced into Form B. |
| `references/failure-mode-dispatch.md` | The full failure-mode taxonomy + architect-visibility tier per failure + the surfacing convention each tier uses. |
| `references/github-project-v2.md` | Live v0.5.0 projection — invocation entries for the 8 protocol actions over GitHub Project v2 (Form A bash CLI). |

When a new backend projection ships, its per-projection reference file lands in this same `references/` directory under the projection's identifier (e.g., `references/github-project-v2.md`, `references/linear.md`, `references/jira.md`) — the projection's reference file declares the projection's chosen Form, the per-action invocation patterns, the custom-state folding mapping, the markdown / native body conversion, and the supported setup capabilities.
