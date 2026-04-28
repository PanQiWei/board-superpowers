# State on disk

Every file, env var, and external store the plugin reads or writes — with the producer / consumer of each piece, and the degradation behavior when something is unavailable. Read this when you need to debug "why does the plugin think X" or "where would I find the audit row for that action".

## Host-local state (under `~/.board-superpowers/`)

This directory is plugin-managed and host-scoped — never in any repo's git tree. Every entry below is created by the plugin's bootstrap or runtime; the user does not hand-edit them except via the explicit override files.

| Path | Tracked? | Written by | Read by | What it carries |
|------|----------|------------|---------|------------------|
| `~/.board-superpowers/manifest.yml` | host-local | `bootstrap-host.sh`, `bootstrap-project.sh` (appends entries) | SessionStart hook + entry skill (state probe) | List of `(host, repo)` pairs that have been bootstrapped on this machine; absence = "this is a fresh host, route to bootstrapping-repo". |
| `~/.board-superpowers/repos/<normalized>/state.yml` | host-local | `bootstrap-project.sh` (initial write), `bsp_inject_routing_block` (hash updates), `migrating-repo-version` (`last_seen_version_in_repo` bumps) | SessionStart hook, entry skill, tamper-detection routines | Per-`(host, repo)` durable state: `schema_version`, `repo_bootstrapped_at`, `last_seen_version_in_repo`, `features_enabled` list, `routing_blocks[].block_hash` for tamper detection. **Does NOT carry `audit_db_url`** — that lives in `credentials.yml` below. |
| `~/.board-superpowers/repos/<normalized>/audit-local.jsonl` | host-local | `audit-log-write.sh` (only on degradation) | Architect / Consumer manually for "where did action X go" forensics | Append-only jsonl trace of audit rows when the BYO DB write failed; each row carries a `mode` field naming the degradation cause (no DB URL, network unreachable, schema mismatch, etc.). |
| `~/.board-superpowers/credentials.yml` | host-local, chmod `0600` | `bootstrap-project.sh` step 2e (interactive prompt or `--audit-db-url` flag) | `bsp_resolve_audit_db_url` (called by `audit-log-write.sh`) | BYO RDBMS connection string under the `audit_db_url:` key. Resolution priority: `BOARD_SP_AUDIT_DB_URL` env var (highest, ephemeral) → this file → none (caller falls back to jsonl mode=no-db). |
| `~/.board-superpowers/overrides.yml` | host-local | User (hand-edited) | `bsp_resolve_autonomy_class` | Optional. User-level `autonomy_overrides:` map promoting / demoting specific `action_id` defaults. The project-level override file (below) wins on conflict. |

### `<normalized>` derivation

Every per-repo path under `~/.board-superpowers/repos/` is keyed by the `<normalized>` form of the primary repo's absolute path: leading `/` stripped, remaining `/` replaced with `-`. Example: `/Users/foo/proj` → `Users-foo-proj`. The normalization is deterministic in the forward direction but **one-way** — multiple repo paths can collide on the same `<normalized>` (e.g., `/Users/foo-bar/proj` and `/Users/foo/bar/proj` both yield `Users-foo-bar-proj`). Always derive `<normalized>` from a known repo root via `bsp_primary_repo_root` + `bsp_normalize_repo_path`, never by trying to invert it. Using the worktree path or `git rev-parse --show-toplevel` produces a different normalized key and breaks state lookup.

## Per-repo state (under `<repo>/.board-superpowers/`)

This directory lives inside each consuming repo. Two files are intended to be committed (team-shared); `bootstrap-project.sh` writes them but does NOT auto-commit — the architect must `git add` them after bootstrap. The rest are gitignored or runtime-generated.

| Path | Tracked? | Written by | Read by | What it carries |
|------|----------|------------|---------|------------------|
| `<repo>/.board-superpowers/config.yml` | committed | Architect (hand-edited at bootstrap) | `claim-card.sh`, `submit-pr.sh`, `read-board.sh`, every Producer / Consumer skill | Project coordinates (`<owner>/<number>`), team-shared settings (e.g., `base_branch`, `default_execution_skill`). |
| `<repo>/.board-superpowers/config.local.yml` | gitignored (via `*.local.*`) | User (hand-edited) | `bsp_resolve_autonomy_class`, WIP enforcement | Per-user fields: `wip_limit`, `autonomy_overrides:`. Project layer wins over `~/.board-superpowers/overrides.yml` on conflict. |
| `<repo>/.board-superpowers/.venv/` | gitignored | `bootstrap-project.sh` via `uv sync` | Plugin's Python helpers (PyYAML for override parsing, etc.) | Per-repo Python venv. Lives next to `pyproject.toml` and `uv.lock` so plugin-version isolation works repo by repo. |
| `<repo>/.board-superpowers/pyproject.toml` | intended-committed (architect must `git add`) | `bootstrap-project.sh` (copies template) | `uv` toolchain | Plugin runtime deps manifest. NOT in the auto-gitignore — appears as untracked after bootstrap until the architect commits it. |
| `<repo>/.board-superpowers/uv.lock` | intended-committed (architect must `git add`) | `bootstrap-project.sh` (copies template) | `uv` toolchain | Lockfile for deterministic plugin installs across machines. NOT in the auto-gitignore — appears as untracked after bootstrap until the architect commits it. |

## Routing-block files (in the consuming repo's tree)

The plugin injects a fenced markdown block into two files at the consuming repo's root, so any agent session in this repo gets the routing rules from `AGENTS.md` / `CLAUDE.md` auto-load.

