# ADR 0018: M7 multi-stage per-block routing protocol with form-detect prerequisite + Codex 32 KiB budget

**Status:** proposed
**Date:** 2026-04-28
**Deciders:** PanQiWei (architect)

## Context

Through `v0.4.0`, M7 (Agent routing — the module that injects
plugin routing metadata into the user repo's `AGENTS.md` and
`CLAUDE.md`) is a **single monolithic stage**:
`bsp_inject_routing_block` writes one routing block bounded by
one `<!-- board-superpowers:routing -->` marker pair. Three
structural weaknesses surface once the bootstrap redesign treats
each module's payload as a versioned contract:

1. **No content-block versioning.** One opaque region, one
   content hash. Adding a second routing block (e.g., Manager /
   Consumer dispatch alongside the existing skill-routing
   trigger) means rewriting the whole region; architect-modified
   halves lose all granularity.
2. **No form detection.** The script picks a target file by
   filesystem probe at each invocation — no cached `form`
   (`cc-only` / `codex-only` / `dual` / `neither`) in state.
   Architects who add `AGENTS.md` to a previously CC-only repo
   (or remove one) cannot trigger re-injection without manual
   intervention; the lifecycle model has no signal to flip M7
   to `stale`.
3. **No size-budget awareness.** Codex CLI walks Git root → cwd
   concatenating every `AGENTS.md` and stops at
   `project_doc_max_bytes` — default **32 KiB**
   ([`PLUGIN_DEVELOPMENT.md`](../../../PLUGIN_DEVELOPMENT.md)
   line 309). Past the cap is silently truncated. A monolithic
   M7 block growing unbounded can push architect content past
   the limit and corrupt routing with no failure signal.

The stage-registry shape (ADR-0014) plus the 4-state lifecycle
(ADR-0013) give M7 a place to expose its internal structure as
multiple registry rows. This ADR formalizes that restructuring.

## Decision

M7 is restructured as a **multi-stage per-block protocol** with
three structural elements:

### 1. Prerequisite form-detect stage

A new automated stage `m7.repo.detect-agentsmd-form` runs
**before** any inject-block stage. Its `target_state` records
`form` (enum `cc-only` / `codex-only` / `dual` / `neither`,
derived from probing `AGENTS.md` and `CLAUDE.md` presence) and
`agentsmd_total_bytes` (post-concat-walk total used to gate
downstream stages against the 32 KiB budget). Locality is
`repo-shared` — the `form` value lives in the repo's
`state.yml` (per-clone-physical, not git-tracked) so each clone
re-detects on bootstrap rather than inheriting another clone's
filesystem layout.

### 2. Per-block inject stages

