# 03 — Config schemas

> Pin every YAML config the plugin reads or writes:
> `~/.board-superpowers/settings.yml` (host-shared),
> `~/.board-superpowers/repos/<repo-identity>/settings.yml` (repo-shared),
> `~/.board-superpowers/repos/<repo-identity>/credentials.yml` (per-repo audit DSN),
> `<repo>/.board-superpowers/settings.yml` (repo-git),
> `<repo>/.board-superpowers/settings.local.yml` (repo-clone).
> Schemas are surfaced in their canonical v0.5.0+ form
> per ADR-0024 (rename), ADR-0021 (two-section layout),
> ADR-0013 (stages_completed[] fingerprint shape), and
> ADR-0015 (per-repo credentials). Supersedes the v0.4.0
> layout of `manifest.yml`, `state.yml`, `config.yml`,
> `config.local.yml`, and host-shared `credentials.yml`
> and `overrides.yml`.
>
> **v0.4.0 → v0.5.0+ name mapping** (ADR-0024):
>
> | v0.4.0 path | v0.5.0+ path | Locality |
> |-------------|-------------|----------|
> | `~/.board-superpowers/manifest.yml` | `~/.board-superpowers/settings.yml` | host-shared |
> | `~/.board-superpowers/overrides.yml` | folded into `~/.board-superpowers/settings.yml` `modules.m8_autonomy` | host-shared |
> | `~/.board-superpowers/repos/<repo-identity>/state.yml` | `~/.board-superpowers/repos/<repo-identity>/settings.yml` | repo-shared |
> | `<repo>/.board-superpowers/config.yml` | `<repo>/.board-superpowers/settings.yml` | repo-git |
> | `<repo>/.board-superpowers/config.local.yml` | `<repo>/.board-superpowers/settings.local.yml` | repo-clone |
> | `~/.board-superpowers/credentials.yml` (host-shared) | `~/.board-superpowers/repos/<repo-identity>/credentials.yml` (per-repo) | repo-shared |

---

## Cross-config conventions

These rules apply to every YAML file in this section:

- **Format: YAML.** Per §1.5 cross-cutting principles. YAML over
  TOML rationale at this scale: `settings.yml` continues the
  existing YAML precedent; gratuitous format diversity costs more
  than TOML's modest type-safety wins.
- **`schema_version: <int>` field** — every `settings.yml` file
  carries a file-level `schema_version` (for the `stages_completed[]`
  entry shape per ADR-0013). Each `modules.<id>` section carries an
  independent per-module `schema_version` (for that module's
  config-item schema per ADR-0021). `credentials.yml` does NOT carry
  `schema_version` (user-editable, hand-editable convention). Per
  I-11 / I-12.
- **Two-section layout (ADR-0021).** Every `settings.yml` file
  carries two top-level data structures:
  1. `stages_completed[]` — machine-managed lifecycle source of
     truth; authoritative; SKILL writes, hook reads for diff.
  2. `modules.<id>` — architect-facing projection by module;
     derived from `stages_completed[]`; SKILL regenerates on
     stage completion; hand-edits detected on next SKILL pass.
- **Write protection.** Plugin-managed `stages_completed[]`
  section is silently overwritten by the plugin on each stage
  completion. `modules.<id>` projection is also SKILL-managed;
  hand-edits trigger detection + re-elicitation (not silent
  overwrite) per ADR-0021. `credentials.yml` is written once by
  the M4 stage; subsequently user-editable.
- **Permissions.** `~/.board-superpowers/` is mode `0700`.
  `~/.board-superpowers/repos/<repo-identity>/credentials.yml`
  is mode `0600` — strict (per ADR-0015). `<repo>/.board-superpowers/`
  inherits the repo's umask.
- **`schema_version` migration policy** (per I-12 + ADR-0013):
  file-level `schema_version` bumps on every additive change to
  the `stages_completed[]` entry shape; per-module `schema_version`
  bumps independently when a module's `compute_target_state()`
  semantics change (ADR-0021). Older plugin builds reading
  newer-than-known-schema files MUST fail loudly with a
  `please upgrade` message rather than silently dropping unknown
  fields. Versioned-and-additive only.

---

## `~/.board-superpowers/settings.yml` — HostManifest (host-shared)

Plugin-managed; per-host. Owned by the **HostBootstrap aggregate**
(0003 § 3.3.5). Replaces `manifest.yml` + `overrides.yml` from
v0.4.0 per ADR-0024. Two-section layout per ADR-0021.

### Tracked in git? — **No** (per I-13).

### Permissions

Directory `~/.board-superpowers/` is mode `0700`. File mode
inherits umask (typically `0644` after `umask 022`).

