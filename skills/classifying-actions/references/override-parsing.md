# Override parsing — autonomy_overrides yaml schema + merge precedence

The matrix in `matrix.md` defines defaults. Architects can promote
specific rows from R to A (or demote A to R) via two layers of yaml
overrides.

## Schema

Both layers use the same `autonomy_overrides:` list-of-objects shape:

```yaml
autonomy_overrides:
  - action_id: 5             # integer matching a row in matrix.md
    class: A                 # A | R | N (target class to apply)
    since: "2026-05-15T09:00:00Z"  # ISO 8601 UTC; when override took effect
    evolved_by: "github_username"   # who made the change (audit purpose)
    note: "Backlog → Ready promoted after 2 months stable use"  # optional one-liner
```

Required fields per entry: `action_id`, `class`, `since`, `evolved_by`.
Optional: `note`.

## Two layers

| Layer | File | Scope |
|-------|------|-------|
| User layer | `~/.board-superpowers/overrides.yml` | Applies to every project on this host |
| Project layer | `<repo>/.board-superpowers/config.local.yml` | Applies only to this project on this host |

`config.local.yml` is gitignored via `*.local.*` pattern; per-architect.

## Merge semantics

When resolving the effective class for an `action_id`:

1. Start with the matrix default from `matrix.md`.
2. Apply the matching entry from user layer if present (overrides default).
3. Apply the matching entry from project layer if present (overrides user layer).
4. Result is the effective class.

**Project layer wins on conflict.** Same `action_id` set differently in
both layers → project wins.

## Helper invocation

Callers don't parse yaml directly. The helper `bsp_resolve_autonomy_class
<action_id> <repo_root>` in `scripts/lib/common.sh` handles parsing and
merging, returning the final class on stdout. The helper uses
venv-managed PyYAML; if venv is unavailable, it returns the matrix
default (overrides cannot apply without yaml parsing).

## Audit gate

Writing or modifying any `autonomy_overrides` entry is itself an
R-class action (matrix row 10 — modifies a source-of-truth file).
Architects who want to promote a row write the override + commit it
through the normal R-class flow.
