# consuming-card — Stage 4: Submit PR, Rework, and Post-merge Cleanup

Full detail for the Submit stage (nodes D1-D3, E1-E2) and the rework loop.

## D1+D2 — PR-submit pre-flight: card body sync (action_id 112)

Before drafting the PR body, sync the card body to reflect the verified state:

1. Fetch the current card body:
   ```bash
   gh issue view <N> --json body --jq '.body' > /tmp/card-<N>-current.md
   ```
2. Toggle every AC checkbox: `[ ]` → `[x]` (implemented and verified),
   or `[!]<one-line reason>` for items split into a follow-up card (with the reason inline).
   Bare `[ ]` is forbidden at PR-submit time — `board-superpowers:enforcing-pr-contract`
   Contract B will reject the PR if any bare `[ ]` remains.
3. If the card's Notes section contains "post-implementation summary goes here" or
   equivalent placeholder, append a 3-5 line summary covering:
   - What shipped (behavioral changes, files added/removed).
   - What is behind a flag or split into a follow-up card.
   - Any decision made during implementation that future readers need to know.
4. Compute SHA256 of before and after for audit evidence:
   ```bash
   sha256sum /tmp/card-<N>-current.md
   # edit to produce /tmp/card-<N>-new-body.md
   sha256sum /tmp/card-<N>-new-body.md
   ```
