---
name: using-board-superpowers
description: Use as the FIRST skill when a board-superpowers session starts and the user's intent is unclear, OR when the SessionStart hook injected an INVOKE marker, OR when no other board-superpowers skill matched. Routes the session into Producer (managing-board) or Consumer (consuming-card) mode based on the message vocabulary, prior session state, or hook-injected intent. Apply this skill liberally — it costs little and makes the routing explicit; preferable to letting Claude pick the wrong molecular skill silently.
when_to_use: Use as the FIRST router when a session starts on a repo using board-superpowers and intent is ambiguous, when no other plugin skill matched, or when handling a SessionStart hook's INVOKE marker. Also when the user says "set up board-superpowers" or asks "what does this plugin do".
---

# using-board-superpowers

> **Skeleton type**: C (router-pattern). Entry layer — routes
> only, never does work itself. Body target: ≤ 200 lines.
>
> **REQUIRED SUB-SKILLS** (routing targets only — never composed
> as procedure):
> - `board-superpowers:managing-board` (Producer routine)
> - `board-superpowers:consuming-card` (Consumer lifecycle)

## What this skill does

Three things, in order:

1. **Verify dependencies** are present (`bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh`). If they
   fail, surface the dep-check output and stop — no point
   routing further work into a broken plugin.
2. **Consume any hook-injected intent marker** (per
   `docs/architecture/0005-contracts/02-hook-contracts.md`
   § "Intent-injection markers"). v1-minimum: the hook injects
   only friendly comments, NOT `INVOKE: bootstrapping-repo` or
   `INVOKE: migrating-repo-version` (those skills are
   deferred). If a future version restores those markers, this
   skill consumes them and routes accordingly.
3. **Route the user's message** to the right molecular skill
   using the vocabulary table below.

## Routing table

| Signal | Route to |
|--------|---------|
| Literal `[board-card:#N]` token in message | `board-superpowers:consuming-card` (with N as `$card_number`) |
| "claim card N" / "work on card N" / "implement #N" / "let's take #N" | `board-superpowers:consuming-card` |
| "what should I work on" / "morning briefing" / "today's plan" | `board-superpowers:managing-board` (daily routine) |
| "review the PRs" / "Review Queue" / "what's in In Review" | `board-superpowers:managing-board` (review-queue routine) |
| "new requirement" / "intake this idea" / "I have a feature" | `board-superpowers:managing-board` (intake routine) |
| "what's blocked" / "triage the board" | `board-superpowers:managing-board` (triage routine) |
| "set up board-superpowers" / "first time on this repo" | (deferred to v1-complete via `bootstrapping-repo`) — surface friendly "manually set up GitHub Project + standard labels for now; bootstrap skill ships in v1-complete" |
| "decompose this design doc" / "split this into cards" | (deferred to v1-complete via `decomposing-into-milestones`) — surface friendly "the architect hand-decomposes for now; decomposition skill ships in v1-complete" |
| "what's new in this version" / "migrate" | (deferred to v1-complete via `migrating-repo-version`) — surface friendly "no prior version exists yet; migration skill ships in v1-complete" |
| Anything else clearly board-related but not in the table | Ask the user to disambiguate — do NOT pick a default |

## Routing discipline

This skill MUST NOT do real work itself. If a route lands on
this skill but the message doesn't match any signal, **ask** —
don't guess. Wrong routing = wrong worktree / wrong board
mutation; the cost of asking is low.

The skill MAY answer purely informational questions about
board-superpowers itself ("what does this plugin do", "what
skills are available") inline without routing. See
`references/first-time-user-guide.md` for the canonical
introduction text.

## Hook-injected intent markers (v1-minimum behavior)

The SessionStart hook (`hooks/session-start.sh`) emits
`additionalContext` JSON. v1-minimum payload contents:

- Always: a status line confirming `board-superpowers v0.1.0-minimum loaded`
- If dep check failed: the failing checks + install hints
- If `.board-superpowers/config.yml` is absent: a friendly note
  about manual setup (NO `INVOKE: bootstrapping-repo` marker —
  the deferred skill doesn't exist yet)

When this skill triggers, check the most recent system-injected
context for the dep check output. If checks failed, surface
that BEFORE attempting any routing — a broken plugin can't run
the routes anyway.

## Cross-platform notes

This skill is `mode: both` (CC + Codex). The routing logic uses
only Tier 1 frontmatter + body content; no `arguments` /
`argument-hint` here (the routing target's argument-hint is what
ultimately shows in autocomplete).

On Codex CLI, the SessionStart hook is wired via
`~/.codex/hooks.json`. The dep-check output reaches this skill
via the same `additionalContext` payload — no platform-specific
code path needed.

## Friendly intro for first-time invocations

If this is the user's first time invoking the plugin (detection:
`.board-superpowers/config.yml` does NOT exist in the current
repo), prepend the response with a 3-sentence orientation:

> board-superpowers is a board-driven scheduling layer on top
> of `superpowers` and `gstack`. It routes every session into
> Manager (board orchestration) or Consumer (one-card-to-PR)
> mode and delegates real work — TDD, debugging, review, QA —
> to the sibling plugins. v1-minimum scope: 5 of 10 skills
> shipped (see SKILLS.md § "v1 minimum vs v1 complete").

Then proceed with routing. See `references/first-time-user-guide.md`
for the longer setup walkthrough used when the user explicitly
asks "set up this plugin".

## Anti-pattern: routing that becomes work

If you find yourself writing procedure inline in this SKILL.md
("first do X, then do Y, then check Z"), STOP — that's
molecular skill territory. Route to (or create) a molecular
skill instead. Entry skills routing is one decision per turn,
not a procedure.
