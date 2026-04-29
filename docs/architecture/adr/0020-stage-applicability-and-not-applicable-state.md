# ADR 0020: Stage applicability — `applicable_when` predicate + `not-applicable` 5th lifecycle state

**Status:** proposed
**Date:** 2026-04-28
**Deciders:** PanQiWei (architect)

## Context

The unified check-script trigger model (ADR-0012) and the
declarative state schema (ADR-0013) treat every stage in the
registry (ADR-0014) as **always applicable**: the lifecycle
diffs `(generation, target_state_hash)` for every stage on
every session and emits a marker for any stage in `never-run`
or `stale`. At v0.4.0 this assumption was implicit — no
declarative way to express "this stage applies only when X."
Conditional behavior was inlined in executor scripts: M3
stages internally checked GitHub Project settings before
acting, and M3 itself hard-coded GitHub Project as the only
board backend.

Three structural problems follow from inline-in-executor
conditionality:

1. **Invisible to the lifecycle.** A stage that no-ops because
   its precondition fails still records `completed` (or
   re-runs every session if the executor is non-idempotent).
   Architect-facing summaries cannot distinguish "stage ran
   and did real work" from "stage exited 0 because its
   condition was false" — surfaces show
   "stage X completed in 0ms" for stages that did nothing.
2. **M3 is hard-coded to GitHub Project.** Per
   [`05-bootstrap-surface-redesign.md`](../0002-product-features-and-flows/05-bootstrap-surface-redesign.md)
   § "Functional modules" → M3, the redesign reframes M3 as
   "Board operations (BoardAdapter-driven)" — operations
   dispatched through the
   [ADR-0005](./0005-board-adapter-contract.md) BoardAdapter
   abstraction. M3 stages need a declarative way to
   participate only when the selected backend (chosen by
   `m10.repo.choose-kanban-backend`) declares the relevant
   capability. Without a registry-level gate, every M3 stage
   inlines a backend-name check that drifts as adapters land.
3. **No generic conditional-stage mechanism.** "Applies only
   when X" recurs across non-board-related stages — Codex-only
   stages already carry a `platforms` coarse predicate
   (ADR-0016), and future stages may gate on architect-chosen
   feature flags. A bespoke gate per recurrence is the exact
   tech debt this redesign exists to eliminate.

## Decision

The stage registry gains an **`applicable_when` predicate**
field (per ADR-0014 § "Column / field semantics"), and the
4-state lifecycle (per ADR-0013) is extended to **five
states** by adding **`not-applicable`** as a peer to
`never-run` / `completed` / `stale` / `deprecated`.

`applicable_when` is an optional per-stage field. When
present, the hook evaluates the predicate before the
generation / hash diff. The predicate has three forms:

1. **Declarative setting-path.**
   `applicable_when: {setting_path: <dot.path>, one_of: [<values>]}`.
   True when the value at `<dot.path>` in the merged settings
   (per ADR-0021 layering) is one of `<values>`. Most stages
   use this form.
2. **Declarative board-capability.**
   `applicable_when: {board_capability: <name>}`. True when
   the BoardAdapter selected by
   `m10.repo.choose-kanban-backend` declares `<name>` in its
   capability set (capability declaration on the adapter
   contract, ADR-0005, extended by ADR-0022). M3 stages use
   this form — `m3.repo.ensure-labels` declares
   `{board_capability: ensure-labels}`,
   `m3.repo.validate-status-field` declares
   `{board_capability: status-field-schema}`.
3. **Python predicate reference.**
   `applicable_when_fn: <module.callable>`. Escape hatch for
   conditions that cannot be expressed declaratively. The
   callable receives the merged settings dict and returns a
   bool. Authors are pushed toward forms 1 and 2 by the
   schema — form 3 requires a justification comment and a
   CI determinism test.

`not-applicable` is the 5th lifecycle state. Detection rule:
`applicable_when` evaluates false. Behavior: the hook **does
not emit a marker** for `not-applicable` stages and the SKILL
**does not execute** them even if invoked manually — the
lifecycle state takes precedence. If `applicable_when` later
evaluates true (architect changed the gating setting), state
flips on next session: `never-run` if no historical entry
exists, or `completed` if an entry from a prior applicable
window matches the current generation / hash. No re-prompt
for re-entry into the applicable window — the existing
entry's fingerprint is authoritative.

Predicate evaluation is **hook-side and IO-free**. Forms 1
and 2 are settings-dict lookups + small comparisons; form 3
is a pure Python call. None perform IO (no GitHub API call,
no DB query, no network egress). Evaluation MUST stay within
ADR-0012's ≤200ms hook budget — predicates that need IO are
a registry bug caught by CI.

## Consequences

### Positive

- **Conditional stages are first-class.** Backend-aware,
  feature-flag-gated, and platform-gated stages all use one
  registry field; the lifecycle surfaces them with a
  distinct state instead of hiding the condition inside an
  executor.
- **M3 hard-coding is dissolved.** `m3.repo.*` stages
  declare capability requirements; v0.5.0's
  GitHub-Project-v2 adapter declares
  `[ensure-labels, status-field-schema]` and both stages
  participate; future Linear / Jira adapters declare their
  own capability sets and M3 stages re-route automatically
  via `not-applicable`. No backend-name comparison anywhere
  in stage executors.