### v1 schema (v0.5.0+)

```yaml
schema_version: 1
last_seen_plugin_version: "0.5.0"

# Section 1 — machine-managed lifecycle (authoritative)
stages_completed:
  - stage_id: m1.host.write-settings
    status: completed
    completed_at: "2026-04-28T10:30:00Z"
    plugin_version: "0.5.0"
    generation: 1
    target_state_hash: "d4e5f6..."
    target_state:
      uv_version: "0.5.7"
    target_state_schema_version: 1
    last_error: null

# Section 2 — architect-facing projection (derived, SKILL-managed)
modules:
  m1_host_environment:
    schema_version: 1
    uv_version: "0.5.7"
  m8_autonomy:
    schema_version: 1
    autonomy_overrides: []   # folded from legacy overrides.yml
  m9_codex_hooks:
    schema_version: 1
    codex_hooks_registered: true
```

### Field types and defaults (top-level + Section 1)

| Field | Type | Required? | Notes |
|-------|------|-----------|-------|
| `schema_version` | integer | yes | File-level; `1` at v0.5.0; bumped per I-12 on additive changes to entry shape |
| `last_seen_plugin_version` | string (semver) | yes | Updated on each session's SKILL pass |
| `stages_completed[]` | list of stage entries | yes | Authoritative lifecycle source of truth; hook reads for diff (ADR-0012/ADR-0013) |
| `stages_completed[].stage_id` | string | yes | e.g., `m1.host.write-settings`; from registry (ADR-0014) |
| `stages_completed[].status` | enum | yes | `completed \| stale \| deprecated \| failed \| pending-architect-input` |
| `stages_completed[].completed_at` | string (ISO 8601, UTC) | yes when status=completed | When this stage last ran successfully |
| `stages_completed[].plugin_version` | string (semver) | yes | Plugin version at completion time |
| `stages_completed[].generation` | integer | yes | Layer 1 fingerprint — matches registry `generation`; O(1) diff |
| `stages_completed[].target_state_hash` | string (sha256 hex) | yes | Layer 2 fingerprint — sha256 of canonical YAML emit of `target_state` |
| `stages_completed[].target_state` | object | yes | Layer 3 fingerprint — structured ground truth for `stale` diffs |
| `stages_completed[].target_state_schema_version` | integer | yes | Per-stage schema version for `target_state` shape evolution |
| `stages_completed[].last_error` | string or null | yes | Last executor error message; null when status=completed |

### Section 2 — `modules.<id>` keys at host-shared locality

| Module key | Schema version | Content |
|------------|----------------|---------|
| `m1_host_environment` | 1 | `{uv_version: str}` — from m1.host.* stages |
| `m8_autonomy` | 1 | `{autonomy_overrides: [...]}` — folded from legacy `overrides.yml` per ADR-0024 |
| `m9_codex_hooks` | 1 | `{codex_hooks_registered: bool}` — from m9.host.register-codex-hooks |

### Rationale link

- ADR-0024 — rename from `manifest.yml`; fold `overrides.yml`.
- ADR-0021 — two-section layout + per-module `schema_version`.
- ADR-0013 — per-stage entry shape (three-layer fingerprint).
- 0003 § 3.3.5 HostBootstrap aggregate — entity-level home.
- `0002-product-features-and-flows/05-bootstrap-surface-redesign.md`
  § "Four settings files" — design authority.

---

## `~/.board-superpowers/repos/<repo-identity>/settings.yml` — RepoState (repo-shared)

Plugin-managed; **host-local, per-repo**. Owned by the
**RepoBootstrap aggregate** (0003 § 3.3.6). Replaces `state.yml`
from v0.4.0 per ADR-0024. Two-section layout per ADR-0021.

### Repo identity scheme (ADR-0017)

`<repo-identity>` is derived from the repo's GitHub `origin` URL:

```
https://github.com/PanQiWei/board-superpowers.git → PanQiWei-board-superpowers
git@github.com:PanQiWei/board-superpowers.git     → PanQiWei-board-superpowers
```

Strip scheme prefix + `.git` suffix; extract `<owner>/<repo>` path;
replace `/` with `-`. HTTPS and SSH forms resolve to the same key.

Fallback for local-only repos (no `origin`): `_path-<normalized>`
where `<normalized>` is the absolute path with leading `/` stripped
and remaining `/` replaced by `-`. The `_path-` prefix prevents
collision with GitHub identities (GitHub usernames cannot start with
`_`).