| Path | Tracked? | Written by | Hash recorded in | Notes |
|------|----------|------------|------------------|-------|
| `<repo>/AGENTS.md` | committed | `bsp_inject_routing_block` | `state.yml:routing_blocks[]` | Source of truth for both Codex CLI and Claude Code (CC reads via the sibling `CLAUDE.md` shim's `@`-include). |
| `<repo>/CLAUDE.md` | committed | `bsp_inject_routing_block` | `state.yml:routing_blocks[]` | Either the canonical block (when this is the only file) or a one-line stub redirect to `AGENTS.md`. Stub form records no hash. |

The fenced block uses two distinct marker pairs (fence sentinels in the source, injection markers in the target) — see `runtime-mechanism.md` § "Routing block: fence sentinels and target markers" for the byte-level details.

## Environment variables

| Var | Set by | Read by | Effect when unset |
|-----|--------|---------|--------------------|
| `CLAUDE_PLUGIN_ROOT` | Claude Code at plugin load | `hooks/session-start.sh`, every script via `bsp_plugin_root` | Codex CLI uses `CODEX_PLUGIN_ROOT` instead; `bsp_plugin_root` resolves whichever is set. |
| `CODEX_PLUGIN_ROOT` | Codex CLI at plugin load | Same as above | Same as above. |
| `BOARD_SP_WORKTREE_DIR` | User (export in shell rc) | `bsp_pick_worktree_dir`, `bsp_worktree_path` | Default: `${HOME}/.config/superpowers/worktrees`. |

`bsp_plugin_root()` (in `scripts/lib/common.sh`) papers over the CC vs Codex env-var split — always call the helper, never hard-code either var.

## External store: BYO RDBMS

The audit log lives in a user-supplied database (Postgres / MySQL / SQLite, per the 6-scheme allowlist). The connection URL is recorded in `~/.board-superpowers/credentials.yml` under the `audit_db_url:` key (chmod `0600`); `bsp_resolve_audit_db_url` reads it at write time. The runtime override `BOARD_SP_AUDIT_DB_URL` env var beats the file but does not persist.

Schema (one table, `audit_log`):

| Column | Type | Carries |
|--------|------|----------|
| `id` | bigserial / autoincrement | Primary key. |
| `recorded_at` | timestamp | When the row was written (UTC). |
| `action_id` | int | The catalog id (matches the matrix row in `classifying-actions/references/`). |
| `decision` | enum (`A`, `R`, `N`) | What the classifier returned. |
| `skill` | text | The molecular skill that decided. |
| `actor_role` | enum (`producer`, `consumer`) | Who ran the action. |
| `approval_stage` | enum (`auto`, `propose`, `approved`, `rejected`) | A-class rows are `auto`; R-class rows are `propose` then `approved` / `rejected`. |
| `outcome` | enum (`success`, `failure`) | What actually happened. |
| `payload` | json | Per-`action_id` structured payload (card_number, before/after sha, etc.). |
| `mode` | text (nullable) | Degradation cause when present (no DB, schema mismatch); null on direct DB writes. |

`auditing-actions` carries the per-`action_id` payload templates so callers don't have to remember each shape; `audit-log-write.sh` does the actual write and falls back to `audit-local.jsonl` when the DB is unreachable.

## Reading order when debugging

When something looks wrong, walk the state files in this order:

1. **`~/.board-superpowers/manifest.yml`** — does this host think this repo is bootstrapped?
2. **`~/.board-superpowers/repos/<normalized>/state.yml`** — what version did the plugin last see, and are the routing-block hashes still consistent?
3. **`<repo>/.board-superpowers/config.yml` + `config.local.yml`** — are project coords and per-user limits sensible?
4. **`audit_log` table OR `audit-local.jsonl`** — was the action recorded? If only the jsonl has it, the BYO DB was unreachable when the action ran.
5. **GitHub Project + Issue + PR state** — the user-visible truth; if internal records say "merged" but GitHub says "open", trust GitHub.

Most pipeline incidents resolve at step 1 or 2 (a stale or missing host-local file). The deeper steps come into play only when the stored state is consistent but the live behavior is not.

## Lifecycle of these files

The state files come into existence at well-defined moments:

| Moment | What gets created |
|--------|-------------------|
| First-ever session on a host | `~/.board-superpowers/manifest.yml` (empty until the first repo is bootstrapped) |
| First session in a new repo | `<repo>/.board-superpowers/config.yml`, `config.local.yml` template, `pyproject.toml`, `uv.lock`, `.venv/` (created via `uv sync`); `~/.board-superpowers/repos/<normalized>/state.yml`; routing block injected into `AGENTS.md` / `CLAUDE.md`; new entry appended to `manifest.yml` |
| First mutating action | `audit_log` row in BYO RDBMS — OR — `audit-local.jsonl` line if the DB is unreachable |
| Plugin version bump | `state.yml:last_seen_version_in_repo` updated, possibly accompanied by schema migration of the audit table |
| Routing block re-injection | `state.yml:routing_blocks[].block_hash` updated; old hash recorded in case rollback is needed |

Files do NOT get cleaned up when a repo is removed from the host — `manifest.yml` retains the entry and `~/.board-superpowers/repos/<normalized>/` retains the state directory. This is a deliberate choice so accidentally moved or temporarily-offline repos don't lose their plugin state. The user can prune manually.

## Concurrency notes

Two sessions on the same `(host, repo)` reading and writing concurrently is supported — the plugin uses GitHub as the coordination plane, not the host filesystem. The host-local files (`state.yml`, `audit-local.jsonl`) are written via short atomic operations (replace-with-temp-then-rename for yaml, append-only for jsonl), so simultaneous writers do not corrupt them.

What is NOT supported is two sessions claiming the same Card simultaneously — but that contention is detected at the GitHub layer (the second `claim-card.sh` finds the Card already `In Progress` and aborts), not the filesystem.
