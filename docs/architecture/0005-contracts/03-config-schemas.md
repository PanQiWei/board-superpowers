# 03 — Config schemas

> Pin every YAML config the plugin reads or writes:
> `~/.board-superpowers/manifest.yml`,
> `~/.board-superpowers/repos/<normalized>/state.yml`,
> `<repo>/.board-superpowers/config.yml`,
> `~/.board-superpowers/overrides.yml`,
> `~/.board-superpowers/credentials.yml`. Schemas are surfaced in
> their canonical v1 form; this file finalizes the
> `autonomy_overrides:` and `credentials.yml` shapes deferred from
> ADR-0006 § 4 and §5.

---

## Cross-config conventions

These rules apply to every YAML file in this section:

- **Format: YAML.** Per §1.5 cross-cutting principles. YAML over
  TOML rationale at this scale: `config.yml` is the existing
  precedent and gratuitous format diversity costs more than TOML's
  modest type-safety wins.
- **`schema_version: <int>` field on plugin-managed files only.**
  `manifest.yml` and `state.yml` carry it; `config.yml`,
  `overrides.yml`, `credentials.yml` do NOT (they're user-editable
  and use commented-out placeholders for forward extension — the
  YAGNI half of I-12). Per I-11 / I-12.
- **Write protection.** Plugin-managed files (`manifest.yml`,
  `state.yml`) are silently overwritten by the plugin on the next
  state-update cycle if the user hand-edited them. User-editable
  files (`config.yml`, `overrides.yml`, `credentials.yml`) are
  read-only from the plugin's perspective after `bootstrap-project.sh`
  writes the initial `config.yml`.
- **Permissions.** `~/.board-superpowers/` is mode `0700`.
  `~/.board-superpowers/credentials.yml` is mode `0600` — strict.
  `<repo>/.board-superpowers/` inherits the repo's umask.
- **`schema_version` migration policy** (per I-12): integer-bump on
  every additive change; lazy-on-read; older plugin builds reading
  newer-than-known-schema files MUST fail loudly with a
  `please upgrade` message rather than silently dropping unknown
  fields. Migrations are versioned-and-additive — they add fields,
  never remove or rename. See "Migration runner" at the bottom of
  this file.

---

## `~/.board-superpowers/manifest.yml` — HostManifest

Plugin-managed; per-host. Owned by the **HostBootstrap aggregate**
(0003 § 3.3.5).

### Tracked in git? — **No** (per I-13).

### Permissions

Directory `~/.board-superpowers/` is mode `0700`. File mode
inherits umask (typically `0644` after `umask 022`).

### v1 schema

```yaml
schema_version: 1
host_bootstrapped_at: "2026-04-26T10:30:00Z"   # ISO 8601 UTC
last_seen_version: "0.1.0"                      # semver string
```

### Field types and defaults

| Field | Type | Required? | Notes |
|-------|------|-----------|-------|
| `schema_version` | integer | yes | `1` at v1; bumped per I-12 on every additive migration |
| `host_bootstrapped_at` | string (ISO 8601, UTC, `Z` suffix) | yes | Set once at F-B1 firing; never updated |
| `last_seen_version` | string (semver) | yes | Updated by F-B3 at every host version transition |

### Origin

§1.5 (the canonical sample lives in `0002-product-features-and-flows/05-bootstrap-surface.md`).

### Rationale link

- §1.5.1 F-B1 — first-time host bootstrap fills this file.
- §1.5.3 F-B3 — host version-transition updates `last_seen_version`.
- 0003 § 3.3.5 HostBootstrap aggregate — entity-level home.

---

## `~/.board-superpowers/repos/<normalized-repo-path>/state.yml` — RepoState

Plugin-managed; **host-local, per-repo**. Owned by the
**RepoBootstrap aggregate** (0003 § 3.3.6).

### Path normalization

`<normalized-repo-path>` is the repo's absolute path with the
leading `/` stripped and every remaining `/` replaced by `-`.

| Repo absolute path | Normalized directory name |
|--------------------|---------------------------|
| `/Users/panqiwei/my-project-repo` | `Users-panqiwei-my-project-repo` |
| `/Users/panqiwei/Dev/repos/nemori-ai/board-superpowers` | `Users-panqiwei-Dev-repos-nemori-ai-board-superpowers` |
| `/home/alice/work/api-server` | `home-alice-work-api-server` |

