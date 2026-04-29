# Kanban Protocol — top-level contract

> **Status:** accepted (2026-04-28).
> **Type:** semantic / mental-model contract. NOT an SDK.
> **Audience:** agents (runtime); second-adapter authors (design-time);
> plugin maintainers (evolution).

This document is the **semantic root** of every other contract in
[`0005-contracts/`](./README.md). The 01-08 files pin
implementation-level shapes (script stdout, hook payloads, config
schemas, audit log columns); they all derive their meaning from the
Kanban Protocol established here.

---

## Why this document exists

board-superpowers v1 had two motivating questions colliding in the
spec:

1. *"How does an agent reason about a kanban board across different
   backends (GitHub Project v2 / Linear / Jira / future) without
   having to learn each backend's API?"*
2. *"How do we commit to substrate pluggability (P2a, ADR-0001) when
   we cannot control the API surface of any backend we adapt to?"*

ADR-0005 first answered both with an SDK-shaped contract — five
read+write methods, a `Result[T]` shape, a six-`ErrorKind` enum.
That answer assumes the caller is a deterministic program reading
function signatures. In an **agentic** plugin, the caller is an
agent reading SKILL bodies and MCP tool descriptions; the same
ontological commitment is better expressed as a **protocol**
(semantic mental model that agents adapt to backend-specific
projections), not an SDK (function table the agent must dispatch
through).

This document elevates the answer one level: **Kanban Protocol** is
the universal mental model; every backend (GitHub Project v2 today;
Linear / Jira / future) ships a **projection** of that protocol —
expressed via a SKILL reference file, a plugin-shipped MCP server,
a CLI wrapper, or any combination thereof. The agent speaks
protocol; the projection translates to backend.

ADR-0025 supersedes ADR-0005 § Decision and § Type definitions in
that light: ADR-0005's contract surface is no longer "the contract
every adapter must implement." It is now **the v1
GitHubProjectAdapter implementation projection** — one specific
shape the protocol takes when the backend is GitHub Project v2 and
the transport is bash + `gh` CLI. Different transports (MCP,
REST), different backends, different projections.

---

## What the Kanban Protocol IS — and is NOT

**The Kanban Protocol IS:**

- A **semantic mental model.** Eight named actions; six canonical
  states; a small ontology (Board / Card / Status / Claim / PR
  Link / Label / Comment); identity rules (`Card.key` is opaque,
  not parseable); branch-naming convention (`claim/<key-slug>-
  <title-slug>`).
- A **stable contract.** Once accepted, action semantics, state
  transitions, identity rules, and ontology are immutable modulo
  superseding ADR. Agent behavior compiled against this protocol
  must remain valid across plugin minor versions.
- A **multi-projection target.** Each backend exposes the same
  protocol through whatever transport fits — bash CLI, plugin-
  shipped MCP server, REST/GraphQL client. Projections differ;
  protocol does not.
- **Backend-agnostic.** No protocol element names a specific
  backend. GitHub-shaped affordances (`#42`, `Closes #N`, `gh
  project item-edit`) are projection details, not protocol
  elements.

**The Kanban Protocol is NOT:**

- ❌ **An SDK** — no function signatures, no parameter lists, no
  return types beyond semantic outcome. ADR-0005's `Result[T]` /
  `ErrorKind` typing belongs to the v1 GitHubProjectAdapter
  projection (and any future projection that finds it useful);
  it is not promoted to protocol.
- ❌ **A discovery / introspection mechanism.** The protocol does
  not specify how an agent discovers which projection applies on
  the current repo — that is the responsibility of the
  `operating-kanban` skill (which reads
  `<repo>/.board-superpowers/config.yml` § `kanban:`) and the
  `bootstrapping-repo` skill (which writes that config).
- ❌ **A complete enumeration of backend capabilities.** Custom
  fields, backend-specific affordances (Linear cycles, Jira
  custom workflows, GitHub draft items) are explicitly NOT
  surfaced through the protocol. Each backend's reference file
  documents what its native richness loses (or preserves
  internally) to fit the protocol.
- ❌ **A test contract.** Whether a backend correctly implements
  the protocol is verified at the projection layer (operating-
  kanban references; per-backend integration tests). Protocol
  itself is read by humans and agents, not by test runners.

---

## Audiences and how to read this document

This document is multi-audience. Each audience reads it
differently:

| Audience | What they extract | How they use it |
|----------|-------------------|-----------------|
| **Agents** (runtime) | The eight action semantics + the six-state machine + identity rules | Form a mental model of "what is happening on the board"; dispatch to per-backend projection (operating-kanban references) for invocation |
| **Second-adapter authors** (design-time) | The action contracts (pre/post/error/idempotency) + the custom-state folding rule + the body-schema contract | Translate to native API on the new backend; produce a projection (SKILL reference + optional MCP server + optional CLI wrapper) |
| **Plugin maintainers** (evolution) | The "IS / IS NOT" boundary + the immutability commitment + the protocol→projection ownership split | Decide whether a feature request lands at protocol layer or projection layer; resist projection-shaped concepts leaking into protocol |

Reading order on first pass: Ontology → Identity → State machine →
Action contracts → Compliance levels → Implementation surface. The
order tracks "what exists" → "how it is named" → "how it changes
state" → "what operations agents perform" → "what subset a backend
must support" → "how a backend exposes itself."

---

## Ontology

