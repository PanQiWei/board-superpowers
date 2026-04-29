# ADR 0013: Declarative state schema + 5-state lifecycle + K8s-style three-layer fingerprint

**Status:** proposed
**Date:** 2026-04-28
**Deciders:** PanQiWei (architect)

## Context

Today's bootstrap mechanism (per
[`../0002-product-features-and-flows/05-bootstrap-surface.md`](../0002-product-features-and-flows/05-bootstrap-surface.md))
infers completion from file presence — "is bootstrapped" =
"`manifest.yml` exists with valid `schema_version`". Per
[`05-bootstrap-surface-redesign.md`](../0002-product-features-and-flows/05-bootstrap-surface-redesign.md)
§ "Why a redesign" item 1, this implicit-state model has three
structural costs: no sub-step granularity (interruption
recovery relies on per-executor idempotency hacks), no
cross-version drift detection (a plugin upgrade that changes a
stage's expected target leaves the file present and the system
thinks the repo is current), and no declarative migration seam
(F-B3 / F-B4 version transition needs a "what changed between
version N and N+1" primitive that file-presence cannot supply).

ADR-0012 collapses bootstrap and migration into a single "diff
current vs target, run the missing or stale parts" mechanism.
That decision is only realizable if state is declarative —
explicit `{stage_id, status, fingerprint, target_state}`
entries — and if "current vs target" is cheap enough to run
on every `SessionStart` hook (≤200ms budget per ADR-0012). Per
design doc § "Goals" → G3 state must also be independent of
repo on-disk path so a fresh clone of the same
`(host, GitHub repo)` sees a consistent snapshot. ADR-0014
records the registry contract that supplies the target state;
this ADR records the *recorded state* shape and the lifecycle
that compares the two.

## Decision

Bootstrap progress is recorded declaratively as per-stage
entries in partitioned status files. Each entry carries a
**three-layer fingerprint** — `generation` integer
(fast-path) + derived `target_state_hash` (verification) +
structured `target_state` (ground truth) — that the unified
check script (ADR-0012) compares against the stage registry
(ADR-0014) to compute one of five lifecycle states.

The five states (per design doc § "Stage lifecycle states"):

- **`never-run`** — no entry exists for this `stage_id` AND
  the stage's `applicable_when` predicate (per ADR-0020) is
  true (or absent).
- **`completed`** — entry exists; recorded `generation` and
  `target_state_hash` both match the current registry.
- **`stale`** — entry exists; `generation` differs (maintainer
  bumped it) OR `target_state_hash` differs (semantics changed
  without a bump). SKILL re-runs; structural diff between
  recorded and current `target_state` surfaces diagnostics.
- **`deprecated`** — recorded `stage_id` no longer appears in
  the current registry. Entry preserved as history.
- **`not-applicable`** — the stage's `applicable_when`
  predicate evaluates false against current settings (per
  ADR-0020). Hook does not emit a marker; SKILL does not
  execute. State flips back to `never-run` (no historical
  entry) or `completed` (prior applicable-window entry exists)
  when the predicate later evaluates true.

Plus two **transient SKILL-only states** the SKILL writes
mid-flow and the lifecycle treats as effectively `never-run`:
`failed` (executor returned non-zero, `last_error` recorded)
and `pending-architect-input` (agentic stage waiting for
architect response).

Per design doc § "Per-stage entry shape", each entry is:

```yaml
- stage_id: m4.repo.apply-audit-ddl
  status: completed
  completed_at: 2026-04-28T14:23:12Z
  plugin_version: v0.5.0
  generation: 7                    # Layer 1 — registry-bumped int
  target_state_hash: d4e5f6...     # Layer 2 — sha256(canonical target_state)
  target_state:                    # Layer 3 — structured ground truth
    audit_log: { schema_version: 2, columns_required: [event_id, ...] }
  target_state_schema_version: 1
  last_error: null
```

The three layers map onto the check loop:

1. **Layer 1 — `generation` int compare** (O(1)). Hook reads
   `entry.generation == registry[stage_id].generation`; if
   equal, skip without further work. Borrowed directly from
   Kubernetes' `metadata.generation` /
   `status.observedGeneration` pattern.
2. **Layer 2 — `target_state_hash` compare** (O(YAML emit)).
   Catches the failure mode where a maintainer changed
   `target_state` semantics without bumping `generation`.
3. **Layer 3 — structured `target_state` diff** (deep-equality,
   O(state size)). Never read by the hook; invoked only by
   the SKILL when re-running a `stale` stage to produce
   human-readable migration diagnostics ("audit_log needs
   column `event_uuid`").

The hash is computed over a **canonical YAML emit** per design
doc § "Canonicalization invariant for hash stability":
deep-sorted keys; fixed 2-space block indent; `\n`-normalized
line endings with trailing-whitespace strip; per-stage
hash-allowlist paths stripped before hashing
(`last_validated_at`, `last_run_id`, `external_validated_at`,
`external_ttl_seconds`, any `[hash-excluded]` field); sha256
the result. Excluded fields still appear in recorded
`target_state` for forensics but do not contribute to identity.

Schema migration is **module-local** (per design doc
§ "Schema-migration seam" + § "Cross-version evolution"). When
a module's `compute_target_state()` semantics change, the
maintainer bumps that stage's `generation`; recorded entries
flip to `stale`; the SKILL re-runs and uses Layer 3 diff for
"what changed" messages. No central migration runner — each
module owns its evolution through its registry entry plus its
`stages_lib/<stage_id>.py` callables (per ADR-0014).

## Consequences

### Positive

- **Sub-step granularity recovers cleanly from interruption.**
  A mid-bootstrap crash leaves entries for stages that ran;
  next session sees unfinished as `never-run`, finished as
  `completed`. No per-executor idempotency hacks.
- **Cross-version drift is automatically detected.** Plugin
  upgrade bumps a stage's `generation` → recorded entry no
  longer matches → flips to `stale` → SKILL re-runs.
  ADR-0012's unified-trigger model relies entirely on this.
- **Hook stays cheap.** Layer 1 absorbs the steady-state in
  O(1); Layer 2 only runs on generation match; Layer 3 never
  runs in the hook. The ≤200ms budget holds.
- **Migration messages are architect-readable.** When a stage
  goes `stale`, the SKILL has both old and new `target_state`
  and produces a concrete diff, not "version mismatch, please
  re-bootstrap." Layer 2 also backstops forgotten-generation-
  bump bugs by catching content drift.
- **Module-local migration eliminates a central runner.** Each
  module's `compute_target_state()` IS the migration spec for
  that module. No `migrations/` directory; no ordered registry.

### Negative

- **YAML verbosity.** Each entry carries three layers; stages
  with large target states (M4 audit DDL: ~30 columns × 3
  tables) run hundreds of YAML lines. Mitigated by
  partitioning status files by locality (design doc § "Four
  status files (one per locality)").
- **Canonicalization discipline is non-negotiable.**
  `compute_target_state()` MUST be deterministic — embedded
  timestamps or set iteration order break hash stability and
  produce false-`stale` on every session. CI must round-trip
  each stage's output and assert hash stability (test
  placement is tracked in design doc § "Open design choices").
- **Hash-allowlist is a per-stage maintenance burden.** Adding
  a non-deterministic field without registering it in
  `hash_excluded_fields` silently breaks hash equality.
  Mitigated by JSON Schema validation (per ADR-0014).
- **`deprecated` entries accumulate without auto-prune.** v1
  ships no auto-prune; status files grow over plugin lifetime.
  A future `bsp-prune-deprecated.sh` helper can land if
  accumulation becomes a problem.

## Alternatives considered

### α — Three-layer fingerprint stack (chosen)

The decision recorded above. `generation` + derived hash +
structured ground truth is the canonical pattern in production
stateful-resource systems. Kubernetes' `metadata.generation`
increments on each spec mutation; controllers compare against
`status.observedGeneration` as a fast-path before structural
reconciliation. Terraform's `serial` integer increments on
each state mutation; the JSON state file carries the
structured ground truth. Pulumi stack checkpoints follow the
same pattern. board-superpowers borrows this shape directly,
adding Layer 2 (hash) because K8s controllers re-reconcile on
every tick (a forgotten bump self-corrects) but
board-superpowers' hook does not — the hash backstop is
required.

### β — Pure-hash (Nix-style)

Rejected. Nix derivations are pure-hash because Nix builds
are immutable: a hash mismatch means "rebuild from scratch
into a new store path," with no "what changed" to explain.
That does not transfer to stateful resources. Bootstrap
stages mutate a long-lived audit DB, `manifest.yml`, and
routing-block injection; when a stage goes `stale` the
architect needs to know *what specifically changed* so a delta
migration ("add column `event_uuid`") is possible instead of a
destructive replace. Pure-hash collapses every change into
"hashes differ, re-run from scratch," losing the delta and the
diagnostic. Hash's verification value is preserved as Layer 2,
not as a replacement for structured ground truth.

### γ — Pure-structured (no fast-path hash)

Rejected. A pure-structured model forces the hook to
deep-equal `compute_target_state()` against `entry.target_state`
on every session for every stage. With ~14 stages and audit
DDL target states running into hundreds of structured fields,
that is ms-scale work per stage × every hook tick — wasted in
the dominant steady-state case once a repo is bootstrapped.
Layer 1's integer compare absorbs the steady-state in O(1);
skipping the fast-path makes the hook do work it does not need
to do. ADR-0012's ≤200ms budget might hold at v0.4.0 scale,
but the design would not survive registry growth.

### δ — Boolean "is bootstrapped" with timestamp (status quo at v0.4.0)

Rejected. This is the model the redesign exists to replace. A
single `bootstrapped_at: <timestamp>` cannot express sub-step
granularity, cannot detect cross-version drift (the timestamp
does not change when an expected target changes), and cannot
drive ADR-0012's unified bootstrap-and-migration mechanism.
Mid-bootstrap interruption is also unrecoverable: if the file
exists the system assumes complete even when only half the
stages ran. Per design doc § "Why a redesign" item 1, this is
the structural weakness the redesign explicitly targets.

## Notes

**Ansible check-mode** is a fourth surveyed pattern that does
not apply: Ansible diffs "current vs declared" at execution
time but has no persistent state file between runs —
check-mode re-derives current state from each target host on
every invocation. board-superpowers needs persistent state
because per-repo RDBMS schema and external GitHub state are
too expensive to re-query on every hook tick. The two
transient SKILL-only states (`failed`,
`pending-architect-input`) are not part of the lifecycle's
comparison logic; the hook treats them as effectively
`never-run` and their purpose is operational diagnostics.

## Related

- ADR-0012 — Unified check-script trigger model; this ADR
  supplies the lifecycle states that the trigger consults.
- ADR-0014 — Stage registry contract; this ADR consumes the
  registry's `generation`, `target_state_schema`,
  `compute_target_state()`, and `hash_excluded_fields` fields.
- [ADR-0007](./0007-plugin-runtime-derived-constraints.md) —
  Plugin-runtime-derived constraints; the hook-cheapness
  invariant (C-PLUGIN) drives the requirement that Layer 1
  be O(1).
- [`../0002-product-features-and-flows/05-bootstrap-surface-redesign.md`](../0002-product-features-and-flows/05-bootstrap-surface-redesign.md)
  — Living design doc; § "Per-stage entry shape" +
  § "Stage lifecycle states" +
  § "Hash-allowlist (fields excluded from hash)" +
  § "Why three layers, not just hash" +
  § "Schema-migration seam" + § "Cross-version evolution"
  are this ADR's authoritative references.
- [`../0005-contracts/03-config-schemas.md`](../0005-contracts/03-config-schemas.md)
  — Config-schema migration policy (versioned-and-additive,
  lazy-on-read) that per-stage `target_state_schema_version`
  evolution inherits.
