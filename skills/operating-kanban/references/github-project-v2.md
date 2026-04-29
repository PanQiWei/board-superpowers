# operating-kanban — github-project-v2 projection reference

The Form A bash CLI projection of the Kanban Protocol for GitHub
Project v2 backends. v0.5.0 ships this as the only live projection
instance; second-projection authors (Linear, Jira, etc.) take this
file as a reference shape for their own `references/<projection-id>.md`.

## Form

Form A (bash CLI). Invocation surface: `gh project` / `gh issue` /
`gh api graphql` calls plus the `bsp_*` helper family from
`scripts/lib/common.sh`. Stdin / stdout / exit-code conventions
follow `form-a-bash.md` § "Invocation conventions" verbatim — this
file refines them only where the GitHub backend imposes
projection-specific behaviour.

## Backend identity

- **Projection ID**: `github-project-v2`. The literal string the
  M10 stage persists into
  `<repo>/.board-superpowers/settings.yml § modules.m10_kanban.<kanban-id>.projection`.
- **`project_ref` shape**: `<owner>/<project-number>` — for example
  `PanQiWei/4`. Round-trip stable; the same shape is used uniformly
  across this projection's invocations so upgrade paths stay
  mechanical.
- **`Card.key`**: the GitHub Issue number rendered as a string —
  `"68"`, not the underlying GraphQL node ID. Per the Kanban
  Protocol § Identity contract, `Card.key` is the display-stable
  opaque string the agent uses in `[board-card:#68]` references.
  GraphQL node IDs are projection-internal and never surface above
  this file.
- **Status field discovery**: a `ProjectV2SingleSelectField` named
  exactly `Status`. The field ID is resolved on first call via
  `bsp_gh_field_id <project-id> Status` and cached per session.
- **Status options**: the six canonical states from the Kanban
  Protocol (Backlog / Ready / In Progress / In Review / Done /
  Blocked). Custom-state folding applies if a user-extended option
  appears on the field — the option folds to `Backlog` with a
  stderr warning, per the Kanban Protocol § "Custom-state folding"
  contract. Folding never fails the dispatch.

## Action invocations

Each protocol action below documents its **invocation pattern**
(the exact `gh` / `bsp_*` shape), **return shape** (the structured
response the dispatcher hands back to the caller), **idempotency**
(whether a re-invocation with the same arguments is safe), and any
**error semantics** beyond the generic exit-code mapping in
`form-a-bash.md`.

### `read_board`

- **Invocation**: `gh project item-list <project-number> --owner
  <owner> --format json --limit <N>`. The dispatcher's helper
  paginates internally when the project has more items than the
  caller's `--limit`.
- **Return**: list of card records `(key, title, status, labels,
  url)`; ordering is GitHub's native creation order, callers sort
  client-side if needed.
- **Idempotency**: pure read.
- **Errors**: exit `4` on rate-limit / 5xx (retryable per
  `Retry-After`); exit `3` on missing `gh project` scope.

### `read_card`

- **Invocation**: `gh issue view <key> --repo <owner>/<repo>
  --json body,title,labels,state,url,createdAt,updatedAt`.
- **Return**: full card record, including the `display_*`
  parent / sub-issue fields when the Issue has sub-issues attached
  via GitHub's tasklists feature.
- **Idempotency**: pure read.
- **Errors**: exit `2` when the Issue exists but is not on the
  Project; exit `1` when the Issue does not exist.

### `create_card`

- **Invocation**: two-call composite —
  `gh issue create --repo <owner>/<repo> --title <title> --body
  <body> --label <l1>,<l2>,...` followed by
  `gh project item-add <project-number> --owner <owner> --url
  <issue-url>`. The dispatcher reads the new Issue's number from
  the first call's stdout and threads it into the second.
- **Return**: the new `Card.key` (Issue number as string).
- **Idempotency**: NOT idempotent. Re-running creates a duplicate
  Issue. The caller's molecular skill guards against duplicate
  creation by reading the board first; this projection does not
  attempt deduplication.
- **Errors**: exit `1` on title collision when the repo has the
  duplicate-title pre-receive hook enabled (rare); exit `4` on
  rate-limit during the `item-add` half (the Issue exists but is
  not on the Project — caller retries `item-add` only).

