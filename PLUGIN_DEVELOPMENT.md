# Plugin Development Guide

> **Required reading** for anyone modifying `hooks/`, `scripts/`,
> `skills/`, `.claude-plugin/`, `.codex-plugin/`, or any
> `marketplace.json` in this repo. All design decisions in this
> codebase derive from the contracts documented below. If a contract
> changes upstream, update this doc in the same PR that touches
> dependent code.

board-superpowers is a **dual-platform plugin** — it must run as a
first-class plugin on both:

- **Claude Code** (Anthropic) — official docs root: <https://code.claude.com/docs/>
- **OpenAI Codex CLI** — official docs root: <https://developers.openai.com/codex/>

This document references the official documentation for both products
and notes where their plugin contracts converge, diverge, and where
documentation gaps exist that you must work around.

**URL freshness:** all URLs verified 2026-04-27. Re-verify when
modifying related code; a moved or broken canonical URL is a
load-bearing fact and must be patched in the PR that catches it.

---

## TL;DR — surface mapping

| Surface | Claude Code | Codex CLI | Notes |
|---------|-------------|-----------|-------|
| Plugin manifest | `.claude-plugin/plugin.json` | `.codex-plugin/plugin.json` | Both require `name`, `version`, `description`. Codex adds a richer optional `interface` block. |
| Marketplace manifest | `marketplace.json` (registered via `/plugin marketplace add`) | `marketplace.json` (registered via `codex plugin marketplace add`) | Both support local sources; schemas are similar but not identical. |
| Plugin install env var | `${CLAUDE_PLUGIN_ROOT}` (set during hook + script execution) | _no equivalent_ (resolve via `BASH_SOURCE` / relative paths) | Only Claude Code provides this convenience. |
| Project instructions | `CLAUDE.md` (auto-loaded) | `AGENTS.md` (auto-loaded; lookup walks Git root → cwd) | board-superpowers bootstrap must inject routing into **both** files. |
| Skills | `skills/<name>/SKILL.md` (full YAML frontmatter) | `skills/<name>/SKILL.md` (+ optional `agents/openai.yaml` for display metadata) | `name`/`description` portable; richer Claude frontmatter is Claude-only. |
| Hooks | `hooks/hooks.json` (28+ events) | `~/.codex/hooks.json` or `[hooks]` in `config.toml` (6 events) | `SessionStart` / `PreToolUse` / `PostToolUse` / `UserPromptSubmit` / `Stop` exist on **both**. |
| Slash commands | merged into skills | exposed via plugin / skill UI (`/plugins`) | |
| MCP servers | `.mcp.json` shipped with plugin | `mcpServers` field in `.codex-plugin/plugin.json` | Both can ship MCP servers natively. |

---

## Claude Code

### Plugin manifest (`.claude-plugin/plugin.json`)

- **Official docs**: <https://code.claude.com/docs/en/plugins-reference.md>
- Required: `name` (unique identifier; becomes skill namespace),
  `description`. Optional: `version` (semver, defaults to git SHA if
  omitted), `author`, `homepage`, `repository`, `license`.
- Identity for `/plugin list` and namespace for slash commands
  (`/<plugin-name>:<skill>`).

```json
{
  "name": "my-plugin",
  "description": "What this plugin does",
  "version": "1.0.0",
  "author": { "name": "Author Name" },
  "homepage": "https://github.com/user/repo",
  "repository": "https://github.com/user/repo",
  "license": "MIT"
}
```

### Marketplace manifest (`marketplace.json`)

- **Official docs**: <https://code.claude.com/docs/en/plugin-marketplaces.md>
- One marketplace can bundle one or many plugins; same schema
  regardless of count. Sources: `github`, `git`, `local` path, URL,
  NPM package.
- Registered via `/plugin marketplace add <source>`.

```json
{
  "plugins": [
    {
      "name": "plugin-name",
      "description": "What it does",
      "version": "1.0.0",
      "source": { "source": "github", "repo": "user/repo" }
    }
  ]
}
```

