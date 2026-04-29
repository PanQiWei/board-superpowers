# operating-kanban — action-dispatch reference

Per-action invocation patterns for the eight Kanban Protocol actions, parameterized by Form. The semantic contracts (intent, pre-condition, post-condition, idempotency, failure modes) are pinned in the protocol document; this file documents the **dispatch shape** — what the call looks like, what the caller gets back.

## Dispatch shape per action

Each action below has the same six-row layout:

- **Caller passes**: the parameters the caller hands to this skill.
- **Form A invocation**: bash CLI projection invocation pattern.
- **Form B invocation**: plugin-shipped MCP server projection invocation pattern.
- **Form C invocation**: REST / GraphQL projection invocation pattern.
- **Return shape**: the structured response handed back to the caller.
- **Idempotency**: the protocol-level idempotency property.

Form B and Form C entries are documented for the v1.x roadmap; v0.5.0 ships only Form A via the GitHub Project v2 projection. Each per-projection reference file (`references/<projection-id>.md`) refines these patterns to the concrete invocation for that backend.

### `read_board`

| Row | Value |
|-----|-------|
| Caller passes | `(kanban_id)` — optional, defaults to active primary on single-kanban repos. |
| Form A invocation | The projection's reference file documents the helper script (typically `scripts/read-board.sh` or a per-projection equivalent) that wraps the backend CLI's project-listing call. |
| Form B invocation | Tool call equivalent (e.g., `mcp__<server>__list_issues` for a Linear-style MCP server) per the projection's MCP tool description. |
| Form C invocation | HTTP GET to the backend's project-items endpoint; pagination handled per projection. |
| Return shape | List of card records, each containing `(key, title, status, labels, url)`. Order is backend-native; callers sort client-side if needed. |
| Idempotency | Read; trivially idempotent. |

### `read_card`

| Row | Value |
|-----|-------|
| Caller passes | `(kanban_id, card_key)`. |
| Form A invocation | `gh issue view <key> --repo <owner/repo> --json body,title,labels,state` for the GitHub projection; per-projection variants for others. |
| Form B invocation | Tool call (`mcp__<server>__get_issue` or equivalent). |
| Form C invocation | HTTP GET on the backend's per-issue endpoint. |
| Return shape | Full card record: `(key, title, body, status, labels, url, timestamps, display_parent?, display_children_count?, display_hierarchy_path?)`. The `display_*` fields are present only when the backend exposes a parent / sub-issue surface. |
| Idempotency | Read; trivially idempotent. |

### `create_card`

| Row | Value |
|-----|-------|
| Caller passes | `(kanban_id, title, body, labels, status=Backlog)`. |
| Form A invocation | `gh issue create` + `gh project item-add` for the GitHub projection; the backend assigns `Card.key`. |
| Form B invocation | Tool call (`mcp__<server>__create_issue` or equivalent). |
| Form C invocation | HTTP POST to the backend's create-issue endpoint. |
| Return shape | The new card's `Card.key` (assigned by the backend). |
| Idempotency | Not idempotent at v0.5.0. Callers guard against duplicate creation across retries by reading the board first. |

### `transition_card`

| Row | Value |
|-----|-------|
| Caller passes | `(kanban_id, card_key, target_status)`. |
| Form A invocation | `gh project item-edit` for the GitHub projection's Status field; the backend's reference file documents the field-id resolution. |
| Form B invocation | Tool call (`mcp__<server>__transition_issue` or equivalent); transition-id resolution per the backend (Jira fires by id; Linear sets workflow state). |
| Form C invocation | HTTP POST / PATCH to the backend's transition / state-set endpoint. |
| Return shape | `(success | refused | conflict)`. Refused → illegal transition; conflict → concurrent modification (caller re-reads and re-decides). |
| Idempotency | Transitioning to the current status is a successful no-op (NOT an error). |

### `claim_card`

