# operating-kanban — github-project-v2 projection reference

GitHub Project v2 projection (Form A — bash CLI). Reader is the runtime caller invoking a protocol action against this backend; this file is a paste-and-run reference. Each per-action section gives you the shell snippet, expected exit codes, idempotency note, and a worked-output example.

## Backend identity

- **Projection ID**: `github-project-v2`. Recorded literally in `<repo>/.board-superpowers/settings.yml § modules.m10_kanban.kanbans[].projection`.
- **`project_ref` shape**: `<owner>/<project-number>`. Example: `PanQiWei/4`.
- **`Card.key`**: the GitHub Issue number rendered as a string. Example: `"68"`. The agent uses this in `[board-card:#68]` references; GraphQL node IDs are projection-internal and never surface.
- **Identity tuple**: `(kanban_id, Card.key)` — for the GitHub backend the tuple maps to `(kanban_id, issue_number)`. Example: `("primary", "68")` resolves to `https://github.com/PanQiWei/board-superpowers/issues/68` in project `PanQiWei/4`.
- **Status field**: a `ProjectV2SingleSelectField` named exactly `Status` with the six canonical options (Backlog / Ready / In Progress / In Review / Done / Blocked). Field ID resolved on first call via `bsp_gh_field_id` and cached per session. Custom-state options on the field fold to `Backlog` with a stderr warning.

## Action procedures

### `read_board`

To list every card on the board with its canonical status, do:

```bash
set -euo pipefail
: "${BSP_PROJECT_REF:?missing}"  # e.g. PanQiWei/4
owner="${BSP_PROJECT_REF%/*}"
project_num="${BSP_PROJECT_REF##*/}"

gh project item-list "$project_num" --owner "$owner" --format json --limit 500
```

- **Exit codes**: `0` success with JSON on stdout; `3` if `gh project` scope missing (re-auth: `gh auth refresh -s project`); `4` rate-limit (retry per `Retry-After` from stderr).
- **Idempotency**: pure read; safe to repeat.
- **On non-zero exit**: surface stderr verbatim per `failure-mode-dispatch.md` § form-a tier mapping.
- **Worked example**: stdout is a JSON object with `.items[]`; pipe through `python3 -c 'import json,sys; [print(i["content"]["number"], i["content"]["title"], i["status"], sep="\t") for i in json.load(sys.stdin)["items"]]'` for tab-separated rows.

### `read_card`

To fetch one card's full body and metadata, do:

```bash
set -euo pipefail
: "${BSP_REPO:?missing}"  # owner/repo, e.g. PanQiWei/board-superpowers
card_key="$1"

gh issue view "$card_key" \
  --repo "$BSP_REPO" \
  --json body,title,labels,state,url,createdAt,updatedAt
```

- **Exit codes**: `0` success with JSON on stdout; `1` if the Issue does not exist; `2` if the Issue exists but is not on the Project.
- **Idempotency**: pure read.
- **On non-zero exit**: surface stderr verbatim per `failure-mode-dispatch.md`. For exit `2`, the caller may want to also call `read_board` to confirm the project membership.
- **Worked example**: stdout is a JSON object; `python3 -c 'import json,sys; print(json.load(sys.stdin)["title"])' < /dev/stdin` extracts the title.

### `create_card`

To land a new card in `Backlog`, do (two-call composite):

```bash
set -euo pipefail
: "${BSP_REPO:?missing}"
: "${BSP_PROJECT_REF:?missing}"
title="$1"
body_file="$2"  # path to the card body markdown
labels="$3"     # comma-separated, e.g. "type:feature,size:M"

# Step 1: create the Issue
issue_url="$(gh issue create \
  --repo "$BSP_REPO" \
  --title "$title" \
  --body-file "$body_file" \
  --label "$labels")"

# Step 2: add to the Project
owner="${BSP_PROJECT_REF%/*}"
project_num="${BSP_PROJECT_REF##*/}"
gh project item-add "$project_num" \
  --owner "$owner" \
  --url "$issue_url"

# Return the new Card.key (issue number from the URL)
echo "${issue_url##*/}"
```

- **Exit codes**: `0` success; `1` if title collides under a duplicate-title pre-receive hook (rare); `4` rate-limit during `item-add` (Issue created but not added — caller retries the second call only).
- **Idempotency**: NOT idempotent — re-running creates a duplicate Issue. Guard at the molecular layer by reading the board first.
- **On non-zero exit between steps**: the Issue may exist while not yet on the project. Re-run `gh project item-add` only.
- **Worked example**: stdout prints the new key on its own line, e.g. `127`.

### `transition_card`

To move a card to a new canonical status, do:

```bash
set -euo pipefail
: "${BSP_PROJECT_REF:?missing}"
card_key="$1"
target_status="$2"  # one of: Backlog / Ready / In Progress / In Review / Done / Blocked

owner="${BSP_PROJECT_REF%/*}"
project_num="${BSP_PROJECT_REF##*/}"

# Resolve the project + field + option IDs (cached per session)
project_id="$(bsp_gh_project_id "$owner" "$project_num")"
field_id="$(bsp_gh_field_id "$owner" "$project_num" Status)"
option_id="$(bsp_gh_field_option_id "$owner" "$project_num" Status "$target_status")"
item_id="$(bsp_gh_item_id "$owner" "$project_num" "$card_key")"

gh project item-edit \
  --project-id "$project_id" \
  --id "$item_id" \
  --field-id "$field_id" \
  --single-select-option-id "$option_id"
```

- **Exit codes**: `0` success (including the no-op case where current status equals target); `2` for an illegal protocol-level transition (validate against the six-state machine before invoking — caller responsibility); `4` for GitHub-side conflict (item edited concurrently — caller re-reads and re-decides).
- **Idempotency**: yes — transition to the current status is a no-op success.
- **On non-zero exit**: surface stderr verbatim. For `4`, retry once after re-reading the card; if the conflict persists, route via `failure-mode-dispatch.md` tier C.
- **Worked example**: silent success on stdout; stderr captures any GraphQL warnings.

### `claim_card`

To acquire exclusive Consumer ownership and create the claim worktree, do:

```bash
set -euo pipefail
card_key="$1"
title="$2"
kanban_id="${BSP_KANBAN_ID:-primary}"

bash "${CLAUDE_PLUGIN_ROOT}/scripts/claim-card.sh" \
  --kanban-id "$kanban_id" \
  --card-key "$card_key" \
  --title "$title"
```

