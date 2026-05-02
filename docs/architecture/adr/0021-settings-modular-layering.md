# ADR 0021: Settings modular layering — two-section split + per-module schema_version

**Status:** proposed
**Date:** 2026-04-28
**Deciders:** PanQiWei (architect)

## Context

ADR-0013 declared `settings.yml` (one per non-`external`
locality) as the unified architect-facing surface and fixed
the per-stage entry shape (three-layer fingerprint:
`generation` int + `target_state_hash` + structured
`target_state`). ADR-0014 fixed the registry supplying the
target. Neither fixed the **internal layout of a settings
file**. Two questions remained:

1. Architects open `settings.yml` to *configure* the plugin
   (audit DSN, autonomy presets, kanban backend, WIP limit).
   A flat `stages_completed[]` is machine-shaped —
   fingerprints, hashes, timestamps, internal `stage_id` keys
   — so architects reading it see lifecycle bookkeeping
   instead of the few knobs that matter to them.
2. Modules evolve schemas at different cadences (M4 audit
   when a DDL column lands; M8 autonomy when preset semantics
   shift; M10 kanban when a BoardAdapter capability ships).
   Coupling them through one file-level `schema_version`
   forces co-evolution and single-moment mass migration.

Both resolve through the same move: a second top-level
section namespaced by module, with its own version axis per
module.

## Decision

Every `settings.yml` carries **two top-level data structures
plus file-level metadata** (`schema_version`,
`plugin_version`, locality-specific bookkeeping):

1. **`modules.lifecycle.<stage_id>`** (canonical lifecycle
   store, supersedes earlier `stages_completed[]` flat-list
   design) — keyed dict of per-stage lifecycle entries with
   the three-layer fingerprint per ADR-0013. **Authoritative**
   lifecycle source of truth. Hook and `_lifecycle.py` read
   `modules.lifecycle.<id>` directly (O(1) key lookup).
   Machine-managed; architects do not edit it directly.
   `bsp_stage_state_set` / `bsp_stage_state_get` in
   `scripts/lib/common.sh` are the sole write path.
2. **`modules.<id>`** — namespaced config-item projection,
   one section per Axis-C module. **Derived** view holding
   only architect-facing config items of that module's
   stages. Re-written deterministically by SKILL on stage
   completion (atomic `mktemp + mv`).

> **Schema migration note (v0.5.0):** The earlier draft of
> this ADR declared `stages_completed[]` as the authoritative
> lifecycle source-of-truth and named `modules.<id>` the
> derived projection. The implementation adopts
> `modules.lifecycle.<stage_id>` as the authoritative store
> instead. Rationale: O(1) key lookup vs O(N) flat-list scan;
> natural fit under the `modules.*` namespace; consistent with
> `common.sh` helpers and `_lifecycle.py` round-trip tests.
> The `stages_completed[]` flat list is **deprecated**;
> new code MUST NOT write to it. The template file
> (`scripts/templates/settings.repo-shared.yml`) retains
> a stub `stages_completed: []` for schema-version
> compatibility only.

Authority direction is **`modules.lifecycle.<stage_id>` →
`modules.<config-id>`**: lifecycle fingerprint entries are the
source of truth; the per-module config-item projection
regenerates deterministically on every stage completion.
Architect hand-edits to `modules.<id>` config sections are
detected on the next SKILL pass (projection vs. source
comparison) and trigger validation + re-elicitation rather
than direct mutation. Mirrors Helm `values.yaml` vs.
chart-default values — projection editing passes through the
chart's interface, not the values storage.

Each `modules.<id>` carries an independent `schema_version`
for **module-local schema migration**, decoupled from the
file-level `schema_version` (only changes when the
`modules.lifecycle` entry shape itself changes — rare,
additive only per
[`../0005-contracts/03-config-schemas.md`](../0005-contracts/03-config-schemas.md))
and from other modules (M4 bumping `m4_audit.schema_version`
does not move `m8_autonomy.schema_version`). A module schema
bump → that module's stages emit new `target_state` shape →
`target_state_hash` changes → ADR-0013's lifecycle flips them
to `drifted` → SKILL re-runs with structural diff messages.

Module section keys follow `m{number}_{snake_case_name}`
(e.g., `m4_audit`, `m7_routing`, `m8_autonomy`,
`m10_kanban`) — number prefix preserves Axis-C module
identity, snake-case suffix is architect-readable, ADR-0014's
JSON Schema gate enforces it at load time. The per-stage
registry field `module_section_path` (ADR-0014) names the
dotted path under `modules.` where projection lands; SKILL
writes both `modules.lifecycle.<stage_id>` (lifecycle entry)
and `modules.<path>` (config projection) synchronously on
completion.

**Future-module inclusion procedure.** When plugin v(N+1)
introduces a new module, three artifacts change and **no
SKILL or hook code does**: (1) add stages to
`scripts/stages-registry.yml` under unique `stage_id`s
(`m11.host.*` etc.); (2) define the projection schema in
`scripts/stages-registry.schema.json` under
`definitions/modules/m11_<name>`; (3) implement per-stage
callables in `scripts/stages_lib/<stage_id>.py`. Registry-only
edits are the **only** supported path for new architect-facing
features — any module bypassing this re-introduces the
bespoke per-feature UX cost the redesign exists to eliminate.

