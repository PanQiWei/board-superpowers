# ADR 0026: Multi-kanban support + lifecycle states + flat-Card hierarchy stance

**Status:** accepted; § "Multi-kanban semantics" schema field name amended in #68 — `modules.m10_kanban.<id>.backend` renamed to `modules.m10_kanban.<id>.projection` (per ADR-0027 § Decision 4 vocabulary anchor; semantic unchanged)
**Date:** 2026-04-29
**Deciders:** PanQiWei (maintainer)

## Context

ADR-0025 elevated the Kanban Protocol to top-level contract. Three
follow-on questions surfaced in design conversation
(2026-04-28..29) that ADR-0025 deliberately deferred:

1. **Multi-kanban**: a single repo MAY want to bind multiple
   kanbans (one for primary feature work, one for compliance,
   one for ops, etc.). Current schema and runtime assume one
   kanban per repo.
2. **Lifecycle states**: a kanban is not just "exists" or "doesn't
   exist." It can be in temporary read-only (release freeze),
   archived (project phase ended), or retired (config removed).
   Each transition has SOP and audit implications.
3. **Card hierarchy**: GitHub Sub-issues are GA in 2025, Linear has
   Initiative → Project → Issue → Sub-issue, Jira has Epic → Story
   → Sub-task. Should the Kanban Protocol's `Card` ontology adopt
   parent-child relationships?

Each question was put through adversarial review (codex
critiques #1 and #3) on 2026-04-28..29, surfacing several
structural design errors in the maintainer's first-draft
proposals. This ADR encodes the post-critique synthesis.

A fourth question — **scripts/ vs GitHub MCP dual projection** —
also surfaced but is deferred to v1.x as ADR-0014, since v1.0
ships only the Form A (bash + `gh` CLI) projection of the
GitHubProjectAdapter and the dual-transport question only
becomes load-bearing once Form B / Form C projections actually
ship. ADR-0014 will encode the dispatch envelope, audit
contract, and `transport: cli|mcp|dual` semantics when v1.x
demand pulls forward.

## Decision

This ADR makes three coupled decisions, each grounded in the
Kanban Protocol's transport-agnostic stance (ADR-0025) and the
positioning premises P1 / P2b / P3 / P7.

### 1. Lifecycle states — 5 states; all transitions R-class

A kanban entity (NOT a card) traverses 5 states:

```
              ┌───────────┐
              │   Bound   │  settings.yml entry exists; schema validated
              └─────┬─────┘
                    │ activate (R)
                    ▼
          ┌──►┌───────────┐
          │   │   Active  │  routines read+write
   resume │   └─────┬─────┘
          │         │ suspend (R)
          │         ▼
          │   ┌───────────┐
          └───│ Suspended │  read-only; existing claims continue;
              └─────┬─────┘  new claims rejected
                    │ archive (R) — fails if active claims exist,
                    ▼              unless architect provides disposition
              ┌───────────┐
              │  Archived │  routines skip; explicit query OK;
              └─────┬─────┘  not surfaced in daily / review-queue
                    │ retire (R)
                    ▼
              ┌───────────┐
              │  Retired  │  config entry removed; audit history
              └───────────┘  preserved; backend untouched; rebind allowed
```

**`Provisioned` is NOT a lifecycle state.** Whether the backend
board exists is an external fact the plugin does not observe.
The lifecycle starts at `Bound` (`settings.yml` has an entry
under `modules.m10_kanban` + schema validated) — `bind` is the
operation that moves "no entry" to `Bound`.

**All transitions are R-class** (per ADR-0006 D-AUTONOMY-1):
`bind` / `activate` / `suspend` / `resume` / `archive` /
`retire` all require architect approval. Original draft
classified `retire` as N-class; rejected because ADR-0006
specifies `N=0` at v1 and config mutation is uniformly
R-class.

**Suspend / archive interaction with in-flight claims**:

- **`suspend`**: blocks new claims and Producer mutations;
  existing claimed cards continue their lifecycle (Consumer
  finishes the PR, merges through). Architect MAY supply
  `--hard` flag to also block existing-claim transitions, in
  which case in-flight Consumers are forced to surface to the
  architect.
- **`archive`**: **fails** if any active claims exist on this
  kanban, unless the architect supplies a disposition flag
  for each active claim (`--finish` lets the claim continue;
  `--release` returns the claim to Ready; `--freeze` suspends
  the claim until the kanban is unarchived).

`retire` is reversible by re-bind from scratch. Audit history
preserved across retire.

### 2. Multi-kanban support — `modules.m10_kanban.kanbans:` list with v1.0 carve-out

#### Schema

The kanban registry lives under main's M10 module (per ADR-0021
settings modular layering + ADR-0024 `m10.repo.choose-kanban-
backend` config-item stage). `<repo>/.board-superpowers/settings.yml`
gains a list-shaped projection at `modules.m10_kanban.kanbans`:

