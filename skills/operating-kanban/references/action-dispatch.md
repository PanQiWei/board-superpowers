# operating-kanban — action-dispatch reference

## How to use this file

You arrive here with an action name. Find its section below. Each section gives you:

- One-line intent — what the action does at the protocol level.
- Input/output shape — what to pass, what comes back.
- Per-Form invocation pointers — Form A bash CLI / Form B MCP tool / Form C REST. The pointer routes you into the projection's reference file (`references/<projection-id>.md` § action-name) plus the per-Form conventions file (`form-a-bash.md` / `form-b-mcp.md` / `form-c-rest.md`).
- Idempotency — yes / no plus a one-line note.
- Failure tier — A / B / C / D — plus a one-line note. Full tier semantics live in `failure-mode-dispatch.md`.

Run the recipe in your active projection's reference file (`references/<projection-id>.md`) using the rules below. The protocol contracts (intent, pre/post conditions, idempotency property) are uniform across every projection; only the invocation shape differs by Form.

## Audit hand-off — sequencing rule for the seven mutating actions

Before invoking any of `create_card` / `transition_card` / `claim_card` / `release_claim` / `link_pr_to_card` / `comment_on_card`, your molecular skill MUST have already consulted `classifying-actions` and started the audit sequence. This skill sits in the middle of the sandwich:

1. Caller's molecular skill consults `classifying-actions` → gets `A` or `R`.
2. Caller writes the propose audit row (R) or notes the auto-class (A) per `auditing-actions`.
3. Caller invokes this skill to dispatch the action through the active projection.
4. Caller writes the resolve audit row (R) or the auto-class final row (A) based on the typed return shape this skill hands back.

This skill does not write audit rows; the caller does. The split keeps dispatch backend-aware (via the projection layer) without coupling it to the audit-log schema.

## `read_board`

- **Intent**: snapshot all cards on the board with their canonical statuses.
- **What you pass**: `(kanban_id?)` — optional; defaults to the active primary on single-kanban repos.
- **What you get back**: list of card records `(key, title, status, labels, url)`. Order is backend-native; sort client-side if needed.
- **Form A — bash CLI**: the projection's reference file documents the helper script (typically a `gh project item-list` wrapper) plus pagination handling. See `form-a-bash.md` for exit-code mapping.
- **Form B — MCP tool**: the projection names a tool such as `mcp__<server>__list_issues`; the reference documents the tool input shape. See `form-b-mcp.md`.
- **Form C — REST / GraphQL**: HTTP GET against the backend's project-items endpoint; pagination per the projection. See `form-c-rest.md`.
- **Idempotent?**: yes (read).
- **Failure tier**: typically tier C (audit-row) for transient transport, tier D (surface immediately) for auth or registry failures. See `failure-mode-dispatch.md`.

## `read_card`

- **Intent**: fetch one card's complete body, labels, status, url, timestamps.
- **What you pass**: `(kanban_id, card_key)`.
- **What you get back**: full card record `(key, title, body, status, labels, url, timestamps, display_parent?, display_children_count?, display_hierarchy_path?)`. The `display_*` fields are present only when the backend exposes a parent / sub-issue surface.
- **Form A — bash CLI**: the projection's reference file documents a `gh issue view --json ...` invocation (or the per-projection equivalent).
- **Form B — MCP tool**: the projection names a tool such as `mcp__<server>__get_issue`.
- **Form C — REST / GraphQL**: HTTP GET on the backend's per-issue endpoint.
- **Idempotent?**: yes (read).
- **Failure tier**: tier C for transient transport, tier D for missing-card-on-project or missing-issue. See `failure-mode-dispatch.md`.

## `create_card`

- **Intent**: land a new card in `Backlog`.
- **What you pass**: `(kanban_id, title, body, labels)`. The backend assigns `Card.key`; status starts at `Backlog`.
- **What you get back**: the new `Card.key` (opaque string per the protocol identity contract).
- **Form A — bash CLI**: typically a two-call composite — `gh issue create` + `gh project item-add`. See the projection's reference file for the exact call shape.
- **Form B — MCP tool**: the projection names a tool such as `mcp__<server>__create_issue`.
- **Form C — REST / GraphQL**: HTTP POST to the backend's create-issue endpoint.
- **Idempotent?**: NO. Re-running creates duplicates. Guard at the molecular layer by reading the board first if you need to retry safely.
- **Failure tier**: tier C for transient transport mid-composite (Issue created but project add failed), tier D for auth or invalid-input. See `failure-mode-dispatch.md`.

## `transition_card`

