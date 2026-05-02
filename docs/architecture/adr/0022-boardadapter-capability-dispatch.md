# ADR 0022: BoardAdapter capability dispatch (M3 stages route via BoardAdapter capabilities) + M10 BoardAdapter-selection module

**Status:** proposed; § M3 capability dispatch superseded by ADR-0027 (M3 dispatches via Kanban Protocol projection, not BoardAdapter SDK); § M10 module existence preserved (canonical stage name renamed per ADR-0027 § 4)
**Date:** 2026-04-28
**Deciders:** PanQiWei (architect)

## Context

[ADR-0005](./0005-board-adapter-contract.md) committed the
BoardAdapter contract as the seam every backend (GitHub Project
v2, future Linear / Jira) must implement against. ADR-0005's
own Notes call out the honesty gap: the contract ships as
design intent, but the reference implementation is not yet
refactored to call through a `BoardAdapter` interface.

At v0.4.0 the bootstrap surface concretizes that gap. The two
M3 stages — `m3.repo.ensure-labels` and
`m3.repo.validate-status-field` — inline `gh` CLI invocations
directly in their executor scripts. The stage registry has no
notion of which backend the repo uses; both stages run
unconditionally on every bootstrapped repo and silently presume
GitHub Project v2. Three implicit assumptions fall out: backend
identity is fixed (nothing records the architect's choice or
dispatches on it); stages own backend knowledge ("swap in a
Linear adapter" requires editing every M3 stage's executor);
and there is no skip path for non-applicable backends.

The bootstrap-surface redesign
([`../0002-product-features-and-flows/05-bootstrap-surface.md`](../0002-product-features-and-flows/05-bootstrap-surface.md))
closes this gap with two structural shifts: the `not-applicable`
lifecycle state (per ADR-0020) gives stages a clean skip path,
and the `applicable_when` predicate field on the stage registry
lets each stage declare its conditions declaratively. M3 needs
a predicate vocabulary and a selection seam to turn ADR-0005's
"design intent" into a runtime dispatch surface.

## Decision

Two coupled additions land together:

**(1) New module M10 — BoardAdapter selection.** A standalone
module whose sole stage `m10.repo.choose-kanban-backend`
(agentic, `repo-git` locality, `confirm-only` flag) elicits the
architect's choice of board backend at first-time bootstrap and
persists it into the repo-git settings file. The v0.5.0 enum
contains exactly one option, `github-project-v2` (single-choice
confirmation). Future `linear` / `jira` options land via
registry-only enum extension; each option's `introduced_in`
metadata gates re-prompt so existing repos are not asked again
when the enum grows.

**(2) M3 stages re-architect to dispatch through BoardAdapter
capabilities.** The M3 module is renamed "Board operations
(BoardAdapter-driven)". Each M3 stage carries an
`applicable_when: {board_capability: <name>}` predicate (the
declarative capability-check form added per ADR-0020). Each
BoardAdapter implementation declares which capabilities it
supports — the v0.5.0 GitHub-Project-v2 adapter declares
`[ensure-labels, status-field-schema]`, exactly matching the
two shipped M3 stages. The evaluator resolves each predicate
by looking up M10's recorded `kanban_backend`, finding the
matching adapter, and asking whether the named capability is
declared. M3 stages depend on `m10.repo.choose-kanban-backend`
so the backend is selected before any board operation runs.

Concretely: each M3 stage's executor calls
`BoardAdapter.<capability>()` instead of inline `gh` commands —
the v0.5.0 GitHub-Project-v2 adapter delegates internally to
`gh`; future adapters delegate to their own backends; the stage
code knows nothing about backend identity. A future Linear
adapter declaring `[ensure-labels]` only would let
`m3.repo.ensure-labels` run normally while
`m3.repo.validate-status-field` evaluates `applicable_when` to
false → returns `not-applicable` per ADR-0020 → silently
skipped (no marker, no executor invoked). An adapter declaring
neither capability turns the entire M3 module into a no-op for
that repo, with the skip reason visible in the lifecycle audit.

## Consequences

### Positive

- **ADR-0005 becomes a runtime dispatch surface, not just a
  design-intent contract.** M3 executors call into the
  `BoardAdapter` interface; a second-adapter author has a
  concrete dispatch entry point (the `applicable_when`
  predicate plus the per-capability method) to implement
  against.
- **Adding a new backend is purely declarative.** A new adapter
  registers in the M10 enum and declares its capability set; no
  M3 stage edits required. Capability-matching scales with
  adapter count, not stage count.
- **Skip surfaces are observable.** `not-applicable` states
  produced by capability mismatch flow through the same
  lifecycle audit as any other state per ADR-0020 — the skip
  reason is visible in bootstrap summaries.
- **M3 module name now matches its character.** Rename from the
  implicit "GitHub Project v2 operations" to "Board operations
  (BoardAdapter-driven)" eliminates v0.4.0 naming debt.

### Negative

- **One additional agentic stage at first-time bootstrap.** The
  architect now confirms a single-choice prompt
  (`m10.repo.choose-kanban-backend`) that has only one option
  at v0.5.0 — the seam exists for future expansion but at
  v0.5.0 adds one extra interaction with no visible payoff.
  Mitigated by treating it as a confirmation, not a decision
  (default pre-selected; press enter).
- **Capability declarations become a contract surface.** Adding
  or renaming a capability requires coordinated edits across
  every adapter declaring it and every M3 stage requiring it.
  ADR-0005 supersession governs vocabulary changes; per-adapter
  capability lists follow the same immutability discipline as
  the contract surface.
- **`applicable_when` evaluator depends on M10 having run.**
  Encoded as `depends_on: [m10.repo.choose-kanban-backend]` on
  every M3 stage — ADR-0012's topological executor enforces
  ordering.

## Alternatives considered

**Per-backend stage families (`M3-GitHub` / `M3-Linear` /
`M3-Jira` as separate modules).** Rejected. The registry gains
N row families for one operational surface every time a backend
is added — N independently-drifting codebases, the exact tech
debt the redesign eliminates elsewhere (per ADR-0012's
single-mechanism principle). Capability dispatch keeps M3 one
module and shifts variance into the adapters where it belongs.

**Backend-name matching via
`applicable_when: {kanban_backend: github-project-v2}`.**
Rejected. Couples the stage definition to backend identifiers —
a future Linear adapter would require editing every M3 stage's
`applicable_when` to add `linear` to the allowed list, even
when Linear happens to support the same operation.
Capability-matching inverts the dependency: adapters declare
what they can do; stages declare what they need; the predicate
resolves through that declaration. New adapters add capability
declarations, never stage edits.

**Inline backend dispatch in the executor (status quo at
v0.4.0).** Rejected. Per ADR-0020's argument that
`not-applicable` must surface through the lifecycle, hidden
dispatch means the lifecycle cannot distinguish "ran and
succeeded" from "skipped because inapplicable" — no skip
reason, no audit entry, no surfacing in bootstrap summaries.
Pushing backend-conditional behavior into the executor hides it
from every observation surface the redesign exists to produce.

**Bake capability declaration into ADR-0005 method
signatures.** Considered. ADR-0005 could declare a
`capabilities` enum on the BoardAdapter base class itself.
Rejected as out-of-scope — ADR-0005 is immutable-modulo-
supersession and the v1 contract surface is intentionally small.
The capability mechanism lives in the adapter implementation
layer (each adapter exposes `get_capabilities() -> set[str]`)
and is consulted by the `applicable_when` evaluator, not by
the public method surface. A future supersession candidate once
second-adapter experience informs the right vocabulary.

## Notes

- Capability vocabulary at v0.5.0 is two strings
  (`ensure-labels`, `status-field-schema`), matching M3 stages
  1:1 because v0.5.0 has only the GitHub-Project-v2 adapter.
  Registry-internal — no external surface depends on it — so
  renames are cheap until a second adapter ships.
- M10's single-option enum at v0.5.0 is intentional: the
  agentic prompt + persisted-choice infrastructure ships now;
  enum width is what future ADRs expand. Shipping the seam at
  width-1 makes width-2 a registry-only edit later.
- The M3-executor refactor (inline `gh` → `BoardAdapter`
  calls) is bundled with ADR-0005's wrapper-port commitment
  ("wrapper port lands before v1 GA"). This ADR formalizes the
  dispatch surface; the wrapper-port PR delivers the
  implementation.

## Related

- [ADR-0005](./0005-board-adapter-contract.md) — The
  BoardAdapter contract this ADR turns into a runtime dispatch
  surface; capability declarations layer on top of the v1
  method surface without altering it.
- ADR-0001 — Pluggable board backend; the architectural
  commitment this ADR makes observable at runtime.
- ADR-0020 — Stage applicability + `not-applicable` lifecycle
  state; defines the predicate forms (including the
  declarative capability-check form) and the surfacing
  semantics this ADR's M3 stages depend on.
- ADR-0012 — Unified check-script trigger model; the
  topological executor that honors the
  `depends_on: [m10.repo.choose-kanban-backend]` edge.
- ADR-0013 / ADR-0014 — Lifecycle state schema + stage
  registry contract; carry the `applicable_when` field
  populated on M3 rows.
- [`../0002-product-features-and-flows/05-bootstrap-surface.md`](../0002-product-features-and-flows/05-bootstrap-surface.md)
  — Living design doc; § "Functional modules" M3 + M10 and
  § "Stages" M3 + M10 rows are this ADR's authoritative
  reference.
