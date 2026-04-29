# operating-kanban — Form C (REST / GraphQL) reference

Form C is the direct REST or GraphQL invocation form: the projection reference file documents the HTTP endpoint shape (method, path, body, content-type), auth header derivation, and response parsing; this skill issues the HTTP calls directly through `curl` (or a thin Python `urllib` wrapper for complex JSON handling).

**v0.5.0 has no live Form C projection.** This file is an authoring guide for v1.x roadmap projections that cannot fit Form A (no scriptable CLI) or Form B (no vendor MCP server, OR the vendor MCP server's tool surface is too coarse). The form exists explicitly so future authors are not forced into Form B when neither CLI nor MCP suits.

## When backends choose Form C

A projection ships as Form C when its backend has:

- A documented REST or GraphQL API but no maintained CLI (or the CLI is dead / vendor-deprecated).
- No vendor MCP server (or one whose tool surface forces too many round trips for a single protocol action).
- A stable auth model — OAuth 2.0 client credentials, API key in header, or PAT — that maps to `<repo>/.board-superpowers/credentials.yml` storage.

The first v1.x Form C candidate is **direct Linear API access** (Linear's GraphQL endpoint at `https://api.linear.app/graphql`) — chosen over Form B when the architect rejects MCP transport (sandbox restrictions, auditability concerns, or per-call latency budget). A second candidate is **direct Jira Cloud REST** when Atlassian's MCP OAuth flow is too heavy for a non-interactive bootstrap path.

## Auth header derivation

Per the projection reference file's `Auth` section, the dispatch layer reads credentials from `<repo>/.board-superpowers/credentials.yml` (a per-repo, host-local, gitignored file outside the plain-text settings.yml — same protection model as Form B's `userConfig.sensitive`). The projection reference file documents:

- **Credential field names** — e.g., `linear_api_key`, `jira_oauth_access_token`, `jira_oauth_refresh_token`.
- **Header derivation** — the exact transformation from credential value to HTTP header. Examples:
  - API key: `Authorization: Bearer <linear_api_key>`.
  - PAT: `Authorization: token <github_pat>`.
  - OAuth 2.0: `Authorization: Bearer <access_token>`, with refresh-on-401 logic flowing through the projection's documented refresh procedure.
- **Token lifecycle** — when the dispatch layer rotates / refreshes tokens. OAuth-2.0 projections document the refresh endpoint + the dispatch layer's "on 401, refresh once and retry" policy.

The dispatch layer never inlines credential values into log lines, audit rows, or stderr. Captured response bodies are scrubbed of `Authorization` headers before they hand back to the caller.

## Request shape

Each action's projection reference file documents three rows:

- **HTTP method + path** — e.g., `POST /graphql` for GraphQL, `PATCH /rest/api/3/issue/<key>` for Jira REST.
- **Body / content-type** — JSON for REST, GraphQL query string + variables for GraphQL. The projection reference file pins the exact body shape with placeholders for the action's parameters.
- **Expected status code on success** — `200` for most reads, `201` for creates, `204` for state-only updates. Anything else routes through `failure-mode-dispatch.md` per the matching tier.

The dispatch layer issues the HTTP call through `curl --silent --show-error --fail-with-body`:

- `--fail-with-body` returns non-zero exit on 4xx/5xx but still emits the response body to stdout for parsing — critical for surfacing the vendor's error message to the architect.
- `--silent --show-error` suppresses progress noise but preserves error text on stderr.
- Timeouts MUST be set explicitly (`--max-time 30` is the v1.x default; projections override per documented latency expectations).

For complex JSON construction (multi-line GraphQL queries with string-escaped variable substitution), the dispatch layer falls back to a Python `urllib` wrapper invoked through the plugin's per-repo venv (per ADR-0007 + the per-repo venv discipline in [`AGENTS.md`](../../../AGENTS.md) § "Why per-repo venv"). Shell-only construction is preferred; Python wrappers are reserved for cases where shell quoting fails the test of sanity.

## Response parsing

REST responses are parsed with `python3 -c 'import json,sys; ...'` (no `jq` dependency, same convention as Form A). GraphQL responses are parsed twice: once for the `errors` array (any non-null entry surfaces as a typed failure), once for the `data` payload. The projection reference file documents the per-action response shape and the field-extraction expressions.

Pagination is per-projection: REST APIs typically use `Link: <next>` headers or `?page=N` query strings; GraphQL APIs typically use cursor-based `pageInfo { endCursor, hasNextPage }`. The `read_board` action's reference-file row documents the pagination convention, including any rate-limit-aware backoff.

## Form C ↔ Form A/B semantic equivalence

Same as Form B: the protocol action's intent is projection-independent; only the dispatch shape differs. The translation from Form A or Form B to Form C is mechanical:

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

The git-layer push is again the atomicity boundary — Form C's `claim_card` and `release_claim` mix HTTP for the kanban side and `git push` for the branch side. The projection reference file documents both halves and the dispatch layer composes them.

## Idempotency property

Form C idempotency depends on the underlying HTTP method and the backend's semantics:

- `GET` is idempotent (read-only).
- `PUT` is idempotent (replace by ID).
- `PATCH` is **conditionally** idempotent — most backends treat patching to the current state as a no-op success, but the projection reference file MUST verify and document.
- `POST` is generally NOT idempotent — `create_card` and `comment_on_card` are not-idempotent at the protocol level for this reason.
- `DELETE` is idempotent in spirit (resource gone after the call) but MAY return 404 on the second call; the dispatch layer treats 404-on-DELETE as success.

When the backend supports HTTP idempotency keys (`Idempotency-Key` header, common on payment-style APIs but rare on issue trackers), the projection reference file MAY use them to upgrade `create_card` to idempotent. v1.x roadmap projections do not assume support.

## Failure mode notes

Form C failures arrive as HTTP status codes plus response bodies. The dispatch layer maps:

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

## Related

- `action-dispatch.md` — per-action dispatch shape, parameterized by Form. The Form C column is what this file concretizes.
- `form-a-bash.md` / `form-b-mcp.md` — the comparable contracts for the other two forms.
- `failure-mode-dispatch.md` — failure surfacing across all three forms.
- ADR-0027 § Decision 3 — bootstrap-side dispatch through projection reference files; the conventions apply to Form C's setup capabilities (e.g., a `provision-rest-credentials` capability for OAuth bootstrap).
- The first v1.x Form C reference projection (planned): potentially `references/linear-rest.md` (direct Linear GraphQL) or `references/jira-rest.md`, depending on which lands first.