- The wrapper performs four steps in order: (1) `transition_card` to `In Progress`; (2) create worktree at `${BOARD_SP_WORKTREE_DIR:-$HOME/.config/superpowers/worktrees}/<repo>/claim/<kanban-id>-<card_key>-<slug>`; (3) create branch `claim/<kanban-id>-<card_key>-<slug>`; (4) `git push origin <branch>`. The push is the atomicity boundary — it wins or loses the race against other Consumers.
- **Exit codes**: `0` claim acquired; `2` race-loss (another Consumer's push arrived first — read `git ls-remote` to surface the winner) or WIP cap exceeded.
- **Idempotency**: re-claiming an already-claimed-by-self card is a no-op success. Re-claiming an already-claimed-by-another card returns race-loss.
- **On non-zero exit**: surface stderr verbatim per `failure-mode-dispatch.md` tier D — the architect chooses whether to retry, override WIP, or pick a different card.
- **Worked example**: stdout prints `claim acquired: <branch>` on success; stderr captures progress.

### `release_claim`

To release an active claim and delete the claim branch, do:

```bash
set -euo pipefail
card_key="$1"
kanban_id="${BSP_KANBAN_ID:-primary}"

# Find and delete the claim branch on origin
branch="$(git ls-remote --heads origin "claim/${kanban_id}-${card_key}-*" \
  | awk '{sub("refs/heads/","",$2); print $2; exit}')"
[ -n "$branch" ] && git push origin --delete "$branch"

# Then flip status back (default: Ready) via the § transition_card recipe.
```

- **Exit codes**: `0` released; `git push --delete` of an already-deleted branch returns "remote ref does not exist" — treat as success.
- **Idempotency**: yes — releasing an already-released claim is a no-op success.
- **On non-zero exit**: surface stderr verbatim. Branch-already-gone is tier B (log-only, treat as success); other failures route per `failure-mode-dispatch.md`.

### `link_pr_to_card`

To link a PR to its card so the merge auto-closes the card, do:

```bash
set -euo pipefail
pr_number="$1"
card_key="$2"

# Read current PR body
pr_body="$(gh pr view "$pr_number" --json body --jq .body)"

# Idempotency check — skip append if trailer already present
if printf '%s\n' "$pr_body" | grep -qE "^Closes #${card_key}\b"; then
  echo "already linked"
  exit 0
fi

# Append trailer and update
new_body="$(printf '%s\n\nCloses #%s\n' "$pr_body" "$card_key")"
gh pr edit "$pr_number" --body "$new_body"
echo "linked"
```

- **Exit codes**: `0` success; `1` PR not found; `4` rate-limit.
- **Idempotency**: yes — trailer presence is checked before appending. Repeated calls are safe.
- **On non-zero exit**: surface stderr verbatim per `failure-mode-dispatch.md`.
- **Worked example**: stdout prints `linked` (first run) or `already linked` (subsequent runs).

### `comment_on_card`

To append a comment on a card, do:

```bash
set -euo pipefail
: "${BSP_REPO:?missing}"
card_key="$1"
body="$2"  # comment text; must be ≤ 65536 chars (GitHub limit)

# Pre-check length client-side to avoid wasting an API call
if [ "${#body}" -gt 65536 ]; then
  echo "length exceeded" >&2
  exit 2
fi

gh issue comment "$card_key" \
  --repo "$BSP_REPO" \
  --body "$body"
```

- **Exit codes**: `0` posted; `2` length exceeded (client-side guard); `4` rate-limit.
- **Idempotency**: NO — each call posts a fresh comment. Do not retry on transient failures unless the caller has explicit dedup logic.
- **On non-zero exit**: surface stderr verbatim per `failure-mode-dispatch.md`.

## Setup capabilities

### `ensure-labels`

To ensure the canonical board-superpowers label set exists on the GitHub repository backing this Project, do:

```bash
set -euo pipefail
: "${BSP_REPO:?missing}"  # owner/repo
plugin_root="${CLAUDE_PLUGIN_ROOT:-$(bsp_plugin_root)}"

bash "${plugin_root}/scripts/setup-labels.sh" "$BSP_REPO"
```

The wrapper script:

1. Reads the canonical label set from its constants block.
2. Calls `gh label list --repo "$BSP_REPO" --json name,color,description` and parses with `python3` to detect missing entries.
3. For each missing entry, calls `gh label create --repo "$BSP_REPO" --name <n> --color <c> --description <d>`.
4. For each present-but-drifted entry, calls `gh label edit --repo "$BSP_REPO" <n> --color <c> --description <d>`.
5. Emits a summary on stdout: `created=<n>, updated=<n>, unchanged=<n>`.

- **Idempotency**: yes — a repo with all canonical labels already in the correct shape produces zero `gh label create` / `edit` calls; exit `0` with `created=0, updated=0, unchanged=N`.
- **Exit codes**: `0` success; `1` any underlying `gh` error (auth, network, repo not found).
- **On non-zero exit**: surface stderr verbatim per `failure-mode-dispatch.md`. The bootstrap stage executor propagates as a stage failure.

### `validate-status-field`

To verify the GitHub Project's `Status` field contains all six canonical options, do:

```bash
set -euo pipefail
: "${BSP_PROJECT_REF:?missing}"
owner="${BSP_PROJECT_REF%/*}"; project_num="${BSP_PROJECT_REF##*/}"

gh api graphql -f query='
  query($owner:String!,$num:Int!){user(login:$owner){projectV2(number:$num){
    field(name:"Status"){... on ProjectV2SingleSelectField{options{name}}}}}}
' -F owner="$owner" -F num="$project_num" | python3 -c '
import json,sys
canon={"Backlog","Ready","In Progress","In Review","Done","Blocked"}
opts={o["name"] for o in json.load(sys.stdin)["data"]["user"]["projectV2"]["field"]["options"]}
missing=canon-opts; extra=opts-canon
if missing: print("missing:",",".join(sorted(missing)),file=sys.stderr); sys.exit(2)
if extra:   print("custom-state (folds to Backlog):",",".join(sorted(extra)),file=sys.stderr)
print("ok")'
```

- **Idempotency**: pure read — validation never mutates the field.
- **Exit codes**: `0` success (all six canonical options present); `2` missing canonical option (architect intervention required); `1` underlying `gh` error.
- **On non-zero exit**: for exit `2`, surface the diff to the architect via the bootstrap-stage config-item elicitation protocol — the architect either adds the missing option in the GitHub Project UI or accepts a custom-state-folding decision. For exit `1`, route per `failure-mode-dispatch.md`.

## Failure-mode overrides

This projection inherits the cross-Form taxonomy from `failure-mode-dispatch.md`. The GitHub backend imposes three projection-specific overrides:

- **Rate limit (primary or secondary)**: `gh` exits `4`; stderr distinguishes the two — secondary rate-limits carry a `Retry-After` header and are retryable after the indicated delay; primary rate-limits require back-off until the reset epoch in the response headers. Surface the retry hint to the caller.
- **Project not found**: `gh project view <project-number> --owner <owner>` exits `1` with stderr matching `not found`. Surface to the architect: the projection's `project_ref` may be misconfigured in `settings.yml § modules.m10_kanban`.
- **Insufficient `gh` scope**: `gh` exits `1` with stderr matching `requires the .* scope`. Surface with explicit guidance: re-authenticate via `gh auth refresh -s project`.

## Related

- `form-a-bash.md` — Form A invocation conventions (exit-code table, helper preference, worktree-relative paths).
- `action-dispatch.md` — protocol-action dispatch sequencing and the audit hand-off contract.
- `failure-mode-dispatch.md` — generic failure-mode taxonomy this file's overrides extend.
- `backend-selection.md` — how the active projection is resolved at runtime from `settings.yml § modules.m10_kanban`.

---

**Maintainer reference (board-superpowers repo only; not shipped with plugin install)**: the projection setup-capability declaration contract, the M3 stage definitions, and the protocol-level contract for the per-projection capability registry originate in the maintainer-side ADR record (ADR-0022, ADR-0027) and the protocol contract page `docs/architecture/0005-contracts/00-kanban-protocol.md`. This file's prose IS self-contained — the maintainer pointer is for plugin maintainers wanting to update the projection with full design context.
