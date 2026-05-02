# ADR 0012: Unified check-script trigger model (absorbs `migrating-repo-version`)

**Status:** proposed
**Date:** 2026-04-28
**Deciders:** PanQiWei (architect)

## Context

Today's bootstrap mechanism (per
[`../0002-product-features-and-flows/05-bootstrap-surface.md`](../0002-product-features-and-flows/05-bootstrap-surface.md))
splits "first-time bootstrap" and "version transition" into two
parallel families that share most of their dispatch logic but
no implementation:

- **F-B1 / F-B2** (host bootstrap + per-repo bootstrap) ship today;
  driven by the `bootstrapping-repo` SKILL.
- **F-B3 / F-B4** (host version transition + per-repo version
  transition) are designed in spec but **not implemented at
  v0.4.0**; reserved for the deferred `migrating-repo-version`
  SKILL.

This split has three structural weaknesses surfaced by the
v0.4.0 ship and the #43 bootstrap-audit-contract drift work:

1. **Implicit completion state.** "Is bootstrapped" is inferred
   from "file exists with a valid `schema_version`". No record of
   which sub-step ran, when, or under which plugin version.
   Mid-bootstrap interruption recovers only via each step's
   hand-rolled idempotency check; cross-version drift detection
   is impossible from local files.
2. **Duplicate dispatch logic.** F-B3 / F-B4 (migration) need the
   same "compute diff between current state and target state"
   primitive that F-B1 / F-B2 (bootstrap) need — only with
   different starting states (existing partial vs nothing). A
   separate `migrating-repo-version` SKILL would re-implement
   what `bootstrapping-repo` already needs internally.
3. **Hook is observation-blind to version drift.** At v0.4.0
   `hooks/session-start.sh` checks file *presence* only
   (`manifest.yml` exists; `state.yml` exists). It does not
   compare the recorded `last_seen_version` against the current
   `plugin.json:version`. Architects upgrading the plugin rely
   on out-of-band release notes or manual re-bootstrap.

## Decision

Bootstrap and migration are **unified** into a single mechanism:
a stateless **check script** runs on every `SessionStart` hook,
computes the diff between the current plugin's stage registry
and the recorded per-stage status entries, and emits an
`INVOKE: bootstrapping-repo` marker if any stage is `never-run`
or `stale` (per the 5-state lifecycle defined in ADR-0013).

Concretely:

- The deferred `migrating-repo-version` SKILL is **absorbed
  and removed from the v1 catalog**. Migration becomes "running
  the diff that the lifecycle model identifies as `stale`."
  There is no separate migration code path.
- The hook is **observation-only**: reads partitioned status
  files, runs the lifecycle diff, emits a marker if needed.
  Never writes status. Never executes a stage.
- The `bootstrapping-repo` SKILL is the **single executor** for
  every stage that needs running — automated and agentic alike.
- Status drift (architect upgraded plugin → some stages
  `stale`) and first-time bootstrap (no entries → all stages
  `never-run`) are handled by the **same code path**. The
  lifecycle finds different state distributions but the dispatch
  logic is one.

The hook's pseudo-code is captured in
[`05-bootstrap-surface.md`](../0002-product-features-and-flows/05-bootstrap-surface.md)
§ "Trigger model" → "Hook flow (pseudocode)".

## Consequences

### Positive

- **Single mechanism, fewer moving parts.** No separate
  `migrating-repo-version` SKILL to maintain. The
  [`SKILLS.md`](../../SKILLS.md) catalog drops one entry.
- **Hook permanently cheap.** ~200ms (four small YAML reads +
  ~20 hash comparisons + emit). Comfortably under CC's ≤5s soft
  limit and well within Codex's no-documented-timeout window.
- **Plugin upgrades auto-detected.** Adding a new stage in
  plugin v(N+1) → existing repos see `never-run` for that
  `stage_id` on next session → triggered automatically. No
  "what's new" architect prompt required; no manual
  re-bootstrap.
- **Schema migration auto-detected.** Changing a stage's
  expected target (DDL bump, content template change) bumps the
  registry's `generation` integer (per ADR-0013) → `stale` →
  re-run. Schema migration is **module-local** (each module
  owns its migration via its `compute_target_state()`),
  removing the need for a central migration runner.
- **Single-direction state flow.** Hook reads → SKILL writes →
  next hook reads. No interleaved hook-and-SKILL writes to
  fight; concurrency reduces to "multiple hooks reading + one
  SKILL writing", which is trivial.

