# ADR — architecture decision records

ADRs capture decisions that shaped board-superpowers and would be
expensive or contentious to revisit. Each is immutable once
accepted; superseding one creates a new ADR that links to the old.

## Numbering

Four-digit, monotonic, no gaps. Reuse a number only if the previous
ADR was rejected before being accepted (no live readers).

## Statuses

- `proposed` — draft, open for feedback
- `accepted` — merged, in force
- `superseded by ADR-<N>` — kept for history; new ADR points back
- `rejected` — never landed; kept so future readers don't re-litigate
- `stub` — file exists, content not yet written (used during the
  initial skeleton phase only)

## Template

```markdown
# ADR <N>: <Title>

**Status:** proposed | accepted | superseded by ADR-<N> | rejected
**Date:** YYYY-MM-DD
**Deciders:** <names / roles>

## Context

What forces (technical, organizational, product) made this decision
necessary? What were we observing before?

## Decision

The choice we made, stated as a positive present-tense claim.

## Consequences

What changed because of this choice — good and bad. What new
constraints does it impose. What's now possible that wasn't.

## Alternatives considered

What else we evaluated and why each lost. One paragraph each.

## Notes                          <!-- OPTIONAL -->

Precedent clarifications, exceptions, or attribution that don't fit
elsewhere. Examples:
- Why this ADR's number reuses one previously occupied by a stub
  (immutability exception)
- Why this ADR ships before its full implementation lands (canonical
  source vs as-of-date artifact)

Omit if no such notes apply.

## Related

- ADR-<N> (if any)
- Cross-references to `0003-domain-model/`, `0005-contracts.md`,
  `0006-failure-modes.md` entries
```

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [0001](./0001-pluggable-board-backend-with-github-project-v1.md) | Pluggable board backend (GitHub Project v2 as v1 reference adapter) | accepted |
| [0002](./0002-claim-via-branch-push.md) | Atomic claim via remote branch push | accepted |
| [0003](./0003-worktree-per-consumer.md) | One worktree per Consumer session | accepted |
| [0004](./0004-composition-over-reimplementation.md) | Composition over reimplementation of TDD/QA | accepted |
| [0005](./0005-board-adapter-contract.md) | v1 BoardAdapter contract surface | accepted; § Consequences amended by ADR-0010 |
| [0006](./0006-producer-autonomy-boundary.md) | Producer autonomy boundary — autonomous-with-transparency, with explicit permission matrix | accepted |
| [0007](./0007-plugin-runtime-derived-constraints.md) | Plugin-runtime-derived constraints — three constraints arising from CC / Codex plugin physics | proposed |
| [0008](./0008-plugin-to-plugin-skill-invocation.md) | Plugin-to-plugin composition via SKILL invocation (vs subagent spawn / MCP / direct import) | accepted |
| [0009](./0009-allow-sqlite-as-byo-audit-db.md) | Allow SQLite as a BYO audit DB scheme (supersedes ADR-0006 §5 partial) | accepted |
| [0010](./0010-re-anchor-deadlines-ai-cadence.md) | Re-anchor ADR-0005 Consequences deadlines to v1 GA + project-wide AI cadence 100x convention (supersedes ADR-0005 § Consequences partial) | accepted |
| [0011](./0011-defer-producer-routines-to-v1x.md) | Defer Producer routines F-03..F-07 + F-10..F-15 to v1.x pending demand pull | accepted |
| [0012](./0012-unified-check-script-trigger-model.md) | Unified check-script trigger model (absorbs `migrating-repo-version` skill) | proposed |
| [0013](./0013-declarative-state-schema-and-lifecycle.md) | Declarative state schema + 5-state lifecycle + K8s-style three-layer fingerprint | proposed |
| [0014](./0014-stage-registry-contract.md) | Stage registry contract — YAML metadata + Python helpers + JSON Schema validation | proposed |
| [0015](./0015-m4-audit-per-repo-locality.md) | M4 audit module per-repo locality (replaces host-shared `credentials.yml`) | proposed |
| [0016](./0016-cross-platform-parity-contract.md) | Cross-platform parity contract via the `platforms` field on every stage | proposed |
| [0017](./0017-i13-invariant-revision-cross-clone-state-sharing.md) | I-13 invariant revision — cross-clone state sharing via GitHub-based identity (revises I-13 in `07-cross-cutting-invariants.md`) | proposed |
| [0018](./0018-m7-multi-stage-routing-block-protocol.md) | M7 multi-stage per-block routing protocol with form-detect prerequisite + Codex 32 KiB AGENTS.md budget | proposed |
| [0019](./0019-zero-config-sqlite-default-audit-backend.md) | Zero-config SQLite as default per-repo audit backend (extends ADR-0009) | proposed |
| [0020](./0020-stage-applicability-and-not-applicable-state.md) | Stage applicability — `applicable_when` predicate + `not-applicable` 5th lifecycle state | proposed |
| [0021](./0021-settings-modular-layering.md) | Settings modular layering — two-section split + per-module `schema_version` | proposed |
| [0022](./0022-boardadapter-capability-dispatch.md) | BoardAdapter capability dispatch + M10 BoardAdapter-selection module | proposed |
| [0023](./0023-architect-ux-and-config-item-protocol.md) | Architect UX — sequential per-stage flow + 5-element config item protocol | proposed |
| [0024](./0024-settings-rename-and-config-item-stages.md) | settings.yml rename + new config-item stages (`m5.repo.set-wip-limit`, `m10.repo.choose-kanban-backend`) | proposed |