### `${CLAUDE_PLUGIN_ROOT}`

- **Official docs**: <https://code.claude.com/docs/en/plugins-reference.md>
- Set during hook execution and inside skill bodies that invoke
  commands. Resolves to the plugin's installation directory (e.g.,
  `~/.claude/plugins/board-superpowers`).
- **Hard rule**: never hard-code `~/.claude/plugins/...` — always
  reference via `${CLAUDE_PLUGIN_ROOT}`.

### Hooks (`hooks/hooks.json`)

- **Official docs**: <https://code.claude.com/docs/en/hooks.md>
- **Available events** (board-superpowers uses **`SessionStart` only**):
  `SessionStart`, `SessionEnd`, `UserPromptSubmit`,
  `UserPromptExpansion`, `Stop`, `StopFailure`, `PreToolUse`,
  `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`,
  `PermissionDenied`, `PostToolBatch`, `FileChanged`, `CwdChanged`,
  `ConfigChange`, `InstructionsLoaded`, `Notification`,
  `WorktreeCreate`, `WorktreeRemove`, `SubagentStart`, `SubagentStop`,
  `TeammateIdle`, `TaskCreated`, `TaskCompleted`, `PreCompact`,
  `PostCompact`, `Elicitation`, `ElicitationResult`.
- Handler types: `command` (bash), `http`, `mcp` tool, `prompt`,
  `agent`.
- **Input via stdin**: JSON with `session_id`, `cwd`, `hook_event_name`,
  event-specific fields.
- **Output**: JSON with optional `decision` (blocking), `continue`,
  `suppressOutput`, `systemMessage`, `reason`,
  `hookSpecificOutput.additionalContext` (this is what
  board-superpowers uses to inject the dep-alert banner).
- **Exit codes**: `0` success, `2` blocking error, others non-blocking.
- **Default timeout**: 600s (board-superpowers sets 10s in its
  `hooks.json`).

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

### Skills (`SKILL.md`)

- **Official docs**: <https://code.claude.com/docs/en/skills.md>
- **Layout**: `skills/<name>/SKILL.md` (required) +
  `references/<topic>.md` (optional; lazy-loaded via Markdown links).
