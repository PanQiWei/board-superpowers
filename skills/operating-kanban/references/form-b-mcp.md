# operating-kanban — Form B (plugin-shipped MCP server) reference

Form B is the plugin-shipped MCP server invocation form: the plugin registers the backend's MCP server through its plugin manifest's `.mcp.json` (Claude Code) or `mcp_servers` block (Codex CLI), and the projection reference file names the MCP tools and their input/output shapes; this skill calls the MCP tools through the platform's MCP runtime.

**v0.5.0 has no live Form B projection.** This file is an authoring guide for the v1.x roadmap — the first Form B candidate is the Linear projection backed by Linear's official MCP server. The contract below is concrete enough that future Form B authors can ship a projection without re-deriving it.

## When backends choose Form B

A projection ships as Form B when its backend has:

- An official, vendor-published MCP server with stable tool definitions.
- A permission model compatible with `userConfig.sensitive` credential storage (per the platform's MCP runtime — CC keychain on macOS, Codex `mcp login` on Codex CLI).
- A tool surface that covers enough of the eight protocol actions for the projection to advertise compliance ≥ L1 (and ≥ L2 for Consumer-flow support).

Linear is the canonical Form B candidate at v1.x: Linear's MCP server is well-maintained, exposes `list_issues` / `get_issue` / `create_issue` / `update_issue` / `comment_on_issue` natively, and Linear's API key model maps cleanly to `userConfig.sensitive`. Atlassian's Remote MCP for Jira Cloud is a second candidate, with the caveat that its OAuth flow is heavier than Linear's API-key flow.

## Plugin-manifest registration

The plugin manifest (`.claude-plugin/plugin.json` for CC; `.codex-plugin/plugin.json` for Codex CLI) registers the MCP server statically per platform conventions. The convention is documented in [`PLUGIN_DEVELOPMENT.md`](../../../PLUGIN_DEVELOPMENT.md) § "MCP server registration"; this section captures the Form-B-specific contract:

- The MCP server registration is **conditional on the projection being active** — registering an unused MCP server consumes architect tool budget. The plugin manifest references the server unconditionally; the projection reference file owns the gating ("only invoke these tools when the active projection is `linear`").
- `userConfig.sensitive` fields name the per-projection credential keys. CC stores them in the macOS keychain; Codex stores them via `codex mcp login` per the Codex CLI MCP credential flow.
- The MCP server's tool names are NOT renamed by the plugin — the projection reference file documents the vendor's actual tool names (e.g., `mcp__linear__list_issues`) and adapts the plugin's protocol-action vocabulary to the vendor's vocabulary at the dispatch layer.

## Per-action MCP tool-call shape

Each action's projection reference file documents the dispatch on three rows:

- **Tool name** — the exact MCP tool the protocol action invokes (e.g., `mcp__linear__list_issues`).
- **Input schema** — the JSON shape the tool expects, mapping the protocol action's parameters into the vendor's parameter names. Field-by-field mapping; no implicit conversions.
- **Response shape** — the JSON shape the tool returns and how the dispatch layer flattens it back into the protocol's return shape (per `action-dispatch.md` § "Return shape").

Form B dispatch reads the projection reference file's per-action mapping and issues the MCP tool call through the platform runtime. The dispatch layer never invents a tool name — if the vendor's tool surface lacks coverage for a protocol action, the projection's compliance level drops accordingly (e.g., a backend MCP without a state-transition tool advertises L0 only).

## Credential storage — `userConfig.sensitive`

Per CC's MCP runtime conventions and Codex CLI's MCP login flow:

- API keys / OAuth tokens / refresh tokens MUST be declared `userConfig.sensitive` so the platform stores them outside the plain-text settings.yml.
- The projection reference file documents the credential field names and their lifecycle (one-shot setup at bootstrap, refresh-on-failure for OAuth, etc.).
- `<repo>/.board-superpowers/settings.yml` MAY reference the credential field NAMES but MUST NEVER inline the secret values — that would leak through git, audit log dumps, and `cat settings.yml` shell sessions.

Bootstrap-side wiring lands through `bootstrapping-repo`'s setup-capability dispatch (per ADR-0027 § Decision 3): a Form-B projection declares a `provision-mcp-credentials` capability, and the bootstrap stage executor dispatches through this skill into the projection's reference-file procedure for the credential prompt.

## Lifecycle — install → registration → discovery → invocation

1. **Plugin install** — the plugin's manifest is read by the platform's plugin loader; `.mcp.json` server entries are registered with the MCP runtime.
2. **First-time bootstrap** — when the architect picks a Form-B projection at the M10 stage, the bootstrap flow runs the `provision-mcp-credentials` setup capability per ADR-0027 § 3 to populate `userConfig.sensitive` keys.
3. **Tool discovery** — the platform's MCP runtime advertises the registered tools to the model on session start. The dispatch layer's `mcp__<server>__<tool>` references resolve at call time.
4. **Invocation** — every Form-B protocol-action dispatch issues exactly one MCP tool call; the response is parsed per the projection reference file.

The lifecycle is uniform across CC and Codex CLI; the differences are in the credential-storage backend (keychain vs. `mcp login`) and the runtime's MCP tool advertisement format. Both are abstracted by the platform; this skill's dispatch layer sees a single tool-call surface.

## Form A ↔ Form B semantic equivalence

The same protocol action's intent / pre-condition / post-condition are projection-independent. Only the dispatch shape differs. Authoring a Form B projection is therefore a translation from Form A's bash-CLI vocabulary to MCP tool-call vocabulary, NOT a reinvention of the action contract:

| Action | Form A invocation (v0.5.0 GitHub) | Form B equivalent (Linear, illustrative) |
|--------|-----------------------------------|------------------------------------------|
| `read_board` | `gh project item-list <project>` | `mcp__linear__list_issues(project=<id>)` |
| `read_card` | `gh issue view <key> --json ...` | `mcp__linear__get_issue(id=<key>)` |
| `create_card` | `gh issue create` + `gh project item-add` | `mcp__linear__create_issue(...)` |
| `transition_card` | `gh project item-edit --single-select-option-id <X>` | `mcp__linear__update_issue(state_id=<X>)` |
| `claim_card` | `claim-card.sh` (status flip + worktree + branch push) | `mcp__linear__update_issue(state=...)` + `git push` (git layer is Form-independent) |
| `release_claim` | status flip + `git push --delete` | tool call + `git push --delete` |
| `link_pr_to_card` | `submit-pr.sh` (Closes-trailer injection) | `mcp__linear__attach_pr` OR fallback body insertion |
| `comment_on_card` | `gh issue comment` | `mcp__linear__create_comment` |

The git-layer push is the atomicity boundary regardless of Form — Form B's `claim_card` and `release_claim` still run `git push` outside the MCP path, because branch publication is a git-server operation, not a kanban-backend operation. This is identical to Form A.

## Failure mode notes

Form B failures arrive as MCP tool-call errors with structured error codes, NOT as exit codes. The dispatch layer maps:

- **Transport errors** (network timeout, MCP server crashed) → caller-visible `transient`.
- **Auth errors** (401 from the underlying API, OAuth refresh failed) → caller-visible `auth-failed`.
- **Tool-not-found** (MCP server up but tool name missing from advertisement) → caller-visible `unknown-projection-call` — surface immediately, do not retry.
- **Server errors** (5xx from the underlying API) → caller-visible `server-failure` — caller policy decides retry.

`failure-mode-dispatch.md` documents the surfacing tiers per category.

## Related

- `action-dispatch.md` — per-action dispatch shape, parameterized by Form. The Form B column is what this file concretizes.
- `form-a-bash.md` — the comparable contract for the v0.5.0-live Form A projection.
- `form-c-rest.md` — the third invocation form, for when neither CLI nor MCP fits.
- `failure-mode-dispatch.md` — failure surfacing across all three forms.
- [`PLUGIN_DEVELOPMENT.md`](../../../PLUGIN_DEVELOPMENT.md) § "MCP server registration" — platform-level MCP wiring.
- ADR-0027 § Decision 3 — bootstrap-side dispatch through projection reference files; the same conventions apply to Form B's `provision-mcp-credentials` capability.
- The v1.x reference projection (planned): `references/linear.md` — Linear's MCP server projection, the first Form B instance.