## Consequences

### Positive

- **Architect read path is clean.** `modules.<id>` surfaces
  the few knobs architects edit; lifecycle bookkeeping in
  `modules.lifecycle` sits below the fold, labeled
  machine-managed. One physical file serves both roles.
- **Module schemas evolve independently.** M4 DDL bumps move
  only `m4_audit.schema_version`; M8 autonomy evolves its
  own. No file-wide migration cascade.
- **Single authority eliminates drift.** With
  `modules.lifecycle` authoritative, the projection cannot
  silently diverge — SKILL's next pass detects manual edits
  to `modules.<id>` config sections and forces resolution.
- **Future-module path is registry-only.** Three artifacts
  change; SKILL bodies and hook code stay untouched. The
  pluggable-module promise becomes architecturally enforced
  rather than convention-dependent.
- **Mirrors mature industry pattern.** VSCode `settings.json`
  (prefix-namespaced — `editor.x` / `python.x` / `git.x`),
  Helm `values.yaml` (chart-namespaced sections), Kubernetes
  API groups, Cargo features / Bazel BUILD files all
  converge on the same shape.

### Negative

- **Two writes per stage completion.** SKILL writes both
  `modules.lifecycle.<stage_id>` and `modules.<id>` atomically
  — a few extra YAML lines plus a projection-rebuild step;
  negligible at this file size.
- **Hand-edit divergence detection adds a SKILL step.** Every
  re-entry compares projection vs. source-of-truth and
  prompts on divergence. The alternative (silent
  re-derivation overwriting architect edits) is worse.
- **Module naming convention is one more rule.**
  `m{number}_{snake_case}` adds discipline overhead;
  mitigated by ADR-0014's JSON Schema gate at PR time.

## Alternatives considered

### α — Two-section split + per-module `schema_version` (chosen)

Single file, two sections, one authoritative + one derived,
per-module schema axis. Matches VSCode / Helm / K8s industry
pattern.

### β — Single flat structure (no module sections)

Rejected. Mixes machine view (lifecycle fingerprints) with
architect view (config items) — architects mentally filter
lifecycle bookkeeping out of every read. Module schema
migration also collapses onto the file-level `schema_version`,
forcing co-evolution when any one bumps. The v0.4.0 `state.yml`
carried this shape; the redesign exists in part to fix it.

### γ — Multi-file (one settings file per module per locality)

Rejected. Splitting by module yields ~10 modules × 4 localities
= 40 settings files for a fully-bootstrapped repo. IDE
navigation, `grep` across configuration, and human reading all
suffer at that fan-out; cross-module reads become multi-file
aggregations instead of single-file scans.

### δ — Make `modules.<id>` authoritative + derive `stages_completed[]`

Superseded by the chosen approach: `modules.lifecycle.<id>`
IS the authoritative lifecycle store under the `modules.*`
namespace. The earlier concern that putting fingerprints under
`modules.<id>` would "pollute the architect view" is resolved
by reserving the `lifecycle` key as machine-managed (not
an Axis-C config module). The deprecated `stages_completed[]`
flat list is the alternative this approach replaces.

## Notes

Second of two structural moves giving the redesign its
architect-facing shape: ADR-0013 partitioned the file family
by locality; this ADR fixes each file's internal layout.
Together they deliver "one mental model, one filename
family, one in-file shape" across all four non-`external`
localities. The default `module_section_path` (derive
`modules.<m{N}_{name}>` from the stage's Axis-C `module`
field) is sufficient for v1; the field exists for the rare
case where a stage projects into a sibling module's section
(none at v1).

## Related

- [ADR-0013](./0013-declarative-state-schema-and-lifecycle.md)
  — Per-stage entry shape this ADR places into
  `modules.lifecycle.<stage_id>`.
- [ADR-0014](./0014-stage-registry-contract.md) — Defines
  `module_section_path` and the JSON Schema gate validating
  the module naming convention at load time.
- ADR-0012 — Unified check-script trigger model. Hook reads
  Section 1 only; the projection (Section 2) is never read
  by the hook.
- ADR-0017 — I-13 invariant revision; per-locality file
  partitioning relies on the `(host, GitHub repo)`
  repo-identity scheme.
- [`../0002-product-features-and-flows/05-bootstrap-surface.md`](../0002-product-features-and-flows/05-bootstrap-surface.md)
  § "Declarative state schema" → "Settings modular layering"
  / "Why both sections" / "Per-module schema versioning" /
  "Module naming convention" / "Future-module inclusion
  procedure" — authoritative references.
- [`../0005-contracts/03-config-schemas.md`](../0005-contracts/03-config-schemas.md)
  — Migration policy (versioned-and-additive, lazy-on-read)
  per-module `schema_version` evolution inherits.
