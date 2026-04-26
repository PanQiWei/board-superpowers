# using-board-superpowers — routing reference

Decision-tree detail for the routing table in the parent SKILL.md.

## Why an entry skill rather than direct routing in CLAUDE.md

The project's `CLAUDE.md` / `AGENTS.md` may carry a routing block, but those are descriptive — they tell the agent how to think about board-superpowers. The entry SKILL.md is **executable** — it consumes the hook payload, runs dep checks, and explicitly invokes the right downstream skill. The two layers serve different purposes:

- Project routing block in `CLAUDE.md` / `AGENTS.md` = standing context (always loaded by the platform's project-instructions reader, read at every prompt)
- Entry SKILL.md = actionable skill (loaded when triggered, runs the routing transaction)

Removing either makes the system less robust. Project routing block alone risks the agent picking the wrong downstream skill silently; entry SKILL.md alone risks the agent not knowing the plugin exists when no trigger fires.

## When the message matches multiple rows

Messages can hit multiple rows of the routing table. Examples:

- "review the PRs and then I'll claim #12" → ambiguous: review-queue routine OR consuming-card?

Resolution: pick the FIRST action mentioned, do that, then prompt for the next. Do NOT try to chain — the user's "and then" is a sequencing hint, not an atomic transaction.

## When the message matches NO row but seems board-related

Examples: "remind me of the WIP rule", "what's the audit log schema again", "explain the daily routine".

These are **informational** queries about the plugin's contracts. Don't route to a downstream skill — answer inline by referencing `board-canon` (for state machine / WIP / schema questions), or by reading the relevant skill's body (for routine descriptions).

## When the message is genuinely off-topic

Examples: "fix this React bug in src/auth/login.tsx".

Don't route — the plugin doesn't apply. Respond normally as the agent would without the plugin loaded. The plugin's presence shouldn't make the agent refuse off-topic work.

## Hook-injected marker handling

When the SessionStart hook injects an `INVOKE: <skill>` marker:

1. Verify the marker's `<skill>` is one of the actually-shipping plugin skills.
2. If known: invoke it directly via the Skill tool, passing the marker's `REASON:` as orientation.
3. If unknown: surface the marker text + a "skill not yet available — falling back to user's natural-language routing" note.

The `INVOKE:` payload is a **hint**, not a contract — the entry skill is allowed to override if context contradicts.

## Cross-plugin signals to NOT route through this skill

Some user phrases sound board-related but actually belong to sibling plugins:

| Phrase | Belongs to |
|--------|-----------|
| "let's brainstorm this" | `superpowers:brainstorming` (route directly, not via this skill) |
| "investigate this bug" | `gstack:/investigate` |
| "QA this URL" | `gstack:/qa` |
| "code review my diff" | `gstack:/review` + `superpowers:requesting-code-review` |

When the user's intent is sibling-plugin-scoped, this skill should NOT artificially capture it. Let the sibling plugin's matcher handle. The entry skill exists to route board-scoped intent — not to be the universal entry point for all sessions in this repo.