Each repo on each host gets exactly one `state.yml`; multiple hosts
working on the same git remote independently maintain their own.

### Tracked in git? — **No** (host-local).

`state.yml` lives outside any repo and is never committed. Each
architect's host independently runs F-B2 once per repo, writes its
own `state.yml`, and uses it thereafter. Multi-architect symmetry
(I-3) holds because each host is independent — there is no shared
file to silently overwrite across collaborators. Collaboration
visibility surfaces through `<repo>/.board-superpowers/config.yml`
(committed) and the routing block in `CLAUDE.md` / `AGENTS.md`
(committed); the bootstrap fact itself is local to each architect.

### v1 schema

```yaml
schema_version: 1
repo_bootstrapped_at: "2026-04-26T11:00:00Z"
last_seen_version_in_repo: "0.1.0"
features_enabled:
  - bootstrap.host
  - bootstrap.per_repo
routing_blocks:
  - target_file: "CLAUDE.md"
    block_hash: "sha256:<64-hex-lowercase>"
    injected_at: "2026-04-26T11:00:01Z"
  - target_file: "AGENTS.md"
    block_hash: "sha256:<64-hex-lowercase>"
    injected_at: "2026-04-26T11:00:01Z"
```

### Field types and defaults

| Field | Type | Required? | Notes |
|-------|------|-----------|-------|
| `schema_version` | integer | yes | `1` at v1 |
| `repo_bootstrapped_at` | string (ISO 8601, UTC) | yes | Set once at F-B2 firing on this host |
| `last_seen_version_in_repo` | string (semver) | yes | Updated by F-B4 at every per-host repo version transition |
| `features_enabled` | list of strings | yes | Feature IDs in dotted form (`bootstrap.host`, `bootstrap.per_repo`, …). At v1 a list (on/off only); future migration converts list → map of `feature_id` → config blob |
| `routing_blocks` | list of objects | yes | One element per file the plugin tracks: at minimum `CLAUDE.md` and `AGENTS.md`. List form (not map keyed by filename) so adding a new target file is an append, not a schema change |
| `routing_blocks[].target_file` | string (repo-relative path) | yes | E.g. `CLAUDE.md`, `AGENTS.md`, future `.cursorrules` |
| `routing_blocks[].block_hash` | string `sha256:<64 hex>` | yes | SHA256 (lowercase hex) of bytes between the marker pair, **excluding** the markers themselves |
| `routing_blocks[].injected_at` | string (ISO 8601, UTC) | yes | Updated each time F-B4 re-injects this entry |

### `block_hash` exact format

`sha256:` (literal prefix) + 64 lowercase hex characters. Total
length: 71 characters. Per F-B2 + F-B4 pin in §1.5.5 / I-11.

The hash is computed over **bytes between** the marker pair,
**excluding** `<!-- board-superpowers:routing -->` and
`<!-- /board-superpowers:routing -->` themselves. Trailing newline
inclusion: include the final `\n` before the closing marker (so
"block content" matches what the SoT file at
`skills/using-board-superpowers/references/agentsmd-routing.md`
emits). Whitespace between the markers and the block content is
also part of the hashed region — re-injection writes a deterministic
form (one blank line above and below the block within the markers).

### Rationale link

- §1.5.2 F-B2 — initial write (incl. `block_hash` first computation).
- §1.5.4 F-B4 — `block_hash` re-check + 3-way prompt on mismatch.
- I-10 (mirror rule), I-11 (plugin-owned vs user-owned region),
  I-12 (schema versioning), I-13 (state.yml host-local, never in git).
- 0003 § 3.3.6 RepoBootstrap aggregate — entity home.
- [`07-path-conventions.md`](./07-path-conventions.md) "Per-host
  layout — `~/.board-superpowers/`" — directory structure +
  normalization rule canonical home.

---

## `<repo>/.board-superpowers/config.yml` — RepoConfig

User-editable; per-repo. Owned by the **RepoConfig aggregate**
(0003 § 3.3.7).

### Tracked in git? — **Yes** (per I-13). Team-shared.

### v1 schema