### `transition_card`

- **Invocation**: resolve the Status field's option ID via
  `bsp_gh_field_option_id <project-id> Status <target-status>`,
  resolve the project item ID via `bsp_gh_item_id <project-id>
  <key>`, then
  `gh project item-edit --project-id <project-id> --id <item-id>
   --field-id <field-id> --single-select-option-id <option-id>`.
- **Return**: `(success | refused | conflict)`. The dispatcher
  layers the protocol-level legality check (per `board-canon`'s
  state machine) on top of the GitHub-level call; refused
  transitions never reach `gh`.
- **Idempotency**: transitioning to the current status is a
  successful no-op.
- **Errors**: exit `2` on illegal protocol-level transition
  (caught before `gh`); exit `4` on GitHub-side conflict (item
  edited concurrently — caller re-reads and re-decides).

### `claim_card`

- **Invocation**: the canonical implementation is
  `scripts/claim-card.sh`, which performs the four-step claim
  transaction (the branch-naming convention `claim/<kanban-id>-<key>-<title-slug>`
  is the atomic single-point-of-truth claim primitive — `git push`
  of that branch is what wins or loses a race between Consumers):
  `transition_card` to `In Progress` → create worktree at
  `$BOARD_SP_WORKTREE_DIR/<repo>/<branch>` → create branch
  `claim/<kanban-id>-<key>-<title-slug>` → `git push origin
  <branch>` (the atomicity boundary). The push wins or loses the
  race; the dispatcher reads `git ls-remote` after a loss to
  surface who won.
- **Return**: `(claim acquired | race lost | wip exceeded |
  refused)`.
- **Idempotency**: NOT idempotent against partial-failure
  mid-transaction — a script crash between status flip and push
  leaves the card in an `In Progress` state with no branch on
  origin. Recovery is via `release_claim` + retry.
