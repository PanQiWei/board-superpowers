---
name: using-board-superpowers
description: Use as the FIRST skill when a board-superpowers session starts and the user's intent isn't clearly board-related vs general coding. Routes the session into either Producer mode (the managing-board skill, for board orchestration like "what should I work on" / "review the PRs" / "intake this idea") or Consumer mode (the consuming-card skill, for claiming and implementing a specific card). Apply this skill liberally when the message is generically about "the board" / "this plugin" without naming a specific routine or card — the routing cost is low and explicit routing is preferable to guessing the wrong downstream skill silently. Skip this skill when the user's message clearly matches a downstream skill directly (e.g., "[board-card:#12]" goes straight to consuming-card).
when_to_use: Use as a router when intent is ambiguous, when no other board-superpowers skill matched, when the user asks "what does this plugin do" / "how does this work" / "what's available", OR when the SessionStart hook injected an INVOKE marker pointing at a specific downstream skill.
---

# using-board-superpowers

This is the entry skill — first touch when a board-superpowers session starts. It routes; it does not perform real work itself.

The skill handles three things, in this order:

1. **Verifies dependencies** are present (`bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh`, or the equivalent absolute path on Codex). If they fail, surface the dep-check output and stop — no point routing further work into a broken plugin.

2. **Consumes any hook-injected intent marker** delivered as `additionalContext` from the SessionStart hook. Markers follow the format `INVOKE: <skill-name>` followed by `REASON: <one-line>`. The marker is a fast-path hint; if a marker arrives, route to the named skill directly and pass through the reason as orientation.

3. **Routes the user's message** to the right downstream skill using the table below.

## Routing table

| Signal in user message | Route to |
|------------------------|---------|
| Literal `[board-card:#N]` token | `board-superpowers:consuming-card` (with N as `$card_number`) |
| "claim card N" / "work on card N" / "implement #N" / "let me take #N" / "let's pick up N" | `board-superpowers:consuming-card` |
| "what should I work on" / "morning briefing" / "today's plan" | `board-superpowers:managing-board` (daily routine) |
| "review the PRs" / "what's in In Review" / "merge ready" | `board-superpowers:managing-board` (review-queue routine) |
| "new requirement" / "intake this idea" / "I have a feature" | `board-superpowers:managing-board` (intake routine) |
| "what's blocked" / "triage the board" / "release stale claims" | `board-superpowers:managing-board` (triage routine) |
| "what does this plugin do" / "how does this work" / "what's available" | Answer inline (informational query) — see `references/first-time-user-guide.md` |
| "set up board-superpowers on this repo" / "first time on this repo" | Surface manual-setup walkthrough from `references/first-time-user-guide.md` |
| Anything clearly board-related but not in the table | Ask the user to disambiguate — do NOT pick a default |

## Routing discipline

This skill MUST NOT do real work itself. If a route lands here but the message doesn't match any signal, **ask** — don't guess. Wrong routing = wrong worktree / wrong board mutation; the cost of asking is low.

The skill MAY answer purely informational questions about board-superpowers itself ("what does this plugin do", "what skills are available") inline without routing. See `references/first-time-user-guide.md` for the canonical introduction text.

## Cross-plugin signals to NOT capture

Some user messages sound board-related but actually belong to sibling plugins. Do not artificially capture these:

| Phrase | Belongs to |
|--------|-----------|
| "let's brainstorm this" | `superpowers:brainstorming` (will route itself) |
| "investigate this bug" | `gstack:/investigate` |
| "QA this URL" | `gstack:/qa` |
| "code review my diff" | `gstack:/review` + `superpowers:requesting-code-review` |

This entry skill exists to route board-scoped intent — not to be the universal entry point for all sessions in this repo.

## Hook-injected intent markers

The SessionStart hook (`hooks/session-start.sh`) emits `additionalContext` JSON with:

- A status line confirming the plugin is loaded.
- Any failed dep-check details with install hints.
- A friendly note about manual setup if the per-repo `.board-superpowers/config.yml` is absent.

When this skill triggers, check the most recent system-injected context for the dep-check output. If checks failed, surface that BEFORE attempting any routing — a broken plugin can't run the routes anyway.

If a future plugin version starts injecting `INVOKE: <skill>` markers via the same `additionalContext` channel, the marker is a hint, not a contract — this skill remains free to override based on richer message context.

## Cross-platform notes

This skill works on both Claude Code and Codex CLI. The routing logic uses only `name` + `description` frontmatter; downstream skills' Tier-2 fields (like the `argument-hint` on `consuming-card`) take effect after routing.

On Codex CLI, the SessionStart hook is wired via `~/.codex/hooks.json` after running `bash scripts/register-codex-hooks.sh --install-user` once per Codex install. The dep-check output reaches this skill via the same `additionalContext` payload — no platform-specific code path needed.

## Friendly intro for first-time invocations

If this is the user's first time invoking the plugin (detection: `.board-superpowers/config.yml` does NOT exist in the current repo), prepend the response with a 3-sentence orientation:

> board-superpowers is a board-driven scheduling layer on top of `superpowers` and `gstack`. It routes every session into Manager (board orchestration) or Consumer (one-card-to-PR) mode and delegates real work — TDD, debugging, review, QA, security audit — to the sibling plugins. See `references/first-time-user-guide.md` for the per-repo setup walkthrough.

Then proceed with routing.

## Anti-pattern: routing that becomes work

If you find yourself writing procedure inline in this skill ("first do X, then do Y, then check Z"), STOP — that's downstream-skill territory. Route to (or ask the architect to create) the right skill instead. Entry-skill routing is one decision per turn, not a procedure.