- **Architect-readable summaries.** Output distinguishes
  "completed" from "not-applicable (predicate false:
  kanban_backend=linear)." No more zero-work
  "completed in 0ms" rows.
- **Re-applicability is automatic.** Architect flips
  `kanban_backend` from `github-project-v2` to `linear` →
  next session the M3 stages flip from `completed` to
  `not-applicable` (entry preserved) and the new backend's
  capability stages flip from `not-applicable` to
  `never-run`. No explicit migration step.

### Negative

- **Predicate registry surface to validate.** The JSON
  Schema (ADR-0014) must reject malformed `applicable_when`
  blocks, missing `board_capability` names not declared by
  any registered adapter, and `setting_path`s that don't
  resolve in the settings schema. CI gating absorbs the
  cost.
- **`applicable_when_fn` escape hatch.** Form 3 admits
  arbitrary Python; a non-deterministic predicate (clock
  read, random) breaks lifecycle stability. Mitigation: CI
  round-trips every form 3 predicate against fixed inputs
  and asserts determinism.
- **Capability declaration becomes adapter-contract
  surface.** ADR-0005 gains a capability declaration
  mechanism (specified in ADR-0022). New adapters that
  forget to declare a capability silently make all stages
  requiring it `not-applicable` — visible in summaries but
  easy to miss. CI test asserts every shipped adapter
  declares the capability set its dependent stages need.

## Alternatives considered

### α — `applicable_when` predicate + `not-applicable` 5th state (chosen)

The decision recorded above. Single declarative mechanism;
hook-cheap; lifecycle-visible; covers board-capability,
setting-path, and escape-hatch cases under one schema.

### β — Inline-in-executor conditions (status quo at v0.4.0)

Rejected. The model the redesign exists to replace.
Conditions live inside executor scripts; lifecycle sees only
"completed" / "never-run" / "stale" and cannot surface why a
stage no-op'd. M3's hard-coded GitHub Project assumption is
v0.4.0's instance of this anti-pattern; without a
registry-level gate, every future conditional stage repeats
the mistake.

### γ — Per-backend stage families (`M3-GitHub` / `M3-Linear` / ...)

Rejected. Splitting M3 into one module per backend
duplicates the module structure for what is fundamentally
one capability surface — labels are labels regardless of
backend. The split also doesn't solve generic conditional
applicability for non-board-related stages (overrides,
Codex hook registration, feature flags), which would still
need a parallel mechanism. One mechanism handling all
conditional cases is strictly simpler than N module-family
conventions.

### δ — Always-applicable stages; let executors no-op

Rejected. Same "invisible to lifecycle" problem as β, with
added clutter in summaries ("stage X completed in 0ms" for
the no-op path) and code-duplication of the precondition
check across every executor. Predicate evaluation belongs in
one place (the hook, gating execution) not N places.

## Notes

`applicable_when` is **independent of** `platforms` (the
coarse `cc-only` / `codex-only` / `both` filter, per
ADR-0016). `platforms` is the special-cased
runtime-environment predicate; `applicable_when` is the
fine settings / capability predicate. Both must be true for
a stage to participate — a stage with `platforms: codex-only`
AND `applicable_when: {board_capability: status-field-schema}`
participates only on Codex AND only when the selected adapter
declares that capability. The composition rule lives in
ADR-0016.

The transient SKILL-only states (`failed`,
`pending-architect-input`, per ADR-0013) are orthogonal to
applicability. A stage that was `pending-architect-input`
and then becomes `not-applicable` (architect changed the
gating setting) is treated as `not-applicable` next session;
the pending entry is preserved as history but no longer
drives execution.

## Related

- [ADR-0005](./0005-board-adapter-contract.md) — BoardAdapter
  contract; the `board_capability` predicate form resolves
  through this contract's capability declaration surface
  (extended by ADR-0022).
- ADR-0012 — Unified check-script trigger model; predicate
  evaluation runs inside the hook flow defined there and
  inherits the ≤200ms budget.
- ADR-0013 — Declarative state schema + lifecycle; this ADR
  extends the 4-state lifecycle to 5 states.
- ADR-0014 — Stage registry contract; this ADR adds the
  `applicable_when` field to the column-semantics
  enumeration and JSON Schema validation.
- ADR-0016 — Cross-platform parity contract; defines
  `platforms` (coarse predicate) and the composition rule
  with `applicable_when` (fine predicate).
- ADR-0021 — Settings modular layering; settings paths
  resolved by `applicable_when: {setting_path: ...}` follow
  layering and merge semantics defined there.
- ADR-0022 — BoardAdapter capability dispatch; defines how
  adapters declare capability sets that the
  `board_capability` predicate form resolves against.
- [`../0002-product-features-and-flows/05-bootstrap-surface-redesign.md`](../0002-product-features-and-flows/05-bootstrap-surface-redesign.md)
  — Living design doc; § "Stage lifecycle states" (5-state
  table including `not-applicable`), § "Stage registry
  contract" → "Column / field semantics" (`applicable_when`
  row), § "What the lifecycle model asks of each stage" (MAY
  bullet for `applicable_when`), and § "Functional modules"
  → M3 are this ADR's authoritative references.
