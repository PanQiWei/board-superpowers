# DB write conventions — invoking audit-log-write.sh

The script lives at `$(bsp_plugin_root)/scripts/audit-log-write.sh`.
Callers invoke it from bash with structured args. The script handles
URL parsing, scheme dispatch, parameterized INSERT, and jsonl fallback
on failure. Callers do NOT touch SQL directly.

## Required args

| Arg | Values |
|-----|--------|
| `--action-id` | integer matching a row in classifying-actions/references/matrix.md |
| `--decision` | `A` / `R` / `N` (the result from classifying-actions) |
| `--skill` | the calling skill's name (e.g., `consuming-card`) |
| `--approval-stage` | `auto` / `propose` / `approved` / `rejected` |
| `--outcome` | `success` / `failure` |
| `--payload` | JSON string |

## Optional args

| Arg | Default | When to set |
|-----|---------|-------------|
| `--repo-root` | `bsp_primary_repo_root` from `$PWD` | When invoking from a script that runs outside the repo's git tree |

## Per-action_id payload templates

Each row in the matrix has its own payload shape. Below are the most
common shapes; for the full per-row schema, the implementation lives in
`audit-log-write.sh`.

### `action_id = 100` (Consumer claim card)

```json
{
  "card_number": 42,
  "branch": "claim/42-oauth-callback",
  "worktree": "/home/.../worktrees/proj/claim/42-oauth-callback",
  "session_slug": "s-a7b3",
  "base_branch": "main"
}
```

### `action_id = 1` (Producer create cards)

```json
{
  "card_number": 42,
  "title": "Sign in with Google — happy path",
  "labels": ["type:feature", "size:S"],
  "size": "S",
  "depends_on": [44]
}
```

### `action_id = 2` (Producer edit card body)

```json
{
  "card_number": 42,
  "before_sha256": "sha256:<64-hex>",
  "after_sha256": "sha256:<64-hex>",
  "sections_changed": ["Acceptance Criteria"]
}
```

### `action_id = 8` (Cancel claim — R-class)

```json
{
  "card_number": 42,
  "branch": "claim/42-oauth-callback",
  "rationale": "<why canceling>",
  "delete_branch": true,
  "delete_worktree": false
}
```

For the full per-row catalog (all 14 Producer rows + 14 Consumer rows + 9 Bootstrap rows),
see `docs/architecture/0005-contracts/06-audit-log-schema.md` § "Per-action_id payload sub-schemas"
and the payload templates in this file.

## Quoting and escape

Callers pass `--payload` as a normal shell-quoted string. The script
handles JSON parsing and SQL parameterization internally:

- sqlite path: stdlib `sqlite3` with `?` placeholders → zero injection.
- postgres path: `psql -v key=value` parameters with `:'key'` substitution.
- mysql path: PyMySQL protocol-level params with `%s` placeholders.

No hand-written SQL escape on any path.

## Exit codes

The script exits 0 when the row was written somewhere (DB or jsonl).
Non-zero exit codes (only 2, for arg errors) require caller action.
Degraded modes (DB unavailable, venv missing) are NOT exit-failure
states — they exit 0 after writing to jsonl with a `mode` field
identifying the degradation cause.

## Bootstrap payload templates (action_id 200-208)

Bootstrap rows record the 9 mutating actions of `bootstrapping-repo`
(host manifest + per-repo sub-steps). All are A-class by default;
each writes one entry on success / failure.

| `action_id` | Action |
|-------------|--------|
| 200 | Bootstrap host (manifest write) |
| 201 | Bootstrap project step 2a (labels create) |
| 202 | Bootstrap project step 2c (config.yml + config.local.yml write) |
| 203 | Bootstrap project step 2d (.gitignore append) |
| 204 | Bootstrap project step 2e (credentials.yml write) |
| 205 | Bootstrap project step 2f (uv sync per-repo venv) |
| 206 | Bootstrap project step 2g (audit-init dispatch) |
| 207 | Bootstrap project step 4 (routing block injection) |
| 208 | Bootstrap project step 3 (state.yml write) |

### `action_id = 200` (Bootstrap host)

```json
{
  "host_manifest_path": "/home/.board-superpowers/manifest.yml",
  "schema_version": 2,
  "host_bootstrapped_at": "2026-04-28T05:30:00Z",
  "uv_version": "0.5.7"
}
```

### `action_id = 201` (Bootstrap labels create)

```json
{
  "labels_created": ["type:feature", "type:bug", "..."],
  "labels_skipped": [],
  "owner": "PanQiWei",
  "repo": "board-superpowers"
}
```

### `action_id = 202` (Bootstrap config.yml + config.local.yml write)

```json
{
  "config_path": "/repo/.board-superpowers/config.yml",
  "local_config_path": "/repo/.board-superpowers/config.local.yml",
  "force_overwrite": false
}
```

### `action_id = 203` (Bootstrap gitignore append)

```json
{
  "gitignore_path": "/repo/.gitignore",
  "blocks_appended": ["claims", "venv"],
  "blocks_already_present": []
}
```

### `action_id = 204` (Bootstrap credentials write)

```json
{
  "credentials_path": "/home/.board-superpowers/credentials.yml",
  "scheme": "sqlite",
  "chmod": "0600",
  "via": "interactive_prompt|flag|env|preexisting"
}
```

### `action_id = 205` (Bootstrap uv sync venv)

```json
{
  "venv_path": "/repo/.board-superpowers/.venv",
  "uv_lock_sha256": "...",
  "packages_installed": ["pyyaml", "pymysql"]
}
```

### `action_id = 206` (Bootstrap audit-init dispatch)

```json
{
  "scheme": "sqlite",
  "schema_version_applied": 2,
  "ddl_outcome": "applied|already_at_version"
}
```

### `action_id = 207` (Bootstrap routing injection)

```json
{
  "files_injected": ["AGENTS.md", "CLAUDE.md"],
  "block_sha256": {"AGENTS.md": "...", "CLAUDE.md": "..."},
  "stub_redirect_skipped": []
}
```

### `action_id = 208` (Bootstrap state.yml write)

```json
{
  "state_path": "/home/.board-superpowers/repos/<normalized>/state.yml",
  "schema_version": 1,
  "features_enabled": ["bootstrap.host", "bootstrap.per_repo"]
}
```