One stage per content block, shape `m7.repo.inject-block.<name>`.
The `v0.4.0+redesign` registry carries two **required** blocks:
`m7.repo.inject-block.routing-rule` (skill-routing trigger
prose, the v0.4.0 single-block era's content restructured) and
`m7.repo.inject-block.skill-routing` (Manager / Consumer
dispatch rules, split out from the same monolithic block). Each
block carries its own marker pair
(`<!-- board-superpowers:<block-name> -->` /
`<!-- /board-superpowers:<block-name> -->`), its own content
hash fed through the three-layer fingerprint (ADR-0013) for
independent block-level drift detection, a `kind` flag
(`required` / `optional`) controlling injection authority, and
a `block_max_bytes` registry field (default **4096** = 4 KiB)
enforced at write time.

### 3. `form` propagation through `target_state`

Every `m7.repo.inject-block.*` stage's `target_state` includes
the `form` value cached by the prerequisite. Because the
fingerprint compares `target_state` structurally (ADR-0013),
any change to the repo's routing-target file structure
(architect adds AGENTS.md to a previously CC-only repo; removes
CLAUDE.md; etc.) flips **every** M7 inject stage to `stale`
simultaneously and triggers full re-injection on next session —
no separate "re-run all blocks" signal needed; the lifecycle
model surfaces it mechanically.

### 4. Required vs optional `kind`

`kind=required` blocks are auto-injected by
`scripts/bootstrap-project.sh` with no architect interaction
(both current blocks are required). `kind=optional` blocks
(recommended-but-not-load-bearing prompt hints) are surfaced by
the `bootstrapping-repo` SKILL and injected only after explicit
architect accept; the optional list is **currently empty**. The
SKILL flow MUST contain a
`for each optional block in registry → prompt architect` loop
(no-op when empty) so future optional blocks land via
registry-only edits without SKILL code changes.

### 5. Codex 32 KiB budget enforcement

Two hard caps complement the lifecycle:

- **Single-block size cap**: ≤ 4 KiB per block
  (`block_max_bytes` registry field, default 4096).
- **Plugin total budget on AGENTS.md**: ≤ 8 KiB across all M7
  blocks plus all sub-directory AGENTS.md contributions —
  leaving ≥ 24 KiB headroom for the architect's own
  AGENTS.md content.

The `m7.repo.detect-agentsmd-form` stage measures
post-concat-walk total size; if a pending injection would push
the AGENTS.md total over budget, the stage refuses to inject
and surfaces a warning marker for architect attention rather
than silently corrupting routing through Codex truncation.

## Consequences

### Positive

- **Per-block independent versioning.** Plugin upgrades touching
  one block re-run only that block's stage; architect edits to a
  different block survive — marker-pair content hash detects
  per-block drift, not file-level drift.
- **Mechanical re-injection on file-structure change.** `form`
  propagation means the same lifecycle diff handles "architect
  adopted CC + Codex dual-platform" cleanly — no special
  "re-detect routing targets" code path.
- **Production-safe Codex integration.** 32 KiB budget enforced
  as explicit refusal, not silent truncation. Failure mode is
  "architect sees a warning marker", not "agent loads
  half-truncated routing rule and hangs".
- **Registry-driven extensibility.** New required block = one
  row + `target_state` callable; new optional block = same plus
  a one-line `kind` flag. No SKILL or script-shape change.

### Negative

- **More registry rows.** The single v0.4.0 row becomes three
  (`detect-agentsmd-form` + two `inject-block.*`). Mitigated by
  declarative registry + small count relative to the ~20 total.
- **Pre-v1 breaking change.** v0.4.0-bootstrapped repos do not
  auto-migrate; architects delete the legacy routing region and
  re-bootstrap (per design doc's "Pre-v1 breaking changes
  accepted").
- **Budget enforcement adds a refusal path.** Sessions where
  cumulative AGENTS.md content exceeds 24 KiB before M7 runs see
  a warning marker instead of injection; architect must prune
  AGENTS.md or raise `project_doc_max_bytes`.

## Alternatives considered

### α — Per-block multi-stage + form-detect prerequisite (chosen)

This ADR's decision. Block-level resolution + mechanical
file-structure re-evaluation + explicit budget enforcement.

### β — Single monolithic M7 stage (status quo at v0.4.0)

Rejected. Three failure modes documented in § "Context": no
per-block versioning, no form detection, no size-budget
awareness. Each is independently disqualifying for the
bootstrap redesign's contract-versioning goal.

### γ — Single per-file stage (monolithic but file-aware: "keep AGENTS.md in sync with current required + accepted optional blocks")

Rejected. Keeps file-level atomicity (one stage per target
file) but loses per-block independent versioning. An architect
who accepts optional block 1 and declines optional block 2
forces the stage to overwrite both or none — block-level
resolution gone.

### δ — No size cap, trust Codex to not truncate

Rejected. Codex's 32 KiB is a documented hard limit
([`PLUGIN_DEVELOPMENT.md`](../../../PLUGIN_DEVELOPMENT.md)
line 309); silent truncation past the cap is documented
behavior. Skipping enforcement turns a known contract into a
production landmine — agents load half-truncated routing prose
with no failure signal, surfacing only via downstream "why does
the agent ignore the routing rule" debugging.

## Notes

The block-level marker pair convention
(`<!-- board-superpowers:<block-name> -->`) extends the existing
`<!-- board-superpowers:routing -->` shape from `v0.1.0-minimum`.
Old single-block markers are not auto-rewritten; the v0.4.0 →
redesign transition treats them as architect content (the
block-content-hash check sees the old marker pair as "no current
required block matches" and inject stages write fresh blocks
alongside, leaving the architect to delete the legacy region
manually). The `bootstrapping-repo` SKILL surfaces this as a
prompt the first time the lifecycle observes the legacy region.

The 4 KiB / 8 KiB figures are deliberately conservative:
8 KiB plugin + 24 KiB architect headroom = 32 KiB Codex cap, no
slack for sibling sub-directory AGENTS.md contributions in
deeply nested repos. Bumping the per-plugin budget is a
future-ADR question; first cut errs safe.

## Related

- ADR-0012 — Unified check-script trigger model. The
  per-stage diff this ADR's restructured M7 stages feed into.
- ADR-0013 — Declarative state schema + 4-state lifecycle +
  K8s-style three-layer fingerprint. The block-level
  fingerprint comparison this ADR exploits.
- ADR-0014 — Stage registry contract. The YAML row shape
  this ADR's three new M7 rows occupy.
- [`../0002-product-features-and-flows/05-bootstrap-surface-redesign.md`](../0002-product-features-and-flows/05-bootstrap-surface-redesign.md)
  — Living design doc; § "Functional modules" → M7 +
  § "Stages" M7 rows + § "Decided" entries on M7 are this
  ADR's authoritative reference.
- [`../../../PLUGIN_DEVELOPMENT.md`](../../../PLUGIN_DEVELOPMENT.md)
  line 309 — Codex `project_doc_max_bytes` 32 KiB
  documentation; the load-bearing constraint for § "Decision"
  element 5.
