# bootstrapping-repo — introduction

This is the conceptual onboarding for an architect who just ran `bootstrapping-repo` for the first time on this `(host, repo)` pair. Surface this content inline if the architect asks "what does this thing actually do" during or after F-B2 — otherwise treat it as on-demand reading.

## What is board-superpowers?

board-superpowers is a **scheduling layer** that sits on top of two sibling plugins:

- **`superpowers`** — the coding-discipline library (`brainstorming`, `writing-plans`, `test-driven-development`, `systematic-debugging`, `verification-before-completion`, `requesting-code-review`).
- **`gstack`** — the production-quality bookends (`/office-hours`, `/plan-ceo-review`, `/plan-eng-review`, `/review`, `/qa`, `/cso`).

board-superpowers does not reimplement what those plugins already do. It coordinates **when** they run, **what card** they target, and **who reviews** the result — using GitHub as the substrate. There is no server. The board lives on a GitHub Project, the work lives in a git worktree, the audit lives in your own RDBMS (or in a degraded local trace if you opt out).

## The two-role mental model

Every session in a board-superpowers repo plays one of two roles. The first thing you do in a new session is decide which:

| Role | When | Skill that drives it |
|------|------|----------------------|
| **Producer / Manager** | You are orchestrating the board — daily briefing, intaking new ideas, reviewing open PRs, triaging blocked cards. You are NOT writing implementation code. | `managing-board` |
| **Consumer / Implementer** | You are claiming and implementing ONE specific card from start to PR. You are NOT shaping the board. | `consuming-card` |

The roles are intentionally separate. A Producer session that drifts into implementation makes the board the Producer's responsibility forever; a Consumer session that drifts into board orchestration burns context that should have been spent on the card.

The router `using-board-superpowers` makes the role decision for you on session start — it reads the user's first message and either fires the bootstrap chain (you just did this), routes to `managing-board`, or routes to `consuming-card`. If the intent is ambiguous it asks rather than guessing.

## Day-1 happy path

Once F-B1 + F-B2 are both done, your first day with the plugin looks like this:

1. **Bootstrap** (you just did this — F-B1 + F-B2 are complete).
2. **First Manager session** — open a fresh CC / Codex session and say "let's intake this feature: <one-line idea>". The router fires `managing-board` (intake routine), which walks you through deciding whether the idea needs `gstack:/office-hours` (direction-setting), `gstack:/plan-eng-review` (architecture lock), `superpowers:brainstorming` (decomposition), or direct card creation.
3. **Decompose into Ready cards** — the architect hand-decomposes the brainstorming output into small cards on the board, each with the canonical 5-section body schema (per `board-canon`).
4. **First Consumer session** — open a fresh session, type `[board-card:#N]`, the router fires `consuming-card`. That skill creates a worktree, drives Red→Green→Refactor TDD via `superpowers:test-driven-development`, runs the verification chain (`superpowers:verification-before-completion`, `gstack:/review`, `superpowers:requesting-code-review`), and submits the PR with the three-section contract.
5. **Review and merge** — the Producer (probably you) reviews the PR via `managing-board` (review-queue routine) and merges. The card auto-transitions to Done.

The Producer / Consumer split lets you context-switch cleanly: Producer sessions track the bigger picture; Consumer sessions go deep on one card without the board's gravity tugging at your attention.

## Frequently-asked first-time questions

### Do I need a Postgres / MySQL DB just to use this?

No. The BYO-RDBMS audit log is **opt-in** and supports SQLite (host-local) per ADR-0009. If you decline BYO-RDBMS at F-B2 step 2e entirely, every A-class action degrades to R-class — meaning the agent asks you to acknowledge every mutating action instead of acting autonomously. That is a usable mode (just chattier); reconsider RDBMS later if the prompts get tedious.

### What if my GitHub Project does not have the 6 statuses yet?

You need to create the Status field's options manually in the GitHub Project UI before F-B2 can succeed. Per ADR-0001, the bootstrap script does NOT create the project or its options — single-select option creation via the GraphQL API is unreliable with standard tokens, and we deliberately do not work around that. See `references/project-creation-walkthrough.md` for the UI steps. Once the field is set up correctly, re-invoke this skill — F-B1 detects the manifest already exists (idempotent fast path), and F-B2 picks up where step 2b previously aborted.

### What does this plugin actually DO at runtime?

Three things, in three different places:

- **In your CC / Codex session**, two skills (`managing-board` for Producer, `consuming-card` for Consumer) drive the workflow with cross-plugin handoffs to `superpowers` and `gstack`.
- **On GitHub**, the source of truth — your Project, your Issues (= cards), your branches (`claim/<N>-<slug>`), your PRs (with the three-section contract).
- **On your machine**, two state files — `~/.board-superpowers/manifest.yml` (host-level, version tracking) and `~/.board-superpowers/repos/<normalized>/state.yml` (per-repo, host-local), plus the optional BYO-RDBMS audit log.

Nothing runs as a daemon. Nothing watches your filesystem. The plugin's primitives all execute when the agent calls them inside a session.

### Why two state files instead of one?

Because the install is per-host (one plugin reachable from many sessions across many repos) but the workflow is per-repo (each project has its own board). Some events fire host-wide on plugin upgrade (changelog highlights — F-B3); other events fire per-repo on first-touch-after-upgrade (feature opt-in, routing-block re-injection — F-B4). The two-layer state machine is what lets those events fire correctly without double-firing or missing.

The committed-vs-host-local split is also important: `config.yml` is committed (your team agrees on `OWNER/NUMBER` and the WIP cap), but `state.yml` is host-local (every architect's machine independently tracks its bootstrap state). This is invariant I-13 in the spec.

### What if I screw up and want to start over?

You can re-run this skill with the `--force` flag on either script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap-host.sh" --force
bash "${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap-project.sh" \
  --owner OWNER --project NUM --force
```

Both rewrite their state files unconditionally. The routing block injection is idempotent and recognizes its own marker pair, so it does not duplicate. To remove all bootstrap state for this repo entirely, delete `~/.board-superpowers/repos/<normalized>/` (host-local) and `<repo>/.board-superpowers/` (in-repo), then re-bootstrap.

The `<normalized>` directory name is the repo's absolute path with leading `/` stripped and remaining `/` replaced by `-`. For `/Users/foo/proj` that is `Users-foo-proj`.

## What this skill does NOT do

- It does not seed your board with cards. After all stages are applied, your board is empty — the first card is your responsibility (use the Manager session intake routine).
- It does not configure the BYO-RDBMS schema for you. The credential-setup step records your DSN in `credentials.yml`; the schema is applied via `scripts/audit-init.sh` during the M4 audit-DDL stage and `board-superpowers:auditing-actions` writes use that schema thereafter.
- It does not run *after* all stages are applied during a normal working session. Once lifecycle shows all stages as `applied`, the entry skill routes directly to `managing-board` or `consuming-card` without invoking this skill. Plugin upgrades that add new stages re-trigger this skill automatically through the hook's lifecycle diff.