- **Intent**: move a card from one canonical status to another.
- **What you pass**: `(kanban_id, card_key, target_status)`. The target must be a legal edge in `board-canon`'s state machine — caller validates before invoking.
- **What you get back**: `(success | refused | conflict)`. Refused → illegal transition (caught before the backend call). Conflict → concurrent modification (caller re-reads and re-decides).
- **Form A — bash CLI**: typically a `gh project item-edit --field-id <Status> --single-select-option-id <X>` call; the projection's reference file documents the field-id resolution helper.
- **Form B — MCP tool**: a transition tool (Jira fires by transition id; Linear sets workflow state).
- **Form C — REST / GraphQL**: HTTP POST / PATCH to the backend's transition / state-set endpoint.
- **Idempotent?**: yes — transitioning to the current status is a successful no-op.
- **Failure tier**: tier D for illegal-transition (pre-condition violation; not retryable), tier C for transient conflict (retry once after re-read). See `failure-mode-dispatch.md`.

## `claim_card`

- **Intent**: acquire exclusive Consumer ownership of a card.
- **What you pass**: `(kanban_id, card_key, title)`. Title is used for slug generation.
- **What you get back**: `(claim acquired | race lost | wip exceeded | refused)`. Race-loss → another Consumer's `git push` arrived first; surface who won via `git ls-remote`.
- **Form A — bash CLI**: the canonical implementation is a wrapper script (e.g., `scripts/claim-card.sh`) that performs status flip → worktree creation → branch creation → `git push origin <branch>`. The push is the atomicity boundary.
- **Form B — MCP tool**: a composite — status flip via the MCP server's transition tool plus the same git-layer push outside the MCP path. The git-layer push is the atomicity boundary regardless of Form.
- **Form C — REST / GraphQL**: same composite as Form B; the HTTP call replaces the MCP tool call.
- **Idempotent?**: re-claiming an already-claimed-by-self card is a successful no-op. Re-claiming an already-claimed-by-another card is a race-loss failure.
- **Failure tier**: tier D for race-loss, wip-exceeded, or refused (caller must surface to architect). See `failure-mode-dispatch.md`.

## `release_claim`

- **Intent**: release Consumer ownership; delete the claim branch.
- **What you pass**: `(kanban_id, card_key)`.
- **What you get back**: `(released | not held | branch already gone)`.
- **Form A — bash CLI**: composite — `git push origin --delete <claim-branch>` plus a `transition_card` back to the pre-claim status (typically `Ready`, unless releasing as part of a `Done` merge).
- **Form B — MCP tool**: MCP transition tool for the status flip plus git push for branch deletion.
- **Form C — REST / GraphQL**: HTTP for the status flip plus git push for branch deletion.
- **Idempotent?**: yes — releasing an already-released claim is a no-op success.
- **Failure tier**: tier C for transient transport, tier B (log-only) for "branch already gone" (treat as success). See `failure-mode-dispatch.md`.

## `link_pr_to_card`

- **Intent**: establish bidirectional discoverability between a Card and a PR.
- **What you pass**: `(kanban_id, card_key, pr_url, pr_body)`.
- **What you get back**: `(linked | already linked | fallback inserted)`.
- **Form A — bash CLI**: the projection's reference file documents the trailer-injection path (typically idempotent injection of `Closes #<key>` into the PR body so the backend's auto-link / auto-close webhook chain fires on merge).
- **Form B — MCP tool**: the MCP server's link-issue-to-pr tool, OR the same body-insertion fallback when the backend has no native linking tool.
- **Form C — REST / GraphQL**: HTTP call to the backend's native link endpoint, OR body-insertion fallback.
- **Idempotent?**: yes — trailer presence is checked before appending.
- **Failure tier**: tier C for transient transport, tier D for auth. See `failure-mode-dispatch.md`.

## `comment_on_card` (OPTIONAL)

- **Intent**: append a textual exchange entry on a card.
- **What you pass**: `(kanban_id, card_key, comment_body)`.
- **What you get back**: `(posted | not supported | length exceeded)`. Backends MAY decline with `not supported`; callers fall back to PR-body discussion or surface to the user.
- **Form A — bash CLI**: typically `gh issue comment <key> --body ...` (or per-projection equivalent).
- **Form B — MCP tool**: a comment tool such as `mcp__<server>__comment_on_issue`.
- **Form C — REST / GraphQL**: HTTP POST to the backend's comments endpoint.
- **Idempotent?**: NO — each call posts a new comment. The protocol does not require retry guard.
- **Failure tier**: tier C for transient transport, tier B for length-exceeded (caller decides whether to truncate). See `failure-mode-dispatch.md`.

## Related

- `backend-selection.md` — how the active projection is resolved before any of these procedures runs.
- `form-a-bash.md` / `form-b-mcp.md` / `form-c-rest.md` — per-Form dispatch conventions.
- `failure-mode-dispatch.md` — the failure-tier semantics referenced from each section above.
- Per-projection reference files (`references/<projection-id>.md`) — concrete invocations for each backend.