- **Errors**: exit `2` on race-loss (another Consumer's push
  arrived first); exit `2` on WIP cap exceeded (per
  `board-canon`'s WIP formula).

### `release_claim`

- **Invocation**: composite — `git push origin --delete
  claim/<kanban-id>-<key>-<title-slug>` to delete the remote
  branch, plus `transition_card` back to `Ready` (the default;
  callers may override the post-release status when releasing as
  part of a `Done` merge). The composite-key `(kanban_id,
  Card.key)` is preserved across release + re-claim, so a
  released card stays addressable in the audit log and in
  subsequent claim attempts.
- **Return**: `(released | not held | branch already gone)`.
- **Idempotency**: re-releasing an already-released claim is a
  no-op; the second `git push --delete` returns "remote ref does
  not exist" which the dispatcher treats as success.

### `link_pr_to_card`

- **Invocation**: PR-body trailer injection — the dispatcher
  ensures the PR body contains `Closes #<key>` so GitHub's
  auto-link / auto-close webhook chain fires on merge. The
  trailer is idempotent: re-running checks for the trailer's
  presence before appending. The Consumer's `enforcing-pr-contract`
  Step 10 owns the PR-body authoring; this projection only
  refines the trailer-shape contract for GitHub.
- **Return**: `(linked | already linked | fallback inserted)`.
- **Idempotency**: yes (trailer presence is checked before
  appending).

### `comment_on_card` (OPTIONAL)

- **Invocation**: `gh issue comment <key> --repo <owner>/<repo>
  --body <body>`.
- **Return**: `(posted | length exceeded)`. GitHub's per-comment
  size cap (65536 chars) is the only failure mode at the comment
  layer; the dispatcher pre-checks length client-side and returns
  `length exceeded` without firing `gh`.
- **Idempotency**: NOT idempotent — each call posts a new
  comment. The protocol marks `comment_on_card` itself as
  not-idempotent, so callers do not retry on transient failures.

## Setup capabilities

Per the projection setup-capability declaration contract, this
projection declares the following **setup capabilities**, which the
M3 stage predicate evaluator consumes via
`applicable_when: kanban_projection_capability: <name>`. v0.5.0
declares two; future projections may declare more or fewer.

### `ensure-labels`

- **Purpose**: ensure the canonical board-superpowers label set
  exists on the GitHub repository backing this Project. The label
  set is declared in `scripts/setup-labels.sh`'s constants block.
- **Invocation form**: Form A bash. The M3 stage executor calls
  `scripts/setup-labels.sh` with `<owner>` and `<repo>` as
  arguments. The script enumerates the canonical label set, calls
  `gh label list --repo <owner>/<repo>` to detect missing
  labels, then `gh label create` for each missing entry.
- **Idempotency**: yes. A repo with all canonical labels already
  present produces zero `gh label create` calls — the script
  exits 0 with no mutation. Re-running is safe and cheap.
- **Error modes**: the script exits `1` on any underlying `gh`
  error (auth, network, repo not found). The M3 stage observes
  the exit code and propagates as a stage failure under the
  bootstrap-stage applicability model; `not-applicable` is
  emitted only when the predicate evaluator determines the
  capability is not declared, which never happens for v0.5.0
  `github-project-v2` (the capability is always declared).
- **Maps to**: M3 stage `m3.repo.ensure-labels` (the canonical M3
  stage name is finalized in the paired-PR rebase that lands
  alongside this skill).

### `validate-status-field`

- **Purpose**: verify the GitHub Project's `Status` single-select
  field contains all six canonical Status options (Backlog /
  Ready / In Progress / In Review / Done / Blocked).
- **Invocation form**: Form A bash. The M3 stage executor calls
  `gh api graphql` with a query enumerating the Status field's
  options, then diffs the returned set against the canonical six.
- **Idempotency**: pure read. Validation never mutates the field.
- **Error modes**: when the diff finds a missing canonical
  option, the stage surfaces the diff to the architect via the
  bootstrap-stage config-item elicitation protocol — the
  architect then either adds the missing option in the GitHub
  Project UI or accepts a custom-state-folding decision (the
  Kanban Protocol allows folding a backend-specific status to one
  of the six canonical statuses, which surfaces a stderr warning
  but never fails dispatch). Validation that succeeds emits no
  architect-visible output.
- **Maps to**: M3 stage `m3.repo.validate-status-field` (the
  canonical M3 stage name is finalized in the paired-PR rebase
  that lands alongside this skill).

## Failure-mode overrides

This projection inherits the generic taxonomy from
`failure-mode-dispatch.md`. The GitHub backend imposes three
projection-specific overrides:

- **GitHub API rate limit**: `gh` returns exit `4` from any call
  that hits a primary or secondary rate-limit. The 4xx body
  distinguishes the two: secondary rate-limits carry a
  `Retry-After` header and are retryable after the indicated
  delay; primary rate-limits require back-off until the reset
  epoch in the response headers. The dispatcher surfaces the
  retry hint to the caller; callers decide whether to retry.
- **Project not found**: `gh project view <project-number>
  --owner <owner>` exits `1` with stderr matching `not found`.
  The dispatcher surfaces this to the architect — the
  projection's `project_ref` may be misconfigured in
  `settings.yml § modules.m10_kanban`.
- **Insufficient `gh` scope**: `gh` exits `1` with stderr
  matching `requires the .* scope`. The dispatcher surfaces with
  explicit guidance: re-authenticate via `gh auth refresh -s
  project` to grant the required Project v2 scope.

## Related

- `form-a-bash.md` — Form A invocation conventions (exit-code
  table, helper preference, worktree-relative paths). This file's
  projection-specific overrides above layer on top.
- `action-dispatch.md` — protocol-action dispatch sequencing and
  the audit hand-off contract (caller → classify → propose →
  dispatch → resolve).
- `failure-mode-dispatch.md` — generic failure-mode taxonomy
  this file's overrides extend.
- `backend-selection.md` — how the active projection is resolved
  at runtime from `settings.yml § modules.m10_kanban`.

---

**Maintainer reference (board-superpowers repo only; not shipped with plugin install)**: the projection setup-capability declaration contract, the M3 stage definitions, and the protocol-level contract for the per-projection capability registry originate in the maintainer-side ADR record (ADR-0022, ADR-0027) and the protocol contract page `docs/architecture/0005-contracts/00-kanban-protocol.md`. This file's prose IS self-contained — the maintainer pointer is for plugin maintainers wanting to update the projection with full design context.