```yaml
# board-superpowers project config.
# Managed by using-board-superpowers. Safe to edit by hand.

project: "OWNER/NUMBER"
wip_limit: 5

# Future fields (not yet consumed):
#   base_branch: main
#   default_execution_skill: superpowers:subagent-driven-development
#   autonomy_overrides:                # see 03-config-schemas.md
#     - action_id: 5
#       class: A
#       since: "2026-05-15T09:00:00Z"
#       evolved_by: "github_username"
```

### Field types and defaults

| Field | Type | Required? | Default | Notes |
|-------|------|-----------|---------|-------|
| `project` | string in `OWNER/NUMBER` form (YAML quoting is stylistic; the value is the bare string) | yes | — | Round-trip stable per ADR-0005 (BoardAdapter `parse / serialize`). The example `project: "OWNER/NUMBER"` is YAML-quoted only to avoid the `/` parser quirk; `project: OWNER/NUMBER` is also valid. |
| `wip_limit` | positive integer | no | `5` | Soft limit; counted as `In Progress + In Review`; `Blocked` does NOT count (I-6) |
| `base_branch` | string (branch name) | no (commented placeholder) | `main` (auto-detected from `origin/HEAD`) | Future; not yet read by `claim-card.sh` |
| `default_execution_skill` | string | no (commented placeholder) | `superpowers:subagent-driven-development` | Future |
| `autonomy_overrides` | list of objects | no (commented placeholder at v1) | `[]` | See "Autonomy overrides schema" below |

### No `schema_version` field

Per I-11 / I-12 / §1.5 cross-cutting: `config.yml` is **not**
schema-versioned. Future fields appear as commented-out placeholders
rather than schema-version migrations, deliberately matching the
existing hand-editable convention. Editing `config.yml` is the
architect's prerogative; the plugin reads it and never rewrites it
beyond the initial `bootstrap-project.sh` write.

### Rationale link

- §1.5.2 F-B2 — initial write by `bootstrap-project.sh`.
- I-6 (WIP limit), I-11, I-13.
- ADR-0005 (BoardAdapter — `project:` round-trip stability).
- ADR-0006 §4 (autonomy overrides — finalized below).
- 0003 § 3.3.7 RepoConfig aggregate — entity home.

---

## `~/.board-superpowers/overrides.yml` — user-layer autonomy overrides

User-editable; per-host (applies to every project on this machine).
Optional: only present if the architect chose to promote at least
one R-class action across all projects.

### Tracked in git? — **No** (lives at `~/.board-superpowers/`).

### v1 schema

```yaml
# board-superpowers user-level autonomy overrides.
# Hand-editable. Applies to every project on this host.
# Per-project overrides in <repo>/.board-superpowers/config.yml take precedence.

autonomy_overrides:
  - action_id: 5             # ADR-0006 §3 matrix row id
    class: A                 # A | R | N (per ADR-0006 §1)
    since: "2026-05-15T09:00:00Z"
    evolved_by: "github_username"
    note: "Backlog → Ready promotion approved after 2 months stable use"
```

### Project-layer mirror

The same schema lives under `autonomy_overrides:` in
`<repo>/.board-superpowers/config.yml`. The two layers merge per
"Merge semantics" below.

### Field types and defaults

| Field | Type | Required? | Notes |
|-------|------|-----------|-------|
| `autonomy_overrides` | list of objects | yes (top-level key) | Empty list `[]` = no overrides |
| `autonomy_overrides[].action_id` | integer | yes | Matrix row id from ADR-0006 §3 (`1`–`14` for Producer rows; `100`–`105` for Consumer rows per [`06-audit-log-schema.md`](./06-audit-log-schema.md)) |
| `autonomy_overrides[].class` | string `A` \| `R` \| `N` | yes | The desired class. v1 supports R → A promotion and (future) A → R demotion. `N` is reserved (no v1 use case; v1 has `N=0` per ADR-0006 §3) |
| `autonomy_overrides[].since` | string (ISO 8601, UTC) | yes | When the override took effect — appears in the AuditEntry that records the override write |
| `autonomy_overrides[].evolved_by` | string | yes | GitHub username (or other architect-identity string) of the person who made the change. Audit purpose. |
| `autonomy_overrides[].note` | string | no | Free-form one-liner explaining the rationale |

### Merge semantics

Project layer **overrides** user layer for any matching `action_id`.

