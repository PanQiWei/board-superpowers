# ADR 0015: M4 audit module per-repo locality (replaces host-shared credentials.yml)

**Status:** proposed
**Date:** 2026-04-28
**Deciders:** PanQiWei (architect)

## Context

The audit log persistence target was set by [ADR-0006](./0006-producer-autonomy-boundary.md) §5
(BYO RDBMS) and extended by [ADR-0009](./0009-allow-sqlite-as-byo-audit-db.md)
(SQLite as a 6th allowlisted scheme). Both ADRs treated the
audit destination as **per-architect / per-host** infrastructure:
the v0.3.0 implementation writes a single
`~/.board-superpowers/credentials.yml` (mode `0600`) and every
repo on the host resolves its DSN from that one file.

The v0.4.0 ship and the #43 bootstrap-audit-contract drift
work surfaced a structural consequence the original ADRs did
not anticipate. One DSN per host means one audit DB per host:
architects running board-superpowers across multiple repos on
the same workstation have audit rows from every repo landing
in the same database. The `project` column (per ADR-0006 §5
schema) distinguishes them logically, but physical isolation
is absent — credential rotation, DB corruption, backup, and
debugging dumps are all-repos-or-nothing. Architect intent is
per-repo isolation: each repo carries its own credentials, DB,
and backend choice. The #43 evaluation classified this as a
bug, not a quirk — drift between architect intent and shipped
contract. The fix is contract-level: the locality of every M4
stage needs to be per-repo, uniformly.

The bootstrap-redesign design doc
([`05-bootstrap-surface-redesign.md`](../0002-product-features-and-flows/05-bootstrap-surface-redesign.md)
§ "Why a redesign" item 5; § "Functional modules" M4;
§ "Stages" table M4 rows; § "Decided" → "M4 audit module is
per-repo, not host-shared") consolidates this. This ADR
formalizes that decision.

## Decision

**Every M4 stage's locality is `repo-shared`** (per-repo,
host-local, cross-clone-shared via GitHub identity), uniformly.
The host-shared `credentials.yml` is **removed**; it is
replaced by per-repo `credentials.yml` keyed by repo identity.

Concretely: `credentials.yml` relocates from
`~/.board-superpowers/credentials.yml` (host-shared) to
`~/.board-superpowers/repos/<repo-identity>/credentials.yml`
(per-repo, mode `0600`); repo identity is `<owner>-<repo>`
resolved from the repo's `origin` URL (per the redesign's
§ "Repo identity"). All four M4 stages —
`m4.repo.acquire-dsn`, `m4.repo.apply-audit-ddl`,
`m4.repo.flush-pending-audit`, `m4.repo.audit-health-check` —
bind to per-repo identity: `acquire-dsn` writes the per-repo
credentials file, the other three resolve the DSN from that
path, and no M4 stage reads or writes any host-shared
credential location. Each repo's audit log lives independently
(separate DSN, separate DB or SQLite file at
`~/.board-superpowers/repos/<repo-identity>/audit.db`,
separate jsonl fallback at the same parent's
`audit-local.jsonl`). Cross-repo isolation is guaranteed by
construction.

The behavioral forces preserved by ADR-0006 §5 + ADR-0009
(BYO opt-in, R-class degradation when DB unavailable, no
public destinations, no project-tree files, two-entry rule,
friction-as-feature) are unchanged. Only the per-repo-vs-host
bucket of `credentials.yml` and its downstream M4 stages
changes.

## Consequences

**What this enables:**

- **Cross-repo audit isolation by construction.** Credential
  rotation, DB corruption, backup, debugging dump, backend
  swap (SQLite → Postgres) — all scoped to one repo at a time.
- **Per-repo backend choice.** One repo on Postgres, another
  on the zero-config SQLite default. No host-level coupling.
- **M4 siblings co-locate with M1's `state.yml`** under one
  normalized-name parent at mode `0700` — matching ADR-0009's
  path convention.

**What this constrains:**

- **`bootstrap-project.sh` step 2e (M4 `acquire-dsn`) writes
  per-repo, not host.** Cross-repo DSN reuse becomes the
  architect's explicit choice, not a default.
- **No host-shared credential resolution path remains.** The
  `auditing-actions` skill's DB-write helper resolves DSN
  exclusively from per-repo `credentials.yml`. Any reference
  to host-shared `credentials.yml` in shipped code is a bug.
