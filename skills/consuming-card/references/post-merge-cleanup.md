# Post-merge cleanup — contract and cron option

Reference for the close-out sequence that runs once the PR
is merged. Two delivery paths exist: interactive (the Consumer
drives cleanup in the same session) and auto-cron (an OS-level
scheduled job drives it).

## Four-part close-out contract

These steps run for every successful card delivery (A-class).

1. **Verify PR state** — `gh pr view <PR_NUMBER> --json state
   --jq '.state'` must return `MERGED`. If `OPEN`, cleanup is
   premature — abort and wait. If `CLOSED` without merge, this
   is the failure-path exit; use the failure-path audit row,
   not the success row.

2. **Verify card status** — query the GitHub Project for the
   card's current Status field. The webhook typically flips to
   `Done` within 30 seconds of merge. If not flipped after 5
   minutes, surface the lag to the architect rather than racing
   to flip manually — a manual flip on top of an in-flight
   webhook creates a duplicate state change.

3. **Local cleanup** —
   ```bash
   git worktree remove \
     "$HOME/.config/superpowers/worktrees/<repo>/claim/<kanban-id>-<key-slug>-<title-slug>"
   git branch -d claim/<kanban-id>-<key-slug>-<title-slug>   # safe-delete; remote already gone
   # e.g., claim/default-42-refactor-cache
   ```
   If `git branch -d` refuses (unmerged commits detected),
   surface to the architect — do not force-delete.

4. **Audit row** — invoke `board-superpowers:auditing-actions`
   for the post-merge cleanup action; payload includes
   `{card_number, pr_number, merged_at, worktree_removed: true,
   branch_deleted: true}`.

## Auto-cron path

When the architect has set `post_merge_cleanup.auto_cron: true`
in `<repo>/.board-superpowers/config.yml`, the Consumer calls
`scripts/install-post-merge-cron.sh --card <N>` at PR-submit
time. The installed cron / launchd entry polls `gh pr view
--json state` every `poll_interval_minutes` (default 15). On
`MERGED`, `scripts/post-merge-cleanup.sh` runs the four-part
close-out above and self-uninstalls. If the PR is still `OPEN`
after `timeout_hours` (default 48 hours), the entry
self-uninstalls and surfaces a notice to the architect.

On macOS the entry is a launchd `.plist` under
`~/Library/LaunchAgents/`. On Linux it is a crontab line.
`install-post-merge-cron.sh --uninstall --card <N>` handles
removal on either platform.

## Failure modes

| Situation | Behaviour |
|-----------|-----------|
| PR `OPEN` past `timeout_hours` | Cron self-uninstalls; architect notified. Manual cleanup required once the PR resolves. |
| PR `CLOSED` without merge | Treat as failure path: transition card to `Blocked`, release the claim, keep the worktree for forensic use. |
| Worktree has uncommitted changes | `git worktree remove` without `--force` refuses. Surface to the architect; do not force-remove. |
| `gh pr view` network timeout | Retry once after 30 s; on second failure, exit without cleanup. Cron fires again next interval. |

## Cross-references

- `scripts/post-merge-cleanup.sh` — executes the four-part
  close-out.
- `scripts/install-post-merge-cron.sh` — installs and
  uninstalls the OS-level scheduler entry.
- `<repo>/.board-superpowers/config.yml` § `post_merge_cleanup`
  — the config block the architect edits to enable auto-cron.
  The block has the shape `{ enabled: bool, interval_minutes:
  int, timeout_hours: int }`.
