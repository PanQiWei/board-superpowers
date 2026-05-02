# ADR 0027: M3 capability dispatch via Kanban Protocol projection (supersedes ADR-0022 § M3)

**Status:** accepted
**Date:** 2026-04-29
**Deciders:** PanQiWei (architect)

## Context

[ADR-0022](./0022-boardadapter-capability-dispatch.md) (status:
`proposed`) established the M3 stages dispatch via **BoardAdapter
capabilities**: each M3 stage carries
`applicable_when: {board_capability: <name>}`, each BoardAdapter
implementation declares `get_capabilities() -> set[str]`, and stage
executors call `BoardAdapter.<capability>()` SDK methods. ADR-0022
was authored before [ADR-0025](./0025-kanban-protocol-as-top-contract.md)
elevated the **Kanban Protocol** ([`docs/architecture/0005-contracts/00-kanban-protocol.md`](../0005-contracts/00-kanban-protocol.md))
to top-level contract and rescoped ADR-0005's BoardAdapter SDK to
"the v1 GitHubProjectAdapter projection's shape" rather than "the
universal contract every backend implements."

Three downstream consequences make ADR-0022's § M3 dispatch model
incompatible with the post-ADR-0025 architecture:

1. **Vocabulary ownership shifted.** "BoardAdapter capability" is
   anchored in ADR-0005's now-rescoped contract surface. Continuing
   to dispatch M3 through this vocabulary couples bootstrap stages
   to a layer ADR-0025 explicitly demoted to "one projection's
   shape" rather than "the universal contract." Every projection
   landing — not just second-adapter ports — would have to opt in
   or opt out of an SDK shape it doesn't naturally inhabit.

2. **Dispatch shape mismatch.** ADR-0022's executor model — "stage
   code calls `BoardAdapter.<capability>()` directly" — assumes
   function-table dispatch. The Kanban Protocol surfaces backend
   behavior through projection reference files (under
   `skills/operating-kanban/references/<backend>.md`) and Form A
   (bash CLI) / Form B (plugin-shipped MCP server) / Form C
   (REST/GraphQL) invocation conventions, not through compiled
   method dispatch. M3 stages would either re-implement projection
   routing inline at every executor (drift risk) or fail to
   dispatch correctly when a non-Form-A projection (Linear via
   Form B MCP, future Form C REST) ships.

3. **Module naming reflects framing.** ADR-0022 names the M10
   module **"BoardAdapter-selection"** and the stage
   `m10.repo.choose-kanban-backend` (per
   [ADR-0024](./0024-settings-rename-and-config-item-stages.md)
   § Part B). The artifact M10 actually persists is **the active
   Kanban Protocol projection's identifier**, not "an instance of
   an SDK class." Naming inertia would lock the framing to
   ADR-0022's superseded vocabulary across migrations and
   second-projection ports.

#67 (setup-stages v1-complete) is in flight as paired-PR
counterpart and explicitly cites ADR-0022 in its AC-6. Both PRs
cannot ship without converging on a single dispatch model — and
the dispatch model belongs in the protocol layer (this ADR's
authority), not the stage-implementation layer (#67's body). #68
authors this ADR; #67 rebases per the paired-PR contract
documented in #68 AC8 + AC9.

## Decision

**ADR-0022 § M3 (capability dispatch + stage executor model) is
superseded by this ADR.** ADR-0022 § M10 *existence* (a stage that
elicits + persists architect's projection choice) remains in force,
with the canonical stage name amended per § 4 below. ADR-0022's
text is NOT rewritten; only its status header gains the
supersession note.

The replacement model has four parts:

### 1. Capability vocabulary anchored to Kanban Protocol projection

Each Kanban Protocol projection (currently only `github-project-v2`;
future `linear`, `jira`, etc.) declares its **setup capabilities**
in its reference file under
`skills/operating-kanban/references/<projection-id>.md` § "Setup
capabilities". A capability is a free-form lowercase-kebab-case
string identifying a setup operation the projection supports —
v0.5.0 `github-project-v2` declares `[ensure-labels,
validate-status-field]`, matching the two M3 stages shipped per
ADR-0022.

The capability vocabulary is registry-internal — no external surface
depends on it — so renames are cheap until a second projection
ships and pins one. The vocabulary's *owner* is the Kanban
Protocol projection layer; the *consumer* is M3's predicate
evaluator (§ 2 below). Neither references ADR-0005's SDK shape.

### 2. M3 stage predicate

M3 stages declare:

```yaml
applicable_when:
  kanban_projection_capability: <capability-name>
```

(was, per ADR-0022:
`applicable_when: {board_capability: <capability-name>}`.)

The predicate evaluator:

1. Reads
   `<repo>/.board-superpowers/settings.yml § modules.m10_kanban.<kanban-id>.projection`
   — the active projection's identifier (set by M10 stage at
   first-time bootstrap; field name is protocol-anchored per
   [ADR-0026](./0026-multi-kanban-lifecycle-and-flat-card-hierarchy.md)
   § Multi-kanban schema).
2. Loads `skills/operating-kanban/references/<projection-id>.md`
   § "Setup capabilities" — the declared capability set.
3. If the named capability is in the declared set: predicate
   evaluates **true** → stage runs.
4. Otherwise: predicate evaluates **false** → stage returns
   `not-applicable` per [ADR-0020](./0020-stage-applicability-and-not-applicable-state.md).

The predicate's mechanism (declarative capability check + skip via
`not-applicable`) is unchanged from ADR-0022; the *vocabulary
ownership* shifted from ADR-0005's BoardAdapter SDK to the
Kanban Protocol projection layer.