| Row | Value |
|-----|-------|
| Caller passes | `(kanban_id, card_key, title)` — title used for slug generation. |
| Form A invocation | The plugin's `scripts/claim-card.sh` for the GitHub projection: status flip → worktree creation → branch creation → push to origin. The branch name is `claim/<kanban-id>-<key-slug>-<title-slug>` per the canonical branch-naming form. |
| Form B invocation | A composite call: status flip via the MCP server's transition tool, plus the same git-layer push outside the MCP path. The git-layer push is the atomicity boundary regardless of Form. |
| Form C invocation | Same composite as Form B; the HTTP call replaces the MCP tool call. |
| Return shape | `(claim acquired | race lost | wip exceeded | refused)`. Race lost → another Consumer's push won; surface who won via `git ls-remote`. |
| Idempotency | Re-claiming an already-claimed-by-self card is a successful no-op. Re-claiming an already-claimed-by-another card is a race-loss failure. |

### `release_claim`

| Row | Value |
|-----|-------|
| Caller passes | `(kanban_id, card_key)`. |
| Form A invocation | `git push origin --delete <claim-branch>` plus the projection's status-set call (back to Ready, OR stay at current state if the release is part of a merge into Done — the projection decides based on context). |
| Form B invocation | MCP tool for status flip + git push for branch deletion. |
| Form C invocation | HTTP for status flip + git push for branch deletion. |
| Return shape | `(released | not held | branch already gone)`. |
| Idempotency | Releasing an already-released claim is a no-op. |

### `link_pr_to_card`

| Row | Value |
|-----|-------|
| Caller passes | `(kanban_id, card_key, pr_url, pr_body)`. |
| Form A invocation | The plugin's `scripts/submit-pr.sh` for the GitHub projection — idempotently injects the `Closes #<key>` trailer into the PR body at PR-OPEN time so GitHub's auto-link / auto-close webhook chain fires on merge. |
| Form B invocation | The MCP server's link-issue-to-pr tool, OR the same body-insertion path as Form A when the backend has no native linking tool. |
| Form C invocation | HTTP call to the backend's native link endpoint, OR body-insertion fallback. |
| Return shape | `(linked | already linked | fallback inserted)`. |
| Idempotency | Linking an already-linked pair is a no-op. |

### `comment_on_card` (OPTIONAL)

| Row | Value |
|-----|-------|
| Caller passes | `(kanban_id, card_key, comment_body)`. |
| Form A invocation | `gh issue comment <key> --body ...` for the GitHub projection. |
| Form B invocation | Tool call (`mcp__<server>__comment_on_issue` or equivalent). |
| Form C invocation | HTTP POST to the backend's comments endpoint. |
| Return shape | `(posted | not supported | length exceeded)`. Backends may decline with "not supported" — callers fall back to PR-body discussion or surface to the user. |
| Idempotency | Not idempotent (each call is a new comment). |

## Dispatch sequencing — the audit hand-off

Before invoking any of the seven mutating actions (`create_card`, `transition_card`, `claim_card`, `release_claim`, `link_pr_to_card`, `comment_on_card`), the calling skill MUST have already consulted the classification skill and started the audit sequence. This skill is in the middle of that sandwich:

1. Caller's molecular skill consults the classification skill → gets A or R.
2. Caller writes the propose audit row (R) or notes the auto-class (A).
3. Caller invokes this skill to dispatch the action through the active projection.
4. Caller writes the resolve audit row (R) or the auto-class final row (A) based on this skill's return shape.

This skill does not write audit rows. The caller does. The split keeps this skill backend-aware (via the projection layer) without making it audit-aware (which would couple it to the audit log schema).

## Related

- Protocol document § "Action contracts" — the eight action semantics, immutable modulo superseding ADR.
- `references/backend-selection.md` — how the active projection is resolved before any of the above patterns is dispatched.
- `references/form-a-bash.md` / `references/form-b-mcp.md` / `references/form-c-rest.md` — per-Form dispatch conventions.
- Per-projection reference files (`references/<projection-id>.md`) — the concrete invocations for each backend.