All worktrees of the same primary repo share the same
`<repo-identity>` (via `git rev-parse --git-common-dir`), so
worktree-per-Consumer (ADR-0003) works correctly — one bootstrap
per `(host, GitHub repo)`, not per path.

### Tracked in git? — **No** (host-local).

`settings.yml` (repo-shared) lives outside any repo and is never
committed. Multi-architect symmetry (I-3) holds because each host is
independent. Collaboration visibility surfaces through
`<repo>/.board-superpowers/settings.yml` (repo-git, committed) and
the routing block in `CLAUDE.md` / `AGENTS.md` (committed).

### v1 schema (v0.5.0+)

```yaml
schema_version: 1
last_seen_plugin_version: "0.5.0"

# Section 1 — machine-managed lifecycle (authoritative)
stages_completed:
  - stage_id: m4.repo.acquire-dsn
    status: completed
    completed_at: "2026-04-28T11:00:00Z"
    plugin_version: "0.5.0"
    generation: 3
    target_state_hash: "a1b2c3..."
    target_state:
      audit_dsn_configured: true
      dsn_scheme: sqlite
    target_state_schema_version: 1
    last_error: null
  - stage_id: m7.repo.inject-routing-block
    status: completed
    completed_at: "2026-04-28T11:00:01Z"
    plugin_version: "0.5.0"
    generation: 2
    target_state_hash: "e5f6a7..."
    target_state:
      routing_blocks:
        - target_file: "CLAUDE.md"
          block_hash: "sha256:<64-hex-lowercase>"
          injected_at: "2026-04-28T11:00:01Z"
        - target_file: "AGENTS.md"
          block_hash: "sha256:<64-hex-lowercase>"
          injected_at: "2026-04-28T11:00:01Z"
    target_state_schema_version: 1
    last_error: null

# Section 2 — architect-facing projection (derived, SKILL-managed)
modules:
  m4_audit:
    schema_version: 1
    audit_dsn_configured: true
    dsn_scheme: sqlite
  m7_routing:
    schema_version: 1
    routing_blocks:
      - target_file: "CLAUDE.md"
        block_hash: "sha256:<64-hex-lowercase>"
        injected_at: "2026-04-28T11:00:01Z"
      - target_file: "AGENTS.md"
        block_hash: "sha256:<64-hex-lowercase>"
        injected_at: "2026-04-28T11:00:01Z"
```

### Field types and defaults (Section 1 — same shape as host-shared)

Same per-stage entry shape as host-shared `settings.yml` above
(`stage_id`, `status`, `completed_at`, `plugin_version`,
`generation`, `target_state_hash`, `target_state`,
`target_state_schema_version`, `last_error`). Per ADR-0013.

### `block_hash` exact format

`sha256:` (literal prefix) + 64 lowercase hex characters. Total
length: 71 characters. The hash is computed over **bytes between**
the marker pair `<!-- board-superpowers:routing -->` /
`<!-- /board-superpowers:routing -->`, **excluding** the markers
themselves. Trailing newline included; deterministic form (one blank
line above and below the block within the markers). Per I-11.

### Section 2 — `modules.<id>` keys at repo-shared locality

| Module key | Schema version | Content |
|------------|----------------|---------|
| `m4_audit` | 1 | `{audit_dsn_configured: bool, dsn_scheme: str}` — from M4 stages |
| `m7_routing` | 1 | `{routing_blocks: [{target_file, block_hash, injected_at}]}` — from routing-block injection stage |

### Sibling `state.yml` (TTL cache — co-exists with settings.yml)

A separate `~/.board-superpowers/repos/<repo-identity>/state.yml`
co-exists alongside `settings.yml` for fields that are
**hash-excluded** per ADR-0013 (non-deterministic / frequently
updated values must not pollute the fingerprint):

```yaml
# TTL cache — excluded from fingerprint hash (ADR-0013)
external_validated_at: "2026-04-28T11:05:00Z"
external_ttl_seconds: 3600
```

| Field | Type | Purpose |
|-------|------|---------|
| `external_validated_at` | string (ISO 8601, UTC) | Timestamp of last successful external validation (e.g., GitHub API reachability, Status field check) |
| `external_ttl_seconds` | integer | TTL in seconds; external validation is skipped if `now - external_validated_at < external_ttl_seconds` |

### Rationale link

- ADR-0024 — rename from `state.yml`.
- ADR-0017 — GitHub-based repo identity scheme.
- ADR-0021 — two-section layout + per-module `schema_version`.
- ADR-0013 — per-stage entry shape + hash-excluded TTL fields.
- I-10 (mirror rule), I-11 (plugin-owned vs user-owned region),
  I-12 (schema versioning), I-13 (repo-shared, host-local, never in git).