### Negative

- **Architect enters a SKILL session for every cohort change.**
  Any new stage triggers SKILL entry, even when the stage is
  fully automated (e.g., `m1.repo.write-state-yml` writing an
  empty file). Mitigated by the SKILL flow running automated
  stages without architect input — perceived cost is one
  SKILL banner + a few seconds, not an interactive interruption.
- **Hook depends on registry availability.** A corrupted or
  absent `stages-registry.yml` makes the hook unable to compute
  the diff. Hook still exits 0 (per Invariant 3) but emits no
  marker, so the architect sees no progress until the registry
  is repaired. Mitigation: load-time JSON Schema validation
  (per ADR-0014) catches malformed registries at CI time, not
  at hook time.
- **Pre-v1 breaking change.** Switching to this model breaks
  the file-presence-based detection that v0.4.0 ships with.
  Per the design doc's "Pre-v1 breaking changes accepted"
  Decided item, architects delete existing host-local state
  (`~/.board-superpowers/credentials.yml` + any
  `~/.board-superpowers/repos/*/state.yml`) on upgrade and
  re-bootstrap. No in-place migration logic ships.

## Alternatives considered

### α — Hook runs nothing; SKILL handles everything (chosen)

This ADR's decision. SKILL is the single executor.

### β — Hook synchronously runs all automated stages; SKILL handles only agentic

Rejected. CC's `SessionStart` is synchronous-blocking — the
session UI does not start rendering until the hook exits.
Heavy automated stages (`m2.host.install-uv` at 5-15s,
`m2.repo.sync-venv` at 5-30s) would push hook execution past
30-50s on a fresh-bootstrap session. Architects would
experience "session frozen on startup" the first time they
bootstrap a repo. The CC-documented ≤5s soft limit is
conclusive against this option.

### γ — Hook runs "light automated" stages synchronously; SKILL handles "heavy automated" + agentic

Rejected after re-reading G2 carefully. G2's "automated stages
should run without architect attention" was clarified to mean
*without architect attention*, not *without entering an agent
session*. Since SKILL-driven automated execution requires no
architect attention (the agent invokes the executor via `Bash`
tool autonomously), the additional complexity of dual-track
execution (hook executes some stages, SKILL executes others)
is not justified. The split would also fragment error handling
between two surfaces.

### δ — Keep `migrating-repo-version` as a standalone skill

Rejected. The dispatch logic for "diff current state vs target
state, run the missing or stale parts" is identical for
first-time bootstrap and version transition. Maintaining two
code paths for the same primitive is the exact tech debt this
redesign exists to eliminate.

## Notes

The marker grammar emitted by the hook follows the
`INVOKE: <skill> / REASON: <one-line>` convention from
[`../0005-contracts/02-hook-contracts.md`](../0005-contracts/02-hook-contracts.md)
§ "Intent-injection markers". The REASON wording is left to
the implementer; the design doc shows a canonical form
("`<N> stages need running (<list>)`"), but variations that
remain inside the sanitization rules are permitted.

The hook contract (always exit 0; never block session start;
self-contained — must not source `scripts/lib/common.sh`)
remains unchanged from
[`../0005-contracts/02-hook-contracts.md`](../0005-contracts/02-hook-contracts.md)
Invariants 1-3.

## Related

- ADR-0013 — Declarative state schema + 5-state lifecycle +
  K8s-style three-layer fingerprint (the lifecycle model this
  trigger consults).
- ADR-0014 — Stage registry contract (the source of truth
  this trigger reads).
- ADR-0007 — Plugin-runtime-derived constraints; CC's
  SessionStart synchronous-blocking is the C-PLUGIN constraint
  that eliminates option β.
- ADR-0011 — Defer Producer routines to v1.x; this ADR removes
  `migrating-repo-version` from the deferred list (absorbed,
  not deferred).
- [`../0002-product-features-and-flows/05-bootstrap-surface.md`](../0002-product-features-and-flows/05-bootstrap-surface.md)
  — Living design doc carrying the full context;
  § "Trigger model" is this ADR's authoritative reference.
- [`../0005-contracts/02-hook-contracts.md`](../0005-contracts/02-hook-contracts.md)
  — Hook contract that constrains the check script's
  observation-only / always-exit-0 invariants.