- **Frontmatter — full field reference (13 fields, all optional;
  only `description` is recommended):**

  | Field | Required | What it controls |
  |-------|----------|------------------|
  | `name` | No (defaults to dir name) | Display name + `/<plugin-name>:<name>` slash form. Lowercase + hyphen + numbers, ≤64 chars. |
  | `description` | Recommended | Triggering matcher. Combined with `when_to_use`, capped at **1,536 chars** in the skill listing. |
  | `when_to_use` | No | Additional trigger phrases / example requests. Appended to `description` in the listing; counts against the same 1,536-char cap. |
  | `argument-hint` | No | Autocomplete placeholder shown after `/<skill> ` in the slash menu. Examples: `[card-number]`, `"[optional context]"`. **Defensive quoting**: wrap values containing `:`, `,`, `*`, or other YAML special chars in double quotes (root cause of the now-fixed [#22161](https://github.com/anthropics/claude-code/issues/22161) crash). |
  | `arguments` | No | Named positional arguments. Space-separated string or YAML list. Names map to position; body uses `$<name>` substitution. |
  | `disable-model-invocation` | No | `true` = only the user can invoke; Claude won't auto-trigger. Also blocks subagent preload. |
  | `user-invocable` | No | `false` = hide from `/` menu; Claude can still auto-invoke. Use for atomic reflex-skills users don't drive directly. |
  | `allowed-tools` | No | Tools auto-approved while this skill is active. Space-separated string or YAML list. |
  | `model` | No | Model override for the active turn (`inherit` or any `/model` value). |
  | `effort` | No | Effort level override (`low` / `medium` / `high` / `xhigh` / `max`). |
  | `context` | No | `fork` = run in a forked subagent context. Pairs with `agent`. |
  | `agent` | No | Subagent type when `context: fork` (`Explore`, `Plan`, `general-purpose`, or any `.claude/agents/<name>`). |
  | `hooks` | No | Hooks scoped to this skill's lifecycle. See `<https://code.claude.com/docs/en/hooks#hooks-in-skills-and-agents>`. |
  | `paths` | No | Glob patterns limiting auto-trigger to matching files. |
  | `shell` | No | `bash` (default) or `powershell` for `` !`cmd` `` blocks. PowerShell requires `CLAUDE_CODE_USE_POWERSHELL_TOOL=1`. |

- **Description matching**: Claude auto-invokes a skill based on
  `description` (and `when_to_use`) matching user prompts.
  **Description is behavior, not documentation.** Empirically, any
  workflow detail in `description` makes Claude skip the body —
  keep `description` to triggering conditions only.

- **String substitutions in body** (extends the slash-command set):
  - `$ARGUMENTS` — full argument string as typed
  - `$ARGUMENTS[N]` / `$N` — 0-indexed positional access (shell-style quoting)
  - `$<name>` — named arguments declared in `arguments:` frontmatter
  - `${CLAUDE_SESSION_ID}` — current session ID
  - `${CLAUDE_SKILL_DIR}` — directory containing this `SKILL.md`

- Invoked via the `Skill` tool; once invoked, content persists in the
  conversation message stream for the rest of the session.

```yaml
---
name: my-skill
description: What this skill does and when Claude should use it
when_to_use: Additional trigger phrases users actually type
argument-hint: "[primary-arg] [optional-arg]"
arguments: [primary, optional]
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash(npm *) Edit Read
model: inherit
effort: medium
context: fork
agent: general-purpose
paths: ["src/**", "tests/**"]
shell: bash
---
```

### Slash commands

- **Official docs**: <https://code.claude.com/docs/en/skills.md>
  (commands have been merged into skills)
- Both `commands/<name>.md` (flat file) and
  `skills/<name>/SKILL.md` (skill directory) register a slash
  command.
- Plugin commands are namespaced: `/<plugin-name>:<skill-name>`.
- Substitutions: `$ARGUMENTS`, `$ARGUMENTS[N]`, `$0`–`$9`,
  `$<name>` (when `arguments:` frontmatter declares named positional
  parameters), `${CLAUDE_SESSION_ID}`, `${CLAUDE_SKILL_DIR}`.

### MCP server registration

- **Official docs**: <https://code.claude.com/docs/en/plugins-reference.md>
  (MCP servers section)
- `.mcp.json` at plugin root.
- Loaded automatically when the plugin is enabled.

```json
{
  "my-server": {
    "command": "node",
    "args": ["./dist/index.js"],
    "env": { "LOG_LEVEL": "debug" }
  }
}
```

### Settings

- **Official docs**: <https://code.claude.com/docs/en/settings.md>
- `settings.json` at plugin root.
- Plugin-scope keys currently supported: `agent`,
  `subagentStatusLine`. Other keys silently ignored.
- Plugins can rely on (but not override) standard keys
  (`permissions`, `env`, `outputStyle`, `model`) set in user/project
  scope.

---

## Codex CLI

### Plugin manifest (`.codex-plugin/plugin.json`)

- **Official docs**: <https://developers.openai.com/codex/plugins/build>
- Required: `name` (kebab-case), `version` (semver), `description`.
- Optional: `author`, `homepage`, `repository`, `license`,
  `keywords`, `skills`, `mcpServers`, `apps`, `interface` block.
- The `interface` block is richer than Claude's manifest:
  `displayName`, `shortDescription`, `longDescription`,
  `developerName`, `category`, `capabilities`, `websiteURL`,
  `privacyPolicyURL`, `termsOfServiceURL`, `brandColor`,
  `composerIcon`, `logo`, `screenshots`, `defaultPrompt[]`.
- **Plugins are NOT bare directories** — manifest is required.

### Marketplace

- **Official docs**: <https://developers.openai.com/codex/plugins>
- Registered via `codex plugin marketplace add <source>`. Sources:
  GitHub `owner/repo[@ref]`, Git/SSH URL, **local directory**.
- Subcommands: `remove`, `upgrade`. Flags: `--ref`, `--sparse PATH`.
- **There is NO `codex plugin add local <path>`** — local plugins are
  exposed by registering a local marketplace whose `marketplace.json`
  lists them with `"source": {"source": "local", "path": "./..."}`.
- Plugin browser opens with `/plugins`.
- Plugins are toggled in `~/.codex/config.toml`:
  `[plugins."<name>@<marketplace>"]\nenabled = false`.

### Skills (`SKILL.md` + optional `agents/openai.yaml`)

- **Official docs**: <https://developers.openai.com/codex/skills>
  + <https://github.com/openai/skills/tree/main/skills/.system/skill-creator/references>
- **Layout**: `<skill-name>/SKILL.md` (required) + optional
  `scripts/`, `references/`, `assets/`, `agents/openai.yaml`.
- The plugin manifest's `skills` field points at a directory of
  skills.
- `agents/openai.yaml` is officially documented as "extended
  product-specific config for the machine/harness, not the agent."

### Skill frontmatter / metadata

- **Official docs**: <https://github.com/openai/skills/blob/main/skills/.system/skill-creator/references/openai_yaml.md>
- `SKILL.md` frontmatter: `name`, `description` (the only fields
  officially listed).
- **No published character cap** on `description`. The community
  prudence of capping at 1024 chars (e.g., gstack) is not enforced
  by Codex.
- **The only documented budget is aggregate**: skills list is capped
  at "approximately 2% of the model's context window, or 8000
  characters when the context window is unknown." Descriptions
  auto-shorten when many skills are installed.
- `agents/openai.yaml` schema:
  - `interface.{display_name, short_description, icon_small,
    icon_large, brand_color, default_prompt}`
  - `policy.allow_implicit_invocation`
  - `dependencies.tools[]` (only `type: "mcp"` is supported today,
    with `value`, `description`, `transport`, `url`)
- `short_description` in `openai.yaml` has an explicit 25–64 char
  guideline.

### AGENTS.md (project instructions)

- **Official docs**: <https://developers.openai.com/codex/guides/agents-md>
  (mirror: <https://github.com/openai/codex/blob/main/docs/agents_md.md>)
- Auto-loaded **once per run**.
- **Lookup order**: `~/.codex/AGENTS.override.md` →
  `~/.codex/AGENTS.md`, then walk Git root → cwd checking
  `AGENTS.override.md` → `AGENTS.md` → any
  `project_doc_fallback_filenames`.
- Files concatenate root-down. Reading stops at
  `project_doc_max_bytes` (default 32 KiB) or empty file.
- **No formal schema** — free-form Markdown.

### Hooks

- **Official docs**: <https://developers.openai.com/codex/hooks>
- **Codex DOES have lifecycle hooks** (a common misconception is
  that the `notify` config is the only hook surface — it is not).
- **Available events (6)**: `SessionStart`, `PreToolUse`,
  `PermissionRequest`, `PostToolUse`, `UserPromptSubmit`, `Stop`.
- Configured via `~/.codex/hooks.json` or inline `[hooks]` in
  `~/.codex/config.toml`. Per-repo: `<repo>/.codex/hooks.json` or
  `<repo>/.codex/config.toml` (project layer requires trust). Layers
  merge rather than override.
- The `notify = [...]` key in `config.toml` is **not deprecated**;
  it fires only on agent-turn-complete. Use `Stop` hooks for richer
  turn-end logic; keep `notify` for OS-notification one-liners.

### `codex exec` (non-interactive)

- **Official docs**: <https://developers.openai.com/codex/cli/reference>
- Alias: `codex e`. Runs to completion; suitable for CI/scripting.
- Notable flags:
  - `--sandbox` / `-s`: `read-only` | `workspace-write` |
    `danger-full-access`
  - `--full-auto`: preset = `workspace-write` + on-request approvals
  - `--ephemeral`: no session persistence
  - `--output-last-message,-o <file>`
  - `--output-schema <json-schema>`
  - `--json`: NDJSON event stream
- Resumable: `codex exec resume [--last|--all|<SESSION_ID>]`.

### Tool names the model sees

- **Partial docs**: <https://developers.openai.com/codex/cli/features>
- **No canonical "tool reference" page exists** — model-facing tool
  names are inferable from the features page and `codex-rs/core/`
  source.
- Documented built-ins: `shell`, `apply_patch`, `read`, `edit`,
  `web_search`, `file_search`, image generation,
  `code_interpreter` / `computer_use` (in app variant).
- **Treat tool names as implementation detail.** Do not depend on
  exact JSON tool schemas as a stable contract. When a skill needs
  cross-platform language, write generic prose ("read the file at
  X") rather than naming a specific tool.

### MCP integration

- **Official docs**: <https://developers.openai.com/codex/mcp>
- CLI: `codex mcp add <name> -- <command>`, `codex mcp list`,
  `codex mcp remove`, `codex mcp login` (OAuth).
- Persisted under `[mcp_servers.<name>]` in `~/.codex/config.toml`
  or per-repo `<repo>/.codex/config.toml`.
- STDIO keys: `command`, `args`, `env`, `cwd`. HTTP keys: `url`,
  `bearer_token_env_var`, `http_headers`. Common:
  `startup_timeout_sec` (default 10), `enabled`, `enabled_tools`,
  `disabled_tools`.
- `mcpServers` is a first-class field in `.codex-plugin/plugin.json`
  — plugins can ship MCP servers natively.

---

## What this means for board-superpowers

The dual-platform commitment is structurally tractable because the
contract surfaces converge more than they diverge. Concrete
implications for our codebase:

1. **Plugin manifests** — ship both `.claude-plugin/plugin.json`
   AND `.codex-plugin/plugin.json`. They share `name`, `version`,
   `description`. The Codex `interface` block is richer; we fill
   what makes sense.
2. **Marketplaces** — ship a `marketplace.json` per platform. Both
   can reference the same plugin source (this repo).
3. **Hooks** — `hooks/session-start.sh` can be wired into both
   platforms because `SessionStart` exists on both. Register it
   twice: `hooks/hooks.json` for Claude Code, equivalent
   `~/.codex/hooks.json` entry (or per-repo
   `<repo>/.codex/hooks.json`) for Codex.
4. **Skills** — `SKILL.md` body is portable. Frontmatter is
   tiered (the **three-tier discipline** documented in
   `SKILL_DEVELOPMENT.md` § "Three-tier frontmatter discipline"):
   - **Tier 1 — Portable subset, behavior-defining**: `name`,
     `description`. Works on both platforms identically.
   - **Tier 2 — CC-only spec fields, additive UX only**:
     `when_to_use`, `argument-hint`, `arguments`,
     `disable-model-invocation`, `user-invocable`,
     `allowed-tools`, `model`, `effort`, `context: fork`,
     `agent`, `hooks`, `paths`, `shell`. **All 11 are in CC's
     official spec** — Codex parser silently ignores them, which
     is fine *as long as the body's behavior does not depend on
     them*. (Body must still work when `$<named-arg>` is a literal
     string on Codex.)
   - **Tier 3 — Anti-pattern A4** (reject in review): any field
     not in CC's spec **and** not in Codex's spec — gets dropped
     by both runtimes. Examples seen in the wild: `triggers:`,
     `voice-triggers:`, `preamble-tier:`, `version:`, `layer:`,
     `type:`, `mode:`. board-superpowers' own metadata dimensions
     (version + layer + type + mode + bounded-context) live in a
     sibling `.skill-meta.yaml` file, not in frontmatter, exactly
     to avoid this trap.
   - **Codex display metadata**: ship `agents/openai.yaml` alongside
     `SKILL.md` if richer Codex-side display is wanted.
5. **Project instructions** — `bootstrap-project.sh` must inject the
   routing block into **both** `CLAUDE.md` AND `AGENTS.md`. The
   marker pair (`<!-- board-superpowers:routing -->` /
   `<!-- /board-superpowers:routing -->`) is identical in both
   files; `check-deps.sh` matches in either.
6. **Tool-portable skill prose** — when a skill names a tool, prefer
   generic prose ("read the file at X") over tool-specific syntax.
   Reserve tool-specific calls (e.g., the `Bash` tool name) for
   skills that are explicitly Claude-Code-only.
7. **`${CLAUDE_PLUGIN_ROOT}`** — Claude Code only. Codex equivalent:
   scripts must derive their own paths (e.g., resolve via
   `BASH_SOURCE`/relative-to-self). Keep this abstraction in
   `scripts/lib/common.sh` so callers don't need to know which
   platform they're on.
8. **MCP** — neither platform currently runs board-superpowers as an
   MCP server. If we ever add one, ship the MCP server via
   `.mcp.json` (Claude Code) AND the `mcpServers` field in
   `.codex-plugin/plugin.json` (Codex).

---

## Honest gaps in official docs

The following are **not** documented as stable contracts; treat them
accordingly when designing plugin code:

- **Codex model-facing tool names/schemas have no published stable
  contract.** Test with both `codex exec --json` event streams and
  Claude Code transcripts when behavior depends on tool calls.
- **`description` character caps differ by platform.** Claude Code
  caps the **combined** `description` + `when_to_use` text per
  skill at **1,536 chars** in the skill listing (skills doc, 2026).
  Codex publishes no per-skill cap; the only documented constraint
  is an aggregate budget of ~8,000 chars / 2% context. The 1024-char
  cap seen in agentskills.io / third-party tooling is prudence, not
  platform enforcement; treat 1,024 as the defensive cross-platform
  ceiling, 1,536 as the CC absolute ceiling.
- **Codex `notify` config vs new hooks** — both are live; not
  documented as a deprecation pair. New code should use the `Stop`
  hook; keep `notify` only for OS-notification scripts.
- **No published cross-platform skill format spec.** Claude Code's
  frontmatter is a superset; Codex accepts `name`/`description` and
  looks for additional metadata in `agents/openai.yaml`. This
  document defines our own portability rules in the
  "What this means for board-superpowers" section above.

---

## Maintenance discipline for this doc

- All URLs verified **2026-04-27**. **Re-verify when modifying
  related code.** A broken or moved canonical URL is a load-bearing
  fact and must be patched in this PR, not deferred.
- When a new plugin surface lands in either product, add a section
  here **before** the first board-superpowers feature uses it. This
  doc is leading, not trailing.
- When a contract from this doc changes (new hook event, frontmatter
  field renamed, schema breaking change), update both the section
  here AND the dependent code in board-superpowers in the same PR.
- This doc is referenced from `CLAUDE.md`'s "Required reading"
  section and is therefore implicitly loaded into every
  plugin-maintainer session via the `@PLUGIN_DEVELOPMENT.md`
  syntax. Keep it digestible — agents read it cold.

---

## See also

- `CLAUDE.md` — board-superpowers developer guide (architecture,
  change-impact matrix, scripts/skills/hooks-specific maintenance
  rules)
- `README.md` — end-user overview
- `docs/architecture/0001-positioning.md` — project positioning, premises,
  non-goals
- `docs/architecture/adr/` — architecture decision records
- `MULTI_AGENT_DEVELOPMENT.md` — multi-agent / subagent / orchestration
  contracts for CC and Codex (required reading before designing any
  Producer-spawns-Consumer / Mode-2 feature)