```yaml
modules:
  m10_kanban:
    schema_version: 1
    # primary backend selection (existing M10 fields per ADR-0024 §
    # Part B; honored when kanbans list has length 1):
    projection: github-project-v2
    project_ref: PanQiWei/3
    # multi-kanban list — v0.5.0 schema reservation; runtime
    # supports list length 1 only (see carve-out below):
    kanbans:
      - id: primary             # repo-internal alias; unique within this repo
        state: active           # Bound | Active | Suspended | Archived | Retired
        projection: github-project-v2
        project_ref: PanQiWei/3 # OWNER/PROJECT_NUMBER per the v1 GH projection
        role: primary           # exactly 1 primary required across active kanbans
        description: "Feature dev"
        # optional: compliance: L0..L3 (default L3 if backend supports it)
        # optional: wip_limit_local: N (per-kanban WIP cap override)
      - id: legal                # multi-kanban example; v1.x only ships if user opts in
        state: active
        projection: jira            # v1.x roadmap; refused at v1.0 runtime
        project_ref: legal-team/COMPLIANCE
        role: secondary
        description: "Compliance & legal review"
```

The single-backend M10 fields (`modules.m10_kanban.backend` /
`project_ref`) are mirrored to `kanbans[primary]` for v1.0
backward compatibility; v1.x runtime treats the list as
authoritative and the singular fields as the primary's projection
shorthand. ADR-0024 § Part B's M5 `set-wip-limit` stage continues
to write `modules.m5_repo_configuration.wip_limit` as the per-actor
GLOBAL cap; `kanbans[].wip_limit_local` is a per-kanban override
within that global cap (see § WIP semantics below).

#### v1.0 runtime carve-out

v1.0 runtime supports `modules.m10_kanban.kanbans` list of length
**exactly 1**. List length > 1 is a hard-failed configuration:
`bootstrapping-repo` and `operating-kanban` refuse to operate
with a "multi-kanban not yet supported in v1.0; see ADR-0026
Roadmap" capability error. Architects MAY author the longer form
for v1.x preparation, but the plugin will not honor it until v1.x
runtime support lands.

#### Identity rules

Internal Card identity is **always** the composite key
`(kanban_id, Card.key)`. Single-kanban repos and multi-kanban
repos share this rule; v1.0's single-kanban form is a degenerate
case.

User-facing references:

- `[board-card:#42]` (no qualifier) — resolves only when active
  kanban count = 1 (v1.0 default). With multi-kanban, the
  unqualified form is a **hard error**: "multiple active
  kanbans; qualify as `[board-card:<kanban-id>:#42]`."
- `[board-card:legal:#42]` — qualified form; routes to the
  named kanban.

#### Branch naming — uniform with kanban_id

Per ADR-0025's branch-naming abstraction
(`claim/<key-slug>-<title-slug>`), v0.5.0 generalizes further:

```
v0.5.0+ canonical:  claim/<kanban-id>-<key-slug>-<title-slug>
                    e.g., claim/primary-42-fix-bug
                          claim/legal-comp-7-audit
v0.4.x legacy:      claim/<key-slug>-<title-slug>
                    e.g., claim/42-fix-bug
```