Merge algorithm at action-id resolution time:

1. Start with ADR-0006 §3 matrix defaults.
2. Apply each entry from `~/.board-superpowers/overrides.yml`'s
   `autonomy_overrides` (user layer).
3. Apply each entry from `<repo>/.board-superpowers/config.yml`'s
   `autonomy_overrides` (project layer) — **wins on collision**.
4. Result: effective class for this `action_id` on this project on
   this host.

A missing key at any layer falls through to the next; a missing
key at all layers means use the ADR-0006 default for that
`action_id`.

### Audit gate

Writing or modifying any `autonomy_overrides` entry in
`config.yml` is itself an R-class action (matrix row 10 — modifies
SoT `.board-superpowers/config.yml`). Writing to the user-layer
`overrides.yml` is also an R-class action (the user layer is a
SoT mirror of the per-project SoT — both have identical scrutiny).
Per ADR-0006 §4.

### Rationale link

- ADR-0006 §4 (trust evolution clause; schema deferred to 0005).
- I-4 / P8 (default + override + accountability).
- 0003 § 3.3.7 RepoConfig aggregate — `AutonomyOverride` value
  object.

---

## `~/.board-superpowers/credentials.yml` — audit-DB credentials

User-editable; per-host. Optional: only required if the architect
opted to use a file rather than the `BOARD_SP_AUDIT_DB_URL` env
var. Owned by the **AuditTrail aggregate** at the credential layer
(0003 § 3.3.8).

### Tracked in git? — **No** (lives at `~/.board-superpowers/`,
which is itself outside any repo).

### Permissions: **`0600`** (strict — read+write owner only).

### v1 schema

```yaml
# board-superpowers audit-log database credentials.
# chmod 600. Never commit. Never share.

audit_db_url: "postgresql://user:password@host:5432/dbname"
```

### Field types

| Field | Type | Required? | Notes |
|-------|------|-----------|-------|
| `audit_db_url` | string DSN with one of the accepted URL schemes below | yes if file is present | Connection string. Bare file paths, GitHub URLs, and any public destination are forbidden per ADR-0006 §5. SQLite IS allowed per ADR-0009 (6-scheme allowlist below) but only via the explicit `sqlite://` / `sqlite3://` schemes, and only outside the project tree. |

**Accepted URL schemes** (the prefix is the driver discriminator).
Per ADR-0006 §5 + ADR-0009 (which extended the original 4-scheme
allowlist with `sqlite://` / `sqlite3://`):

| Scheme | Driver | Example |
|--------|--------|---------|
| `postgresql://` | Postgres (canonical) | `postgresql://user:pwd@host:5432/db` |
| `postgres://` | Postgres (alias; same as above) | `postgres://user:pwd@host:5432/db` |
| `mysql://` | MySQL (canonical) | `mysql://user:pwd@host:3306/db` |
| `mysql+pymysql://` | MySQL via PyMySQL driver hint (SQLAlchemy-compatible) | `mysql+pymysql://user:pwd@host/db` |
| `sqlite://` | SQLite (canonical) | `sqlite:///Users/alice/.board-superpowers/repos/Users-alice-projects-foo/audit.db` |
| `sqlite3://` | SQLite (alias; same as above) | `sqlite3:///Users/alice/.board-superpowers/repos/Users-alice-projects-foo/audit.db` |

A second-driver author who lands a new RDBMS adapter MUST add its
scheme prefix to this table in the same PR; no implicit driver
discovery.

**SQLite default path suggestion.** When the architect picks
SQLite during F-B2 step 2e interactive UX,
`bootstrap-project.sh` suggests:

```
~/.board-superpowers/repos/<normalized>/audit.db
```

Co-locating with `state.yml` keeps every per-`(host, repo)`
artifact under the same `0700` parent. Other locations under
`~/.board-superpowers/` are accepted; SQLite paths INSIDE the
project tree (e.g., `<repo>/.board-superpowers/audit.db`)
remain forbidden — the default suggestion deliberately steers
the architect away from project-tree files. Per ADR-0009 +
[`07-path-conventions.md`](./07-path-conventions.md) "Per-repo
layout — `~/.board-superpowers/repos/<normalized-repo-path>/`".

### Resolution priority (env var vs file)