- 0003 § 3.3.6 RepoBootstrap aggregate — entity home.
- [`07-path-conventions.md`](./07-path-conventions.md) "Per-host
  layout — `~/.board-superpowers/`" — directory structure +
  identity scheme canonical home.

---

## `<repo>/.board-superpowers/settings.yml` — RepoConfig (repo-git / team-shared)

User-editable; per-repo. Owned by the **RepoConfig aggregate**
(0003 § 3.3.7). Replaces `config.yml` from v0.4.0 per ADR-0024.
Holds the **team-shared** subset of project config — fields whose
value should be identical for every collaborator on this repo. Two-
section layout per ADR-0021; only the `modules.<id>` section carries
architect-editable config items; `stages_completed[]` is absent
(repo-git locality has no machine-managed stages at v1; it is present
as an empty list for schema consistency).

### Tracked in git? — **Yes** (per I-13). Team-shared.

### v1 schema (v0.5.0+)

```yaml
schema_version: 1
last_seen_plugin_version: "0.5.0"

# Section 1 — lifecycle (empty for repo-git locality at v1)
stages_completed: []

# Section 2 — architect-facing config items (team-shared)
modules:
  m3_board:
    schema_version: 1
    project: "OWNER/NUMBER"
  m10_kanban:
    schema_version: 1
    projection: github-project-v2
  m6_post_merge:
    schema_version: 1
    auto_cron: false
    poll_interval_minutes: 15
    timeout_hours: 48
```

### Field types and defaults (`modules.<id>`)

| Module field | Type | Required? | Default | Notes |
|--------------|------|-----------|---------|-------|
| `modules.m3_board.project` | string in `OWNER/NUMBER` form | yes | — | Round-trip stable per ADR-0005's v1 GitHubProjectAdapter projection (`parse / serialize`). The example `project: "OWNER/NUMBER"` is YAML-quoted only to avoid the `/` parser quirk; `project: OWNER/NUMBER` is also valid. Reads as a deprecated alias for `modules.m10_kanban.project_ref` when the active projection is `github-project-v2` (per ADR-0026 + ADR-0027). |
| `modules.m10_kanban.projection` | enum string | yes | `github-project-v2` | Per ADR-0027 vocabulary anchor (`projection`, not `backend`). v0.5.0 ships `github-project-v2` only; future `linear` / `jira` options added via registry-only enum extension per ADR-0024 + the same-PR `operating-kanban/references/<projection>.md` contract. The full v0.5.0 `modules.m10_kanban` schema (with `project_ref`, `compliance`, multi-kanban `kanbans[]` list) is documented in the dedicated section below. |
| `modules.m6_post_merge.auto_cron` | boolean | no | `false` | Opt-in. When `true`, `install-post-merge-cron.sh --card <N>` is called at PR-submit time |
| `modules.m6_post_merge.poll_interval_minutes` | positive integer | no | `15` | Poll interval for cron-driven post-merge cleanup |
| `modules.m6_post_merge.timeout_hours` | positive integer | no | `48` | Cron self-uninstalls if PR still OPEN past this threshold |

### `block_hash` preservation

The `modules.m7_routing.routing_blocks` entries (routing block
hashes) are stored in the repo-shared `settings.yml`, NOT in the
repo-git file. The repo-git file does not carry routing block state
— that is host-local, per ADR-0017.

### `modules.m10_kanban` block — v0.5.0 planned schema (NOT YET SHIPPED)

> **Status:** forward-looking. Not yet shipped. The block lands in
> `<repo>/.board-superpowers/settings.yml` (per ADR-0024 settings
> rename) under main's M10 module key (per ADR-0021 settings
> modular layering). Bootstrap writes happen via the M10 config-
> item stage `m10.repo.choose-kanban-backend` (ADR-0024 § Part B);
> runtime reads happen via the v0.5.0 `operating-kanban` atomic
> skill (ADR-0025 + [`00-kanban-protocol.md`](./00-kanban-protocol.md)).
> Documented here so consuming code authored against v0.5.0 has a
> single canonical schema reference; pre-v0.5.0 plugin builds MUST
> ignore unknown sub-fields silently rather than fail.

The v0.5.0 `modules.m10_kanban` block makes backend selection
explicit and factors out the GitHub-shaped `project:` field
into a backend-shaped opaque `project_ref` string. Per
[`00-kanban-protocol.md`](./00-kanban-protocol.md) the protocol is
backend-agnostic; the M10 module is where the active
**projection** is named.

