# ADR 0009: Allow SQLite as a BYO audit DB scheme (supersedes ADR-0006 §5 partial)

**Status:** accepted
**Date:** 2026-04-27
**Deciders:** PanQiWei (maintainer)

## Context

ADR-0006 §5 set the persistence target for the audit log: a
relational database the architect provides (BYO RDBMS). At v1
the §5 backend constraint named **Postgres or MySQL only** and
explicitly rejected SQLite as "file-based; re-introduces the
local-persistence anti-pattern under a different name."

Six months of dogfood reality on this very repo, plus solo /
small-team usage feedback, surface a friction the original
constraint did not anticipate:

- The typical board-superpowers user is **one architect on one
  repo**. The `(host, repo) → 1 architect` mapping is the modal
  case, not the exception. Producer and Consumer sessions on a
  single host serialize through the architect's prompt cadence —
  there is exactly one writer to the audit log at any given
  moment.
- Provisioning Postgres or MySQL **just to write a few audit
  lines per day** is ergonomically heavy. Container setup,
  credential rotation, port management, backup story — all
  upfront cost paid before the first `manifest.yml` lands.
- Architects respond rationally: they skip the DB, accept the
  R-class degradation indefinitely, and the audit log never
  comes online. The `audit_db_url` field stays empty across
  hundreds of A-class actions, defeating the point of having an
  audit log schema at all.

SQLite's actual disqualifier in ADR-0006 §5 was **multi-writer
contention** plus the *local-persistence anti-pattern*. The
multi-writer worry does not apply to the modal `(host, repo) →
1 architect` deployment. The local-persistence worry is
addressable: a SQLite file under `~/.board-superpowers/` is
already in the same host-local territory as `manifest.yml`,
`state.yml`, and `credentials.yml` — none of which are in the
project tree, none in git, all under user-mode `0700`.

The solo-developer reality requires re-evaluating the §5
backend constraint without re-litigating the rest of §5
(propose-and-resolve two-entry rule, BYO opt-in, R-class
degradation, no public destinations). Hence: a partial
supersession.

## Decision

Allow `sqlite://` and `sqlite3://` URI schemes alongside the
existing four. The full `audit_db_url` allowlist is now **6
schemes**:

| Scheme | Driver |
|--------|--------|
| `postgresql://` | Postgres (canonical) |
| `postgres://` | Postgres (alias) |
| `mysql://` | MySQL (canonical) |
| `mysql+pymysql://` | MySQL via PyMySQL driver hint |
| `sqlite://` | SQLite (canonical) |
| `sqlite3://` | SQLite (alias) |

The default SQLite path suggested by `bootstrap-project.sh`
step 2e is:

```
~/.board-superpowers/repos/<normalized>/audit.db
```

Rendered as a SQLAlchemy DSN this becomes (note **4 slashes**
between scheme and absolute path):

```
sqlite:////Users/<user>/.board-superpowers/repos/<normalized>/audit.db
```

**SQLite uses 4 slashes for absolute paths** (`sqlite:////` then
`/Users/...`); the 3-slash form is interpreted relative to
`cwd` per SQLAlchemy convention and would silently write to the
wrong location. Because the suggested path is always absolute,
every DSN this plugin emits or accepts MUST use the 4-slash
form. Co-locating `audit.db` with `state.yml` keeps every
per-`(host, repo)` artifact under the same `0700` parent, with
one normalized-name sub-directory per pair (per
`07-path-conventions.md`).

### Forces preserved (not relaxed by this ADR)

- **BYO opt-in.** No auto-default audit DB. The architect must
  still explicitly choose to provision (any scheme) — declining
  produces the R-class degradation notice.
- **R-class degradation when DB unavailable.** ADR-0006 §5's
  fallback rule stands: missing `audit_db_url` → A-class actions
  degrade to R-class.
- **No public destinations.** Card comments, dedicated audit
  issue, GitHub Discussions remain forbidden.
- **No project-tree files.** SQLite under the repo's own tree
  (`<repo>/.board-superpowers/audit.db`) remains forbidden — the
  default suggestion deliberately steers the architect to
  `~/.board-superpowers/`.
- **Two-entry rule for R-class.** Propose + resolve writes
  unchanged.