These are the protocol's first-class objects. Every backend
projection MUST surface all of them; backends with richer native
ontologies (Linear's cycles, Jira's epics, GitHub's draft items)
are responsible for either folding the richness into one of these
or treating it as backend-internal state invisible to the agent.

### Board

A kanban board. The protocol does NOT specify how a board is
created or destroyed — backend bootstrap responsibility, surfaced
via [`bootstrapping-repo`](../../../skills/bootstrapping-repo/SKILL.md).
The protocol assumes a board exists, identified by an opaque
`ProjectRef` string (parsed by the active backend; see
[Identity](#identity) below).

Maps to: `Project` aggregate in
[`0003-domain-model/03-aggregates-and-entities.md`](../0003-domain-model/03-aggregates-and-entities.md)
§ Project.

### Card

A leaf work item — the smallest unit of kanban flow. Has identity
(`Card.key`), human-readable display (`Card.title`), narrative
content (`Card.body` in markdown), state membership
(`Card.status`), classification (`Card.labels`), web pointer
(`Card.url`), and timestamps.

Maps to: `Card` aggregate in
[`0003-domain-model/03-aggregates-and-entities.md`](../0003-domain-model/03-aggregates-and-entities.md)
§ Card.

### Status

The lifecycle phase a card occupies. Protocol-level Status is a
**closed enum of six canonical values**:

```
Backlog | Ready | In Progress | In Review | Done | Blocked
```

Backends with richer native taxonomies fold to canonical (see
[Custom-state folding rule](#custom-state-folding-rule)).

The full state machine and per-transition contracts live in
[`board-canon`](../../../skills/board-canon/SKILL.md) § State
machine; that skill is the single point of truth (SPOT) for the
state machine. Protocol document references it; does not duplicate.

### Claim

A signal that a specific Session owns a specific Card for the
duration of one Consumer cycle. Materialized in the **git layer**
(a `claim/<key-slug>-<title-slug>` branch on origin), NOT at the
board layer — the board is an observer.

Maps to: `ClaimBranch` + `ClaimMarker` member entities of the
`ConsumerLogical` aggregate in
[`0003-domain-model/03-aggregates-and-entities.md`](../0003-domain-model/03-aggregates-and-entities.md).

Rationale for git-layer materialization: ADR-0002.

### PR Link

A bidirectional discoverable association between a Card and a Pull
Request. Protocol does NOT prescribe the linking mechanism — the
backend reference decides whether the link lives in PR body text,
in branch naming convention, in the backend's native git
integration, or in some combination.

Protocol-level requirement: from `Card.url` an agent can navigate
to the PR; from the PR an agent can navigate back to `Card.key`.

### Label

A classification tag attached to a Card. Protocol-level
vocabulary (the agent always reasons in these):

| Namespace | Examples | Required by protocol? |
|-----------|----------|----------------------|
| `type:` | `type:feat`, `type:fix`, `type:chore`, `type:docs`, `type:refactor`, `type:test` | yes |
| `size:` | `size:XS`, `size:S`, `size:M`, `size:L` | yes |
| backend-extension | per-backend, e.g., `suspended` | optional |

The required namespaces are **protocol-layer concepts**: every
projection MUST surface labels in `type:` and `size:` namespaces
to the agent. The projection chooses HOW that surface is
realized in the native backend — GitHub uses repo-scope labels,
Linear can use team-scope or workspace-scope labels, Jira can
use components or labels or custom fields. The agent always
sees `Card.labels` as a flat `list[str]` containing
`type:<value>` and `size:<value>` strings (regardless of how
the backend stores them natively); the projection's reference
file documents the mapping.

Native richer label semantics (Linear team-vs-workspace,
Jira components-vs-labels-vs-custom-fields) MAY be preserved
backend-internally for the projection's own use, but MUST NOT
leak into the agent-visible `Card.labels` list — only the
canonical `type:` / `size:` namespaces and any optional
backend-extension entries appear there.

### Comment

A textual exchange entry on a Card. **Optional** at protocol
level — not every backend supports comments uniformly, and not
every workflow needs them. v1 callers do not require comment
support; backends advertise whether they implement
[`comment_on_card`](#comment_on_card) at L1 compliance.

---

## Identity

How the protocol names objects. Backends with native identity
schemes (GitHub `#42`, Linear `TEAM-42`, Jira `PROJ-42`)
contribute their native string into protocol identity slots.

### `Card.key`

Display-stable opaque string assigned by the backend at card
creation. **Not parseable**: callers MUST NOT attempt to
recover board structure (project, team, namespace) from the key
alone. Protocol guarantees:

- **Unique within a Board.** Two cards on the same board never
  share a key.
- **Stable across the card lifetime.** `Card.key` does not
  change as the card moves through states; it does not change
  on rename or relabel.
- **Display-friendly.** Users recognize and quote it ("card 42",
  "ENG-42"); agents pass it through opaquely.

Backend examples:

| Backend | `Card.key` format | Source |
|---------|-------------------|--------|
| GitHub Project v2 | `<issue-number>` (e.g., `42`) | GitHub Issue number |
| Linear (future) | `<team-prefix>-<number>` (e.g., `eng-42`) | Linear issue identifier |
| Jira (future) | `<project-key>-<number>` (e.g., `proj-42`) | Jira issue key |

### `Card.url`

Web URL pointing to the card's canonical view in the backend's
UI. Used by humans (clicking through from a CLI listing) and by
agents (linking back from PR body). Protocol guarantees the URL
resolves to the Card while it exists; behavior on archived /
deleted cards is backend-defined.

### Branch naming

Every Consumer claim branch has the form:

```
claim/<key-slug>-<title-slug>
```

Where:

- `<key-slug>` = `slugify(Card.key)`
  - Lowercase, alphanumeric + hyphens.
  - GitHub: `42` → `42`.
  - Linear: `ENG-42` → `eng-42`.
  - Jira: `PROJ-42` → `proj-42`.
- `<title-slug>` = `slugify(Card.title)` truncated to ≤40 chars.

The full slugifier rules and edge cases live in
[`board-canon`](../../../skills/board-canon/SKILL.md) § Branch
naming. board-canon will become the SPOT for branch naming once
its v0.5.0 patch lands (board-canon currently still hard-codes
the GitHub-shaped `claim/<N>-<slug>` form; the patch generalizes
to `claim/<key-slug>-<title-slug>`). Until that patch ships,
this protocol document is the authoritative cross-backend form
and board-canon's prose is read in light of this generalization.

**Why branch naming is protocol-level**: the claim primitive
(ADR-0002) is git-layer atomic. Branch names are observable by
every Consumer and Producer session via `git ls-remote`, across
machines, without the board's involvement. Naming convention IS
the inter-session communication channel.

**Migration note**: prior to v0.5.0, branch naming was
`claim/<N>-<slug>` where N is GitHub issue number — implicitly
GitHub-shaped. The v0.5.0 abstraction generalizes N to
`<key-slug>` derived from `Card.key`. ADR-0001 and ADR-0002 carry
this patch in their § Decision sections; existing GitHub-Project-
v2 claim branches (e.g., `claim/42-fix-bug`) remain valid because
GitHub `<key-slug>` of `42` is `42`.

---

## Multi-kanban semantics

A single repo MAY bind multiple kanbans (e.g., one for primary
feature work, one for compliance, one for ops). The protocol
treats this as a first-class scenario; v1.0 ships single-kanban
runtime support, with the schema reserved for v1.x runtime
expansion.

Detailed lifecycle states, schema, and migration semantics live
in [ADR-0026](../adr/0026-multi-kanban-lifecycle-and-flat-card-hierarchy.md).
This section is the protocol-level contract.

### Identity is always the composite key `(kanban_id, Card.key)`

Whether the repo has 1 kanban or N, internal Card identity is
ALWAYS `(kanban_id, Card.key)`. Single-kanban repos are a
degenerate case where every reference shares one `kanban_id`; the
protocol does not gain a new shape under multi-kanban — only the
identifying tuple gains mandatory disambiguation.

### Disambiguation in user-facing references

| Reference shape | Resolution rule |
|-----------------|-----------------|
| `[board-card:#42]` (no qualifier) | Resolves only when active kanban count = 1. With multi-kanban, the unqualified form is a hard error: *"multiple active kanbans; qualify as `[board-card:<kanban-id>:#42]`"*. |
| `[board-card:legal:#42]` (qualified) | Routes to the named kanban regardless of count. |

Single-kanban v1.0 repos behave identically to v0.4.x — the
unqualified form continues to work because the disambiguation
rule degenerates to the single available kanban.

### Branch naming uniformity

Per the abstracted form (above § Branch naming):

```
v0.5.0+ canonical:  claim/<kanban-id>-<key-slug>-<title-slug>
v0.4.x legacy:      claim/<key-slug>-<title-slug>
```

Legacy v0.4.x branches remain valid via a parser fallback in
operating-kanban; physical rename is NOT performed during
migration. `migrating-repo-version` registers the legacy
branches against the migrated repo's `primary` kanban via
on-disk state, preserving the binding without rewriting git
refs.

### WIP semantics — per-actor cross-kanban total

Default WIP cap is **per-actor, cross-kanban total**. Architect
attention is a single budget that does not partition across
kanbans; a Consumer holding 3 cards in `primary` and 2 cards in
`legal` has WIP=5, not WIP=3 + WIP=2 separately.

Optional override: `kanbans[].wip_limit_local: N` adds a
per-kanban cap (the kanban-local count must not exceed BOTH the
global cap AND the local cap).

### Cross-kanban moves are forbidden

A Card belongs to one kanban for its entire lifetime. There is
no protocol-level operation that re-homes a Card to a different
kanban. "Moving" a misfiled Card is two operations:

1. Retire the Card on the source kanban (`transition_card → Done`
   with a `reason: misfiled` note, OR delete via backend UI).
2. Create a fresh Card on the destination kanban with the same
   body content.

Both operations are independently audited. Cross-kanban
sequencing dependencies (`Card A depends on Card B` where they
live on different kanbans) are protocol-allowed; the
`depends-on` reference in B's identity must qualify with
`<kanban-id>:` per the disambiguation rule above.

### Compliance level applies per kanban

Each kanban entry advertises its own `compliance: L0..L3` level
(see [Compliance levels](#compliance-levels) below). Operations
on a kanban are gated by THAT kanban's level; agents must check
the active kanban's compliance before dispatching an action that
requires a higher level than the kanban supports.

---

## State machine

The six canonical states + legal transitions are SPOT'd in
[`board-canon`](../../../skills/board-canon/SKILL.md) § State
machine. Protocol document cites that SPOT instead of duplicating;
this section provides the cross-backend semantics. **board-canon
v0.4.x still phrases the state-machine table with GitHub-shaped
flavor (e.g., references to `<N>` in branch examples).** The
v0.5.0 patch on board-canon generalizes those to
`<key>` / `<key-slug>`; until then, read board-canon's table in
light of the abstraction this protocol establishes.

### Canonical state graph

```
            ┌──────────────┐
            │   Backlog    │  intake landing zone
            └──────┬───────┘
                   │ promote (Manager / decompose skill)
                   ▼
            ┌──────────────┐
            │    Ready     │  available for claim
            └──────┬───────┘
                   │ claim_card (Consumer takes ownership)
                   ▼
            ┌──────────────┐
            │ In Progress  │◀──────┐
            └──────┬───────┘       │ revisions
                   │ submit-pr     │
                   ▼               │
            ┌──────────────┐       │
            │  In Review   │───────┘
            └──────┬───────┘
                   │ merge
                   ▼
            ┌──────────────┐
            │     Done     │  terminal
            └──────────────┘

   Lateral state, accessible from In Progress, exits to In Progress:
            ┌──────────────┐
            │   Blocked    │
            └──────────────┘
```

### Transition meanings (cross-backend, semantic-only)

| From → To | Meaning | Pre-condition |
|-----------|---------|---------------|
| Backlog → Ready | Card has met its INVEST gate; Manager promotes for claim | Body has all 5 mandatory sections + Acceptance criteria pass INVEST + estimate set + no hard `depends-on` blocked |
| Ready → In Progress | A Consumer has claimed the card | An atomic claim primitive succeeded (git-layer push of `claim/<key-slug>-<title-slug>`); WIP cap not exceeded |
| In Progress → In Review | Consumer has opened a PR | PR exists, PR body honors three-section contract |
| In Review → In Progress | Reviewer requested changes | Outstanding "request changes" review submitted |
| In Review → Done | PR merged | PR is in merged state (NOT closed without merge) |
| In Progress → Blocked | External dependency unresolved | Blocker named in a Card comment; "haven't started" is not a blocker |
| Blocked → In Progress | Blocker resolved | Blocker note marked resolved |

### Custom-state folding rule

Backends with richer native taxonomies (Linear's customizable
workflow states, Jira's per-project workflow + transitions) MUST
fold native states into the six canonical at projection time:

- **Native state maps cleanly to a canonical state** → the backend
  reference file lists the mapping; agent sees only the canonical
  name.
- **Native state has no canonical equivalent** → the backend
  projection MUST fold it to `Backlog` and emit a stderr warning
  identifying the unmapped native state. Agents MUST NOT silently
  drop the card.
- **Mapping schema is per-backend; mapping values may be
  per-repo.** The backend reference file (per
  `operating-kanban/references/<backend>.md`, lands when the
  operating-kanban skill ships v0.5.0) documents the *schema* —
  what fields the mapping has, which canonical states each
  field can target, what conversion losses are acceptable. The
  *values* filling that schema are per-repo: a Jira project
  on this repo with a custom 8-state workflow declares its
  fold-table in `<repo>/.board-superpowers/config.yml`
  overrides at bootstrap. Per-card folding is forbidden —
  folding is a global property of the backend's taxonomy as
  configured on this repo, never resolved per-card.

Rationale: the six-state vocabulary IS the agent's mental model.
Allowing native-state leakage past projection would force the
agent to reason about every backend's workflow customization,
defeating the purpose of having a protocol.

---

## Body schema

Every `Card.body` follows the schema SPOT'd in
[`board-canon`](../../../skills/board-canon/SKILL.md) § Card body
schema. The protocol-level rule is:

- **`Card.body` is markdown** as the protocol's representation.
- Backends without native markdown (e.g., Jira's ADF) are
  responsible for two-way conversion at the projection layer.
  Agents always read and write markdown; what the backend stores
  natively is invisible.
- Conversion fidelity is best-effort. Backend reference files
  document known lossy elements (Jira ADF: nested code blocks,
  collapsed sections, etc.) and the agent-visible workaround.

The 5 mandatory sections (`Goal` / `Acceptance criteria` /
`Out of scope` / `Dependencies` / `Notes`) and the 6th optional
section (`Execution Hints`), the thin-pointer block, and the
bottom marker pair (`<!-- board-superpowers:audit-trail -->` and
`<!-- board-superpowers:creator-trace -->`) are protocol-level
contract: every backend projection MUST preserve them. board-canon
is the source of truth for their exact structure.

---

## Card hierarchy

The Kanban Protocol's `Card` ontology is **flat**. Cards relate
to each other through `depends-on` / `depended-on-by` (sequencing
dependency, NOT containment). There is no parent-child
relationship at protocol level.

This is a deliberate decision grounded in **AI-native concept
hygiene** — see
[`../0001-positioning.md`](../0001-positioning.md)
§ "AI-native concept hygiene" and ADR-0026 § "3. Card hierarchy"
for the full rationale. In short: sub-issue / sub-task is a
human-cadence agile artifact whose six historical purposes either
die outright in AI-cadence software R&D or shift one level up
into Thread / Milestone. Adopting parent-child at protocol level
would buy nothing that Thread + sibling Cards + dependencies
don't already provide, while costing protocol purity (parent
Cards would be non-claimable, would violate the *one Card = one
Consumer session = one PR* invariant, and would introduce a
status-derivation rule that doesn't even agree across backends).

### Display-only metadata fields

When a backend has native sub-issue / sub-task / parent
relationships (GitHub Sub-issue, Linear sub-issue, Jira
Sub-task), the projection surfaces three **display-only** fields
on the protocol-flat Card:

```
Card schema additions (display-only; agent-readable for context
but NOT protocol-significant — transitions / claims / WIP do
not consume these):

  display_parent: <key>?                 # backend's parent Card.key
  display_children_count: int?           # backend's child count
  display_hierarchy_path: [<key>...]     # root-to-this Card path
```

These fields are **read-projected** from backend native nesting
on each `read_card` / `read_board`. They are **never written by
board-superpowers** to backend native sub-issue APIs.
`decomposing-into-milestones` continues to emit siblings +
dependencies; it never invokes backend native sub-issue creation.

### Multi-tier backend hierarchy mapping

Backends with multi-tier hierarchies map to board-superpowers'
existing work hierarchy (per
[`../0002-product-features-and-flows/01-work-hierarchy.md`](../0002-product-features-and-flows/01-work-hierarchy.md)):

| Backend tier | board-superpowers concept |
|--------------|---------------------------|
| Initiative (Linear / Jira Premium) | **Thread** (named work mainline) |
| Project (Linear) / Epic (Jira) | **Milestone** (deliverable bucket) |
| Issue (GitHub / Linear / Jira) | **Card** (leaf work item) |
| Sub-issue / Sub-task | **Card** (sibling) + `display_parent` metadata |

The leaf-most level is always the claimable `Card`. Upper tiers
are organizational context, surfaced through Thread / Milestone
aggregation in `managing-board` routines.

### What is explicitly NOT done

- ❌ A `Card.parent` field at protocol level.
- ❌ Auto-created `depends-on` edges from native hierarchy
  (sequencing ≠ containment).
- ❌ Parent status auto-derivation from children
  (cross-backend semantics disagree).
- ❌ A `Card.kind: feature | story | task` enum.
- ❌ Markdown-body `## Parent` section convention.
- ❌ `parent:#42` labels as protocol-level mechanism.

Each is rejected for reasons in ADR-0026.

---

## Action contracts

The protocol surface is **eight actions**. Every backend projection
MUST implement actions through L1 compliance (see [Compliance
levels](#compliance-levels) below). Actions through L2 are
required for backends supporting Consumer claim flow.
`comment_on_card` is OPTIONAL.

Each action is a **semantic contract**, not a function signature.
The "see operating-kanban/references/<backend>.md for invocation"
note tells the agent where the projection-specific procedure
lives.

### `read_board`

**Intent.** Take a snapshot of all cards on a board, with their
canonical statuses.

**Pre-condition.** Board exists; agent has read access.

**Post-condition.** Agent holds a list of `(key, title, status,
labels, url)` tuples covering every card visible to the agent.
Order is backend-native; callers sort client-side if order matters
to them.

**Failure modes.**
- Board not found → projection surfaces this distinctly; agent
  routes to bootstrapping-repo.
- Permission denied → agent surfaces to the user; does not retry.
- Network / transport failure → projection retries per its own
  policy; surfaces persistent failure.
- Partial-result tolerance: malformed individual cards are silently
  omitted with a stderr warning; whole-board fetch does NOT fail
  on a few weird cards.

**Idempotency.** Read; trivially idempotent.

**See operating-kanban references/<backend>.md § read_board for
invocation.**

### `read_card`

**Intent.** Fetch one card's complete content (body, labels,
status).

**Pre-condition.** Card exists on the board.

**Post-condition.** Agent holds the full Card record (key, title,
body, status, labels, url, timestamps).

**Failure modes.**
- Card not found → projection surfaces distinctly; not a transport
  failure.
- Schema mismatch (card body does not parse against the body
  schema, e.g., missing mandatory section) → projection surfaces
  with the offending section name; agent decides whether to repair
  or report.

**Idempotency.** Read; trivially idempotent.

### `create_card`

**Intent.** Land a new card in `Backlog`.

**Pre-condition.** Board exists; agent has write access; all
labels named in the call exist on the board (label provisioning
is bootstrap responsibility, NOT projection responsibility).

**Post-condition.** A new card exists on the board with the
specified body, labels, and `status = Backlog`. Card.key is
assigned by the backend; agent receives it.

**Failure modes.**
- Label does not exist on board → projection surfaces; agent does
  NOT auto-create labels (uniform across backends even when the
  backend allows lazy creation, to keep behavior consistent).
- Permission denied → surfaced; not retried.
- No idempotency key at v1 → caller responsibility to guard
  against duplicate creation across retries (typical guard:
  `read_board` before retry).

**Idempotency.** Not idempotent at v1.

### `transition_card`

**Intent.** Move a card from its current canonical status to
another canonical status.

**Pre-condition.** Card exists; the (current_status, target_status)
pair is a legal transition per
[`board-canon`](../../../skills/board-canon/SKILL.md) § State
machine; caller has authority to make the transition (Consumer
holds claim, OR Manager has architect role).

**Post-condition.** `Card.status = target_status`. (Audit log
emission is a board-superpowers cross-cutting invariant — see
[`auditing-actions`](../../../skills/auditing-actions/SKILL.md)
— and applies to every mutating action regardless of compliance
level. It is not a protocol postcondition; it is a plugin
invariant the calling skill enforces.)

**Failure modes.**
- Illegal transition → projection refuses BEFORE calling backend;
  agent surfaces the violation.
- Concurrent modification (card status changed underneath us) →
  projection surfaces a conflict; agent re-reads and re-decides.
- Backend transition mechanism is non-trivial: Jira fires
  transitions by ID, Linear sets workflow states, GitHub edits a
  field option. Projection internalizes the mechanism; agent sees
  one semantic action.

**Idempotency.** Transitioning to current status is a successful
no-op (NOT an error).

### `claim_card`

**Intent.** Acquire exclusive Consumer ownership of a card.

**Pre-condition.** `Card.status == Ready`; no active claim branch
exists for this card on origin; Consumer's WIP count + 1 ≤ WIP
cap.

**Post-condition.** A `claim/<key-slug>-<title-slug>` branch
exists on origin (push succeeded); `Card.status == In Progress`.
Atomicity is enforced at the **git layer** by `git push
--force-with-lease=<ref>:` semantics (ADR-0002), NOT at the
board layer. (Audit log emission is a plugin invariant; see
note under `transition_card`.)

**Failure modes.**
- Race lost (another Consumer's push won) → projection returns
  a "claim not acquired" signal; agent surfaces who won
  (observable from `git ls-remote`).
- Card not in `Ready` → projection refuses BEFORE pushing.
- WIP cap exceeded → projection refuses BEFORE pushing.
- git-layer push transport error → projection surfaces; partial
  state (board status updated, branch push failed, or vice versa)
  is the Consumer's responsibility to surface to the architect,
  not silently retry. (TODO: a backend-agnostic recovery contract
  for partial-state claim is a known v1.x design item — see
  ADR-0006 row 8 for the architect-override boundary; the full
  recovery protocol lands in a follow-up PR alongside
  operating-kanban's claim-flow projection.)

**Idempotency.** Re-claiming an already-claimed-by-self card is a
successful no-op. Re-claiming an already-claimed-by-another card
is a race-loss failure.

### `release_claim`

**Intent.** Release Consumer ownership of a card.

**Pre-condition.** Caller is the holder of the claim (or has
architect override per ADR-0006 row 8).

**Post-condition.** `claim/<key-slug>-<title-slug>` branch is
deleted from origin; `Card.status` returns to `Ready` (or stays at
its current state if the claim is being released as part of a
merge into Done — the projection decides based on context).

**Failure modes.**
- Caller does not hold the claim (and lacks architect override) →
  projection refuses; surfaces audit log entry to architect.
- Branch deletion failure → projection retries per its policy;
  partial state surfaced to architect if persistent.

**Idempotency.** Releasing an already-released claim is a no-op.

### `link_pr_to_card`

**Intent.** Establish bidirectional discoverability between a
Card and a Pull Request.

**Pre-condition.** Card exists; PR exists; Card.status ∈
`{In Progress, In Review}`.

**Post-condition.** From `Card.url` an agent can navigate to the
PR; from the PR an agent can navigate back to `Card.key`. The
linking mechanism (PR body text, backend native API, branch-name
convention) is projection-internal.

**Failure modes.**
- Card or PR not found → projection surfaces distinctly.
- Backend's native auto-link fails (the linking mechanism — PR-
  body marker, branch-name convention, smart-commit syntax,
  backend native API — is unavailable on this repo or rejected
  at the linking step) → projection falls back to inserting an
  explicit pointer in PR body; surfaces a warning.

**Merge-trigger Done transition.** When the PR merges, the
`In Review → Done` transition is expected to happen. The
mechanism by which the merge triggers the transition is
projection-defined: GitHub's auto-close-on-merge for issues
referenced via `Closes` syntax; Linear's git integration auto-
moving issues with branch keys; Jira's smart-commit
post-processing. Backends without a native auto-trigger fall
back to the calling skill (`consuming-card` Step 12 cleanup, or
the post-merge cron) explicitly invoking `transition_card` to
land the Done state.

**Idempotency.** Linking an already-linked pair is a no-op.

### `comment_on_card` *(OPTIONAL)*

**Intent.** Append a textual exchange entry to a card.

**Pre-condition.** Card exists; backend supports comments at
projection layer.

**Post-condition.** Comment is visible on the card to the next
`read_card` reader.

**Failure modes.**
- Backend does not support comments → projection surfaces "not
  implemented" distinctly; caller decides whether to fall back to
  PR-body discussion or surface to the user.
- Comment too long for backend (Linear has length limits, Jira
  has none) → projection truncates with a stderr warning OR
  surfaces a hard error per the backend reference.

**Idempotency.** Not idempotent (each call is a new comment).

---

## Compliance levels

Backends declare their compliance level in
`<repo>/.board-superpowers/config.yml § kanban`:

```yaml
kanban:
  backend: github-project-v2          # enum
  project_ref: PanQiWei/3              # OWNER/PROJECT_NUMBER per
                                       # ADR-0005 GitHubProjectAdapter
                                       # projection (NOT OWNER/REPO)
  compliance: L3                      # advertised level
```

| Level | Required actions | What it enables |
|-------|------------------|-----------------|
| **L0** (read-only) | `read_board`, `read_card` | `managing-board` daily routine; review-only Producer flows |
| **L1** (write) | L0 + `create_card`, `transition_card`, `comment_on_card` (optional flag) | Producer intake (F-08), `decomposing-into-milestones`, basic Manager mutation |
| **L2** (claim) | L1 + `claim_card`, `release_claim`, `link_pr_to_card` | Full Consumer flow (F-C0..F-C14) |
| **L3** (full v1) | L2 + verified body-schema preservation + custom-state folding documentation | All v1 features |

**Audit log emission is a plugin invariant, not a compliance
requirement.** Every mutating action in board-superpowers writes
an audit entry through the calling skill's invocation of
`auditing-actions` (per ADR-0006); the projection itself does not
own audit emission. Compliance levels do not gate audit; audit
applies at every level.

**v1.0 ships at L3 for `github-project-v2`.** Future Linear and
Jira projections declare their own compliance level when they
ship; agents reading config detect and refuse Consumer flow on L0
or L1 backends until L2 is reached.

---

## Implementation surface (backend projections)

A backend projection is the concrete realization of the protocol
on one backend, on one transport. v1 recognizes three projection
forms:

### Form A: bash CLI projection

The reference shape: a `lib/adapters/<backend>.sh` (or equivalent)
plus per-action invocation patterns documented in
`operating-kanban/references/<backend>.md`. Agent reads the
reference and runs the documented commands.

**v1.0 GitHubProjectAdapter is Form A** — bash + `gh` CLI. ADR-0005
defines the SDK-shape this projection takes; that ADR is now scoped
to "the v1 GitHubProjectAdapter implementation projection," not
"the universal contract."

### Form B: plugin-shipped MCP server projection

A `.mcp.json` entry shipped at plugin root (Claude Code) or
referenced via `.codex-plugin/plugin.json § mcpServers` (Codex
CLI). The MCP server provides tool calls whose tool descriptions
are the per-action invocation patterns. Agent reads tool
descriptions and calls them directly through the platform's MCP
runtime.

**v1.x roadmap**: future Linear projection is expected to be
Form B, wrapping the official Linear MCP server. Jira projection
similarly via Atlassian Remote MCP.

Plugin-platform support varies by platform:

- **Claude Code**: `userConfig.sensitive: true` in
  `.claude-plugin/plugin.json` stores tokens / API keys in the
  system keychain; `${user_config.KEY}` substitution is
  available in `.mcp.json` `env` fields. `Elicitation` /
  `ElicitationResult` hook events let plugins intercept MCP
  tool calls that ask the user for input.
- **Codex CLI**: OAuth flow via `codex mcp login <server-name>`
  for MCP servers that advertise OAuth (configurable
  `mcp_oauth_callback_port` / `mcp_oauth_callback_url`); HTTP
  transport accepts `bearer_token_env_var` / `http_headers` for
  static auth. `Elicitation` is not part of Codex's six-event
  hook surface today.

Each Form B projection cites which platform feature it relies on
in its `references/<backend>.md` so v1.x adapter authors plan
auth flow without surprises.

Plugin-platform MCP details: see
[`PLUGIN_DEVELOPMENT.md`](../../../PLUGIN_DEVELOPMENT.md)
§ "MCP server registration" (Claude Code) and § "MCP integration"
(Codex CLI).

### Form C: REST/GraphQL projection

A bash or python wrapper invoking backend REST/GraphQL endpoints
directly. Used when a backend has no MCP server and CLI is
insufficient. v1 has no Form C projection; the form is recognized
in the protocol so future authors do not feel forced to ship Form
B.

### Why three forms, not one

Different backends have different "natural" projection forms, and
forcing a single form (e.g., "every projection MUST be Form B")
adds artificial integration cost. The protocol is **transport-
agnostic**: agentic loops adapt at runtime to whatever projection
the backend reference provides. The three forms ARE the
documented degrees of freedom.

### What every projection MUST provide

Independent of form, every backend projection MUST ship the
following (with the carve-out below for the v1.0 GitHub
projection while the supporting infrastructure lands):

1. **A reference file** at
   `skills/operating-kanban/references/<backend>.md` documenting
   per-action invocation, custom-state folding mapping, and
   capability deltas (which optional actions supported, what
   conversion losses).
2. **A capability declaration** in
   `adapter-capabilities.md` (sibling spec doc — lands with
   first non-GitHub projection in v1.x; not required while
   GitHubProjectAdapter is the only projection) — the
   cross-backend matrix of what each projection supports.
3. **Bootstrap support** — the
   [`bootstrapping-repo`](../../../skills/bootstrapping-repo/SKILL.md)
   skill knows how to write a `<repo>/.board-superpowers/config.yml`
   `kanban:` block selecting this backend and provisioning
   credentials (`provision_credentials()` sub-contract per
   backend).

**v1.0 carve-out.** The `operating-kanban` skill (which owns the
`references/<backend>.md` directory) and `adapter-capabilities.md`
both ship after this protocol document — `operating-kanban` in
v0.5.0, `adapter-capabilities.md` when the second projection
arrives. While both are pending, the v1.0 GitHub projection
satisfies (1) and (2) implicitly through the existing
`gh`-bound scripts plus ADR-0005's contract surface; bootstrap
support (3) ships as part of the v0.5.0 changes that introduce
the `kanban:` config block.

---

## Relationship to ADR-0005

ADR-0005 originally established **the BoardAdapter contract** —
five read+write methods (`list_cards`, `get_card`,
`get_status_options`, `create_card`, `set_card_status`),
`Result[T]` shape, six `ErrorKind` values, status mapping policy,
contract semantics (idempotency, partial-result tolerance, label
lifecycle, etc.).

After ADR-0025, ADR-0005 is **rescoped**:

- **Was**: "the contract every adapter must implement" (universal).
- **Is now**: "the v1 GitHubProjectAdapter implementation
  projection" — one specific shape Form A takes when the
  transport is bash + `gh` CLI.

ADR-0005's contract surface remains valid AS A PROJECTION, not as
the universal contract. New backend projections do NOT inherit
ADR-0005's `Result[T]` shape verbatim — they realize the protocol
in whatever shape fits their transport (Form B's MCP tool
descriptions; Form C's REST response handling).

ADR-0005's amended Status field reads: `accepted; § Consequences
amended by ADR-0010; § Decision and § Type definitions amended by
ADR-0025`.

---

## Out of scope at v1

Each is a deliberate omission. Adding any requires a new ADR (or
a v1 supersession of this protocol document).

- **`delete_card`** — destructive action. Manager surface
  (managing-board) handles archival via labels and status, not
  deletion. Agents do not delete user data.
- **`archive_card`** — backend-specific (GitHub doesn't have a
  dedicated archive concept; Linear does). Folded into
  `transition_card → Done` for v1; revisit if a backend exposes
  archival semantics that distort Done.
- **`set_card_priority`** — orthogonal to canonical state
  machine; backend-specific (Jira priorities, Linear priorities,
  GitHub doesn't have a native concept). Out of v1 scope.
- **`link_card_to_milestone`** — milestones are a v1 concept on
  the Producer surface (F-09 decomposing-into-milestones), but
  the linkage between Card and Milestone is a Manager-internal
  concern, not a protocol-level operation. Out of protocol scope.
- **Bulk operations** — each protocol action operates on one
  card. Aggregation happens in the calling skill. Bulk would
  multiply the protocol surface without a v1 caller demanding
  it.
- **Webhook / push-shaped change detection** — protocol is
  poll-shaped at v1. Manager session reads the board on
  routine cadence. Webhook receivers are a future ADR.
- **Pagination** — v1 callers iterate full lists. Pagination is
  a future addition when scale demands it.

---

## Versioning + immutability

The Kanban Protocol is **immutable modulo superseding ADR**. Any
change to:

- The eight action names or semantic contracts.
- The six canonical state names or legal transitions.
- The ontology object set (Board / Card / Status / Claim / PR
  Link / Label / Comment).
- Identity rules (`Card.key` opaqueness, branch-naming convention).
- Compliance level definitions.

…requires a new ADR that supersedes this document's relevant
section. The supersession ADR records the `before` and `after`
form so decision history stays traceable.

Strictly **additive** changes (new optional fields on Card; new
optional action documented as OPTIONAL; new compliance level
above L3) are NOT contract-breaking. They land via PR with a
note in the Status header at the top of this document
(`accepted; extended by PR #N`).

---

## Falsification

The Kanban Protocol's load-bearing claim is: *agents reasoning
in protocol terms can dispatch correctly to any backend
projection they encounter, without learning backend specifics
beyond what the projection's reference file documents.*

**Falsification triggers**:

1. **Multi-projection silent failure.** A second backend
   projection ships, and an existing skill (managing-board /
   consuming-card / decomposing-into-milestones / bootstrapping-
   repo) requires source edits to work on it that go beyond
   pointing at a different backend reference. Then the protocol
   is leaking projection details.
2. **Projection-shape leakage.** Protocol document or any
   `board-canon` reference accumulates GitHub-shaped (or any
   other backend-shaped) idiom. Then the protocol is not
   genuinely backend-agnostic.
3. **Custom-state explosion.** A real-world backend's workflow
   has so many native states that the folding-rule produces
   information loss the user notices. Then the six-state
   enumeration is too small (consider adding a state via ADR;
   keep folding rule for the rest).

If any of these triggers fires within the first three real-world
projections (current GitHub + 2 future), the protocol returns to
ADR-shaped supersession; we adjust shape rather than carry a
broken commitment.

---

## Related

- ADR-0001 — Pluggable board backend; commits substrate
  pluggability that this protocol makes universally tractable.
- ADR-0002 — Atomic claim via remote branch push; the git-layer
  primitive for `claim_card`.
- ADR-0005 — v1 BoardAdapter contract surface; rescoped by
  ADR-0025 to "v1 GitHubProjectAdapter implementation
  projection."
- ADR-0010 — AI-cadence convention + ADR-0005 Consequences
  re-anchor; affects this protocol via the falsification check
  on substrate pluggability.
- ADR-0025 — Kanban Protocol as top-level contract (the ADR
  promoting this document to spec authority).
- [`board-canon`](../../../skills/board-canon/SKILL.md) — schema
  rules SPOT (state machine details, Card body schema, branch
  naming slugifier, WIP counting); protocol document references,
  does not duplicate.
- [`operating-kanban`](#) — backend projection dispatch SPOT
  (lands v0.5.0); per-backend reference files live under its
  `references/` directory.
- [`0001-positioning.md`](../0001-positioning.md) P2a, P4a,
  P4b — substrate commitment + composition stance this protocol
  operationalizes.
- [`0003-domain-model/03-aggregates-and-entities.md`](../0003-domain-model/03-aggregates-and-entities.md)
  — Card / Project / ConsumerLogical aggregates this protocol's
  ontology aligns with.
- [`PLUGIN_DEVELOPMENT.md`](../../../PLUGIN_DEVELOPMENT.md)
  § "MCP server registration" / § "MCP integration" — Form B
  projection platform basis.
