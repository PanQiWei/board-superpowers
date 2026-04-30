# operating-kanban — Form B (plugin-shipped MCP server) reference

**Use this file ONLY when authoring a future Form B (MCP-server) projection.** Runtime callers do not enter this file in current ship — return to your active projection's reference file via `backend-selection.md`.

The rest of this document is an authoring contract for Form B. Read it when you are about to add a new projection whose backend exposes a vendor MCP server (Linear, Jira Cloud, etc.); the contract is concrete enough that a Form B projection can ship without re-deriving the wiring.

## Form B at a glance — what you are committing to as an author

When you author a Form B projection, you are committing to:

- Register the backend's MCP server in the plugin manifest (`.claude-plugin/plugin.json` for Claude Code; `.codex-plugin/plugin.json` for Codex CLI) per the platform's MCP-server registration shape.
- Document, in your projection reference file, the exact MCP tool names plus per-action input / response shapes that the dispatch layer hands the platform's MCP runtime.
- Store credentials through `userConfig.sensitive` so secrets stay out of the plain-text settings.yml.

Form B's payoff: the backend's vendor-published, vendor-maintained tool definitions handle the auth flow, schema validation, and retry policy that Form A or Form C would force you to script by hand.

## When backends choose Form B

To author a Form B projection, the backend you target should have:

- An official, vendor-published MCP server with stable tool definitions.
- A permission model compatible with `userConfig.sensitive` credential storage (Claude Code keychain on macOS, Codex `mcp login` on Codex CLI).
- A tool surface that covers enough of the eight protocol actions for the projection to advertise compliance ≥ L1 (and ≥ L2 for Consumer-flow support).

Linear is the canonical Form B candidate: Linear's MCP server is well-maintained, exposes `list_issues` / `get_issue` / `create_issue` / `update_issue` / `comment_on_issue` natively, and Linear's API key model maps cleanly to `userConfig.sensitive`. Atlassian's Remote MCP for Jira Cloud is a second candidate, with the caveat that its OAuth flow is heavier than Linear's API-key flow.

## To author a Form B projection — 5 authoring steps

1. **Register the MCP server in the plugin manifest.** Add the server entry to `.claude-plugin/plugin.json` (Claude Code reads `mcpServers` blocks) and `.codex-plugin/plugin.json` (Codex CLI reads `mcp_servers` blocks). Both honor `userConfig.sensitive` for credential keys. Reference the server unconditionally — the projection reference file owns the gating ("only invoke these tools when the active projection is `<your-projection>`").
2. **Declare the credential fields as `userConfig.sensitive`.** Name the per-projection credential keys (e.g., `linear_api_key`, `jira_oauth_access_token`, `jira_oauth_refresh_token`). Claude Code stores them in the macOS keychain; Codex stores them via `codex mcp login`. Document the lifecycle in your reference file (one-shot setup at bootstrap, refresh-on-failure for OAuth, etc.).
3. **Document the per-action MCP tool-call shape.** For each protocol action your projection supports, write three rows in the projection reference file:
   - **Tool name** — the exact MCP tool the protocol action invokes (e.g., `mcp__linear__list_issues`). Do NOT rename the vendor's tool; document its actual name.
   - **Input schema** — the JSON shape the tool expects, mapping the protocol action's parameters into the vendor's parameter names. Field-by-field; no implicit conversions.
   - **Response shape** — the JSON shape the tool returns and how the dispatch layer flattens it back into the protocol's return shape (per `action-dispatch.md` § "Return shape").
4. **Wire bootstrap-side credential provisioning.** Declare a `provision-mcp-credentials` setup capability in your projection reference file. The bootstrap stage executor dispatches through this skill into the projection's reference-file procedure for the credential prompt. The bootstrap stage executor never invokes a backend directly; it always goes through this skill's per-projection reference file.
5. **Map the Form B failure surface.** Document, in your projection reference file, which MCP error codes you expect (`tool-not-found`, `permission-denied`, `invalid-input`, plus any backend-specific codes) and the failure-mode taxonomy entry each maps to. Inherit tier assignments from `failure-mode-dispatch.md`'s base table; override only when your backend's semantics genuinely diverge.

## Lifecycle the platform runs for you — install → registration → discovery → invocation

