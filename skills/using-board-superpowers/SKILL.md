---
name: using-board-superpowers
description: Use as the FIRST skill when a board-superpowers session starts and the user's intent isn't clearly board-related vs general coding. Routes the session into either Producer mode (the managing-board skill, for board orchestration like "what should I work on" / "review the PRs" / "intake this idea") or Consumer mode (the consuming-card skill, for claiming and implementing a specific card). Apply this skill liberally when the message is generically about "the board" / "this plugin" without naming a specific routine or card — the routing cost is low and explicit routing is preferable to guessing the wrong downstream skill silently. Skip this skill when the user's message clearly matches a downstream skill directly (e.g., "[board-card:#12]" goes straight to consuming-card).
when_to_use: Use as a router when intent is ambiguous, when no other board-superpowers skill matched, when the user asks "what does this plugin do" / "how does this work" / "what's available", OR when the SessionStart hook injected an INVOKE marker pointing at a specific downstream skill.
---

# using-board-superpowers

This is the entry skill — first touch when a board-superpowers session starts. It routes; it does not perform real work itself.

The skill operates in three steps. Steps 1-3 are the **Layer 2 reliable gate** of the bootstrap surface (the SessionStart hook is Layer 1, advisory). Per [`docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md`](../../docs/architecture/0002-product-features-and-flows/05-bootstrap-surface.md) § "three-layer alert + intent-injection strategy", Layer 2 always re-runs the same dep + state check Layer 1 ran, so routing works even when CC `SessionStart` delivery silently drops the hook output.

## Step 1 — re-run dep + state check (Layer 2 reliable gate)

The hook is best-effort; this skill is the contract. Always run BOTH probes itself, even if the hook fired correctly.

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh --machine` (or the equivalent absolute path on Codex). Parse stdout — when non-empty, exactly three lines arrive:

   ```
   MISSING=<csv-or-empty>
   ROUTING_INJECTED=<yes|no>
   PROJECT=<absolute path>
   ```

   When stdout is empty, all is well — proceed to step 2. When stdout is non-empty, surface the dep / routing problem to the user before any further routing — a broken plugin can't run the routes anyway.

2. Probe the host-local state files (paths per [`07-path-conventions.md`](../../docs/architecture/0005-contracts/07-path-conventions.md) "Per-host layout"):

   - `~/.board-superpowers/manifest.yml` — present or absent?
   - `~/.board-superpowers/repos/<normalized>/state.yml` — present or absent?

   `<normalized>` is the repo's absolute path with leading `/` stripped and remaining `/` replaced by `-` (e.g. `/Users/foo/proj` → `Users-foo-proj`). Use `bsp_normalize_repo_path` from `scripts/lib/common.sh` if invoking helper bash; the hook duplicates the same rule inline (per the self-containment contract).

   For worktrees consult `bsp_pick_worktree_dir` so the probe lands on the right repo root, not the worktree.

## Step 2 — consume `INVOKE: bootstrapping-repo` marker if present

Inspect the system-reminder / `additionalContext` content delivered with this turn for a marker shaped:

```
INVOKE: bootstrapping-repo
REASON: <one-line explanation>
```

Marker grammar is pinned in [`02-hook-contracts.md`](../../docs/architecture/0005-contracts/02-hook-contracts.md) § "Intent-injection markers". Rules:

- **Marker present, recognized skill name** — route immediately to the named skill. At v0.2.0 the only legal value is `bootstrapping-repo`. Pass through the REASON line as orientation context.
- **Marker present, unknown skill name** — stop and surface "unrecognized hook intent marker — please file a bug" rather than guessing.
- **Marker absent BUT step 1 found state files absent** — route the same way (do NOT depend on the hook firing). This is what makes Layer 2 the reliable gate.

The marker is a fast-path optimization, not a correctness requirement. Same routing decision regardless of whether Layer 1 delivered the marker or not.

## Step 3 — chain F-B1 → F-B2 when state files are absent

When step 1's state probe reports a missing file (whether or not step 2 saw the marker), chain bootstrap:

- **`~/.board-superpowers/manifest.yml` absent** — invoke `bash ${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap-host.sh` (F-B1). This writes the host manifest and is idempotent on re-run.
- **Per-repo `state.yml` absent** — invoke the `bootstrapping-repo` skill, which drives F-B2 via `scripts/bootstrap-project.sh`. F-B2 collects `OWNER/NUMBER`, writes per-repo `config.yml` + host-local `state.yml`, and injects the routing block into `AGENTS.md` / `CLAUDE.md`.
- **Both absent** — F-B1 first, then chain into F-B2.

After bootstrap completes, continue with the routing table below for the user's actual request.

## Routing table

The post-bootstrap routing — used after step 1 surfaces no problems and step 2/3 detect no pending bootstrap.

| Signal in user message | Route to |
|------------------------|---------|
| Literal `[board-card:#N]` token | `board-superpowers:consuming-card` (with N as `$card_number`) |
| "claim card N" / "work on card N" / "implement #N" / "let me take #N" / "let's pick up N" | `board-superpowers:consuming-card` |
| "what should I work on" / "morning briefing" / "today's plan" | `board-superpowers:managing-board` (daily routine) |
| "review the PRs" / "what's in In Review" / "merge ready" | `board-superpowers:managing-board` (review-queue routine) |
| "new requirement" / "intake this idea" / "I have a feature" | `board-superpowers:managing-board` (intake routine) |
| "what's blocked" / "triage the board" / "release stale claims" | `board-superpowers:managing-board` (triage routine) |
| "what does this plugin do" / "how does this work" / "what's available" | Answer inline (informational query) — see `references/first-time-user-guide.md` |
| "set up board-superpowers on this repo" / "first time on this repo" | Route to `bootstrapping-repo` skill (F-B2) |
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

## Cross-platform notes

This skill works on both Claude Code and Codex CLI. The routing logic uses only `name` + `description` frontmatter; downstream skills' Tier-2 fields (like the `argument-hint` on `consuming-card`) take effect after routing.

On Codex CLI, the SessionStart hook is wired via `~/.codex/hooks.json` after running `bash scripts/register-codex-hooks.sh --install-user` once per Codex install. The dep-check output and intent-injection marker reach this skill via the same `additionalContext` payload — no platform-specific code path needed.

## Anti-pattern: routing that becomes work

If you find yourself writing procedure inline in this skill ("first do X, then do Y, then check Z"), STOP — that's downstream-skill territory. Route to (or ask the architect to create) the right skill instead. Entry-skill routing is one decision per turn, not a procedure.
