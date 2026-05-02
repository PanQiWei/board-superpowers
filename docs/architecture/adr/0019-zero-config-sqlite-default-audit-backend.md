# ADR 0019: Zero-config SQLite as default per-repo audit backend

**Status:** proposed
**Date:** 2026-04-28
**Deciders:** PanQiWei (architect)

## Context

[ADR-0009](./0009-allow-sqlite-as-byo-audit-db.md) added
`sqlite://` / `sqlite3://` to the BYO audit-DB allowlist
alongside Postgres and MySQL, motivated by solo-developer
ergonomics. ADR-0009 left the picker unchanged:
`bootstrap-project.sh` step 2e still presents a 6-scheme
interactive prompt at first bootstrap, with SQLite as one
branch among others.

At v0.4.0 — after the bootstrap redesign promoted M4 audit
locality from host-shared to per-repo (per ADR-0015) — the
prompt friction surfaces in sharper relief. The modal architect
runs `bootstrapping-repo` once per `(host, GitHub repo)` pair
and has **no preference** over Postgres / MySQL / SQLite at
that moment; the prompt cannot meaningfully educate either,
since a one-line scheme list does not surface the trade-offs
(concurrent-writer semantics, backup, query cost) needed for
an informed pick without docs. The `(host, repo) → 1 architect`
modal deployment that ADR-0009 § "Forces preserved" accepted
**eliminates multi-writer contention as a real concern at
first bootstrap**. SQLite is the right answer for the modal
case; the prompt is a tax on the answer being right.

The unified check-script trigger model (ADR-0012) +
declarative state schema (ADR-0013) already provide the
mechanism to honor a post-bootstrap override: changing
`credentials.yml` bumps `m4.repo.acquire-dsn`'s
`target_state_hash`, the next hook flips the stage to `stale`,
and `m4.repo.apply-audit-ddl` re-runs against the new DSN.
The redesign foundation makes a "default + override" pattern
cheap; the 6-scheme picker is no longer the only way to expose
the choice.

## Decision

The `m4.repo.acquire-dsn` stage's first-bootstrap path is
**zero-config**: it initializes SQLite at
`~/.board-superpowers/repos/<repo-identity>/audit.db` with
no architect prompt, then prints a one-line override hint on
stderr.

Concretely:

- **No DSN prompt at first bootstrap.** The stage writes
  per-repo `credentials.yml` (chmod 0600) with
  `audit_db_url: sqlite:////absolute/path/to/audit.db`
  (4-slash absolute form per ADR-0009) automatically.
- **One-line override note** printed once on stderr after the
  write: `Audit log: SQLite at <path>. To switch DSN, edit
  credentials.yml or run scripts/setup-audit-db.sh`. Not a
  blocking confirmation.
- **WAL mode default** (already in `audit-init.sh` at v0.4.0;
  this ADR formalizes it as the default-path expectation).
- **Override path is post-bootstrap edit.** Architects who
  want Postgres / MySQL edit per-repo `credentials.yml`
  directly; the next session's lifecycle diff detects the DSN
  change and `m4.repo.apply-audit-ddl` re-runs. No migration.
- **Path constraint preserved.** Default lives under
  `~/.board-superpowers/repos/<repo-identity>/audit.db` per
  [`../0005-contracts/07-path-conventions.md`](../0005-contracts/07-path-conventions.md)
  § "Per-host layout". Project-tree `audit.db` remains
  forbidden (ADR-0009's existing rejection).

This makes `m4.repo.acquire-dsn` **automated** on the
first-bootstrap happy path (was `agentic` at v0.3.0); it
escalates to architect attention only if the default-path
parent directory is non-writable.

## Consequences

### Positive

- **First-bootstrap friction drops by one prompt.** The modal
  solo-developer flow no longer pauses on a database picker
  whose right answer is "the one the picker is asking about."
- **Audit log adoption goes from "implicit opt-in" to
  "default-on."** Closes the gap ADR-0009 § "Context"
  identified — architects defer DB provisioning indefinitely
  → audit log never comes online.
- **Override path is honest and discoverable.** A single
  stderr line names both the file to edit and the helper
  script — no buried docs.
- **Lifecycle handles the override re-run for free** via
  ADR-0013's declarative state schema — switching backends is
  "edit yaml, restart session."

### Negative

- **Architects who would have picked Postgres get SQLite by
  default.** They pay one extra step (edit `credentials.yml`,
  restart) versus a hypothetical perfect picker. Mitigated by
  the override note surfacing the cost immediately.
- **Default path collisions are silent.** Two `(host, repo)`
  pairs sharing the same `<repo-identity>` would share one
  `audit.db` file. ADR-0015's GitHub-based identity scheme
  makes this unlikely; transferred-repo edge cases are out of
  v1 scope per P3.
- **Pre-v1 v0.3.0 architects upgrade with manual cleanup**
  (already documented as a pre-v1 breaking change in
  `05-bootstrap-surface.md`; no new migration logic).

## Alternatives considered

**Keep prompting for DSN at first bootstrap (ADR-0009 status
quo).** Rejected. The prompt does not surface trade-off
information needed for an informed choice; most architects
have no preference; first-bootstrap friction is paid every
time the modal answer is the obvious one.

**In-memory SQLite by default + opt-in persistence.** Rejected.
The audit log exists for forensics — a non-persistent default
defeats the purpose of having an audit schema at all.

**Encrypted SQLite (sqlcipher) by default.** Rejected. The
audit DB lives on the architect's own machine under
`~/.board-superpowers/` (mode 0700 parent); the architect owns
the threat model. Mandatory encryption adds a sqlcipher
dependency and key-management story for a threat (host
compromise) out of v1 scope per P3. At-rest encryption is the
encrypted-volume layer's job — orthogonal to the plugin.

**Federated audit (one shared DB across repos by default).**
Rejected. Violates ADR-0015's per-repo isolation. Future
federation ships as an explicit architect-chosen DSN.

## Notes

ADR-0019 promotes SQLite from "permitted option" (ADR-0009) to
"zero-config default"; the 6-scheme allowlist is unchanged.
`setup-audit-db.sh` (named in the override note) is
implementation-time detail — likely a thin wrapper around
`audit-init.sh`. The ADR fixes the name surfaced to architects
so override discoverability is stable.

## Related

- [ADR-0009](./0009-allow-sqlite-as-byo-audit-db.md) — parent;
  permits SQLite as a BYO scheme. ADR-0019 makes it the
  default rather than a co-equal option.
- [ADR-0006](./0006-producer-autonomy-boundary.md) §5 — BYO
  RDBMS opt-in / R-class degradation. ADR-0019 narrows the
  "opt-in" wording: the architect opts in to using the audit
  log, not to provisioning a database.
- ADR-0012 / ADR-0013 / ADR-0015 — unified trigger model,
  declarative state schema, and M4 per-repo locality; together
  they make the post-bootstrap override re-run automatic when
  the architect edits `credentials.yml`.
- [`../0005-contracts/07-path-conventions.md`](../0005-contracts/07-path-conventions.md)
  § "Per-host layout" — `audit.db` sibling location;
  project-tree `audit.db` forbidden rule preserved.
- [`../0002-product-features-and-flows/05-bootstrap-surface.md`](../0002-product-features-and-flows/05-bootstrap-surface.md)
  § "Decided" → "Per-repo audit DB defaults to zero-config
  SQLite" — living design doc this ADR formalizes.