```yaml
modules:
  m10_kanban:
    schema_version: 1
    # primary backend selection (M10 config-item stage writes these
    # per ADR-0024 § Part B; honored as the primary kanban shorthand
    # when kanbans list has length 1):
    projection: github-project-v2          # enum: github-project-v2 (linear/jira are v1.x roadmap)
    project_ref: <opaque-string>        # backend-shaped; GitHub uses OWNER/PROJECT_NUMBER (e.g., PanQiWei/3)
    compliance: L0|L1|L2|L3             # advertised compliance level per Kanban Protocol
    # multi-kanban list — v0.5.0 schema reservation; runtime supports
    # length 1 only (per ADR-0026 v1.0 carve-out):
    kanbans:
      - id: primary
        state: active                   # Bound | Active | Suspended | Archived | Retired
        projection: github-project-v2
        project_ref: <opaque-string>
        role: primary                   # exactly 1 primary required
        # optional: compliance, description, wip_limit_local
```

#### v0.5.0 field types and defaults

| Field | Type | Required? | Default | Notes |
|-------|------|-----------|---------|-------|
| `modules.m10_kanban.schema_version` | int | yes | `1` | Per ADR-0021 modular schema_version contract. Bump on additive change; new ADR for any field rename or removal. |
| `modules.m10_kanban.projection` | string enum | yes (M10 single-backend shorthand) | — | v0.5.0 ships `github-project-v2` only. `linear` / `jira` / future backends are v1.x roadmap; adding a value requires a same-PR `operating-kanban/references/<backend>.md` reference per the protocol "second-adapter authors" contract. |
| `modules.m10_kanban.project_ref` | string (opaque, backend-shaped) | yes (M10 shorthand) | — | Parsed and round-trip-stable per the active backend's projection, NOT per the protocol. For `github-project-v2`: `OWNER/PROJECT_NUMBER` (same shape the legacy top-level `project:` field carried). Per [`00-kanban-protocol.md`](./00-kanban-protocol.md) `Card.key` / identity rules: `project_ref` is opaque to the agent — never parsed past what the backend reference declares. |
| `modules.m10_kanban.compliance` | string enum `L0` \| `L1` \| `L2` \| `L3` | yes | `L1` (when omitted; subject to v0.5.0 finalization) | Advertised compliance level. Authoritative semantics live in [`00-kanban-protocol.md`](./00-kanban-protocol.md). The `operating-kanban` skill reads this field to decide which actions are guaranteed available on this backend / this repo. |
| `modules.m10_kanban.kanbans` | list (objects) | no (v0.5.0); yes (v1.x multi-kanban) | derived from M10 shorthand | List-shaped projection of the kanban registry per ADR-0026. v1.0 runtime hard-fails on length > 1 (ADR-0026 v1.0 carve-out). When omitted, runtime synthesizes a length-1 list from the M10 shorthand fields. |
| `modules.m10_kanban.legacy_claims` | list (mapping) | no | `[]` | Migration register written by the unified setup-stages flow inside `bootstrapping-repo` (per [ADR-0012](../adr/0012-unified-check-script-trigger-model.md), which absorbed the formerly deferred `migrating-repo-version` scope; per ADR-0026 § Branch naming Migration). Stores v0.4.x claim branch metadata bound to the primary kanban's id during the legacy-parser transition window. |

#### Migration from the v0.4.x top-level `project:` field

Legacy v0.4.x and earlier `config.yml` files carry `project:
"OWNER/NUMBER"` at the top level. v0.5.0 plugin builds (which
read `settings.yml` per ADR-0024) MUST treat that as equivalent to:

```yaml
modules:
  m10_kanban:
    schema_version: 1
    projection: github-project-v2
    project_ref: <legacy-project-value>
    compliance: <v0.5.0 default>
```

The M10 config-item stage SHOULD write the explicit
`modules.m10_kanban` block on next bootstrap re-run; an architect
who hand-edits MAY add it directly. The legacy top-level
`project:` field is read-compatible indefinitely — removal would
be a breaking change requiring its own ADR.

#### Multi-kanban roadmap (v1.x)

ADR-0026 ships the `modules.m10_kanban.kanbans` list shape at
v0.5.0 schema layer, with v1.0 runtime hard-failing on list length
> 1. v1.x runtime expansion lifts that constraint; the M10
shorthand fields stay valid for the primary kanban's projection.

### Rationale link

- ADR-0024 — rename from `config.yml`; two-section layout.
- ADR-0021 — `modules.<id>` config-item projection.
- I-11, I-13.
- ADR-0005 — v1 GitHubProjectAdapter projection (round-trip
  stability of `project:` / `project_ref:` for the GitHub backend).