- **Friction-as-feature.** The architect still makes an explicit
  decision; SQLite picker is a prompt, not a silent default.

### Forces relaxed by this ADR

- The previous **"no SQLite"** stance in ADR-0006 §5
  ("Alternatives considered → Allow SQLite as a BYO option →
  Rejected") is reversed. SQLite is now a first-class scheme,
  not a rejected alternative.

## Consequences

**What this enables:**

- **`bootstrap-project.sh` step 2e gains a SQLite branch.** The
  interactive UX presents the 6-scheme allowlist; if the
  architect picks SQLite, the script suggests
  `~/.board-superpowers/repos/<normalized>/audit.db` as the
  default path. Parent directory writability is verified
  before `credentials.yml` is written.
- **Solo-developer audit log adoption becomes realistic.** The
  zero-infra option means architects can flip the audit log on
  during initial bootstrap rather than deferring "until I set
  up Postgres later."
- **Future `auditing-actions` skill must support SQLite
  client.** Python's `sqlite3` stdlib module is sufficient — no
  new runtime dependency. The skill's DB-write helper script
  branches on URL scheme.
- **`03-config-schemas.md` `audit_db_url` schemes table grows
  from 4 rows to 6.** Same shape; same forbidden-destinations
  list; SQLite under the project tree is still forbidden.

**What this constrains:**

- **SQLite picker MUST verify parent dir writability** before
  writing `credentials.yml`. Otherwise the next audit write
  fails opaquely. `bootstrap-project.sh` step 2e aborts with a
  clear error if the directory is non-writable.
- **No multi-architect concurrent writers on one SQLite file.**
  The modal deployment makes this moot; if a future deployment
  needs multi-writer (shared host with two architects on the
  same repo), the architect picks Postgres or MySQL — the choice
  is theirs.

**What this rules out:**

- A SQLite file inside the project tree (e.g.,
  `<repo>/.board-superpowers/audit.db`). The default suggestion
  is host-local on purpose; if the architect overrides to a
  project-tree path, `bootstrap-project.sh` rejects it (same
  rule that forbids `.log` files in the project tree).

## Alternatives considered

**Keep the v1 "Postgres or MySQL only" constraint.** Rejected:
the friction is high enough that adoption stalls; architects
defer DB provisioning indefinitely and never benefit from the
audit log they implicitly opted into by using the plugin.

**Allow SQLite only when explicitly enabled by an env-var
escape hatch.** Rejected: adds ceremony without addressing the
core force (solo-developer ergonomics). The escape hatch becomes
the path everyone takes; might as well bless it as a first-class
scheme.

**Allow SQLite but make Postgres / MySQL the bootstrap
default suggestion.** Rejected: surveys real usage upside-down.
The modal architect is solo; the modal default should be the
zero-infra option. Multi-architect setups are the minority case
and the architect picks accordingly.

## Notes

- SQLite's WAL mode is recommended for any architect who anticipates
  brief overlap between Producer (writing audit entries) and a
  retro / weekly-report query. The `auditing-actions` skill's
  DB-write helper enables WAL on first connection.
- The ADR-0006 §5 paragraph "Alternatives considered → Allow
  SQLite as a BYO option" is now stale. ADR-0006 §5 receives a
  cross-reference paragraph noting the partial supersession by
  this ADR; the alternatives-considered text stays for history.

## Related

- ADR-0006 §5 — partially superseded by this ADR (SQLite scheme
  allowance only). The rest of §5 (BYO opt-in, no auto-default,
  R-class degradation, no public destinations, propose-and-
  resolve two-entry rule) stands.
- `0005-contracts/03-config-schemas.md` — `audit_db_url` schemes
  table extends from 4 to 6 rows.
- `0005-contracts/07-path-conventions.md` — `~/.board-superpowers/repos/<normalized>/`
  per-repo directory now houses three siblings (`state.yml`,
  `audit-local.jsonl`, optional `audit.db`).
- `0002-product-features-and-flows/05-bootstrap-surface.md`
  F-B2 step 2e — interactive picker presents 6 schemes;
  SQLite path suggestion lives here.
- `0001-positioning.md` P3 (solo / small-team scale) — the
  premise that justifies treating the modal `(host, repo) → 1
  architect` mapping as the design center, not an edge case.