- **Spec contract updates land in the same replacement PR** —
  [`../0005-contracts/03-config-schemas.md`](../0005-contracts/03-config-schemas.md)
  (credentials.yml relocation) and
  [`../0005-contracts/07-path-conventions.md`](../0005-contracts/07-path-conventions.md)
  (per-repo path layout for the M4 sibling set).

**Trade-off explicitly registered: pre-v1 breaking change.**

Per the design doc's § "Decided" → "Pre-v1 breaking changes
are accepted", **no in-place migration logic ships**.
Architects upgrading from v0.4.0 (or any earlier version with
host-shared `credentials.yml`):

1. Delete `~/.board-superpowers/credentials.yml`.
2. Re-bootstrap each repo. The unified check script (per
   ADR-0012) sees `m4.repo.acquire-dsn` as `never-run` and
   triggers the agentic prompt on next session start.

Architect-machine state is small and easily recreated;
migration code is complexity without value before v1 GA.

## Alternatives considered

**α — Per-repo `credentials.yml` + breaking-change procedure
(chosen).** This ADR's decision. Cross-repo isolation by
construction; no migration code; release notes carry the
deletion procedure.

**β — Keep host-shared `credentials.yml` + per-repo override
file.** Rejected. The host-shared default leaves cross-repo
pollution as the path of least resistance — most architects
never write the override, and the #43 bug persists. Two-layer
override also complicates `m4.repo.acquire-dsn`'s idempotency
for no material safety gain.

**γ — In-place migration script that copies the host-shared
DSN into each known repo's per-repo `credentials.yml`.**
Rejected. board-superpowers has not had a formal release;
architect-machine state is small; the re-bootstrap path
already exists. Shipping run-once-then-dead-weight migration
code is the exact pre-v1-breaking-change rationale the design
doc formalizes.

**δ — Continue host-shared, document the cross-repo audit
pollution as a known limitation.** Rejected. Conflicts with
architect intent (per-repo isolation is the explicit goal)
and with the #43 evaluation, which classified the drift as a
real bug. Documenting a contract violation as a feature of
the contract is a design code-smell — the contract is what's
wrong, and the contract is what gets fixed.

## Notes

The audit-entry `project` column from ADR-0006 §5 schema
remains useful — a single repo's audit DB still scopes rows
by GitHub Project number (one repo can host multiple
board-tracked projects); only the host-level disambiguation
case it was previously load-bearing for goes away. This ADR
does not change the audit DDL, write mechanism, two-entry
rule, or any other ADR-0006 §5 + ADR-0009 decision — locality
alone is the surface this ADR moves.

## Related

- [ADR-0006](./0006-producer-autonomy-boundary.md) §5 — audit
  log persistence. This ADR refines §5's locality from
  per-host to per-repo; the rest of §5 stands.
- [ADR-0009](./0009-allow-sqlite-as-byo-audit-db.md) — SQLite
  as a first-class scheme + `audit.db` default path under
  `~/.board-superpowers/repos/<normalized>/`. ADR-0009
  anticipated the per-repo parent for `audit.db` /
  `audit-local.jsonl`; this ADR moves `credentials.yml` to it.
- ADR-0012 — Unified check-script trigger model. The
  breaking-change procedure relies on the lifecycle diff
  seeing `m4.repo.acquire-dsn` as `never-run` after the
  architect deletes host-shared state.
- ADR-0013 — Declarative state schema + 5-state lifecycle. M4
  stages' `target_state` carries per-repo identity into their
  hash, making per-repo isolation observable from the diff.
- [`../0002-product-features-and-flows/05-bootstrap-surface-redesign.md`](../0002-product-features-and-flows/05-bootstrap-surface-redesign.md)
  — Living design doc; § "Why a redesign" item 5 + § "Functional
  modules" M4 + § "Stages" M4 rows + § "Decided" entries
  ("M4 audit module is per-repo" + "Pre-v1 breaking changes
  are accepted") are this ADR's authoritative references.
- [`../0005-contracts/03-config-schemas.md`](../0005-contracts/03-config-schemas.md)
  + [`../0005-contracts/07-path-conventions.md`](../0005-contracts/07-path-conventions.md)
  — credentials.yml relocation + per-repo path layout land in
  the replacement PR.