- ADR-0025 + [`00-kanban-protocol.md`](./00-kanban-protocol.md) —
  Kanban Protocol top-level contract; rationale for the `kanban:`
  block's backend / project_ref / compliance shape.
- 0003 § 3.3.7 RepoConfig aggregate — entity home.
- [`06-audit-log-schema.md`](./06-audit-log-schema.md) —
  action_id 113 (post-merge cleanup audit row) that
  `modules.m6_post_merge.auto_cron: true` triggers on each cron run.

---

## `<repo>/.board-superpowers/settings.local.yml` — LocalRepoConfig (repo-clone / per-user)

User-editable; per-repo, per-architect. Owned by the **RepoConfig
aggregate** at the per-user layer (0003 § 3.3.7). Replaces
`config.local.yml` from v0.4.0 per ADR-0024. Holds the
fields that should NOT be team-coordinated:

- `modules.m5_repo_configuration.wip_limit` — personal capacity /
  parallelism choice. Alice running 5 parallel Consumer agents and
  Bob running 1 is not a team-coordination decision; it is each
  architect's local capacity preference (ADR-0024, new stage).
- `modules.m8_autonomy.autonomy_overrides` (per-project layer) —
  personal risk-tolerance choice. Per ADR-0006 §4, each architect
  may promote different R-class actions to A-class without
  imposing that promotion on collaborators.

### Tracked in git? — **No**. Gitignored via the project-wide `*.local.*` pattern.

The `*.local.*` pattern is a project-wide convention: any file
whose name matches `<basename>.local.<ext>` is gitignored
regardless of directory. This generalizes the per-user override
file convention beyond board-superpowers — any future per-user
file in any directory follows the same rule.

### v1 schema (v0.5.0+)

```yaml
schema_version: 1
last_seen_plugin_version: "0.5.0"

# Section 1 — lifecycle (empty for repo-clone at v1)
stages_completed: []

# Section 2 — per-user config items (gitignored)
modules:
  m5_repo_configuration:
    schema_version: 1
    wip_limit: 5
  m8_autonomy:
    schema_version: 1
    # Per-project autonomy overrides (per ADR-0006 §4).
    # Merge precedence: this file's entries beat host-shared
    # settings.yml entries on conflict (project-specific beats
    # user-global).
    autonomy_overrides: []
    #   - action_id: 5
    #     class: A
    #     since: "2026-05-15T09:00:00Z"
    #     evolved_by: "github_username"
    #     note: "..."
```

### Field types and defaults

| Module field | Type | Required? | Default | Notes |
|--------------|------|-----------|---------|-------|
| `modules.m5_repo_configuration.wip_limit` | positive integer | no | `5` | Soft limit; counted as `In Progress + In Review`; `Blocked` does NOT count (I-6). Each architect sets their own value. |
| `modules.m8_autonomy.autonomy_overrides` | list of objects | no | `[]` | Per-project layer. Merge precedence: this file beats host-shared `~/.board-superpowers/settings.yml:modules.m8_autonomy` on conflict. Per ADR-0006 §4. |

### Bootstrap behavior

The `m5.repo.set-wip-limit` stage (ADR-0024) writes the initial
`settings.local.yml` with sensible defaults, including the
`wip_limit` prompt. The file is gitignored before the first commit,
so subsequent collaborators running the setup stages will each
generate their own.

### Rationale link

- ADR-0024 — rename from `config.local.yml`; new `m5.repo.set-wip-limit` stage.
- ADR-0021 — two-section layout + per-module `schema_version`.
- I-6 (WIP limit), I-11, I-13 (per-user state not in git).
- ADR-0006 §4 (autonomy overrides — project / user layers).
- 0003 § 3.3.7 RepoConfig aggregate — per-user layer.

---

## Autonomy overrides — folded into `settings.yml` (ADR-0024)

> **`~/.board-superpowers/overrides.yml` is superseded.** In
> v0.5.0+ the user-layer autonomy overrides are folded into
> `~/.board-superpowers/settings.yml:modules.m8_autonomy`
> (host-shared locality). The per-project layer moves to
> `<repo>/.board-superpowers/settings.local.yml:modules.m8_autonomy`
> (repo-clone locality). The standalone `overrides.yml` file is
> no longer written or read by v0.5.0+ plugin.

The `autonomy_overrides[]` entry shape is unchanged from v0.4.0:

| Field | Type | Required? | Notes |
|-------|------|-----------|-------|
| `action_id` | integer | yes | Matrix row id from ADR-0006 §3 (`1`–`14` for Producer; `100`–`113` for Consumer; `200`–`208` for Bootstrap) |
| `class` | string `A` \| `R` \| `N` | yes | Desired class. v1 supports R → A promotion and (future) A → R demotion |
| `since` | string (ISO 8601, UTC) | yes | When the override took effect |
| `evolved_by` | string | yes | GitHub username of the person who made the change |
| `note` | string | no | Free-form one-liner explaining the rationale |