Migration: the unified setup-stages flow inside
`bootstrapping-repo` (per
[ADR-0012](./0012-unified-check-script-trigger-model.md), which
absorbed the formerly deferred `migrating-repo-version` scope)
registers v0.4.x branches to the migrated repo's primary kanban
via the M10 module's projection at
`~/.board-superpowers/repos/<normalized>/settings.yml` under
`modules.m10_kanban.legacy_claims` (path consistent with ADR-0017
cross-clone state sharing + ADR-0024 settings.yml rename).
Physical branch rename is **not** performed — the legacy parser
in `operating-kanban` accepts both forms during the transition
window.

#### WIP semantics — per-actor cross-kanban total

Default WIP cap is **per-actor**, **cross-kanban total**
(architect attention is a single budget). Per-actor count is
the number of active claim markers held by this actor's
sessions, regardless of which kanban each claim is against.

Optional overrides:

- `kanbans[].wip_limit_local: N` — additional per-kanban cap
  (kanban-local count must not exceed this AND the global
  cap)

### 3. Card hierarchy — flat protocol + display-only metadata

The Kanban Protocol's `Card` ontology stays **flat**. No
parent-child relationship exists at protocol level. Cards
relate via `depends-on` / `depended-on-by` (sequencing
dependency, not containment).

**Rationale anchored to AI-native concept hygiene** (see
[`../0001-positioning.md`](../0001-positioning.md) §
"AI-native concept hygiene"): sub-issue / sub-task are
human-cadence agile artifacts whose six historical purposes
either die outright in AI-cadence software R&D
(decomposition, multi-actor coordination, estimation
aggregation, sprint-internal sequencing) or shift one level
up into Thread / Milestone (stakeholder visibility, mental
chunking). Sub-issue is sibling to sprint, story points,
burndown chart, stand-up, epic — degenerate concepts whose
load-bearing purpose evaporated when implementation throughput
went 100×.

#### Backend-native sub-issue handling — display-only metadata

When projection reads a backend that has native sub-issue /
sub-task / parent relationships (GitHub Sub-issue, Linear
sub-issue, Jira Sub-task), it surfaces three **display-only**
fields on the protocol-flat Card:

```
Card schema additions (display-only; agent-readable but NOT
protocol-significant — transitions / claims / WIP do not
consume these):

  display_parent: <key>?                 # backend's parent Card.key
  display_children_count: int?           # backend's child count
  display_hierarchy_path: [<key>...]     # root-to-this Card path
```

These fields are **read-projected** from backend native nesting
on each read; they are **never written by board-superpowers**
to backend native sub-issue APIs. `decomposing-into-milestones`
continues to emit siblings + dependencies; it never invokes
backend native sub-issue creation.

#### What is explicitly NOT done

- ❌ `parent: <key>` field at protocol level (would create
  non-claimable Card type, violate I-1 invariant).
- ❌ Auto-created `depends-on` edges from native hierarchy
  (sequencing ≠ containment; would block child until parent
  Done, which is wrong for "parent done after all children"
  semantics).
- ❌ Parent status auto-derivation from children
  (cross-backend semantics disagree — GitHub parent can close
  while children open; Linear is configurable; Jira depends
  on workflow. Protocol cannot normalize.).
- ❌ `Card.kind: feature | story | task` enum (imports a
  methodology taxonomy; overlaps with existing `type:*`
  labels).
- ❌ Markdown-body `## Parent` section (body is user-editable;
  drift risk).
- ❌ `parent:#42` labels as protocol-level mechanism (label
  churn; native hierarchy duplication).

#### Multi-tier upper layers map to existing ontology

Backends with multi-tier hierarchies (Linear's Initiative →
Project → Issue → Sub-issue; Jira Premium's Initiative → Epic →
Story → Sub-task) map to board-superpowers' existing work
hierarchy:

| Backend tier | board-superpowers concept |
|--------------|---------------------------|
| Initiative (Linear / Jira Premium) | **Thread** (named work mainline) |
| Project (Linear) / Epic (Jira) | **Milestone** (deliverable bucket) |
| Issue (Linear / Jira) / GitHub Issue | **Card** (leaf work item) |
| Sub-issue / Sub-task | **Card** (sibling) + `display_parent` metadata |

The leaf-most level is always the claimable `Card`. Upper
tiers are organizational context, surfaced through Thread /
Milestone aggregation in `managing-board` routines.

## Consequences

**What this enables:**

- v0.5.0 schema is forward-proof for multi-kanban without
  requiring schema migration when v1.x runtime support lands.
- Lifecycle states give architects explicit operations for
  release freezes, project-phase ends, and config retirement
  with full audit traceability.
- Card hierarchy decision is grounded in AI-native concept
  hygiene, not just cross-backend abstraction trade-offs —
  giving future maintainers / second-projection authors a
  philosophical anchor that survives "but X backend has feature
  Y" pressure.
- Backend-native sub-issues continue to display correctly to
  end users via projection metadata; we don't destroy the
  information they created in the backend UI.

**What this constrains:**

- v1.0 runtime hard-fails on `kanbans:` length > 1; architects
  expecting multi-kanban runtime must wait for v1.x.
- v0.5.0 implementation work (`operating-kanban` skill,
  `bootstrapping-repo` patches that include the v0.4.x →
  v0.5.0 schema migration via the unified setup-stages flow
  per [ADR-0012](./0012-unified-check-script-trigger-model.md),
  `board-canon` v0.5.0 patch) is gated by this ADR's acceptance.
- All claim branches authored under v0.5.0+ MUST use the
  uniform form `claim/<kanban-id>-<key-slug>-<title-slug>`;
  v0.4.x legacy `claim/<key-slug>-<title-slug>` branches
  remain valid via legacy parser.
- `decomposing-into-milestones` skill spec gains an explicit
  refusal clause: never emit "parent + N children" output;
  always emit "N siblings + dependencies."

**What this rules out:**

- A `Card.parent` field at protocol level.
- A `hierarchy_mode: flat | one-level | recursive` config
  knob (rejected because every skill would need to branch on
  hierarchy semantics, undermining the protocol's purpose as
  a single agent mental model).
- Cross-kanban Card moves (a Card belongs to one kanban for
  its lifetime; "moving" is retire-on-source + recreate-on-
  destination, both R-class).
- Silent contract drift on parent-status semantics across
  backends — protocol explicitly does not normalize.

## Alternatives considered

**Multi-kanban: ship the M10 single-backend shorthand only at
v0.5.0; defer the plural `kanbans:` list to v1.x.** Considered.
Rejected because (a) internal identity is always composite
`(kanban_id, Card.key)` per codex critique #1, so the schema
must reflect that forward-compat from day one; (b) migration
from "M10 fields only" → "kanbans list" is a v1.x churn point
we can avoid by shipping list schema (under main's
`modules.m10_kanban.kanbans`) with v1.0 runtime carve-out
(length=1 hard-failed beyond) instead. The M10 single-backend
shorthand stays valid as the primary kanban's projection at
all versions.

**Lifecycle: 6 states including `Provisioned`.** Considered.
Rejected because backend existence is not a board-superpowers
observable; the plugin starts observing at config-entry +
schema-validation, which is `Bound`. Provisioning belongs to
bootstrap docs / human action, not to the lifecycle state
machine.

**Lifecycle: branch naming asymmetric (single-kanban keeps
old form; multi-kanban uses new form).** Considered. Rejected
because every consumer of branch names (claim-card.sh,
ls-remote-based sweeps, post-merge cleanup) would need a
parsing branch in two cases; migrating a repo from single-
kanban to multi-kanban would force branch-rename churn.
Uniform new form + legacy parser is cleaner.

**Lifecycle: `retire` as N-class.** Considered. Rejected
because ADR-0006 sets `N=0` at v1 (no Producer auto-action
class is "Never automatic" at v1). Config mutation is
uniformly R-class. `retire`'s strong preconditions (no active
claims, not sole primary, audit snapshot) provide the
architect-approval gate without needing N-class.