5. Push the updated body:
   ```bash
   gh issue edit <N> --body-file /tmp/card-<N>-new-body.md
   ```
   If `gh issue edit` returns 504 Gateway Timeout: verify post-edit SHA256 matches
   the draft (modulo GitHub's trailing-newline normalization) before retrying —
   GitHub's backend often commits the edit despite the timeout response.
6. Invoke `board-superpowers:auditing-actions` (action_id 112, A-class):
   payload `{card_number, before_sha256, after_sha256, ac_toggle_count,
   sections_changed: ["Acceptance criteria", ...]}`.

## D1 — PR submit with three-section contract

Draft the PR body using the templates from `board-superpowers:enforcing-pr-contract`
§ "Section templates". The required shape:

```markdown
<one-paragraph description: what changed and why>

## Automated Verification

- [x] <command run> — <result>
...

## Human Verification TODO

- [ ] <what reviewer should click / observe>

## Retro Notes

- <reusable lesson for next Consumer>

Closes #<N>
```

The `## Automated Verification` section is required. `## Human Verification TODO`
is optional but must not be filler (omit the section entirely if there is nothing
for the reviewer to verify). `## Retro Notes` is required when reusable lessons
exist; write `n/a — straightforward fix` if genuinely no lessons.

**Sanctioned submit path**:

```bash
bash scripts/submit-pr.sh --title "<title>" --body-file <path> --card <N>
```

The script performs:
- Contract A validation: three-section shape check.
- Contract B validation: confirms all ACs in the card body are `[x]` or `[!]`.
- Idempotent `Closes #<N>` trailer injection at the end of the body.
- `gh pr create` with the validated body.

If validation fails, the error is printed to stderr naming the specific failure.
Re-edit the body to fix it, then retry. Do NOT bypass the script.

**Why the auto-trailer is load-bearing**: GitHub's PR-merge → Issue-close →
ProjectV2 Auto-close webhook chain fires ONLY when the PR body contains a
`Closes #<N>` (or `Fixes #<N>` / `Resolves #<N>`) keyword at PR-OPEN time.
Two production failures documented: PR #42 / card #34 (no trailer at PR-OPEN);
PR #47 / card #45 (body update via `gh pr edit --body-file` stripped the trailer).
In both cases the webhook did not fire and the card required manual close + Status flip.

**Forbidden paths** (both strip the trailer):
- `gh pr create` directly.
- `gh pr edit --body-file` directly.

**Post-OPEN body updates** (retro note expansion, reviewer-finding writeups):

```bash
bash scripts/submit-pr.sh --update-body --pr <PR-N> --body-file <path> --card <N>
```

The `--update-body` mode uses strip-and-reinject logic to preserve the trailer
across arbitrary body updates. It is idempotent across any number of updates.

## D3 — Review-feedback rework loop

When the reviewer requests changes:

1. Pull changes back into the **same worktree** — do NOT create a new branch.
   The claim branch is `claim/<kanban-id>-<key-slug>-<title-slug>`; all commits
   for this card go on this branch.
2. Re-run Stage 2 (implement) for the requested change.
3. Re-run Stage 3 (verify) in full — verification chain, conditional passes.
4. Re-run Step D2 (AC sync) if any checkbox state changed.
5. Re-run `bash scripts/submit-pr.sh --update-body --pr <PR-N> --body-file <path>
   --card <N>` to update the PR body.
6. Re-push the claim branch — GitHub auto-updates the PR with the new commits.
7. The card stays `In Review`; re-pushing triggers re-review.

Rework actions (commits, pushes, PR body updates) are classified and audited per
the same classify-then-audit protocol as any other mutating action.

## E1 — Post-merge cleanup (action_id 113)

Once the PR is merged:

**Step 1 — Verify PR state**

```bash
gh pr view <PR-N> --json state --jq '.state'
```

Must return `MERGED`. If `OPEN`, cleanup is premature — abort and wait. If `CLOSED`
without merge, this is the failure path (action_id for failure close, not 113).

**Step 2 — Verify card transitioned to Done (2-stage verification)**

The GitHub webhook typically flips Status to `Done` within 30 seconds of merge.

After merge, check Status:

```bash
gh project item-list <project-number> --owner <owner> --format json \
  --jq '.items[] | select(.content.number==<N>) | .["Status"]'
```

If Status is NOT `Done` after 5 minutes, branch on the cause:

**Stage (a) — Verify the PR↔Issue link exists**:

```bash
OWNER=$(gh repo view --json owner --jq .owner.login)
REPO=$(gh repo view --json name --jq .name)
gh api graphql -F owner="$OWNER" -F repo="$REPO" -F pr="<PR-N>" -f query='
  query($owner:String!, $repo:String!, $pr:Int!) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$pr) {
        closingIssuesReferences(first: 10) { nodes { number } }
      }
    }
  }' --jq '.data.repository.pullRequest.closingIssuesReferences.nodes'
```

If the result is `[]` (empty), the `Closes #<N>` trailer was missing at PR-OPEN
time. The webhook chain cannot be retroactively replayed. Manual recovery:

1. Edit the PR body to add `Closes #<N>` for the audit-trail record (does NOT
   retrigger the webhook): `gh pr edit <PR-N> --body-file <amended>`.
2. Manually close the Issue: `gh issue close <N> --comment "Closing manually —
   PR body missing Closes keyword at OPEN time. Trailer added retroactively;
   does not retrigger webhook."`.
3. Manually flip ProjectV2 Status to `Done` via `gh project item-edit`.
4. Audit row records `recovery_path: "manual close + manual status flip"`.

**Stage (b) — Link exists but webhook lagged**:

If `closingIssuesReferences` returns the card number AND Status is still not `Done`
after 5 minutes, this is webhook-delivery lag. Do NOT flip Status manually —
overlapping flips risk a flip-flop when the lagged webhook arrives. Surface the lag
to the architect and wait.

**Step 3 — Local cleanup**:

```bash
cd ~/Dev/repos/<repo>   # back to repo root (on main)
git worktree remove "$HOME/.config/superpowers/worktrees/<repo>/claim/<kanban-id>-<key-slug>-<title-slug>"
git branch -d claim/<kanban-id>-<key-slug>-<title-slug>
# Remote was already deleted by the merge; local safe-delete only.
```

If `git branch -d` refuses (unmerged commits detected), surface to architect — do
NOT force-delete. Stale worktrees pollute the worktrees directory and confuse
subsequent claim transactions.

**Step 4 — Audit row**:

Invoke `board-superpowers:auditing-actions` (action_id 113):
payload `{card_number, pr_number, merged_at, worktree_removed: true, branch_deleted: true}`.

### Auto-cron path

For Mode-2 overnight batch or any unattended scenario where the Consumer cannot
wait for the merge, install the auto-cron handler at PR-submit time.

`install-post-merge-cron.sh` is a host-mutating operation (writes a cron
entry to the system crontab). Before invoking it, run the classify-then-audit
protocol:

1. Invoke `board-superpowers:classifying-actions` with `action_id 113` (post-merge
   cleanup, cron-install variant). Expected result: A-class (autonomous).
2. Invoke `board-superpowers:auditing-actions` (action_id 113, A-class, 1 entry).
3. Then invoke the script:

```bash
bash scripts/install-post-merge-cron.sh --card <N>
```

The cron polls `gh pr view --json state` every `poll_interval_minutes` (default 15)
for up to `timeout_hours` (default 48). On `MERGED`, runs the four-part close-out
above and self-uninstalls. On `OPEN` past `timeout_hours`, self-uninstalls and
surfaces a notice to the architect.

Enable via `post_merge_cleanup.auto_cron: true` in
`<repo>/.board-superpowers/config.yml`.

## E2 — Crash / failure path

If the Consumer session exits abnormally (context compaction, timeout, system crash)
before Stage 4 completes:

1. Record a heartbeat audit row marking the partial state (invoke
   `board-superpowers:auditing-actions` with `event_type: session_crash`).
2. Leave the worktree intact — it is the forensic record.
3. Post a card comment summarizing the last known good state and the exact stage
   reached (e.g., "Session crashed after Stage 3 verify, before PR submit").

The next Consumer session resumes by reading the card body + comments,
`cd`-ing into the existing worktree, and picking up from Stage 4 (re-running
the pre-flight and PR submit steps if not completed).