The platform handles four lifecycle stages once your manifest registration lands:

1. **Plugin install** — the platform's plugin loader reads your manifest and registers `.mcp.json` server entries with the MCP runtime.
2. **First-time bootstrap** — when the architect picks your projection at the M10 setup stage, the bootstrap flow runs your `provision-mcp-credentials` setup capability (dispatched through this skill's projection reference file) to populate `userConfig.sensitive` keys.
3. **Tool discovery** — the platform's MCP runtime advertises the registered tools to the model on session start. The dispatch layer's `mcp__<server>__<tool>` references resolve at call time.
4. **Invocation** — every Form B protocol-action dispatch issues exactly one MCP tool call; the dispatch layer parses the response per your projection reference file.

The lifecycle is uniform across Claude Code and Codex CLI; the differences are in the credential-storage backend (keychain vs. `mcp login`) and the runtime's MCP tool advertisement format. Both are abstracted by the platform; the dispatch layer sees a single tool-call surface.

## Form A ↔ Form B semantic equivalence

The same protocol action's intent / pre-condition / post-condition are projection-independent. Only the dispatch shape differs. Authoring a Form B projection is therefore a translation from a comparable Form A projection's bash-CLI vocabulary to MCP tool-call vocabulary, NOT a reinvention of the action contract:

| Action | Form A invocation (GitHub Project v2 reference) | Form B equivalent (Linear, illustrative) |
|--------|--------------------------------------------------|------------------------------------------|
| `read_board` | `gh project item-list <project>` | `mcp__linear__list_issues(project=<id>)` |
| `read_card` | `gh issue view <key> --json ...` | `mcp__linear__get_issue(id=<key>)` |
| `create_card` | `gh issue create` + `gh project item-add` | `mcp__linear__create_issue(...)` |
| `transition_card` | `gh project item-edit --single-select-option-id <X>` | `mcp__linear__update_issue(state_id=<X>)` |
| `claim_card` | `claim-card.sh` (status flip + worktree + branch push) | `mcp__linear__update_issue(state=...)` + `git push` (git layer is Form-independent) |
| `release_claim` | status flip + `git push --delete` | tool call + `git push --delete` |
| `link_pr_to_card` | `submit-pr.sh` (Closes-trailer injection) | `mcp__linear__attach_pr` OR fallback body insertion |
| `comment_on_card` | `gh issue comment` | `mcp__linear__create_comment` |

The git-layer push is the atomicity boundary regardless of Form — Form B's `claim_card` and `release_claim` still run `git push` outside the MCP path, because branch publication is a git-server operation, not a kanban-backend operation. The same atomicity boundary applies to Form A and Form C.

## Failure mode notes

Form B failures arrive as MCP tool-call errors with structured error codes, NOT as exit codes. Map them through the dispatch layer:

- **Transport errors** (network timeout, MCP server crashed) → caller-visible `transient`.
- **Auth errors** (401 from the underlying API, OAuth refresh failed) → caller-visible `auth-failed`.
- **Tool-not-found** (MCP server up but tool name missing from advertisement) → caller-visible `unknown-projection-call` — surface immediately, do not retry.
- **Server errors** (5xx from the underlying API) → caller-visible `server-failure` — caller policy decides retry.

`failure-mode-dispatch.md` documents the surfacing tiers per category.

## Credential storage — `userConfig.sensitive`

Per Claude Code's MCP runtime conventions and Codex CLI's MCP login flow:

- API keys / OAuth tokens / refresh tokens MUST be declared `userConfig.sensitive` so the platform stores them outside the plain-text settings.yml.
- The projection reference file documents the credential field names and their lifecycle.
- `<repo>/.board-superpowers/settings.yml` MAY reference the credential field NAMES but MUST NEVER inline the secret values — that would leak through git, audit log dumps, and `cat settings.yml` shell sessions.

## Related

- `action-dispatch.md` — per-action dispatch shape, parameterized by Form. The Form B column is what this file concretizes.
- `form-a-bash.md` — the comparable contract for projections shipping as Form A.
- `form-c-rest.md` — the third invocation form, for when neither CLI nor MCP fits.
- `failure-mode-dispatch.md` — failure surfacing across all three forms.