### Merge semantics (unchanged)

1. Start with ADR-0006 §3 matrix defaults.
2. Apply `~/.board-superpowers/settings.yml:modules.m8_autonomy.autonomy_overrides`
   (user layer, host-shared).
3. Apply `<repo>/.board-superpowers/settings.local.yml:modules.m8_autonomy.autonomy_overrides`
   (project layer, repo-clone) — **wins on collision**.
4. Result: effective class for this `action_id` on this project on
   this host.

### Audit gate (unchanged)

Writing or modifying any `autonomy_overrides` entry is itself an
R-class action (matrix row 10 — modifies SoT). Per ADR-0006 §4.

### Rationale link

- ADR-0024 — fold `overrides.yml` into host-shared `settings.yml`.
- ADR-0006 §4 (trust evolution clause).
- I-4 / P8 (default + override + accountability).
- 0003 § 3.3.7 RepoConfig aggregate — `AutonomyOverride` value object.

---

## `~/.board-superpowers/repos/<repo-identity>/credentials.yml` — audit-DB credentials (per-repo)

User-editable; **per-repo** (not per-host). Optional: only required
if the architect opted to use a file rather than the
`BOARD_SP_AUDIT_DB_URL` env var. Owned by the **AuditTrail
aggregate** at the credential layer (0003 § 3.3.8). Moved from
host-shared `~/.board-superpowers/credentials.yml` to per-repo
per ADR-0015.

**Why per-repo (ADR-0015):** the host-shared file caused all repos
on the host to share one audit DB, defeating per-repo isolation.
`credentials.yml` now lives alongside `settings.yml` and `audit.db`
in the same `<repo-identity>` directory — one audit backend per
repo, by construction.

### Tracked in git? — **No** (lives outside any repo).

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
| `sqlite://` | SQLite (canonical) | `sqlite:////Users/alice/.board-superpowers/repos/Users-alice-projects-foo/audit.db` |
| `sqlite3://` | SQLite (alias; same as above) | `sqlite3:////Users/alice/.board-superpowers/repos/Users-alice-projects-foo/audit.db` |

**SQLite uses 4 slashes for absolute paths** (`sqlite:////` then
`/Users/...`). The 3-slash form (`sqlite:///relative/path`) is
interpreted relative to `cwd` per SQLAlchemy convention and would
silently write the file to the wrong location. Because the
default path under
`~/.board-superpowers/repos/<normalized>/audit.db` is always
absolute, every `sqlite://` / `sqlite3://` DSN this plugin emits
or accepts MUST use the 4-slash form. Verifiable via
`from sqlalchemy.engine import make_url;
make_url('sqlite:////abs/path').database == '/abs/path'`.

A second-driver author who lands a new RDBMS adapter MUST add its
scheme prefix to this table in the same PR; no implicit driver
discovery.

**SQLite default path suggestion.** When the architect picks
SQLite during the `m4.repo.acquire-dsn` agentic stage,
the SKILL suggests:

```
~/.board-superpowers/repos/<repo-identity>/audit.db
```

Co-locating with `settings.yml` and `credentials.yml` keeps every
per-`(host, repo)` artifact under the same `0700` parent. Other
locations under `~/.board-superpowers/` are accepted; SQLite paths
INSIDE the project tree (e.g., `<repo>/.board-superpowers/audit.db`)
remain forbidden — the default suggestion deliberately steers
the architect away from project-tree files. Per ADR-0009 + ADR-0015 +
[`07-path-conventions.md`](./07-path-conventions.md) "Per-host
layout — `~/.board-superpowers/`".

### Resolution priority (env var vs file)

1. `BOARD_SP_AUDIT_DB_URL` env var if set (highest precedence).
2. `~/.board-superpowers/repos/<repo-identity>/credentials.yml:audit_db_url`
   (per-repo, per ADR-0015).
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
  `~/.board-superpowers/repos/<repo-identity>/audit.db`) —
  partially supersedes ADR-0006 §5's backend constraint.
- ADR-0015 (per-repo credentials.yml locality — replaces
  host-shared location from v0.4.0).
- I-13 (state files in git, machine-state files not).
- 0003 § 3.3.8 AuditTrail aggregate (credentials value object,
  invariant block).

---

## Schema migration model (v0.5.0+)