**Card hierarchy: 1-level parent-child (Option 2 in design
discussion).** Considered. Rejected because (a) AI-native
concept hygiene argument shows sub-issue is sibling-degenerate
to sprint; (b) parent Card would be non-claimable, making
"Card" two ontologically distinct things at once (aggregate
that aggregates, vs leaf work item) — protocol purity loss
not justified by use cases that Thread + Milestone +
dependencies don't already serve.

**Card hierarchy: recursive N-deep tree (Option 3).**
Considered and harder-rejected because recursive hierarchy
imports the full AI-native concept hygiene problem (sub-issue
× N levels) plus complicates state-machine reasoning,
cross-backend status-derivation, and WIP counting.

**Card hierarchy: configurable (`hierarchy_mode: flat | one-
level | recursive`).** Considered and rejected because every
skill would need to branch on hierarchy semantics, defeating
the protocol's purpose as a single agent mental model.

## Notes

- The AI-native concept hygiene argument anchored in
  `0001-positioning.md` is a sibling artifact to this ADR.
  The two land in the same PR; readers of either should be
  pointed at the other.
- Codex critique #1 (kanban lifecycle + multi-kanban) and
  #3 (card hierarchy) were performed via subagent
  adversarial review on 2026-04-28..29; their findings shape
  the post-revision design encoded here. The critiques are
  not preserved as artifacts; this ADR is the synthesis.
- **ADR-0022 needs a follow-up supersession.** Cross-impact
  analysis (2026-04-29) found that ADR-0022 (BoardAdapter
  capability dispatch + M10 BoardAdapter-selection module)
  was authored before ADR-0025 elevated the Kanban Protocol
  to top-level contract. ADR-0022's current language anchors
  M3 capability dispatch to "ADR-0005 BoardAdapter SDK
  shape," which is exactly the framing ADR-0025 supersedes.
  A separate ADR (working name ADR-0027) is queued to revise
  ADR-0022's capability-dispatch hook so M3 dispatches
  capabilities through a Kanban Protocol projection, not
  through ADR-0005's SDK surface. v0.5.0 implementation
  SHOULD treat M10's persisted backend selection as
  protocol-projection metadata, not as ADR-0005-shaped
  adapter handles.
- ADR-0014 (audit dispatch envelope + transport selection
  for v1.x scripts vs MCP question) is queued but not yet
  authored; it depends on real v1.x experience with at least
  one second-form projection. NOTE: in main, ADR-0014 is
  already taken (Stage registry contract); the v1.x audit
  dispatch ADR will get a new free number when authored.
- Card #36 (GitHubProjectAdapter wrapper port) is reframed
  by ADR-0025 + this ADR: it remains useful as a Form A
  projection refactoring task, but is no longer a
  universal-contract gate or a multi-kanban prerequisite.

## Related

- ADR-0025 — Kanban Protocol as top-level contract; this ADR
  builds on its protocol shape.
- ADR-0006 — D-AUTONOMY-1 matrix; lifecycle transitions all
  classify as R-class per its uniform v1 N=0 rule.
- ADR-0001 — Pluggable board backend; multi-kanban is a
  natural extension of substrate pluggability.
- ADR-0002 — Atomic claim via remote branch push; branch-
  naming uniformity carries forward from this ADR's git-layer
  primitive.
- ADR-0010 — AI-cadence convention; underpins the concept
  hygiene argument's quantitative claim (100× throughput).
- [`../0001-positioning.md`](../0001-positioning.md)
  § "AI-native concept hygiene" — companion section
  cataloguing all degenerate human-cadence concepts.
- [`../0005-contracts/00-kanban-protocol.md`](../0005-contracts/00-kanban-protocol.md)
  § "Multi-kanban semantics" + § "Card hierarchy" — protocol-
  document amendments encoding this ADR's decisions at the
  semantic-contract level.
- [`../../../README.md`](../../../README.md) § "Why there's no
  sprint, no sub-issue, no story points" — community-facing
  framing of the concept hygiene argument.
