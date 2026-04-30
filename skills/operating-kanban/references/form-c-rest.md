# operating-kanban — Form C (REST / GraphQL) reference

**Use this file ONLY when authoring a future Form C (REST/GraphQL) projection.** Runtime callers do not enter this file in current ship — return to your active projection's reference file via `backend-selection.md`.

The rest of this document is an authoring contract for Form C. Read it when you are about to add a new projection whose backend exposes a documented REST or GraphQL API but neither a stable CLI (Form A) nor a usable vendor MCP server (Form B) — for example, when the vendor MCP server's tool surface is too coarse, or sandbox / auditability constraints rule out MCP transport.

## Form C at a glance — what you are committing to as an author

When you author a Form C projection, you are committing to:

- Document the HTTP endpoint shape (method, path, body, content-type) per protocol action.
- Document the auth header derivation (API key, PAT, OAuth 2.0 with refresh).
- Read credentials from `<repo>/.board-superpowers/credentials.yml` (per-repo, host-local, gitignored — same protection model as Form B's `userConfig.sensitive`).
- Issue HTTP calls through `curl` (with a thin Python `urllib` fallback for complex JSON construction); parse responses with `python3 -c 'import json,sys; ...'`.

Form C's payoff: when neither CLI nor vendor MCP suits, you are not blocked — you can ship against the raw REST/GraphQL surface without forcing the backend into a worse-fit form.

## When backends choose Form C

To author a Form C projection, the backend you target should have:

- A documented REST or GraphQL API but no maintained CLI (or the CLI is dead / vendor-deprecated).
- No vendor MCP server (or one whose tool surface forces too many round trips for a single protocol action).
- A stable auth model — OAuth 2.0 client credentials, API key in header, or PAT — that maps to `<repo>/.board-superpowers/credentials.yml` storage.

Direct Linear API access (Linear's GraphQL endpoint at `https://api.linear.app/graphql`) is one Form C candidate — chosen over Form B when the architect rejects MCP transport (sandbox restrictions, auditability concerns, or per-call latency budget). Direct Jira Cloud REST is a second candidate when Atlassian's MCP OAuth flow is too heavy for a non-interactive bootstrap path.

## To author a Form C projection — 5 authoring steps

1. **Document the auth model.** In your projection reference file's `Auth` section, name the credential field names (e.g., `linear_api_key`, `jira_oauth_access_token`, `jira_oauth_refresh_token`), the exact header derivation from credential value to HTTP header, and the token lifecycle (when to rotate / refresh).
2. **Document the per-action request shape.** For each protocol action your projection supports, write three rows:
   - **HTTP method + path** — e.g., `POST /graphql` for GraphQL, `PATCH /rest/api/3/issue/<key>` for Jira REST.
   - **Body / content-type** — JSON for REST, GraphQL query string + variables for GraphQL. Pin the exact body shape with placeholders for the action's parameters.
   - **Expected status code on success** — `200` for most reads, `201` for creates, `204` for state-only updates. Anything else routes through `failure-mode-dispatch.md` per the matching tier.
3. **Issue HTTP through `curl --silent --show-error --fail-with-body`.** `--fail-with-body` returns non-zero on 4xx/5xx but still emits the response body to stdout for parsing — critical for surfacing the vendor's error message to the architect. `--silent --show-error` suppresses progress noise but preserves error text on stderr. Set timeouts explicitly (`--max-time 30` is the default; override per documented latency expectations).
4. **Document the response-parsing convention.** REST responses parse with `python3 -c 'import json,sys; ...'` (no `jq` dependency, same as Form A). GraphQL responses parse twice — once for the `errors` array (any non-null entry surfaces as a typed failure), once for the `data` payload. Document the per-action response shape and the field-extraction expressions.
5. **Document pagination + idempotency.** REST APIs typically use `Link: <next>` headers or `?page=N` query strings; GraphQL APIs typically use cursor-based `pageInfo { endCursor, hasNextPage }`. Document the convention. State idempotency per HTTP method (table below) and override only when the backend's semantics genuinely diverge.

For complex JSON construction (multi-line GraphQL queries with string-escaped variable substitution), fall back to a Python `urllib` wrapper invoked through the plugin's per-repo venv (the plugin maintains an isolated `<repo>/.board-superpowers/.venv/` per repo so each repo's plugin-version pin and audit governance behavior stay independent — host-shared venvs leak version skew across repos). Shell-only construction is preferred; Python wrappers are reserved for cases where shell quoting fails the test of sanity.

## Credential handling — never inline secrets

The dispatch layer never inlines credential values into log lines, audit rows, or stderr. Captured response bodies are scrubbed of `Authorization` headers before they hand back to the caller. Auth header derivation examples:

- API key: `Authorization: Bearer <linear_api_key>`.
- PAT: `Authorization: token <github_pat>`.
- OAuth 2.0: `Authorization: Bearer <access_token>`, with refresh-on-401 logic flowing through the projection's documented refresh procedure.

OAuth 2.0 projections document the refresh endpoint plus the dispatch layer's "on 401, refresh once and retry" policy.

## Form C ↔ Form A / Form B semantic equivalence

The same protocol action's intent is projection-independent; only the dispatch shape differs. The translation from Form A or Form B to Form C is mechanical:

| Action | Form A (gh CLI) | Form B (MCP tool) | Form C (HTTP) |
|--------|-----------------|-------------------|---------------|
| `read_board` | `gh project item-list ...` | `mcp__<srv>__list_issues` | `GET /projects/<id>/items` (or GraphQL `query { project { items { ... } } }`) |
| `read_card` | `gh issue view ...` | `mcp__<srv>__get_issue` | `GET /issues/<key>` |
| `create_card` | `gh issue create` + `item-add` | `mcp__<srv>__create_issue` | `POST /issues` (body: title, description, project) |
| `transition_card` | `gh project item-edit ...` | `mcp__<srv>__update_issue` | `PATCH /issues/<key>` (body: state) |
| `claim_card` | `claim-card.sh` (status + git) | tool call + git push | HTTP PATCH + `git push` |
| `release_claim` | status flip + `git push --delete` | tool call + `git push --delete` | HTTP PATCH + `git push --delete` |
| `link_pr_to_card` | `submit-pr.sh` | tool call OR body injection | HTTP POST OR body injection |
| `comment_on_card` | `gh issue comment` | `mcp__<srv>__comment` | `POST /issues/<key>/comments` |

The git-layer push is again the atomicity boundary — Form C's `claim_card` and `release_claim` mix HTTP for the kanban side and `git push` for the branch side. Document both halves and the dispatch layer composes them.

## Idempotency property

Form C idempotency depends on the underlying HTTP method and the backend's semantics:

- `GET` is idempotent (read-only).
- `PUT` is idempotent (replace by ID).
- `PATCH` is **conditionally** idempotent — most backends treat patching to the current state as a no-op success, but verify and document.
- `POST` is generally NOT idempotent — `create_card` and `comment_on_card` are not-idempotent at the protocol level for this reason.
- `DELETE` is idempotent in spirit (resource gone after the call) but MAY return 404 on the second call; the dispatch layer treats 404-on-DELETE as success.

When the backend supports HTTP idempotency keys (`Idempotency-Key` header, common on payment-style APIs but rare on issue trackers), use them to upgrade `create_card` to idempotent. Do not assume support unless the backend's docs name the header explicitly.

## Failure mode notes

Form C failures arrive as HTTP status codes plus response bodies. Map them through the dispatch layer:

- `2xx` → success.
- `3xx` → redirect — `curl --location-trusted` follows up to 5 hops; further redirects surface as `redirect-loop` failure.
- `400`, `422` → caller-visible `bad-request` (the caller's request shape is wrong; do NOT retry).
- `401` → caller-visible `auth-failed` (with one OAuth-refresh attempt for OAuth projections).
- `403` → caller-visible `forbidden` (architect needs to review credentials' scopes).
- `404` → caller-visible `not-found` for reads; success for DELETEs (per idempotency table).
- `409` → caller-visible `conflict` (concurrent modification; caller re-reads and re-decides).
- `429` → caller-visible `rate-limited` with `Retry-After` header surfaced; caller policy decides backoff.
- `5xx` → caller-visible `server-failure`; caller policy decides retry.

`failure-mode-dispatch.md` documents the surfacing tiers per category.

## Setup-capability dispatch

Form C projections that require bootstrap-side wiring (e.g., a `provision-rest-credentials` capability for OAuth bootstrap) declare the capability in the projection reference file and dispatch through this skill's per-projection reference file using the same convention as Form A and Form B. The bootstrap stage executor never invokes a backend directly; it always goes through this skill.

## Related

- `action-dispatch.md` — per-action dispatch shape, parameterized by Form. The Form C column is what this file concretizes.
- `form-a-bash.md` / `form-b-mcp.md` — the comparable contracts for the other two forms.
- `failure-mode-dispatch.md` — failure surfacing across all three forms.
