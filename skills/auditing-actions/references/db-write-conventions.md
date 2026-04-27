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

For the full per-row catalog (all 14 Producer rows + 12 Consumer rows),
read the `audit-log-write.sh` source — each row's INSERT path documents
its required and optional payload fields.

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