Per I-12 + ADR-0013. The v0.5.0 setup-stages redesign replaces
the v0.4.0 shell-script migration runner with a lifecycle-based
approach:

### Trigger semantics (setup-stages model)

**Generation-based drift detection.** A stage re-runs when:
- The stage's recorded `generation` in `stages_completed[]` differs
  from the current registry entry's `generation` (fast-path, O(1)).
- The stage's recorded `target_state_hash` differs from the hash
  of the current `compute_target_state()` output (backstop for
  forgotten-generation-bump bugs).

No explicit "migration runner" script. Each module's
`compute_target_state()` IS the migration spec — when a module
evolves, the maintainer bumps `generation` in the registry; the
lifecycle diff sees `stale` and the SKILL re-runs with structural
diff messages.

### Execution rules

- **Versioned-and-additive only** — `stages_completed[]` entry
  shape changes bump the file-level `schema_version`. Module
  schema changes bump the per-module `schema_version` under
  `modules.<id>`.
- **Older plugin reading newer file → fail loudly.** When a
  session loads a `settings.yml` with `schema_version` higher than
  the plugin's known max, the plugin refuses to operate and emits:
  `"this settings file was written by plugin v<X>; you're on v<Y>;
  please upgrade".` Silently dropping unknown fields is forbidden
  (per I-12).
- **Module-local migration.** Each module's stage(s) re-run when
  `generation` or `target_state_hash` drifts. No central migration
  script directory.

### Pre-v1 breaking change posture

v0.4.0 → v0.5.0 is a **pre-v1 breaking rename**. No in-place
migration logic ships. Architects upgrading from v0.4.0:
1. Delete `~/.board-superpowers/` (or relevant per-repo dirs).
2. Re-bootstrap. The unified check-script (ADR-0012) sees all
   stages as `never-run` and triggers `bootstrapping-repo`.

### Cited rationale

- I-12 (canonical invariant).
- ADR-0012 — unified check-script trigger model.
- ADR-0013 — three-layer fingerprint + 5-state lifecycle.
- ADR-0014 — stage registry `generation` / `compute_target_state()`.
- `0002-product-features-and-flows/05-bootstrap-surface-redesign.md`
  § "Schema-migration seam" + § "Cross-version evolution".

---

## Cross-references

- [`00-kanban-protocol.md`](./00-kanban-protocol.md) — top-level
  Kanban Protocol; the v0.5.0 `kanban:` block above names the
  active backend projection and its compliance level.
- [`05-github-artifact-schemas.md`](./05-github-artifact-schemas.md) —
  routing-block marker pair format; `block_hash` is the bridge
  between this file and `settings.yml` (repo-shared). The artifact
  schemas in 05 are specifically the v1 GitHubProjectAdapter
  projection's contracts; under the `modules.m10_kanban` block they
  apply when `modules.m10_kanban.projection = github-project-v2`
  (per ADR-0026 + ADR-0027 vocabulary anchor).
- [`06-audit-log-schema.md`](./06-audit-log-schema.md) — the
  `action_id` numbers `autonomy_overrides[].action_id` references.
- [`07-path-conventions.md`](./07-path-conventions.md) — the
  precise filesystem layout of `~/.board-superpowers/` and
  `<repo>/.board-superpowers/`.
- [`08-environment-variables.md`](./08-environment-variables.md) —
  `BOARD_SP_AUDIT_DB_URL` definition.
- ADR-0012 — unified check-script trigger model; reads `stages_completed[]`
  from this file's format on every SessionStart.
- ADR-0013 — per-stage entry shape (three-layer fingerprint); the
  canonical authority for `stages_completed[]` field semantics.
- ADR-0014 — stage registry contract; the `generation` and
  `compute_target_state()` fields that this file's `stages_completed[]`
  entries are compared against.
- ADR-0015 — per-repo `credentials.yml` locality.
- ADR-0017 — GitHub-based repo identity; the `<repo-identity>` key in
  `~/.board-superpowers/repos/<repo-identity>/`.
- ADR-0021 — two-section layout + per-module `schema_version`.
- ADR-0024 — settings.yml rename; fold `overrides.yml`.
- ADR-0006 (autonomy boundary, audit-log persistence; `autonomy_overrides:`
  schema folded into `settings.yml:modules.m8_autonomy`).
- ADR-0007 C-PLUGIN-1/-2/-3 (constrains which contracts are even
  allowed).
- `0002-product-features-and-flows/05-bootstrap-surface-redesign.md`
  — design authority for the four settings files.
- 0003 § 3.3.5–3.3.8 (entity-level homes for each file).
- I-10, I-11, I-12, I-13 (the four invariants this file
  operationalizes).