### 3. M3 stage executor invocation

M3 stage executors **invoke the projection's setup procedure**
documented in the projection's reference file under § "Setup
capabilities" → `<capability-name>` subsection. The reference
file specifies, per Form:

- **Form A (bash CLI)** — the exact `gh` / `linear` / future
  CLI invocation, with stdin/stdout/exit-code conventions.
- **Form B (plugin-shipped MCP server)** — the exact MCP tool
  call pattern, including `userConfig.sensitive` lookup and the
  tool's expected response shape.
- **Form C (REST/GraphQL)** — the exact HTTP request shape
  including auth header derivation and response parsing.

The stage executor reads the projection's reference at evaluation
time and dispatches per the form. M3 stages **no longer call
`BoardAdapter.<capability>()` SDK methods**. The
`operating-kanban` atomic SKILL (lands v0.5.0 with this ADR per
#68 AC3) is the runtime owner of the per-projection reference
files — its `references/<backend>.md` files are the projections'
setup procedures, and its dispatch logic is the integration
point.

ADR-0022's executor refactor commitment ("inline `gh` →
`BoardAdapter` calls") is replaced by: "inline `gh` →
`operating-kanban` projection-routed setup invocation". The
operational outcome is identical for the v0.5.0
`github-project-v2` projection (the same `gh` calls happen at
the same times); the *dispatch path* is via the projection's
reference file, not via an SDK method.

### 4. M10 module renamed

M10's canonical stage name is **`m10.repo.choose-kanban-projection`**
(was: `m10.repo.choose-kanban-backend` per ADR-0024 + ADR-0022 —
both anchored to the BoardAdapter SDK shape). The settings.yml
field name remains `modules.m10_kanban.<kanban-id>.projection`
(already protocol-anchored per ADR-0026 § Multi-kanban schema —
no change required there).

The user-facing prompt updates:

- Was (per ADR-0022 + ADR-0024 § Part B): "Choose the kanban
  backend used in this repo..."
- Now: "Choose the kanban projection used in this repo..."

The single-option v0.5.0 enum remains `github-project-v2`. Future
v1.x adapter ships add `linear`, `jira`, etc. — same as ADR-0022's
roadmap, just under the new vocabulary. ADR-0024's M10 stage
definition is amended in-place to reflect the rename (the rename is
strictly additive — every `backend` reference becomes `projection`,
no semantic change). The amendment is recorded in ADR-0024's status
header per § Notes below.

## Consequences

**What this enables:**

- **The Kanban Protocol becomes the only top-level contract M3
  dispatches against.** Adding a new projection (Linear via
  Form B MCP, Jira, future Form C REST) is a single-edit
  operation: drop a reference file under
  `skills/operating-kanban/references/<new-projection>.md`
  declaring the capability set + invocation forms. M3 stages
  auto-route to the new projection without source edits.
- **The dispatch model survives Form A/B/C heterogeneity.**
  Form A bash projections, Form B plugin-shipped MCP projections,
  and Form C REST/GraphQL projections all expose their setup
  procedure through their reference file's text — the stage
  executor reads the form and dispatches uniformly. ADR-0022's
  SDK-method dispatch could not have done this without per-form
  SDK shape proliferation.
- **#67's AC-6 implementation has a citable model.** #67's M3
  stages can implement
  `applicable_when: {kanban_projection_capability: <name>}` per
  this ADR; the M10 stage's canonical name and the persisted
  field are both protocol-anchored. The paired-PR contract per
  #68 AC8 + AC9 is satisfiable by mechanical edits.
- **`operating-kanban` SKILL's role becomes load-bearing across
  bootstrap AND runtime.** Beyond the originally-planned runtime
  read of `modules.m10_kanban` (per ADR-0026), the SKILL now
  also owns the bootstrap-side projection-setup-capability
  registry. Both responsibilities live in the same atomic SKILL
  per the SPOT discipline.

**What this constrains:**

- **`operating-kanban` SKILL must land same-PR as this ADR's
  downstream implementation.** The SKILL's `references/<backend>.md`
  files are the projection's authoritative setup-capability
  declarations; without them, the predicate evaluator has nothing
  to read. (Same-PR contract holds in #68 — the v0.5.0
  implementation card.)
- **#67's M3 stage implementations land per this ADR, not per
  ADR-0022.** Paired-PR contract per #68 AC8 + AC9. #67's M10
  stage uses the new canonical name; #67's M3 stages use the
  new predicate vocabulary; #67's `bootstrapping-repo` SKILL
  rewrite (its AC-4) routes board reads through
  `operating-kanban` rather than direct script invocations.
- **Capability-vocabulary changes affect every projection's
  reference file.** Renaming a capability requires synchronized
  edits across `skills/operating-kanban/references/*.md`. The
  discipline is no different from any other registry-internal
  vocabulary; the same-PR rule applies via the change-impact
  matrix in [`docs/architecture/AGENTS.md`](../AGENTS.md).
- **ADR-0024's M10 stage canonical name is amended.** Per § 4
  above + § Notes below, ADR-0024 gains a status-header
  redirection to this ADR for the M10 stage canonical name.
  The amendment is strictly additive (the field name and stage
  semantics are unchanged; only the user-facing canonical
  identifier renames).

**What this rules out:**

- **`BoardAdapter.<capability>()` SDK calls in M3 stage
  executors.** Pre-#68 M3 stage code (proposed in ADR-0022) MUST
  be rewritten to dispatch through the projection's reference
  file before #67 merges.
- **Per-stage M10 projection selection.** M10 elicits and
  persists ONE projection per kanban; M3 stages dispatch through
  the recorded projection per kanban. No per-stage projection
  override.
- **Inline backend dispatch in M3 stage executors.** The
  projection's reference file is the canonical site of dispatch
  logic; replicating it inline in any M3 stage's executor is a
  contract violation.
- **Cross-anchoring of M3 dispatch to ADR-0005.** ADR-0005's
  BoardAdapter contract surface remains valid as the v1
  GitHubProjectAdapter projection's shape (per ADR-0025), but it
  is no longer the dispatch authority for M3. Future
  projections do NOT inherit ADR-0005's SDK shape.

## Alternatives considered

**Keep ADR-0022 as-is; layer ADR-0027 only on top-of-stack
guidance.** Considered. Rejected because ADR-0022's
`BoardAdapter.<capability>()` executor model is incompatible
with Form B / Form C projections; "guidance to use the
projection layer where convenient" leaves the dispatch model
unsound for non-bash backends. Supersession is structural, not
stylistic.

**Inline supersession into ADR-0022 (rewrite ADR-0022's text
rather than create a new ADR).** Considered. Rejected because
ADR discipline (per
[`adr/README.md`](./README.md)) treats ADRs as
immutable once accepted; ADR-0022 is `proposed`, not `accepted`,
but supersession-via-rewrite still erases the historical record
of why ADR-0025's elevation made the M3 dispatch model
untenable. New ADR + status-header redirection on ADR-0022
preserves the audit trail.

**Keep "BoardAdapter capability" vocabulary; rename internally
only.** Considered. Rejected because the vocabulary's
*anchoring* is the problem — "BoardAdapter" presumes ADR-0005
SDK shape. Renaming the *strings* without retiring the
*concept* leaves the framing unchanged. Supersession of the
dispatch model demands new vocabulary anchored to the Kanban
Protocol projection layer.

**Defer M3 dispatch redesign to v1.x (after #67 ships per
ADR-0022).** Considered. Rejected because the v1-complete
release gate doctrine forbids shipping a v1-minimum workaround.
ADR-0022's model is exactly such a workaround — it would be
retired the moment a non-Form-A projection ships, which the
v1.x roadmap commits to.

**Move dispatch into a new SKILL separate from
`operating-kanban`.** Considered. Rejected because the SPOT
discipline (per [`SKILLS.md`](../../../SKILLS.md) "Atomic-layer
boundary discipline") consolidates "how to act on the active
backend" into one atomic SKILL. Splitting bootstrap-side
setup-capability dispatch from runtime-side action dispatch
into two atomic SKILLs would force every projection to update
two reference-file trees on every change.

## Notes

- This ADR ships in the same PR (#68) as `operating-kanban`
  SKILL's first landing (#68 AC3) and the v0.5.0 board-canon
  patch (#68 AC2). Per #68 AC8 + AC9, #67 (setup-stages
  v1-complete) rebases on post-#68 main and re-anchors its
  M3 stage implementation + M10 module renaming to this ADR.
- **ADR-0022's status header is amended (in-place) to:**
  `proposed; § M3 capability dispatch superseded by ADR-0027 (M3
  dispatches via Kanban Protocol projection, not BoardAdapter
  SDK); § M10 module existence preserved (canonical stage name
  renamed per ADR-0027 § 4)`. The original Decision text is
  preserved (rescoped in interpretation, not redacted) so
  historical readers see ADR-0022's original framing and how
  ADR-0025's elevation forced this revision.
- **ADR-0024's status header is amended (in-place) to:**
  `proposed; § Part B M10 stage canonical name renamed by
  ADR-0027 § 4 (m10.repo.choose-kanban-backend →
  m10.repo.choose-kanban-projection; settings.yml field name
  unchanged)`. The amendment is strictly additive.
- **#67 explicitly anticipated this ADR.** ADR-0026's Notes
  section names "ADR-0027" as the queued supersession; this ADR
  fulfils that prediction. ADR-0026's forward reference does NOT
  need rewriting — it becomes a backward reference once this ADR
  lands, which is correct ADR discipline.
- **ADR-0026's status header is amended (in-place) to:**
  `accepted; § "Multi-kanban semantics" schema field name
  amended in #68 — modules.m10_kanban.<id>.backend renamed to
  modules.m10_kanban.<id>.projection (per ADR-0027 § Decision 4
  vocabulary anchor; semantic unchanged)`. The amendment is
  strictly additive — only the field name renames; the schema
  shape and lifecycle semantics in ADR-0026's Decision sections
  carry forward unchanged.
- The capability vocabulary at v0.5.0 is two strings
  (`ensure-labels`, `validate-status-field`), matching the M3
  stages 1:1 because v0.5.0 has only the `github-project-v2`
  projection. ADR-0022's exact same vocabulary carries forward
  — the *anchoring* changes, not the *capability names*.
- Future `linear` / `jira` projections add their setup
  capabilities under their own reference files; ADR-0022's
  prediction that "a future Linear adapter declaring
  `[ensure-labels]` only would let `m3.repo.ensure-labels` run
  normally while `m3.repo.validate-status-field` evaluates
  `applicable_when` to false → returns `not-applicable`" holds
  unchanged under this ADR's framing.

## Related

- [ADR-0022](./0022-boardadapter-capability-dispatch.md) — this
  ADR's supersession target for § M3; § M10 existence preserved
  with name amended per § 4.
- [ADR-0024](./0024-settings-rename-and-config-item-stages.md)
  — M10 stage definition (canonical name amended in-place per
  this ADR's § 4).
- [ADR-0025](./0025-kanban-protocol-as-top-contract.md) — Kanban
  Protocol as top-level contract; the layer this ADR's dispatch
  model is anchored to.
- [ADR-0026](./0026-multi-kanban-lifecycle-and-flat-card-hierarchy.md)
  — Multi-kanban + flat hierarchy; the
  `modules.m10_kanban.<id>.projection` field name this ADR's
  predicate evaluator reads.
- [ADR-0020](./0020-stage-applicability-and-not-applicable-state.md)
  — Stage applicability + `not-applicable` lifecycle state; the
  predicate-evaluation framework this ADR's
  `kanban_projection_capability` predicate plugs into.
- [ADR-0005](./0005-board-adapter-contract.md) — v1
  BoardAdapter contract surface; rescoped to v1
  GitHubProjectAdapter projection per ADR-0025; this ADR
  confirms the dispatch-layer separation from ADR-0005's
  vocabulary.
- [ADR-0010](./0010-re-anchor-deadlines-ai-cadence.md) —
  AI-cadence convention; underpins the v1-complete-release-gate
  doctrine that motivates this ADR's existence (vs. deferring
  to v1.x).
- [`0005-contracts/00-kanban-protocol.md`](../0005-contracts/00-kanban-protocol.md)
  — The Kanban Protocol document; § "Setup capabilities" is
  the projection-authoring contract for setup-capability
  declaration when v0.5.0 protocol-document amendment lands.
- [`skills/operating-kanban/`](../../../skills/operating-kanban/)
  — Per-projection setup-capability reference (lands v0.5.0
  with #68 AC3); the runtime owner of the dispatch.
- [`docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md`](../0002-product-features-and-flows/05-bootstrap-surface.md)
  § "Modules" M3 / M10 — #67 paired-PR rebase target; #67's
  Phase 3 M3 + M10 stage implementations land per this ADR.
- [`SKILLS.md`](../../../SKILLS.md) § "Atomic-layer boundary
  discipline" — the `operating-kanban` × `board-canon` split
  that supports this ADR's dispatch model.