1. `BOARD_SP_AUDIT_DB_URL` env var if set (highest precedence).
2. `~/.board-superpowers/credentials.yml:audit_db_url`.
3. None → audit DB unavailable → all A-class actions degrade to
   R-class until configured (per ADR-0006 §5 fallback rule).

The dual mechanism is finalized here (ADR-0006 §5 deferred to
0005-contracts). Both work; env-var takes precedence so CI / ops
can override per-process without editing files.

### Forbidden destinations

Per ADR-0006 §5 + ADR-0009 — repeated here because it is a
security contract:

- **No SQLite under the project tree.** `<repo>/.board-superpowers/audit.db`
  and any other path inside the repo working tree is forbidden.
  SQLite under `~/.board-superpowers/` IS allowed per ADR-0009
  (typically the default-suggested
  `~/.board-superpowers/repos/<normalized>/audit.db`).
- **No local `.log` file** under the project tree or
  `~/.board-superpowers/`.
- **No card comment / dedicated audit issue / GitHub Discussion**
  destination (audit must not be public).

### Future fields

Reserved for additive migration if needed (e.g., separate
read-only credentials for retro queries, connection-pool sizing
hints). Not landed at v1.

### Rationale link

- ADR-0006 §5 (BYO RDBMS, persistence rules, backend constraint,
  credential mechanism) — finalization deferred to 0005, landing
  here.
- ADR-0009 (allow SQLite as a 6th scheme; default path under
  `~/.board-superpowers/repos/<normalized>/audit.db`) —
  partially supersedes ADR-0006 §5's backend constraint.
- I-13 (state files in git, machine-state files not).
- 0003 § 3.3.8 AuditTrail aggregate (credentials value object,
  invariant block).

---

## Migration runner

Per I-12. Lives at:

```
${CLAUDE_PLUGIN_ROOT}/scripts/migrations/<file>-v<N>-to-v<N+1>.sh
```

Where `<file>` is `manifest`, `state`, or (future) any new
plugin-managed file.

### Trigger semantics

**Lazy-on-read.** A migration fires the first time a session opens
the file for a write that needs the newer fields, NOT eager-on-
startup. Reads of the file in unchanged shape do not trigger a
migration. Per §1.5.5 cross-cutting principles + Confluent Schema
Registry pattern.

### Execution rules

- **Versioned-and-additive only** — migrations add fields. They do
  NOT remove, rename, or reshape existing fields. Removing /
  renaming requires a new ADR + a multi-version deprecation window.
- **Older plugin reading newer file → fail loudly.** When a
  session loads a file with `schema_version` higher than the
  plugin's known max, the plugin refuses to operate on that file
  and emits: `"this state file was written by plugin v<X>;
  you're on v<Y>; please upgrade".` Silently dropping unknown
  fields is forbidden (per I-12).
- **One migration script per (file, source-version) pair.** Chained
  application supports multi-version upgrades.

### Cited rationale

- I-12 (canonical invariant).
- §1.5.5 TBD-Notes "Migration runner timing" — lazy-on-read decision.
- §1.5.4 F-B4 step 2 — when migrations actually fire.
- §1.5.3 F-B3 — manifest migration mirror.

---

## Cross-references

- [`05-github-artifact-schemas.md`](./05-github-artifact-schemas.md) —
  routing-block marker pair format; `block_hash` is the bridge
  between this file and `state.yml`.
- [`06-audit-log-schema.md`](./06-audit-log-schema.md) — the
  `action_id` numbers `autonomy_overrides[].action_id` references.
- [`07-path-conventions.md`](./07-path-conventions.md) — the
  precise filesystem layout of `~/.board-superpowers/` and
  `<repo>/.board-superpowers/`.
- [`08-environment-variables.md`](./08-environment-variables.md) —
  `BOARD_SP_AUDIT_DB_URL` definition.
- ADR-0006 (autonomy boundary, audit-log persistence; `autonomy_overrides:`
  schema previously deferred here, finalized above).
- ADR-0007 C-PLUGIN-1/-2/-3 (constrains which contracts are even
  allowed).
- §1.5 (the canonical schemas this file normalizes).
- 0003 § 3.3.5–3.3.8 (entity-level homes for each file).
- I-10, I-11, I-12, I-13 (the four invariants this file
  operationalizes).
